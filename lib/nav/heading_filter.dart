import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import 'geo.dart';

/// Курс: гироскоп (поворот вокруг вертикали) + плавная поправка по GPS-курсу.
/// Магнитный компас — только для начального курса, пока не было GPS-курса.
class HeadingFilter {
  double? heading; // градусы от севера
  String source = 'нет курса';

  double _bias = 0; // рад/с, дрейф нуля гироскопа
  final List<double> _g = [0, 0, 9.81];
  bool _gInit = false;
  DateTime? _lastGyro;
  bool _gyroAlive = false;
  bool _hadGps = false;
  bool _stationary = false;
  DateTime? _lastGpsCourse;

  final List<StreamSubscription<dynamic>> _subs = [];

  void start() {
    try {
      _subs.add(accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen(_onAccel, onError: (_) {}, cancelOnError: false));
    } catch (_) {}
    try {
      _subs.add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen(_onGyro, onError: (_) {}, cancelOnError: false));
    } catch (_) {}
    try {
      _subs.add(magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(_onMag, onError: (_) {}, cancelOnError: false));
    } catch (_) {}
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// Машина стоит (по GPS) — можно уточнять дрейф гироскопа.
  void setStationary(bool v) => _stationary = v;

  void _onAccel(AccelerometerEvent e) {
    if (!_gInit) {
      _g[0] = e.x;
      _g[1] = e.y;
      _g[2] = e.z;
      _gInit = true;
      return;
    }
    const a = 0.05;
    _g[0] += a * (e.x - _g[0]);
    _g[1] += a * (e.y - _g[1]);
    _g[2] += a * (e.z - _g[2]);
  }

  List<double> get _up {
    final n = math.sqrt(_g[0] * _g[0] + _g[1] * _g[1] + _g[2] * _g[2]);
    if (n < 1e-3) return [0, 0, 1];
    return [_g[0] / n, _g[1] / n, _g[2] / n];
  }

  void _onGyro(GyroscopeEvent e) {
    final now = DateTime.now();
    final last = _lastGyro;
    _lastGyro = now;
    _gyroAlive = true;
    if (last == null) return;
    var dt = now.difference(last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.2) return;
    final up = _up;
    // Угловая скорость вокруг вертикали (против часовой, если смотреть сверху).
    final rateUp = e.x * up[0] + e.y * up[1] + e.z * up[2];
    if (_stationary) {
      _bias += 0.01 * (rateUp - _bias);
    }
    final corrected = rateUp - _bias;
    if (heading != null) {
      heading = wrap360(heading! - rad2deg(corrected) * dt);
    }
  }

  void _onMag(MagnetometerEvent e) {
    if (_hadGps || !_gInit) return;
    final a = _up;
    final ex = e.x, ey = e.y, ez = e.z;
    // H = E × A (восток), M = A × H (север) — в координатах телефона.
    var hx = ey * a[2] - ez * a[1];
    var hy = ez * a[0] - ex * a[2];
    var hz = ex * a[1] - ey * a[0];
    final hn = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (hn < 0.1) return;
    hx /= hn;
    hy /= hn;
    hz /= hn;
    final mx = a[1] * hz - a[2] * hy;
    final my = a[2] * hx - a[0] * hz;
    final mz = a[0] * hy - a[1] * hx;
    // «Вперёд»: если телефон лежит — верх экрана (y), если стоит в держателе — задняя камера (−z).
    final flat = a[2].abs() > 0.7;
    final double fe = flat ? hy : -hz;
    final double fn = flat ? my : -mz;
    final az = wrap360(rad2deg(math.atan2(fe, fn)));
    if (heading == null) {
      heading = az;
    } else {
      heading = wrap360(heading! + 0.05 * wrap180(az - heading!));
    }
    source = 'компас';
  }

  /// Поправка по GPS-курсу. [speed] м/с, [courseAcc] — точность курса, градусы (если есть).
  void onGps(double course, double speed, double? courseAcc) {
    if (speed < 2.0) return;
    if (courseAcc != null && courseAcc > 0 && courseAcc > 40) return;
    final now = DateTime.now();
    if (heading == null || !_hadGps || !_gyroAlive) {
      heading = course;
    } else {
      final k = speed > 6 ? 0.3 : 0.15;
      heading = wrap360(heading! + k * wrap180(course - heading!));
    }
    _hadGps = true;
    _lastGpsCourse = now;
    source = _gyroAlive ? 'Гиро + GPS' : 'GPS';
  }

  /// Давно не было GPS-курса — честно показываем, что курс держит только гироскоп.
  void refreshSource() {
    if (!_hadGps) return;
    final l = _lastGpsCourse;
    if (l != null && DateTime.now().difference(l).inSeconds > 15) {
      source = _gyroAlive ? 'Гироскоп' : 'GPS';
    }
  }
}
