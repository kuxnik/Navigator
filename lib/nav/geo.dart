import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const double kEarthR = 6371000.0;

double deg2rad(double d) => d * math.pi / 180.0;
double rad2deg(double r) => r * 180.0 / math.pi;

double wrap360(double d) {
  var x = d % 360.0;
  if (x < 0) x += 360.0;
  return x;
}

double wrap180(double d) {
  var x = wrap360(d);
  if (x > 180.0) x -= 360.0;
  return x;
}

/// Расстояние по большому кругу, метры.
double distanceM(LatLng a, LatLng b) {
  final p1 = deg2rad(a.latitude);
  final p2 = deg2rad(b.latitude);
  final dp = p2 - p1;
  final dl = deg2rad(b.longitude - a.longitude);
  final h = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * kEarthR * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Азимут из a на b, градусы от севера по часовой.
double bearingDeg(LatLng a, LatLng b) {
  final p1 = deg2rad(a.latitude);
  final p2 = deg2rad(b.latitude);
  final dl = deg2rad(b.longitude - a.longitude);
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return wrap360(rad2deg(math.atan2(y, x)));
}

/// Точка на расстоянии [dist] метров по азимуту [brg].
LatLng offsetM(LatLng p, double dist, double brg) {
  final d = dist / kEarthR;
  final t = deg2rad(brg);
  final p1 = deg2rad(p.latitude);
  final l1 = deg2rad(p.longitude);
  final p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(t));
  final l2 = l1 + math.atan2(math.sin(t) * math.sin(d) * math.cos(p1), math.cos(d) - math.sin(p1) * math.sin(p2));
  return LatLng(rad2deg(p2), wrap180(rad2deg(l2)));
}

/// Метров на логический пиксель при данном зуме (тайлы 256).
double metersPerPixel(double lat, double zoom) =>
    156543.03392 * math.cos(deg2rad(lat)) / math.pow(2, zoom);

String fmtDist(double m) {
  if (m < 1000) return '${m.round()} м';
  if (m < 10000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} км';
  return '${(m / 1000).round()} км';
}

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h ч ${m.toString().padLeft(2, '0')} мин';
  if (d.inMinutes > 0) return '${d.inMinutes} мин';
  return '${d.inSeconds} с';
}

String fmtClock(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String fmtCoord(double v) => v.toStringAsFixed(5);

double? parseCoord(String s) {
  final t = s.trim().replaceAll(',', '.');
  return double.tryParse(t);
}
