import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'gpx.dart';
import 'models.dart';

class Storage {
  late Directory root;
  late Directory tracksDir;
  late Directory mapsDir;

  Future<void> init() async {
    root = await getApplicationDocumentsDirectory();
    tracksDir = Directory('${root.path}/tracks');
    mapsDir = Directory('${root.path}/maps');
    await tracksDir.create(recursive: true);
    await mapsDir.create(recursive: true);
  }

  File _f(String name) => File('${root.path}/$name');

  Future<dynamic> _readJson(String name) async {
    final f = _f(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String name, Object data) async {
    final f = _f(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path);
  }

  Future<List<Waypoint>> loadPoints() async {
    final j = await _readJson('points.json');
    if (j is! List) return [];
    return j.map((e) => Waypoint.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> savePoints(List<Waypoint> pts) => _writeJson('points.json', pts.map((e) => e.toJson()).toList());

  Future<List<Track>> loadTracks() async {
    final j = await _readJson('tracks.json');
    if (j is! List) return [];
    final out = <Track>[];
    for (final e in j) {
      final t = Track.fromJson(Map<String, dynamic>.from(e as Map));
      final f = File('${tracksDir.path}/${t.fileName}');
      if (!await f.exists()) continue;
      try {
        final parsed = parseGeoFile(await f.readAsString(), t.name);
        t.points = parsed.tracks.isEmpty ? [] : parsed.tracks.expand((p) => p.points).toList();
      } catch (_) {
        t.points = [];
      }
      out.add(t);
    }
    return out;
  }

  Future<void> saveTracks(List<Track> tracks) =>
      _writeJson('tracks.json', tracks.map((e) => e.toJson()).toList());

  Future<List<MapInfo>> loadMaps() async {
    final j = await _readJson('maps.json');
    if (j is! List) return [];
    final out = <MapInfo>[];
    for (final e in j) {
      final m = MapInfo.fromJson(Map<String, dynamic>.from(e as Map));
      if (await File(mapPath(m)).exists()) out.add(m);
    }
    return out;
  }

  Future<void> saveMaps(List<MapInfo> maps) => _writeJson('maps.json', maps.map((e) => e.toJson()).toList());

  Future<Settings> loadSettings() async {
    final j = await _readJson('settings.json');
    if (j is! Map) return Settings();
    return Settings.fromJson(Map<String, dynamic>.from(j));
  }

  Future<void> saveSettings(Settings s) => _writeJson('settings.json', s.toJson());

  String mapPath(MapInfo m) => '${mapsDir.path}/${m.fileName}';
  String trackPath(Track t) => '${tracksDir.path}/${t.fileName}';

  File get recoveryFile => _f('recording.gpx');
}
