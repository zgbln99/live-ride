import 'training.dart';

/// An immutable snapshot of the live ride computer values.
///
/// The recorder publishes one of these on every update so widgets never read
/// mutable state straight off the service.
class RideMetrics {
  const RideMetrics({
    this.speedKmh = 0,
    this.maxSpeedKmh = 0,
    this.distanceMeters = 0,
    this.elapsed = Duration.zero,
    this.recording = Duration.zero,
    this.paused = Duration.zero,
    this.movingTime = Duration.zero,
    this.altitudeMeters,
    this.elevationGainMeters = 0,
    this.elevationLossMeters = 0,
    this.gradientPercent = 0,
    this.heartRate,
    this.averageHeartRate,
    this.maxHeartRate,
    this.cadenceRpm,
    this.averageCadenceRpm,
    this.maxCadenceRpm,
    this.power,
    this.workKj,
    this.sensorSpeedKmh,
    this.gpsAccuracyMeters,
    this.headingDegrees,
    this.pointCount = 0,
    this.hasFix = false,
  });

  final double speedKmh;
  final double maxSpeedKmh;
  final double distanceMeters;

  /// Czas od startu do teraz, razem z każdym postojem.
  final Duration elapsed;

  /// Czas, przez który licznik chodził: [elapsed] bez pauz.
  ///
  /// Krótki postój na światłach, poniżej progu auto-pauzy, wlicza się tutaj —
  /// i dlatego to nie to samo co [movingTime].
  final Duration recording;

  /// Łączny czas pauz, automatycznych i ręcznych razem.
  final Duration paused;

  final Duration movingTime;
  final double? altitudeMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double gradientPercent;
  final int? heartRate;
  final int? averageHeartRate;
  final int? maxHeartRate;

  /// Kadencja z sensora BLE. Null, gdy nikt jej nie nadaje — i wtedy pola
  /// kadencji w ogóle się nie pokazują, zamiast pokazywać zero.
  final double? cadenceRpm;
  final double? averageCadenceRpm;
  final double? maxCadenceRpm;

  /// Moc z miernika. [PowerMetrics.empty] oznacza brak miernika.
  final PowerMetrics? power;

  /// Praca wykonana w kJ — liczona tylko z realnej mocy.
  final double? workKj;

  /// Prędkość z czujnika koła, gdy jest dokładniejsza niż GPS (np. w tunelu
  /// albo na trenażerze).
  final double? sensorSpeedKmh;

  final double? gpsAccuracyMeters;
  final double? headingDegrees;
  final int pointCount;
  final bool hasFix;

  /// Average over moving time — the number a cyclist expects to see.
  double get averageSpeedKmh {
    final seconds = movingTime.inMilliseconds / 1000;
    if (seconds <= 0 || distanceMeters <= 0) return 0;
    return (distanceMeters / seconds) * 3.6;
  }

  /// Average over total elapsed time, including stops.
  double get overallSpeedKmh {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds <= 0 || distanceMeters <= 0) return 0;
    return (distanceMeters / seconds) * 3.6;
  }

  static const RideMetrics empty = RideMetrics();
}
