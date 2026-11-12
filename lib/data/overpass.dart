import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Проходимость грунтовки по тегам OSM.
enum Grade { good, medium, hard, unknown }

class OsmWay {
  OsmWay(this.id, this.points, this.grade);
  final int id;
  final List<LatLng> points;
  final Grade grade;
}

Grade classifyWay(Map<String, dynamic> tags) {
  final tt = tags['tracktype']?.toString();
  final sm = tags['smoothness']?.toString();
  if (tags['4wd_only'] == 'yes' ||
      tt == 'grade4' ||
      tt == 'grade5' ||
      sm == 'horrible' ||
      sm == 'very_horrible' ||
      sm == 'impassable') {
    return Grade.hard;
  }
  if (tt == 'grade3' || sm == 'bad' || sm == 'very_bad') return Grade.medium;
  if (tt == 'grade1' || tt == 'grade2' || sm == 'good' || sm == 'intermediate' || sm == 'excellent') {
    return Grade.good;
  }
  return Grade.unknown;
}

/// Грунтовые дороги из OpenStreetMap (Overpass API) для видимой области.
class OverpassTracks extends ChangeNotifier {
  static const _servers = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  final Map<int, OsmWay> ways = {};
  final List<List<double>> _loaded = []; // [s, w, n, e]
  bool loading = false;
  String? error;
  int version = 0;
  int lastCount = -1; // сколько дорог пришло в последнем ответе // растёт при каждом изменении набора дорог

  bool covered(double s, double w, double n, double e) {
    for (final b in _loaded) {
      if (s >= b[0] && w >= b[1] && n <= b[2] && e <= b[3]) return true;
    }
    return false;
  }

  /// Подгрузить дороги для области, если её ещё нет в кэше.
  Future<void> ensure(double s, double w, double n, double e) async {
    if (loading || covered(s, w, n, e)) return;
    // С запасом, чтобы не дёргать сервер при каждом сдвиге карты.
    final dLat = (n - s) * 0.5;
    final dLon = (e - w) * 0.5;
    s -= dLat;
    n += dLat;
    w -= dLon;
    e += dLon;
    if ((n - s) > 0.6 || (e - w) > 1.0) return; // слишком большая область
    loading = true;
    error = null;
    notifyListeners();
    final bbox = '${s.toStringAsFixed(5)},${w.toStringAsFixed(5)},${n.toStringAsFixed(5)},${e.toStringAsFixed(5)}';
    final q = '[out:json][timeout:30];'
        '(way["highway"="track"]($bbox);way["4wd_only"="yes"]($bbox););'
        'out tags geom;';
    Object? lastErr;
    for (final url in _servers) {
      try {
        final r = await http
            .post(Uri.parse(url), body: {'data': q}, headers: {'User-Agent': 'ru.kuxnik.navigator'})
            .timeout(const Duration(seconds: 45));
        if (r.statusCode != 200) {
          lastErr = 'сервер ответил ${r.statusCode}';
          continue;
        }
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final els = (j['elements'] as List?) ?? const [];
        final remark = j['remark']?.toString();
        if (els.isEmpty && remark != null && remark.isNotEmpty) {
          lastErr = remark;
          continue;
        }
        var cnt = 0;
        for (final el in els) {
          if (el is! Map || el['type'] != 'way') continue;
          final geom = el['geometry'];
          if (geom is! List || geom.length < 2) continue;
          final pts = <LatLng>[
            for (final g in geom)
              if (g is Map && g['lat'] != null && g['lon'] != null)
                LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()),
          ];
          if (pts.length < 2) continue;
          final tags = Map<String, dynamic>.from((el['tags'] as Map?) ?? const {});
          final id = (el['id'] as num).toInt();
          ways[id] = OsmWay(id, pts, classifyWay(tags));
          cnt++;
        }
        lastCount = cnt;
        _loaded.add([s, w, n, e]);
        lastErr = null;
        break;
      } catch (err) {
        lastErr = err;
      }
    }
    loading = false;
    error = lastErr == null ? null : 'Не удалось загрузить грунтовки: $lastErr';
    version++;
    notifyListeners();
  }
}
