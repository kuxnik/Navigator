import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite/sqflite.dart';

/// Прозрачный PNG 1×1 — для отсутствующих тайлов.
final Uint8List _emptyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class MbTilesSource {
  MbTilesSource(this.path);

  final String path;
  Database? _db;
  Future<Database>? _opening;

  Future<Database> _open() {
    if (_db != null) return Future.value(_db!);
    return _opening ??= openDatabase(path, readOnly: true, singleInstance: false).then((d) {
      _db = d;
      return d;
    });
  }

  Future<Uint8List?> tile(int z, int x, int y) async {
    final db = await _open();
    final tmsY = (1 << z) - 1 - y;
    final rows = await db.rawQuery(
      'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1',
      [z, x, tmsY],
    );
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'];
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  /// Название и диапазон масштабов из файла.
  static Future<(String?, int, int)> readMeta(String path) async {
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      String? name;
      int? minZ;
      int? maxZ;
      try {
        final meta = await db.rawQuery('SELECT name, value FROM metadata');
        for (final r in meta) {
          final k = r['name']?.toString();
          final v = r['value']?.toString();
          if (k == 'name') name = v;
          if (k == 'minzoom') minZ = int.tryParse(v ?? '');
          if (k == 'maxzoom') maxZ = int.tryParse(v ?? '');
        }
      } catch (_) {}
      if (minZ == null || maxZ == null) {
        final r = await db.rawQuery('SELECT MIN(zoom_level) AS a, MAX(zoom_level) AS b FROM tiles');
        if (r.isNotEmpty) {
          minZ ??= (r.first['a'] as num?)?.toInt();
          maxZ ??= (r.first['b'] as num?)?.toInt();
        }
      }
      return (name, minZ ?? 0, maxZ ?? 18);
    } finally {
      await db.close();
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}

class MbTilesTileProvider extends TileProvider {
  MbTilesTileProvider(this.source);

  final MbTilesSource source;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MbTilesImage(source, coordinates.z, coordinates.x, coordinates.y);
}

@immutable
class MbTilesImage extends ImageProvider<MbTilesImage> {
  const MbTilesImage(this.source, this.z, this.x, this.y);

  final MbTilesSource source;
  final int z;
  final int x;
  final int y;

  @override
  Future<MbTilesImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MbTilesImage>(this);

  @override
  ImageStreamCompleter loadImage(MbTilesImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    Uint8List? bytes;
    try {
      bytes = await source.tile(z, x, y);
    } catch (_) {
      bytes = null;
    }
    final buf = await ui.ImmutableBuffer.fromUint8List(bytes ?? _emptyPng);
    try {
      return await decode(buf);
    } catch (_) {
      return decode(await ui.ImmutableBuffer.fromUint8List(_emptyPng));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MbTilesImage && other.source.path == source.path && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(source.path, z, x, y);
}
