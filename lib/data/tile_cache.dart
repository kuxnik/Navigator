import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

final Uint8List _emptyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// Постоянный кэш онлайн-тайлов на телефоне: тайл, скачанный один раз,
/// дальше берётся с диска и без интернета, повторно не загружается.
class TileCache {
  TileCache._();

  static Directory? _root;
  static final http.Client _client = http.Client();

  static Future<Directory> root() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    _root = Directory('${base.path}/tiles');
    await _root!.create(recursive: true);
    return _root!;
  }

  static Future<Uint8List?> get(String layer, int z, int x, int y, String url, String userAgent) async {
    final dir = await root();
    final f = File('${dir.path}/$layer/$z/$x/$y.tile');
    if (await f.exists()) {
      try {
        final b = await f.readAsBytes();
        if (b.isNotEmpty) return b;
      } catch (_) {}
    }
    try {
      final r = await _client
          .get(Uri.parse(url), headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      final bytes = r.bodyBytes;
      // Сохраняем в фоне; через временный файл, чтобы не оставить битый тайл.
      () async {
        try {
          await f.parent.create(recursive: true);
          final tmp = File('${f.path}.part');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(f.path);
        } catch (_) {}
      }();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Размер кэша в байтах.
  static Future<int> size() async {
    final dir = await root();
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<void> clear() async {
    final dir = await root();
    if (await dir.exists()) await dir.delete(recursive: true);
    _root = null;
    PaintingBinding.instance.imageCache.clear();
  }
}

/// Тайлы из сети с постоянным кэшем на диске.
class CachedTileProvider extends TileProvider {
  CachedTileProvider(this.layer, this.userAgent);

  /// Имя папки кэша для этого слоя.
  final String layer;
  final String userAgent;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedTileImage(layer, coordinates.z, coordinates.x, coordinates.y, url, userAgent);
  }
}

@immutable
class CachedTileImage extends ImageProvider<CachedTileImage> {
  const CachedTileImage(this.layer, this.z, this.x, this.y, this.url, this.userAgent);

  final String layer;
  final int z;
  final int x;
  final int y;
  final String url;
  final String userAgent;

  @override
  Future<CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedTileImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await TileCache.get(layer, z, x, y, url, userAgent);
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes ?? _emptyPng));
    } catch (_) {
      return decode(await ui.ImmutableBuffer.fromUint8List(_emptyPng));
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedTileImage && other.layer == layer && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(layer, z, x, y);
}
