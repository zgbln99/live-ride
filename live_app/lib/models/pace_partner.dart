import '../core/geo.dart';

/// Z czym zawodnik się ściga.
enum PaceTargetKind {
  speed('Stała prędkość'),
  time('Czas na trasie'),
  previousRide('Poprzedni przejazd'),
  personalBest('Twój rekord');

  const PaceTargetKind(this.label);

  final String label;

  static PaceTargetKind parse(String? value) =>
      PaceTargetKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => PaceTargetKind.speed,
      );
}

/// Definicja wirtualnego rywala.
class PaceTarget {
  const PaceTarget({
    required this.kind,
    required this.label,
    required this.routeDistanceMeters,
    this.targetSpeedKmh,
    this.targetDuration,
    this.referenceTrack = const [],
  });

  final PaceTargetKind kind;
  final String label;

  /// Dystans trasy, po którym ścigają się obaj.
  final double routeDistanceMeters;

  final double? targetSpeedKmh;
  final Duration? targetDuration;

  /// Ślad odniesienia: dystans od startu i czas od startu.
  ///
  /// Ghost z prawdziwego przejazdu nie jedzie równo — zwalnia na podjazdach
  /// i przyspiesza na zjazdach, i o to chodzi.
  final List<({double distanceMeters, Duration elapsed})> referenceTrack;

  /// Prędkość, którą trzeba trzymać, żeby dojechać w [targetDuration].
  double? get impliedSpeedKmh {
    if (targetSpeedKmh != null) return targetSpeedKmh;
    final duration = targetDuration;
    if (duration == null || duration.inSeconds <= 0) return null;
    return routeDistanceMeters / duration.inSeconds * 3.6;
  }

  /// Gdzie rywal jest po [elapsed] od startu.
  ///
  /// Zwraca null, gdy nie ma z czego policzyć — lepiej nie pokazać ghosta niż
  /// pokazać wymyślonego.
  double? distanceAt(Duration elapsed) {
    if (referenceTrack.isNotEmpty) return _interpolateTrack(elapsed);
    final speed = impliedSpeedKmh;
    if (speed == null || speed <= 0) return null;
    return speed / 3.6 * (elapsed.inMilliseconds / 1000);
  }

  double _interpolateTrack(Duration elapsed) {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds <= 0) return 0;
    final last = referenceTrack.last;
    if (seconds >= last.elapsed.inMilliseconds / 1000) {
      return last.distanceMeters;
    }
    for (var i = 1; i < referenceTrack.length; i++) {
      final current = referenceTrack[i];
      final currentSeconds = current.elapsed.inMilliseconds / 1000;
      if (currentSeconds < seconds) continue;
      final previous = referenceTrack[i - 1];
      final previousSeconds = previous.elapsed.inMilliseconds / 1000;
      final span = currentSeconds - previousSeconds;
      if (span <= 0) return current.distanceMeters;
      final t = (seconds - previousSeconds) / span;
      return previous.distanceMeters +
          (current.distanceMeters - previous.distanceMeters) * t;
    }
    return last.distanceMeters;
  }

  /// Kiedy rywal będzie na [distanceMeters].
  Duration? timeAt(double distanceMeters) {
    if (referenceTrack.isNotEmpty) {
      for (var i = 1; i < referenceTrack.length; i++) {
        final current = referenceTrack[i];
        if (current.distanceMeters < distanceMeters) continue;
        final previous = referenceTrack[i - 1];
        final span = current.distanceMeters - previous.distanceMeters;
        if (span <= 0) return current.elapsed;
        final t = (distanceMeters - previous.distanceMeters) / span;
        final millis =
            previous.elapsed.inMilliseconds +
            (current.elapsed.inMilliseconds - previous.elapsed.inMilliseconds) *
                t;
        return Duration(milliseconds: millis.round());
      }
      return referenceTrack.last.elapsed;
    }
    final speed = impliedSpeedKmh;
    if (speed == null || speed <= 0) return null;
    return Duration(seconds: (distanceMeters / (speed / 3.6)).round());
  }
}

/// Gdzie jest rywal względem zawodnika.
class PaceComparison {
  const PaceComparison({
    required this.riderMeters,
    required this.partnerMeters,
    required this.elapsed,
    this.timeDelta,
    this.ghostPosition,
  });

  final double riderMeters;
  final double partnerMeters;
  final Duration elapsed;

  /// Dodatnia wartość znaczy stratę, ujemna przewagę.
  final Duration? timeDelta;

  /// Pozycja ghosta na mapie, gdy da się ją wyznaczyć z geometrii trasy.
  final GeoPoint? ghostPosition;

  /// Dodatnia wartość znaczy przewagę zawodnika w metrach.
  double get distanceDelta => riderMeters - partnerMeters;

  bool get isAhead => distanceDelta >= 0;
}
