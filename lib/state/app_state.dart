import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/gpx.dart';
import '../data/mbtiles.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../nav/geo.dart';
import '../nav/heading_filter.dart';

const List<int> kTrackColors = [
  0xFFB07CFF,
  0xFF5FD38D,
  0xFFFF8A3D,
  0xFF3DD6D0,
  0xFFFF6FA8,
  0xFFE6D84A,
];

class AppState extends ChangeNotifier {
  final Storage storage = Storage();
  final HeadingFilter headingFilter = HeadingFilter();

  bool ready = false;
  String? locationError;

  // Позиция
  LatLng? pos;
  double? accuracy; // м
  double speed = 0; // м/с
  double? altitude;
  DateTime? lastFix;
  bool deadReckoning = false;
  DateTime? drStart;
  double drAccuracy = 0;

  // Данные
  List<Waypoint> points = [];
  List<Track> tracks = [];
  List<MapInfo> maps = [];
  Settings settings = Settings();
  MbTilesSource? _mbSource;
  String? _mbSourceId;

  // Запись трека
  bool recording = false;
  DateTime? recStart;
  final List<TrackPoint> rec = [];
  Timer? _autosave;

  StreamSubscription<Position>? _posSub;
  Timer? _tick;
  DateTime _lastTick = DateTime.now();
  int _idSeq = 0;

  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  double? get heading => headingFilter.heading;
  String get headingSource => headingFilter.source;

  Waypoint? get target {
    final id = settings.targetId;
    if (id == null) return null;
    for (final p in points) {
      if (p.id == id) return p;
    }
    return null;
  }

  MapInfo? get currentMap {
    final id = settings.mapId;
    if (id == null) return null;
    for (final m in maps) {
      if (m.id == id) return m;
    }
    return null;
  }

  MbTilesSource? get mbSource {
    final m = currentMap;
    if (m == null) return null;
    if (_mbSourceId != m.id) {
      _mbSource?.close();
      _mbSource = MbTilesSource(storage.mapPath(m));
      _mbSourceId = m.id;
    }
    return _mbSource;
  }

  Future<void> init() async {
    await storage.init();
    points = await storage.loadPoints();
    tracks = await storage.loadTracks();
    maps = await storage.loadMaps();
    settings = await storage.loadSettings();
    await _recoverRecording();
    headingFilter.start();
    ready = true;
    notifyListeners();
    await startLocation();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _autosave?.cancel();
    _posSub?.cancel();
    headingFilter.dispose();
    super.dispose();
  }

  // ---------- Геопозиция ----------

