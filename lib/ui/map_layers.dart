import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/mbtiles.dart';
import '../data/models.dart';
import '../nav/geo.dart';
import '../state/app_state.dart';

const String kUserAgent = 'ru.kuxnik.navigator';

/// Подложка: выбранная карта .mbtiles или онлайн OSM, если карт нет.
Widget baseTileLayer(AppState s) {
  final m = s.currentMap;
  final src = s.mbSource;
  if (m != null && src != null) {
    return TileLayer(
      key: ValueKey('mb_${m.id}'),
      urlTemplate: 'mbtiles://{z}/{x}/{y}',
      tileProvider: MbTilesTileProvider(src),
      minNativeZoom: m.minZoom,
      maxNativeZoom: m.maxZoom,
      maxZoom: 20,
      userAgentPackageName: kUserAgent,
    );
  }
  return TileLayer(
    key: const ValueKey('osm'),
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxNativeZoom: 19,
    maxZoom: 20,
    userAgentPackageName: kUserAgent,
  );
}

/// Слой публичных GPS-треков OpenStreetMap («здесь кто-то был»).
Widget osmTracesLayer() => TileLayer(
      key: const ValueKey('osm_gps'),
      urlTemplate: 'https://gps.tile.openstreetmap.org/lines/{z}/{x}/{y}.png',
      maxNativeZoom: 20,
      maxZoom: 20,
      userAgentPackageName: kUserAgent,
    );

final Map<String, List<List<LatLng>>> _trackCache = {};

/// Линии трека для отрисовки: прорежено (не чаще 3 м), при [carOnly] —
/// только участки быстрее 15 км/ч.
List<List<LatLng>> trackRuns(Track t, {required bool carOnly}) {
  final key = '${t.id}_${t.points.length}_$carOnly';
  final cached = _trackCache[key];
  if (cached != null) return cached;
  final runs = <List<LatLng>>[];
  final pts = t.points;
  if (!carOnly) {
    final run = <LatLng>[];
    LatLng? last;
    for (final p in pts) {
      final ll = p.pos;
      if (last == null || distanceM(last, ll) >= 3) {
        run.add(ll);
        last = ll;
      }
    }
    if (pts.isNotEmpty && (run.isEmpty || run.last != pts.last.pos)) run.add(pts.last.pos);
    if (run.length >= 2) runs.add(run);
  } else {
    var run = <LatLng>[];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      double? sp = b.speed;
      if (sp == null && a.time != null && b.time != null) {
        final dt = b.time!.difference(a.time!).inMilliseconds / 1000.0;
        if (dt > 0) sp = distanceM(a.pos, b.pos) / dt;
      }
      final fast = sp != null && sp > 4.2;
      if (fast) {
        if (run.isEmpty) run.add(a.pos);
        run.add(b.pos);
      } else if (run.isNotEmpty) {
        if (run.length >= 2) runs.add(run);
        run = <LatLng>[];
      }
    }
    if (run.length >= 2) runs.add(run);
  }
  _trackCache[key] = runs;
  return runs;
}

List<Polyline> trackPolylines(Track t, {required bool carOnly, double width = 3.5}) {
  return [
    for (final r in trackRuns(t, carOnly: carOnly))
      Polyline(
        points: r,
        strokeWidth: width,
        color: Color(t.color),
        borderStrokeWidth: 2,
        borderColor: const Color(0xFF0B0E10),
      ),
  ];
}
