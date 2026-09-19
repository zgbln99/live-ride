import '../core/geo.dart';
import '../models/pace_partner.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';

/// Wirtualny rywal: cel tempa albo ghost z wcześniejszego przejazdu.
///
/// Serwis liczy tylko dwie rzeczy: gdzie rywal jest teraz i o ile zawodnik
/// jest przed nim albo za nim. Resztę — mapę, kolor, dźwięk — robi UI.
class PacePartnerService {
  PaceTarget? _target;
  List<GeoPoint> _routePoints = const [];
  List<double> _routeCumulative = const [];

  PaceTarget? get target => _target;
  bool get isActive => _target != null;

  /// Włącza rywala. [route] jest opcjonalna — bez niej nie ma ghosta na
  /// mapie, ale różnica czasu wciąż działa.
  void start(PaceTarget target, {RideRoute? route}) {
    _target = target;
    _routePoints = route?.points ?? const [];
    _routeCumulative = route?.cumulativeMeters ?? const [];
  }

  void stop() {
    _target = null;
    _routePoints = const [];
    _routeCumulative = const [];
  }

  /// Porównanie w danej chwili jazdy.
  PaceComparison? compare({
    required double riderMeters,
    required Duration elapsed,
  }) {
    final target = _target;
    if (target == null) return null;
    final partnerMeters = target.distanceAt(elapsed);
    if (partnerMeters == null) return null;

    // Różnica czasu jest uczciwsza niż różnica metrów: „30 sekund straty"
    // znaczy to samo pod górę i z górki, a „200 metrów" nie.
    Duration? delta;
    final partnerTimeAtRider = target.timeAt(riderMeters);
    if (partnerTimeAtRider != null) {
      delta = elapsed - partnerTimeAtRider;
    }

    return PaceComparison(
      riderMeters: riderMeters,
      partnerMeters: partnerMeters,
      elapsed: elapsed,
      timeDelta: delta,
      ghostPosition: _pointAt(partnerMeters),
    );
  }

  /// Punkt na trasie w podanym dystansie od startu.
  GeoPoint? _pointAt(double meters) {
    if (_routePoints.length < 2 ||
        _routeCumulative.length != _routePoints.length) {
      return null;
    }
    if (meters <= 0) return _routePoints.first;
    if (meters >= _routeCumulative.last) return _routePoints.last;

    for (var i = 1; i < _routeCumulative.length; i++) {
      if (_routeCumulative[i] < meters) continue;
      final span = _routeCumulative[i] - _routeCumulative[i - 1];
      if (span <= 0) return _routePoints[i];
      final t = (meters - _routeCumulative[i - 1]) / span;
      final a = _routePoints[i - 1];
      final b = _routePoints[i];
      return GeoPoint(
        lat: a.lat + (b.lat - a.lat) * t,
        lon: a.lon + (b.lon - a.lon) * t,
      );
    }
    return _routePoints.last;
  }

  /// Ghost z zapisanego przejazdu.
  ///
  /// Zwraca null, gdy przejazd nie ma dość punktów z dystansem — ghost bez
  /// przebiegu prędkości byłby zwykłym celem tempa udającym prawdziwą jazdę.
  static PaceTarget? fromRide(
    RecordedRide ride, {
    required String label,
    PaceTargetKind kind = PaceTargetKind.previousRide,
  }) {
    if (ride.points.length < 10 || ride.distanceMeters <= 0) return null;
    final start = ride.points.first.recordedAt;
    final track = <({double distanceMeters, Duration elapsed})>[];
    for (final point in ride.points) {
      final elapsed = point.recordedAt.difference(start);
      if (elapsed.isNegative) continue;
      if (track.isNotEmpty &&
          point.distanceMeters <= track.last.distanceMeters) {
        continue;
      }
      track.add((distanceMeters: point.distanceMeters, elapsed: elapsed));
    }
    if (track.length < 5) return null;
    return PaceTarget(
      kind: kind,
      label: label,
      routeDistanceMeters: ride.distanceMeters,
      targetDuration: ride.movingTime,
      referenceTrack: track,
    );
  }
}
