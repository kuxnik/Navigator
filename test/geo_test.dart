import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigator/data/gpx.dart';
import 'package:navigator/nav/geo.dart';

void main() {
  test('расстояние и азимут', () {
    const a = LatLng(55.0, 37.0);
    final b = offsetM(a, 1000, 90);
    expect(distanceM(a, b), closeTo(1000, 1));
    expect(bearingDeg(a, b), closeTo(90, 0.5));
  });

  test('wrap180', () {
    expect(wrap180(350), -10);
    expect(wrap180(-190), 170);
  });

  test('разбор GPX со скоростью из расширений', () {
    const gpx = '''<gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"><trk><name>Тест</name><trkseg>
<trkpt lat="55.1" lon="37.1"><ele>172</ele><time>2026-10-17T06:26:41Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:speed>3.5</gpxtpx:speed></gpxtpx:TrackPointExtension></extensions></trkpt>
<trkpt lat="55.2" lon="37.2"><ele>180</ele><time>2026-10-17T06:26:42Z</time></trkpt>
</trkseg></trk><wpt lat="55.3" lon="37.3"><name>Родник</name></wpt></gpx>''';
    final r = parseGeoFile(gpx, 'file');
    expect(r.tracks.length, 1);
    expect(r.tracks.first.name, 'Тест');
    expect(r.tracks.first.points.first.speed, 3.5);
    expect(r.waypoints.single.name, 'Родник');
  });
}
