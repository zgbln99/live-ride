import 'dart:math' as math;

import '../models/sensor_device.dart';
import '../models/training.dart';
import '../models/ride_metrics.dart';
import 'geo.dart';

/// One position fix, decoupled from the platform plugin so the metric maths
/// can be unit tested without a device.
class RideSample {
  const RideSample({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.altitude,
    this.speedMps,
    this.accuracyMeters,
    this.headingDegrees,
  });

  final double lat;
  final double lon;
  final DateTime timestamp;
  final double? altitude;
  final double? speedMps;
  final double? accuracyMeters;
  final double? headingDegrees;

  GeoPoint get point => GeoPoint(lat: lat, lon: lon, elevation: altitude);

  bool get isValid => point.isValid;
}

/// What the accumulator decided to do with a sample.
enum SampleVerdict {
  /// Counted: distance and time were advanced.
  accepted,

  /// Kept as a track point but not counted as movement (stationary drift).
  stationary,

  /// Thrown away: implausible jump, bad accuracy or out-of-order timestamp.
  rejected,
}

/// Turns a noisy GPS stream into cycling-computer numbers.
///
/// The rules here exist because raw GPS lies: a bike parked at a café still
/// "moves" a few metres a second, a tunnel exit teleports the rider a
/// kilometre, and barometric-free altitude wanders by ten metres while
/// standing still.
class RideMetricsAccumulator {
  /// Above this the fix is a teleport, not a bike.
  static const double maxPlausibleSpeedMps = 30; // 108 km/h

  /// Fixes worse than this are unusable for distance.
  static const double maxUsableAccuracyMeters = 60;

  /// Below this the rider counts as stopped.
  static const double movingSpeedThresholdMps = 1.0; // 3.6 km/h

  /// Gradient is measured over roughly this much road.
  static const double gradientWindowMeters = 120;

  final ElevationAccumulator _elevation = ElevationAccumulator();
  final List<({double distance, double altitude})> _gradientWindow = [];

  RideSample? _lastCounted;
  DateTime? _lastTimestamp;
  int _rejectStreak = 0;

  double _distanceMeters = 0;
  double _movingMilliseconds = 0;
  double _speedMps = 0;
  double _maxSpeedKmh = 0;
  double _gradientPercent = 0;
  double? _altitude;
  double? _accuracy;
  double? _heading;

  int _hrSum = 0;
  int _hrCount = 0;
  int _hrMax = 0;
  int? _hr;

  final PowerAccumulator _power = PowerAccumulator();
  double _cadenceSum = 0;
  int _cadenceCount = 0;
  double _cadenceMax = 0;
  double? _cadence;
  double? _sensorSpeedKmh;
  DateTime? _sensorSpeedAt;
  MetricSource _speedSource = MetricSource.auto;
  double _workJoules = 0;
  DateTime? _lastPowerAt;

  double get distanceMeters => _distanceMeters;
  Duration get movingTime =>
      Duration(milliseconds: _movingMilliseconds.round());

  /// Prędkość pokazywana zawodnikowi.
  ///
  /// „Automatycznie" znaczy: czujnik koła, kiedy nadaje, bo jest szybszy i
  /// nie gubi się w tunelu; GPS, kiedy czujnika nie ma albo zamilkł. Wybór
  /// wprost nadpisuje tę logikę, ale nigdy nie wymyśla wartości — gdy
  /// wskazane źródło milczy, zostaje drugie.
  double get speedKmh {
    final sensor = _freshSensorSpeed;
    return switch (_speedSource) {
      MetricSource.sensor => sensor ?? _speedMps * 3.6,
      MetricSource.gps => _speedMps * 3.6,
      MetricSource.auto => sensor ?? _speedMps * 3.6,
    };
  }

  /// Prędkość z czujnika, o ile nie jest przeterminowana.
  double? get _freshSensorSpeed {
    final value = _sensorSpeedKmh;
    final at = _sensorSpeedAt;
    if (value == null || at == null) return null;
    // Czujnik koła przestaje nadawać, gdy koło stoi; po trzech sekundach
    // milczenia trzymanie ostatniej wartości byłoby kłamstwem.
    if (DateTime.now().difference(at) > const Duration(seconds: 3)) return null;
    return value;
  }

