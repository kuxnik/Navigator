import 'package:latlong2/latlong.dart';

import '../nav/geo.dart';

class Waypoint {
  Waypoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  final String id;
  String name;
  double lat;
  double lon;
  final DateTime created;

  LatLng get pos => LatLng(lat, lon);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
        'created': created.toIso8601String(),
      };

  static Waypoint fromJson(Map<String, dynamic> j) => Waypoint(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        created: DateTime.tryParse(j['created'] as String? ?? ''),
      );
}

class TrackPoint {
  const TrackPoint(this.lat, this.lon, {this.ele, this.time, this.speed});

  final double lat;
  final double lon;
  final double? ele;
  final DateTime? time;

  /// м/с, если записана в файле
  final double? speed;

  LatLng get pos => LatLng(lat, lon);
}

class TrackStats {
  TrackStats({
    required this.distance,
    required this.total,
    required this.moving,
    required this.maxSpeed,
    required this.avgMoving,
    required this.eleMin,
    required this.eleMax,
  });

  final double distance; // м
  final Duration? total;
  final Duration? moving;
  final double? maxSpeed; // м/с
  final double? avgMoving; // м/с
  final double? eleMin;
  final double? eleMax;

  static TrackStats compute(List<TrackPoint> pts) {
    double dist = 0;
    double movDist = 0;
    double movSec = 0;
    double? maxSp;
    double? eMin;
    double? eMax;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      if (p.ele != null) {
        eMin = eMin == null ? p.ele : (p.ele! < eMin ? p.ele : eMin);
        eMax = eMax == null ? p.ele : (p.ele! > eMax ? p.ele : eMax);
      }
      if (i == 0) continue;
      final q = pts[i - 1];
      final d = distanceM(q.pos, p.pos);
      dist += d;
      double? sp = p.speed;
      double? dt;
      if (p.time != null && q.time != null) {
        dt = p.time!.difference(q.time!).inMilliseconds / 1000.0;
        if (sp == null && dt > 0) sp = d / dt;
      }
      if (sp != null && sp < 70) {
        if (maxSp == null || sp > maxSp) maxSp = sp;
      }
      if (dt != null && dt > 0 && sp != null && sp > 0.5) {
        movDist += d;
        movSec += dt;
      }
    }
    Duration? total;
    final t0 = pts.isEmpty ? null : pts.first.time;
    final t1 = pts.isEmpty ? null : pts.last.time;
    if (t0 != null && t1 != null) total = t1.difference(t0);
    return TrackStats(
      distance: dist,
      total: total,
      moving: movSec > 0 ? Duration(seconds: movSec.round()) : null,
      maxSpeed: maxSp,
      avgMoving: movSec > 0 ? movDist / movSec : null,
      eleMin: eMin,
      eleMax: eMax,
    );
  }
}

class Track {
  Track({
    required this.id,
    required this.name,
    required this.fileName,
    required this.source,
    this.visible = true,
    this.color = 0xFF4DA3FF,
    this.points = const [],
  });

  final String id;
  String name;
  final String fileName;

  /// 'rec' — записан в приложении, 'import' — импорт
  final String source;
  bool visible;
  int color;
  List<TrackPoint> points;
  TrackStats? _stats;

  TrackStats get stats => _stats ??= TrackStats.compute(points);
  void resetStats() => _stats = null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'file': fileName,
        'source': source,
        'visible': visible,
        'color': color,
      };

  static Track fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        name: j['name'] as String,
        fileName: j['file'] as String,
        source: j['source'] as String? ?? 'import',
        visible: j['visible'] as bool? ?? true,
        color: j['color'] as int? ?? 0xFF4DA3FF,
      );
}

class MapInfo {
  MapInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.minZoom,
    required this.maxZoom,
    required this.sizeBytes,
  });

  final String id;
  String name;
  final String fileName;
  final int minZoom;
  final int maxZoom;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'file': fileName,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'size': sizeBytes,
      };

  static MapInfo fromJson(Map<String, dynamic> j) => MapInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        fileName: j['file'] as String,
        minZoom: j['minZoom'] as int? ?? 0,
        maxZoom: j['maxZoom'] as int? ?? 18,
        sizeBytes: j['size'] as int? ?? 0,
      );

  String get sizeText {
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1).replaceAll('.', ',')} ГБ';
    return '${mb.round()} МБ';
  }
}

class Settings {
  String? mapId; // null — онлайн OSM
  bool osmTraces = false;
  bool mineLayer = true;
  bool carOnly = false;
  bool ruler = true;
  bool headingUp = true;
  String? targetId;

  Map<String, dynamic> toJson() => {
        'mapId': mapId,
        'osmTraces': osmTraces,
        'mineLayer': mineLayer,
        'carOnly': carOnly,
        'ruler': ruler,
        'headingUp': headingUp,
        'targetId': targetId,
      };

  static Settings fromJson(Map<String, dynamic> j) => Settings()
    ..mapId = j['mapId'] as String?
    ..osmTraces = j['osmTraces'] as bool? ?? false
    ..mineLayer = j['mineLayer'] as bool? ?? true
    ..carOnly = j['carOnly'] as bool? ?? false
    ..ruler = j['ruler'] as bool? ?? true
    ..headingUp = j['headingUp'] as bool? ?? true
    ..targetId = j['targetId'] as String?;
}
