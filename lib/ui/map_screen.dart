import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../nav/geo.dart';
import '../state/app_state.dart';
import 'layers_sheet.dart';
import 'library_screen.dart';
import 'map_layers.dart';
import 'points_screen.dart';
import 'theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.state});

  final AppState state;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// Сглаженные позиция и курс, которые рисуются каждый кадр.
class _Disp {
  const _Disp(this.pos, this.heading);
  final LatLng pos;
  final double? heading;
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final MapController _mc = MapController();
  bool _mapReady = false;
  bool _follow = true;
  Timer? _followResume;
  double _zoom = 15;

  late final Ticker _ticker;
  final ValueNotifier<_Disp?> _disp = ValueNotifier<_Disp?>(null);
  Duration _lastElapsed = Duration.zero;
  LatLng? _dPos;
  double? _dHead;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
    s.overpass.addListener(_onState);
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    s.overpass.removeListener(_onState);
    _followResume?.cancel();
    _ticker.dispose();
    _disp.dispose();
    super.dispose();
  }

  double get _rotation => _mapReady ? _mc.camera.rotation : 0;

  void _onState() {
    if (!mounted) return;
    _maybeLoadGrades();
    setState(() {});
  }

  /// Каждый кадр экрана: курс с гироскопа без задержки, позиция между
  /// отсчётами GPS достраивается по скорости и курсу, всё плавно сглаживается.
  void _onFrame(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastElapsed = elapsed;
    final p = s.pos;
    if (p == null) return;
    final h = s.heading;

    var target = p;
    final lf = s.lastFix;
    if (h != null && s.speed > 1 && lf != null && !s.deadReckoning) {
      final age = DateTime.now().difference(lf).inMilliseconds / 1000.0;
      target = offsetM(p, s.speed * age.clamp(0.0, 1.5), h);
    }

    final aPos = 1 - math.exp(-dt / 0.25);
    final aHead = 1 - math.exp(-dt / 0.06);
    final prev = _dPos;
    if (prev == null || distanceM(prev, target) > 300) {
      _dPos = target;
    } else {
      _dPos = LatLng(
        prev.latitude + (target.latitude - prev.latitude) * aPos,
        prev.longitude + (target.longitude - prev.longitude) * aPos,
      );
    }
    if (h != null) {
      final ph = _dHead;
      _dHead = ph == null ? h : wrap360(ph + wrap180(h - ph) * aHead);
    }

    final old = _disp.value;
    final moved = old == null ||
        distanceM(old.pos, _dPos!) > 0.02 ||
        (old.heading == null) != (_dHead == null) ||
        (old.heading != null && _dHead != null && wrap180(old.heading! - _dHead!).abs() > 0.05);
    if (!moved) return;
    _disp.value = _Disp(_dPos!, _dHead);
    if (_mapReady && _follow) _applyFollow();
  }

  DateTime _lastGradeCheck = DateTime(2000);

  /// Подгрузить грунтовки OSM для видимой области (не чаще раза в 2 с, от 12-го масштаба).
  void _maybeLoadGrades({bool force = false}) {
    if (!_mapReady || !s.settings.osmGrades) return;
    final cam = _mc.camera;
    if (cam.zoom < 12) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastGradeCheck).inSeconds < 2) return;
    _lastGradeCheck = now;
    final b = cam.visibleBounds;
    scheduleMicrotask(() => s.overpass.ensure(b.south, b.west, b.north, b.east));
  }

  void _applyFollow() {
    final p = _dPos ?? s.pos;
    if (p == null) return;
    final h = _dHead ?? s.heading;
    final headingUp = s.settings.headingUp && h != null;
    final zoom = _mc.camera.zoom;
    var center = p;
    if (headingUp) {
      // Позиция — в нижней трети экрана, чтобы видеть больше дороги впереди.
      final hgt = MediaQuery.sizeOf(context).height;
      final shift = hgt * 0.2 * metersPerPixel(p.latitude, zoom);
      center = offsetM(p, shift, h);
    }
    _mc.moveAndRotate(center, zoom, headingUp ? -h : 0);
  }

  void _setFollow(bool v) {
    _followResume?.cancel();
    setState(() => _follow = v);
    if (v && _mapReady) _applyFollow();
  }

  void _onUserGesture() {
    if (_follow) setState(() => _follow = false);
    _followResume?.cancel();
    _followResume = Timer(const Duration(seconds: 8), () {
      if (mounted) _setFollow(true);
    });
  }

  void _zoomBy(double dz) {
    if (!_mapReady) return;
    final cam = _mc.camera;
    _mc.move(cam.center, (cam.zoom + dz).clamp(3.0, 20.0));
    if (_follow) _applyFollow();
  }

  // ---------- Линейка ----------

  static const List<double> _nice = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];

  double _rulerLength(LatLng p) {
    final hgt = MediaQuery.sizeOf(context).height;
    final target = hgt * 0.38 * metersPerPixel(p.latitude, _zoom);
    var best = _nice.first;
    for (final n in _nice) {
      if (n <= target) best = n;
    }
    return best;
  }

  List<Widget> _rulerLayers(LatLng p, double h) {
    final len = _rulerLength(p);
    final step = len / 10;
    final line = [p, offsetM(p, len, h)];
    final circles = <CircleMarker>[];
    for (var i = 1; i < 10; i++) {
      final pt = offsetM(p, step * i, h);
      final major = i.isEven;
      circles.add(CircleMarker(
        point: pt,
        radius: major ? 4.5 : 3,
        color: major ? C.text : const Color(0xFF8FA3B3),
        borderColor: C.halo,
        borderStrokeWidth: 1.5,
      ));
    }
    return [
      PolylineLayer(polylines: [
        Polyline(points: line, strokeWidth: 2.5, color: C.text, borderStrokeWidth: 2, borderColor: C.halo),
      ]),
      CircleLayer(circles: circles),
      MarkerLayer(rotate: true, markers: [
        Marker(
          point: line.last,
          width: 80,
          height: 30,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: C.panel,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: C.text),
              ),
              child: Text(fmtDist(len), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text)),
            ),
          ),
        ),
      ]),
    ];
  }

  // ---------- Карта ----------

  /// Слой, который перерисовывается каждый кадр по сглаженной позиции и курсу.
  Widget _live(Widget Function(LatLng p, double? h) build) => ValueListenableBuilder<_Disp?>(
        valueListenable: _disp,
        builder: (context, d, _) => d == null ? const SizedBox.shrink() : build(d.pos, d.heading),
      );

  Widget _map() {
    final p = s.pos;
    final tgt = s.target;
    final children = <Widget>[baseTileLayer(s)];
    if (s.settings.strava) children.add(stravaLayer());
    if (s.settings.osmTraces) children.add(osmTracesLayer());
    if (s.settings.osmGrades && _zoom >= 11 && s.overpass.ways.isNotEmpty) {
      children.add(PolylineLayer(polylines: gradePolylines(s.overpass)));
    }

    final polys = <Polyline>[];
    if (s.settings.mineLayer) {
      for (final t in s.tracks) {
        if (!t.visible || t.points.length < 2) continue;
        polys.addAll(trackPolylines(t, carOnly: s.settings.carOnly));
      }
    }
    if (s.recording && s.rec.length >= 2) {
      polys.add(Polyline(
        points: [for (final r in s.rec) r.pos],
        strokeWidth: 4,
        color: C.blue,
        borderStrokeWidth: 2,
        borderColor: C.halo,
      ));
    }
    if (polys.isNotEmpty) children.add(PolylineLayer(polylines: polys));

    if (tgt != null) {
      children.add(_live((dp, dh) => PolylineLayer(polylines: [
            Polyline(
              points: [dp, tgt.pos],
              strokeWidth: 3,
              color: C.accent,
              pattern: const StrokePattern.dotted(spacingFactor: 2.5),
            ),
          ])));
    }

    if (s.settings.ruler) {
      for (var i = 0; i < 3; i++) {
        children.add(_live((dp, dh) => dh == null ? const SizedBox.shrink() : _rulerLayers(dp, dh)[i]));
      }
    }

    // Точки
    children.add(MarkerLayer(
      rotate: true,
      markers: [
        for (final w in s.points)
          Marker(
            point: w.pos,
            width: 140,
            height: 58,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => openPointEditor(context, s, w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      w.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: w.id == tgt?.id ? C.accent : C.text,
                      ),
                    ),
                  ),
                  Icon(Icons.location_on, size: 30, color: w.id == tgt?.id ? C.accent : C.blue),
                ],
              ),
            ),
          ),
      ],
    ));

    // Я
    final acc = s.shownAccuracy;
    final dr = s.deadReckoning;
    if (acc != null && acc > 0) {
      children.add(_live((dp, dh) => CircleLayer(circles: [
            CircleMarker(
              point: dp,
              radius: acc,
              useRadiusInMeter: true,
              color: dr ? const Color(0x1FFFB020) : const Color(0x294DA3FF),
              borderColor: dr ? const Color(0x99FFB020) : const Color(0x804DA3FF),
              borderStrokeWidth: 1.5,
            ),
          ])));
    }
    children.add(_live((dp, dh) => MarkerLayer(rotate: true, markers: [
          Marker(
            point: dp,
            width: 44,
            height: 44,
            child: dh == null
                ? Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dr ? C.grey : C.blue,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    margin: const EdgeInsets.all(12),
                  )
                : Transform.rotate(
                    angle: deg2rad(dh + _rotation),
                    child: CustomPaint(painter: _ArrowPainter(dr ? C.grey : C.blue)),
                  ),
          ),
        ])));

    final start = p ?? const LatLng(55.7558, 37.6173);
    return FlutterMap(
      mapController: _mc,
      options: MapOptions(
        initialCenter: start,
        initialZoom: 15,
        minZoom: 3,
        maxZoom: 20,
        backgroundColor: const Color(0xFF1B2226),
        onMapReady: () {
          _mapReady = true;
          _zoom = _mc.camera.zoom;
          if (_follow) _applyFollow();
          _maybeLoadGrades(force: true);
        },
        onPositionChanged: (camera, hasGesture) {
          _zoom = camera.zoom;
          _maybeLoadGrades();
          if (hasGesture) _onUserGesture();
        },
        onLongPress: (tapPosition, point) =>
            showPointDialog(context, s, lat: point.latitude, lon: point.longitude),
      ),
      children: children,
    );
  }

  // ---------- Панели ----------

  Widget _targetCard() {
    final p = s.pos;
    final t = s.target;
    if (p == null || t == null) return const SizedBox.shrink();
    final dist = distanceM(p, t.pos);
    final brg = bearingDeg(p, t.pos);
    return GestureDetector(
      onTap: () => openPointEditor(context, s, t),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(color: Color(0xFF2A2310), shape: BoxShape.circle),
              child: ValueListenableBuilder<_Disp?>(
                valueListenable: _disp,
                builder: (context, d, _) => Transform.rotate(
                  angle: deg2rad(brg + _rotation),
                  child: const Icon(Icons.navigation, color: C.accent, size: 40),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('До цели · ${t.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: C.text2)),
                  Text(fmtDist(dist),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.text, height: 1.1)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('азимут', style: TextStyle(fontSize: 12, color: C.text2)),
                Text('${brg.round()}°',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.text)),
              ],
            ),
            IconButton(
              tooltip: 'Сбросить цель',
              onPressed: () => s.setTarget(null),
              icon: const Icon(Icons.close, color: C.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner() {
    if (s.locationError != null) {
      return Panel(
        border: C.red,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.gps_off, color: C.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(s.locationError!, style: const TextStyle(color: C.text))),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              await s.startLocation();
            },
            child: const Text('Настройки'),
          ),
        ]),
      );
    }
    if (s.deadReckoning) {
      final since = s.drStart == null ? Duration.zero : DateTime.now().difference(s.drStart!);
      return Panel(
        border: C.accent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: C.accent, size: 20),
          const SizedBox(width: 8),
          const Text('Нет GPS', style: TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('счисление по гироскопу · ${fmtClock(since)}',
                style: const TextStyle(color: Color(0xFFD5DAE0))),
          ),
        ]),
      );
    }
    if (s.pos == null) {
      return const Panel(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Поиск спутников…', style: TextStyle(color: C.text)),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _rightColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapButton(
          icon: Icons.navigation,
          tooltip: s.settings.headingUp ? 'Север вверху' : 'Курс вверху',
          active: !s.settings.headingUp,
          onTap: () {
            s.updateSettings((x) => x.headingUp = !x.headingUp);
            if (_follow) {
              _applyFollow();
            } else if (_mapReady && !s.settings.headingUp) {
              _mc.rotate(0);
            }
          },
          child: ValueListenableBuilder<_Disp?>(
            valueListenable: _disp,
            builder: (context, d, _) => Transform.rotate(
              angle: deg2rad(_rotation),
              child: CustomPaint(size: const Size(30, 30), painter: _NorthPainter()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        MapButton(icon: Icons.add, tooltip: 'Приблизить', onTap: () => _zoomBy(1)),
        const SizedBox(height: 8),
        MapButton(icon: Icons.remove, tooltip: 'Отдалить', onTap: () => _zoomBy(-1)),
        const SizedBox(height: 8),
        MapButton(
          icon: Icons.straighten,
          tooltip: 'Линейка по курсу',
          active: s.settings.ruler,
          onTap: () => s.updateSettings((x) => x.ruler = !x.ruler),
        ),
      ],
    );
  }

  Widget _infoRow() {
    final h = s.heading;
    final dr = s.deadReckoning;
    final acc = s.shownAccuracy;
    final srcColor = dr ? C.accent : (s.pos == null ? C.grey : C.green);
    final srcLabel = dr ? 'Счисление' : s.headingSource;
    Widget cell(String v, String l) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: C.text, height: 1)),
                const SizedBox(height: 3),
                Text(l, style: const TextStyle(fontSize: 11, color: C.text2)),
              ],
            ),
          ),
        );
    return Panel(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            cell('${dr ? '≈' : ''}${(s.speed * 3.6).round()}', 'км/ч'),
            const VerticalDivider(width: 1, color: C.panelBorder),
            cell(h == null ? '—' : '${h.round()}°', 'курс'),
            const VerticalDivider(width: 1, color: C.panelBorder),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Container(
                          width: 8, height: 8, decoration: BoxDecoration(color: srcColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(srcLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: srcColor)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(acc == null ? 'точность —' : 'точность ±${acc.round()} м',
                        style: const TextStyle(fontSize: 12, color: C.text2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buttonsRow() {
    Widget btn(Widget w) => Expanded(child: w);
    final recDur = s.recStart == null ? Duration.zero : DateTime.now().difference(s.recStart!);
    return Row(
      children: [
        btn(MapButton(icon: Icons.menu, tooltip: 'Меню', onTap: _openMenu, size: 56)),
        const SizedBox(width: 8),
        btn(MapButton(
          icon: Icons.my_location,
          tooltip: 'Следовать за мной',
          active: _follow,
          size: 56,
          onTap: () => _setFollow(true),
        )),
        const SizedBox(width: 8),
        btn(MapButton(
          icon: Icons.add_location_alt_outlined,
          tooltip: 'Поставить точку здесь',
          size: 56,
          onTap: () {
            final p = s.pos;
            if (p == null) {
              toast(context, 'Позиция ещё не определена. Точку можно поставить долгим нажатием на карте.');
              return;
            }
            showPointDialog(context, s, lat: p.latitude, lon: p.longitude);
          },
        )),
        const SizedBox(width: 8),
        btn(MapButton(
          icon: Icons.fiber_manual_record,
          tooltip: s.recording ? 'Остановить запись' : 'Начать запись трека',
          borderColor: s.recording ? C.red : null,
          size: 56,
          onTap: _toggleRecording,
          child: s.recording
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 12, height: 12, decoration: const BoxDecoration(color: C.red, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(fmtClock(recDur),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text)),
                ])
              : const Icon(Icons.fiber_manual_record, color: C.red, size: 22),
        )),
      ],
    );
  }

  Future<void> _toggleRecording() async {
    if (!s.recording) {
      await s.startRecording();
      toast(context, 'Запись трека начата');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Остановить запись?'),
        content: Text('Записано точек: ${s.rec.length}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Продолжить')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Остановить')),
        ],
      ),
    );
    if (ok != true) return;
    final t = await s.stopRecording();
    toast(context, t == null ? 'Трек слишком короткий, не сохранён' : 'Сохранено: ${t.name}');
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.bg,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Точки'),
              subtitle: Text('${s.points.length} шт.'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => PointsScreen(state: s)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Карты и треки'),
              subtitle: Text('${s.maps.length} карт · ${s.tracks.length} треков'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryScreen(state: s)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Слои карты'),
              onTap: () {
                Navigator.pop(c);
                showLayersSheet(context, s);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти из навигатора?'),
        content: s.recording ? const Text('Идёт запись трека — она будет остановлена и сохранена.') : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Остаться')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok != true) return;
    if (s.recording) await s.stopRecording();
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: _map()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _targetCard(),
                    if (s.target != null && s.pos != null) const SizedBox(height: 8),
                    _banner(),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.topRight, child: _rightColumn()),
                    const Spacer(),
                    _infoRow(),
                    const SizedBox(height: 8),
                    _buttonsRow(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final hgt = size.height;
    final path = Path()
      ..moveTo(w / 2, hgt * 0.08)
      ..lineTo(w * 0.84, hgt * 0.88)
      ..lineTo(w / 2, hgt * 0.7)
      ..lineTo(w * 0.16, hgt * 0.88)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color;
}

class _NorthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(cx, h * 0.1)
          ..lineTo(cx + 5, h / 2)
          ..lineTo(cx - 5, h / 2)
          ..close(),
        Paint()..color = C.red);
    canvas.drawPath(
        Path()
          ..moveTo(cx, h * 0.9)
          ..lineTo(cx - 5, h / 2)
          ..lineTo(cx + 5, h / 2)
          ..close(),
        Paint()..color = C.text2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