  /// Z którego źródła ma iść prędkość.
  set speedSource(MetricSource source) => _speedSource = source;
  double get maxSpeedKmh => _maxSpeedKmh;
  double get elevationGainMeters => _elevation.gainMeters;
  double get elevationLossMeters => _elevation.lossMeters;
  double get gradientPercent => _gradientPercent;
  double? get altitudeMeters => _altitude;
  int? get heartRate => _hr;
  int? get averageHeartRate =>
      _hrCount == 0 ? null : (_hrSum / _hrCount).round();
  int? get maxHeartRate => _hrMax == 0 ? null : _hrMax;

  void addHeartRate(int bpm) {
    if (bpm <= 0 || bpm > 260) return;
    _hr = bpm;
    _hrSum += bpm;
    _hrCount++;
    if (bpm > _hrMax) _hrMax = bpm;
  }

  /// Call when recording is paused so the gap is not counted as a huge jump.
  void breakContinuity() {
    _lastCounted = null;
    _lastTimestamp = null;
    _speedMps = 0;
    _rejectStreak = 0;
  }

  SampleVerdict add(RideSample sample) {
    if (!sample.isValid) return SampleVerdict.rejected;
    final accuracy = sample.accuracyMeters;
    if (accuracy != null && accuracy.isFinite) {
      _accuracy = accuracy;
      if (accuracy > maxUsableAccuracyMeters && _lastCounted != null) {
        return SampleVerdict.rejected;
      }
    }
    if (sample.headingDegrees != null && sample.headingDegrees!.isFinite) {
      _heading = sample.headingDegrees;
    }

    _elevation.add(sample.altitude);
    _altitude = _elevation.smoothedAltitude ?? sample.altitude;

    final previous = _lastCounted;
    final previousTime = _lastTimestamp;
    if (previous == null || previousTime == null) {
      _lastCounted = sample;
      _lastTimestamp = sample.timestamp;
      _speedMps = _plausibleReportedSpeed(sample) ?? 0;
      _pushGradientSample();
      return SampleVerdict.accepted;
    }

    final deltaSeconds =
        sample.timestamp.difference(previousTime).inMilliseconds / 1000;
    if (deltaSeconds <= 0) return SampleVerdict.rejected;

    final step = haversineMeters(previous.point, sample.point);
    final impliedSpeed = step / deltaSeconds;

    if (impliedSpeed > maxPlausibleSpeedMps) {
      _rejectStreak++;
      // A single wild fix is noise. Several in a row means the receiver has
      // genuinely re-acquired somewhere else, so resynchronise without
      // crediting the jump as distance.
      if (_rejectStreak < 3) return SampleVerdict.rejected;
      _rejectStreak = 0;
      _lastCounted = sample;
      _lastTimestamp = sample.timestamp;
      _speedMps = 0;
      return SampleVerdict.stationary;
    }
    _rejectStreak = 0;

    final reported = _plausibleReportedSpeed(sample);
    final speed = reported ?? impliedSpeed;

    // Drift gate: a stationary bike must not accumulate metres. The gate
    // scales with the reported accuracy, but a confident speed reading
    // overrides it so genuinely slow riding still counts.
    final gate = accuracy != null && accuracy.isFinite
        ? accuracy.clamp(2.0, 30.0) * 0.5
        : 3.0;
    final moving = speed >= movingSpeedThresholdMps;
    if (step < gate && !moving) {
      _lastTimestamp = sample.timestamp;
      _speedMps = reported != null && reported < movingSpeedThresholdMps
          ? reported
          : 0;
      return SampleVerdict.stationary;
    }

    _distanceMeters += step;
    _speedMps = speed;
    if (moving) _movingMilliseconds += deltaSeconds * 1000;

    final speedKmh = speed * 3.6;
    if (speedKmh > _maxSpeedKmh &&
        speed < maxPlausibleSpeedMps &&
        (accuracy == null || accuracy < 30)) {
      _maxSpeedKmh = speedKmh;
    }

    _lastCounted = sample;
    _lastTimestamp = sample.timestamp;
    _pushGradientSample();
    return SampleVerdict.accepted;
  }

  double? _plausibleReportedSpeed(RideSample sample) {
    final speed = sample.speedMps;
    if (speed == null || !speed.isFinite || speed < 0) return null;
    if (speed > maxPlausibleSpeedMps) return null;
    return speed;
  }

  void _pushGradientSample() {
    final altitude = _elevation.smoothedAltitude;
    if (altitude == null) return;
    _gradientWindow.add((distance: _distanceMeters, altitude: altitude));
    while (_gradientWindow.length > 2 &&
        _distanceMeters - _gradientWindow.first.distance >
            gradientWindowMeters * 2) {
      _gradientWindow.removeAt(0);
    }
    final oldest = _gradientWindow.first;
    final run = _distanceMeters - oldest.distance;
    if (run < gradientWindowMeters * 0.35) return;
    final rise = altitude - oldest.altitude;
    _gradientPercent = (rise / run * 100).clamp(-35.0, 35.0);
  }

