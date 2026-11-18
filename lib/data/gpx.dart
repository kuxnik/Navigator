import 'package:xml/xml.dart';

import 'models.dart';

class ParsedTrack {
  ParsedTrack(this.name, this.points);
  final String name;
  final List<TrackPoint> points;
}

class ParsedWaypoint {
  ParsedWaypoint(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;
}

class ParsedGeo {
  final List<ParsedTrack> tracks = [];
  final List<ParsedWaypoint> waypoints = [];
}

Iterable<XmlElement> _desc(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

XmlElement? _child(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

String? _childText(XmlElement e, String local) {
  final c = _child(e, local);
  final t = c?.innerText.trim();
  return (t == null || t.isEmpty) ? null : t;
}

double? _d(String? s) => s == null ? null : double.tryParse(s.trim());

/// Разбор GPX или KML. [fallbackName] — имя файла без расширения.
ParsedGeo parseGeoFile(String content, String fallbackName) {
  final doc = XmlDocument.parse(content);
  final root = doc.rootElement.name.local.toLowerCase();
  if (root == 'kml') return _parseKml(doc, fallbackName);
  return _parseGpx(doc, fallbackName);
}

TrackPoint? _gpxPoint(XmlElement p) {
  final lat = _d(p.getAttribute('lat'));
  final lon = _d(p.getAttribute('lon'));
  if (lat == null || lon == null) return null;
  final ele = _d(_childText(p, 'ele'));
  final t = _childText(p, 'time');
  double? sp;
  for (final e in _desc(p, 'speed')) {
    sp = _d(e.innerText);
    if (sp != null) break;
  }
  return TrackPoint(lat, lon, ele: ele, time: t == null ? null : DateTime.tryParse(t), speed: sp);
}

ParsedGeo _parseGpx(XmlDocument doc, String fallbackName) {
  final out = ParsedGeo();
  var n = 0;
  for (final trk in _desc(doc, 'trk')) {
    n++;
    final name = _childText(trk, 'name') ?? (n == 1 ? fallbackName : '$fallbackName $n');
    final pts = <TrackPoint>[];
    for (final p in _desc(trk, 'trkpt')) {
      final tp = _gpxPoint(p);
      if (tp != null) pts.add(tp);
    }
    if (pts.length >= 2) out.tracks.add(ParsedTrack(name, pts));
  }
  for (final rte in _desc(doc, 'rte')) {
    n++;
    final name = _childText(rte, 'name') ?? '$fallbackName (маршрут)';
    final pts = <TrackPoint>[];
    for (final p in _desc(rte, 'rtept')) {
      final tp = _gpxPoint(p);
      if (tp != null) pts.add(tp);
    }
    if (pts.length >= 2) out.tracks.add(ParsedTrack(name, pts));
  }
  var w = 0;
  for (final wpt in _desc(doc, 'wpt')) {
    w++;
    final lat = _d(wpt.getAttribute('lat'));
    final lon = _d(wpt.getAttribute('lon'));
    if (lat == null || lon == null) continue;
    out.waypoints.add(ParsedWaypoint(_childText(wpt, 'name') ?? 'Точка $w', lat, lon));
  }
  return out;
}

List<TrackPoint> _kmlCoords(String text) {
  final pts = <TrackPoint>[];
  for (final tuple in text.trim().split(RegExp(r'\s+'))) {
    final parts = tuple.split(',');
    if (parts.length < 2) continue;
    final lon = _d(parts[0]);
    final lat = _d(parts[1]);
    if (lat == null || lon == null) continue;
    pts.add(TrackPoint(lat, lon, ele: parts.length > 2 ? _d(parts[2]) : null));
  }
  return pts;
}

ParsedGeo _parseKml(XmlDocument doc, String fallbackName) {
  final out = ParsedGeo();
  var n = 0;
  for (final pm in _desc(doc, 'Placemark')) {
    n++;
    final name = _childText(pm, 'name') ?? '$fallbackName $n';
    for (final ls in _desc(pm, 'LineString')) {
      final c = _child(ls, 'coordinates');
      if (c == null) continue;
      final pts = _kmlCoords(c.innerText);
      if (pts.length >= 2) out.tracks.add(ParsedTrack(name, pts));
    }
    // gx:Track
    for (final tr in _desc(pm, 'Track')) {
      final whens = _desc(tr, 'when').map((e) => DateTime.tryParse(e.innerText.trim())).toList();
      final coords = _desc(tr, 'coord').toList();
      final pts = <TrackPoint>[];
      for (var i = 0; i < coords.length; i++) {
        final parts = coords[i].innerText.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final lon = _d(parts[0]);
        final lat = _d(parts[1]);
        if (lat == null || lon == null) continue;
        pts.add(TrackPoint(lat, lon,
            ele: parts.length > 2 ? _d(parts[2]) : null, time: i < whens.length ? whens[i] : null));
      }
      if (pts.length >= 2) out.tracks.add(ParsedTrack(name, pts));
    }
    for (final pt in _desc(pm, 'Point')) {
      final c = _child(pt, 'coordinates');
      if (c == null) continue;
      final pts = _kmlCoords(c.innerText);
      if (pts.isNotEmpty) out.waypoints.add(ParsedWaypoint(name, pts.first.lat, pts.first.lon));
    }
  }
  return out;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String writeGpx(String name, List<TrackPoint> pts) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="Navigator" xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('<trk><name>${_esc(name)}</name><trkseg>');
  for (final p in pts) {
    b.write('<trkpt lat="${p.lat.toStringAsFixed(7)}" lon="${p.lon.toStringAsFixed(7)}">');
    if (p.ele != null) b.write('<ele>${p.ele!.toStringAsFixed(1)}</ele>');
    if (p.time != null) b.write('<time>${p.time!.toUtc().toIso8601String()}</time>');
    if (p.speed != null) b.write('<speed>${p.speed!.toStringAsFixed(2)}</speed>');
    b.writeln('</trkpt>');
  }
  b.writeln('</trkseg></trk></gpx>');
  return b.toString();
}
