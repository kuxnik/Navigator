import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../data/models.dart';
import '../nav/geo.dart';
import '../state/app_state.dart';
import 'library_screen.dart';
import 'map_layers.dart';
import 'theme.dart';

class TrackScreen extends StatelessWidget {
  const TrackScreen({super.key, required this.state, required this.track});

  final AppState state;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final pts = [for (final p in track.points) p.pos];
    final st = track.stats;
    String kmh(double? v) => v == null ? '—' : '${(v * 3.6).round()} км/ч';
    final ele = (st.eleMin != null && st.eleMax != null) ? '${st.eleMin!.round()}–${st.eleMax!.round()} м' : '—';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Трек'),
        actions: [
          IconButton(
            tooltip: 'Поделиться',
            icon: const Icon(Icons.ios_share),
            onPressed: () => shareTrack(state, track),
          ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Удалить «${track.name}»?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
                  ],
                ),
              );
              if (ok == true) {
                await state.deleteTrack(track);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: pts.length < 2
                ? const Center(child: Text('В треке нет точек', style: TextStyle(color: C.text2)))
                : FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(pts),
                        padding: const EdgeInsets.all(36),
                      ),
                      backgroundColor: const Color(0xFF1B2226),
                    ),
                    children: [
                      baseTileLayer(state),
                      PolylineLayer(polylines: trackPolylines(track, carOnly: false, width: 4)),
                      MarkerLayer(markers: [
                        Marker(
                          point: pts.first,
                          width: 22,
                          height: 22,
                          child: _dot(C.green),
                        ),
                        if (distanceM(pts.first, pts.last) > 30)
                          Marker(point: pts.last, width: 22, height: 22, child: _dot(C.red)),
                      ]),
                    ],
                  ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: C.bg,
              border: Border(top: BorderSide(color: C.panelBorder)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(track.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                    '${track.source == 'rec' ? 'Записан в приложении' : 'Импорт'} · ${track.points.length} точек',
                    style: const TextStyle(fontSize: 12, color: C.text2),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 2.4,
                    children: [
                      StatTile(value: fmtDist(st.distance), label: 'расстояние'),
                      StatTile(value: st.total == null ? '—' : fmtDuration(st.total!), label: 'всего'),
                      StatTile(value: st.moving == null ? '—' : fmtDuration(st.moving!), label: 'в движении'),
                      StatTile(value: kmh(st.avgMoving), label: 'средняя'),
                      StatTile(value: kmh(st.maxSpeed), label: 'максимум'),
                      StatTile(value: ele, label: 'высота'),
                    ],
                  ),
                  if (st.eleMin != null && st.eleMax != null && st.eleMax! - st.eleMin! > 1) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(10)),
                      child: CustomPaint(painter: _ElevationPainter(track.points)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: C.accent,
                          foregroundColor: const Color(0xFF1A1406),
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          state.setTrackVisible(track, true);
                          if (!state.settings.mineLayer) state.updateSettings((x) => x.mineLayer = true);
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                        icon: const Icon(Icons.map),
                        label: const Text('Показать на карте', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: C.bg, width: 3),
        ),
      );
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter(this.pts);

  final List<TrackPoint> pts;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = <double>[];
    final ys = <double>[];
    double dist = 0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) dist += distanceM(pts[i - 1].pos, pts[i].pos);
      final e = pts[i].ele;
      if (e == null) continue;
      xs.add(dist);
      ys.add(e);
    }
    if (xs.length < 2 || dist <= 0) return;
    // сглаживание скользящим средним
    final sm = <double>[];
    const w = 8;
    for (var i = 0; i < ys.length; i++) {
      var sum = 0.0;
      var n = 0;
      for (var j = i - w; j <= i + w; j++) {
        if (j < 0 || j >= ys.length) continue;
        sum += ys[j];
        n++;
      }
      sm.add(sum / n);
    }
    var mn = sm.first, mx = sm.first;
    for (final v in sm) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final span = (mx - mn).abs() < 1 ? 1.0 : mx - mn;
    Offset at(int i) => Offset(
          4 + (size.width - 8) * xs[i] / dist,
          6 + (size.height - 12) * (1 - (sm[i] - mn) / span),
        );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    final step = (sm.length / 400).ceil().clamp(1, 1000);
    for (var i = step; i < sm.length; i += step) {
      final o = at(i);
      line.lineTo(o.dx, o.dy);
    }
    final last = at(sm.length - 1);
    line.lineTo(last.dx, last.dy);
    final fill = Path.from(line)
      ..lineTo(last.dx, size.height)
      ..lineTo(4, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0xFF1E3A55));
    canvas.drawPath(
        line,
        Paint()
          ..color = C.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final tp = TextPainter(
      text: const TextSpan(text: 'высота по пути', style: TextStyle(fontSize: 11, color: C.text2)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(8, 4));
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) => old.pts != pts;
}