  double? get cadenceRpm => _cadence;

  double? get averageCadenceRpm =>
      _cadenceCount == 0 ? null : _cadenceSum / _cadenceCount;

  /// Kadencja z sensora. Zera są liczone do średniej celowo: jazda z wybiegu
  /// to część przejazdu i średnia kadencja, która je pomija, kłamie.
  void addCadence(double rpm) {
    if (rpm < 0 || rpm > 250) return;
    _cadence = rpm;
    _cadenceSum += rpm;
    _cadenceCount++;
    if (rpm > _cadenceMax) _cadenceMax = rpm;
  }

  /// Moc z miernika albo trenażera.
  void addPower(int watts, {DateTime? at, double? balancePercent}) {
    if (watts < 0 || watts > 2500) return;
    final now = at ?? DateTime.now();
    _power.add(watts, at: now, balancePercent: balancePercent);
    final previous = _lastPowerAt;
    if (previous != null) {
      final seconds = now.difference(previous).inMilliseconds / 1000;
      // Przerwa dłuższa niż 10 s to nie jazda, tylko luka w danych.
      if (seconds > 0 && seconds <= 10) _workJoules += watts * seconds;
    }
    _lastPowerAt = now;
  }

  /// Prędkość z czujnika koła — nadpisuje GPS tylko wtedy, gdy ktoś ją poda.
  void setSensorSpeed(double? kmh, {DateTime? at}) {
    if (kmh == null || kmh < 0 || kmh >= 150) {
      _sensorSpeedKmh = null;
      _sensorSpeedAt = null;
      _sensorSpeedAt = null;
      return;
    }
    _sensorSpeedKmh = kmh;
    _sensorSpeedAt = at ?? DateTime.now();
  }

  /// Składa migawkę licznika.
  ///
  /// [elapsed] to czas zegarowy od startu, [recording] ten sam czas bez pauz.
  /// Rozróżnienie nie jest kosmetyczne: średnia ogólna dzieli dystans przez
  /// pierwszy, a TSS liczy się z drugiego — kawa na trasie nie ma prawa
  /// podnieść obciążenia treningowego.
  RideMetrics build({
    required Duration elapsed,
    Duration? recording,
    Duration paused = Duration.zero,
    required int pointCount,
    required bool hasFix,
  }) => RideMetrics(
    speedKmh: math.max(0, speedKmh),
    maxSpeedKmh: _maxSpeedKmh,
    distanceMeters: _distanceMeters,
    elapsed: elapsed,
    recording: recording ?? elapsed,
    paused: paused,
    movingTime: movingTime,
    altitudeMeters: _altitude,
    elevationGainMeters: _elevation.gainMeters,
    elevationLossMeters: _elevation.lossMeters,
    gradientPercent: _gradientPercent,
    heartRate: _hr,
    averageHeartRate: averageHeartRate,
    maxHeartRate: maxHeartRate,
    cadenceRpm: _cadence,
    averageCadenceRpm: averageCadenceRpm,
    maxCadenceRpm: _cadenceCount == 0 ? null : _cadenceMax,
    power: _power.hasData ? _power.build(elapsed: recording ?? elapsed) : null,
    workKj: _workJoules > 0 ? _workJoules / 1000 : null,
    sensorSpeedKmh: _sensorSpeedKmh,
    gpsAccuracyMeters: _accuracy,
    headingDegrees: _heading,
    pointCount: pointCount,
    hasFix: hasFix,
  );

  void reset() {
    _elevation.reset();
    _gradientWindow.clear();
    _lastCounted = null;
    _lastTimestamp = null;
    _rejectStreak = 0;
    _distanceMeters = 0;
    _movingMilliseconds = 0;
    _speedMps = 0;
    _maxSpeedKmh = 0;
    _gradientPercent = 0;
    _altitude = null;
    _accuracy = null;
    _heading = null;
    _hrSum = 0;
    _hrCount = 0;
    _hrMax = 0;
    _hr = null;
    _power.reset();
    _cadenceSum = 0;
    _cadenceCount = 0;
    _cadenceMax = 0;
    _cadence = null;
    _sensorSpeedKmh = null;
    _sensorSpeedAt = null;
    _workJoules = 0;
    _lastPowerAt = null;
  }
}