  Future<void> startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationError = 'Геолокация выключена в настройках телефона';
        notifyListeners();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        locationError = 'Нет доступа к геопозиции';
        notifyListeners();
        return;
      }
      locationError = null;
      await _posSub?.cancel();
      final LocationSettings ls;
      if (Platform.isAndroid) {
        ls = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: recording
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'Идёт запись трека',
                  notificationText: 'Навигатор пишет трек в фоне',
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        );
      } else if (Platform.isIOS) {
        ls = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: recording,
          showBackgroundLocationIndicator: recording,
        );
      } else {
        ls = const LocationSettings(accuracy: LocationAccuracy.best);
      }
      _posSub = Geolocator.getPositionStream(locationSettings: ls).listen(
        _onPosition,
        onError: (Object e) {
          locationError = 'Ошибка GPS: $e';
          notifyListeners();
        },
      );
      notifyListeners();
    } catch (e) {
      locationError = 'Ошибка GPS: $e';
      notifyListeners();
    }
  }

  void _onPosition(Position p) {
    pos = LatLng(p.latitude, p.longitude);
    accuracy = p.accuracy;
    speed = p.speed < 0 ? 0 : p.speed;
    altitude = p.altitude;
    lastFix = DateTime.now();
    deadReckoning = false;
    drStart = null;
    headingFilter.setStationary(speed < 0.3);
    if (p.heading >= 0 && speed >= 2) {
      headingFilter.onGps(p.heading, speed, p.headingAccuracy > 0 ? p.headingAccuracy : null);
    }
    if (recording && p.accuracy < 50) {
      final tp = TrackPoint(p.latitude, p.longitude, ele: p.altitude, time: DateTime.now().toUtc(), speed: speed);
      if (rec.isEmpty || distanceM(rec.last.pos, tp.pos) >= 2 || speed > 0.5) {
        rec.add(tp);
      }
    }
    notifyListeners();
  }

  void _onTick() {
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMilliseconds / 1000.0;
    _lastTick = now;
    headingFilter.refreshSource();
    final lf = lastFix;
    if (lf != null && now.difference(lf).inMilliseconds > 3000 && pos != null) {
      if (!deadReckoning) {
        deadReckoning = true;
        drStart = now;
        drAccuracy = accuracy ?? 10;
      }
      final h = heading;
      if (h != null && speed > 0.5 && dt > 0 && dt < 1) {
        final d = speed * dt;
        pos = offsetM(pos!, d, h);
        drAccuracy += 0.08 * d + 0.3 * dt;
      }
    }
    notifyListeners();
  }

  double? get shownAccuracy => deadReckoning ? drAccuracy : accuracy;

  // ---------- Настройки ----------

  void updateSettings(void Function(Settings s) f) {
    f(settings);
    storage.saveSettings(settings);
    notifyListeners();
  }

  // ---------- Точки ----------

  Waypoint addPoint(String name, double lat, double lon, {bool asTarget = false}) {
    final w = Waypoint(id: newId(), name: name, lat: lat, lon: lon);
    points.add(w);
    storage.savePoints(points);
    if (asTarget) {
      updateSettings((s) => s.targetId = w.id);
    } else {
      notifyListeners();
    }
    return w;
  }

  void updatePoint(Waypoint w, {String? name, double? lat, double? lon}) {
    if (name != null) w.name = name;
    if (lat != null) w.lat = lat;
    if (lon != null) w.lon = lon;
    storage.savePoints(points);
    notifyListeners();
  }

  void deletePoint(Waypoint w) {
    points.removeWhere((p) => p.id == w.id);
    storage.savePoints(points);
    if (settings.targetId == w.id) {
      updateSettings((s) => s.targetId = null);
    } else {
      notifyListeners();
    }
  }

  void setTarget(Waypoint? w) => updateSettings((s) => s.targetId = w?.id);

  String nextPointName() => 'Точка ${points.length + 1}';

  // ---------- Запись трека ----------

  Future<void> startRecording() async {
    if (recording) return;
    recording = true;
    recStart = DateTime.now();
    rec.clear();
    _autosave = Timer.periodic(const Duration(seconds: 30), (_) => _writeRecovery());
    await startLocation();
    notifyListeners();
  }

  Future<Track?> stopRecording() async {
    if (!recording) return null;
    recording = false;
    _autosave?.cancel();
    _autosave = null;
    Track? t;
    if (rec.length >= 2) {
      final start = recStart ?? DateTime.now();
      final name = 'Запись ${_two(start.day)}.${_two(start.month)}.${start.year} ${_two(start.hour)}:${_two(start.minute)}';
      t = await _saveTrack(name, List.of(rec), 'rec', 0xFF4DA3FF);
    }
    rec.clear();
    recStart = null;
    try {
      if (await storage.recoveryFile.exists()) await storage.recoveryFile.delete();
    } catch (_) {}
    await startLocation();
    notifyListeners();
    return t;
  }

  Future<void> _writeRecovery() async {
    if (rec.length < 2) return;
    try {
      await storage.recoveryFile.writeAsString(writeGpx('Восстановленная запись', rec));
    } catch (_) {}
  }

  Future<void> _recoverRecording() async {
    try {
      final f = storage.recoveryFile;
      if (!await f.exists()) return;
      final parsed = parseGeoFile(await f.readAsString(), 'Восстановленная запись');
      if (parsed.tracks.isNotEmpty) {
        await _saveTrack('Восстановленная запись', parsed.tracks.first.points, 'rec', 0xFF4DA3FF);
      }
      await f.delete();
    } catch (_) {}
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  Future<Track> _saveTrack(String name, List<TrackPoint> pts, String source, int color) async {
    final id = newId();
    final fileName = '$id.gpx';
    await File('${storage.tracksDir.path}/$fileName').writeAsString(writeGpx(name, pts));
    final t = Track(id: id, name: name, fileName: fileName, source: source, color: color, points: pts);
    tracks.insert(0, t);
    await storage.saveTracks(tracks);
    return t;
  }

  // ---------- Треки ----------

  /// Импорт GPX/KML. Возвращает (кол-во треков, кол-во точек).
  Future<(int, int)> importGeoFile(String path) async {
    final file = File(path);
    final content = await file.readAsString();
    var base = path.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final parsed = parseGeoFile(content, base);
    var ci = tracks.where((t) => t.source == 'import').length;
    for (final pt in parsed.tracks) {
      await _saveTrack(pt.name, pt.points, 'import', kTrackColors[ci % kTrackColors.length]);
      ci++;
    }
    for (final w in parsed.waypoints) {
      points.add(Waypoint(id: newId(), name: w.name, lat: w.lat, lon: w.lon));
    }
    if (parsed.waypoints.isNotEmpty) await storage.savePoints(points);
    notifyListeners();
    return (parsed.tracks.length, parsed.waypoints.length);
  }

  void setTrackVisible(Track t, bool v) {
    t.visible = v;
    storage.saveTracks(tracks);
    notifyListeners();
  }

  Future<void> deleteTrack(Track t) async {
    tracks.removeWhere((x) => x.id == t.id);
    try {
      await File(storage.trackPath(t)).delete();
    } catch (_) {}
    await storage.saveTracks(tracks);
    notifyListeners();
  }

  // ---------- Карты ----------

  Future<MapInfo> importMap(String path) async {
    final src = File(path);
    var base = path.split(Platform.pathSeparator).last;
    final id = newId();
    final fileName = '$id.mbtiles';
    final dst = File('${storage.mapsDir.path}/$fileName');
    await src.copy(dst.path);
    final (name, minZ, maxZ) = await MbTilesSource.readMeta(dst.path);
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final m = MapInfo(
      id: id,
      name: (name == null || name.trim().isEmpty) ? base : name,
      fileName: fileName,
      minZoom: minZ,
      maxZoom: maxZ,
      sizeBytes: await dst.length(),
    );
    maps.add(m);
    await storage.saveMaps(maps);
    updateSettings((s) => s.mapId = m.id);
    return m;
  }

  void selectMap(MapInfo? m) => updateSettings((s) => s.mapId = m?.id);

  Future<void> deleteMap(MapInfo m) async {
    if (_mbSourceId == m.id) {
      await _mbSource?.close();
      _mbSource = null;
      _mbSourceId = null;
    }
    maps.removeWhere((x) => x.id == m.id);
    try {
      await File(storage.mapPath(m)).delete();
    } catch (_) {}
    await storage.saveMaps(maps);
    if (settings.mapId == m.id) {
      updateSettings((s) => s.mapId = null);
    } else {
      notifyListeners();
    }
  }
}
