import '../core/geo.dart';
import '../models/ride_route.dart';
import '../models/route/route_analysis.dart';

/// Stan podjazdu, na którym zawodnik właśnie jest.
class ClimbProgress {
  const ClimbProgress({
    required this.climb,
    required this.alongMeters,
    required this.elapsed,
    this.elevationMeters,
    this.currentGradientPercent,
    this.averageSpeedKmh,
  });

  final Climb climb;

  /// Dystans od startu trasy, nie od początku podjazdu.
  final double alongMeters;

  final Duration elapsed;

  /// Wysokość odczytana z profilu trasy w miejscu, w którym się jest.
  final double? elevationMeters;

  /// Nachylenie liczone z profilu trasy w miejscu, w którym się jest.
  final double? currentGradientPercent;

  final double? averageSpeedKmh;

  double get doneMeters =>
      (alongMeters - climb.startDistanceMeters).clamp(0, climb.lengthMeters);

  double get remainingMeters => climb.remainingMeters(alongMeters);

  /// Ile metrów w pionie zostało. Liczone z wysokości, a nie z dystansu —
  /// `Climb.remainingGain` oczekuje wysokości, nie kilometra.
  double get remainingGainMeters {
    final elevation = elevationMeters;
    if (elevation == null) return 0;
    return climb.remainingGain(elevation);
  }

  double get fraction => climb.progress(alongMeters);

  /// Ile jeszcze zostało, przy tempie utrzymanym do tej pory.
  Duration? get estimatedRemaining {
    final speed = averageSpeedKmh;
    if (speed == null || speed <= 1) return null;
    final seconds = remainingMeters / (speed / 3.6);
    return Duration(seconds: seconds.round());
  }
}

/// Wynik ukończonego podjazdu — to, co zawodnik chce zobaczyć na szczycie.
class ClimbResult {
  const ClimbResult({
    required this.climb,
    required this.duration,
    this.averageSpeedKmh,
    this.averageHeartRate,
    this.averagePowerWatts,
  });

  final Climb climb;
  final Duration duration;
  final double? averageSpeedKmh;
  final int? averageHeartRate;
  final int? averagePowerWatts;

  /// Metry wzniesienia na godzinę — miara tempa na podjeździe.
  double? get vam {
    final hours = duration.inMilliseconds / 3600000;
    if (hours <= 0) return null;
    return climb.gainMeters / hours;
  }
}

/// Śledzi, gdzie zawodnik jest względem podjazdów na trasie.
///
/// Klasa liczy wszystko z geometrii trasy, a nie z kształtu z nawigacji:
/// podjazdy wykryto na punktach trasy, więc rzutowanie musi iść na tę samą
/// linię, inaczej „zostało 300 m" odnosiłoby się do czegoś innego niż profil
/// pod spodem.
class ClimbTracker {
  ClimbTracker({
    this.approachDistanceMeters = 2000,
    this.exitToleranceMeters = 60,
  });

  /// Od jakiego dystansu przed podjazdem zapowiadamy go zawodnikowi.
  final double approachDistanceMeters;

  /// Ile metrów za szczytem wciąż liczymy jako podjazd — GPS potrafi
  /// cofnąć zawodnika o kilkadziesiąt metrów tuż za wierzchołkiem.
  final double exitToleranceMeters;

  RideRoute? _route;
  List<double> _cumulative = const [];
  int _searchIndex = 0;

  double? _alongMeters;
  Climb? _active;
  DateTime? _activeStartedAt;
  double _activeStartDistance = 0;
  final List<ClimbResult> _finished = [];

  ClimbProgress? _progress;

  /// Gdzie na trasie jest zawodnik. Null, dopóki nie ma pozycji.
  double? get alongMeters => _alongMeters;

  ClimbProgress? get progress => _progress;
  Climb? get activeClimb => _active;
  List<ClimbResult> get finished => List.unmodifiable(_finished);

  /// Podjazd zaraz przed zawodnikiem — do zapowiedzi „za 800 m podjazd".
  Climb? get upcomingClimb {
    final along = _alongMeters;
    final route = _route;
    if (along == null || route == null || _active != null) return null;
    for (final climb in route.analysis.climbs) {
      if (climb.startDistanceMeters <= along) continue;
      final distance = climb.startDistanceMeters - along;
      return distance <= approachDistanceMeters ? climb : null;
    }
    return null;
  }

  double? get metersToUpcoming {
    final climb = upcomingClimb;
    final along = _alongMeters;
    if (climb == null || along == null) return null;
    return climb.startDistanceMeters - along;
  }

  bool get hasRoute => (_route?.analysis.climbs.isNotEmpty) ?? false;

  void attach(RideRoute? route) {
    if (identical(route, _route)) return;
    _route = route;
    _cumulative = route?.cumulativeMeters ?? const [];
    reset();
  }

  void reset() {
    _searchIndex = 0;
    _alongMeters = null;
    _active = null;
    _activeStartedAt = null;
    _activeStartDistance = 0;
    _progress = null;
    _finished.clear();
  }

  /// Podaje nową pozycję i zwraca stan podjazdu, jeśli zawodnik na nim jest.
  ///
  /// [averageSpeedKmh], [heartRate] i [powerWatts] służą tylko do podsumowania
  /// podjazdu; bez nich wynik po prostu ich nie pokaże.
  ClimbProgress? update(
    GeoPoint position, {
    DateTime? now,
    double? averageSpeedKmh,
    int? heartRate,
    int? powerWatts,
  }) {
    final route = _route;
    if (route == null || route.points.length < 2) return null;

    final projection = projectOnPolyline(
      position,
      route.points,
      _cumulative,
      fromIndex: _searchIndex,
    );
    if (projection == null) return null;
    _searchIndex = projection.segmentIndex;
    final along = projection.alongMeters;
    _alongMeters = along;

    final at = now ?? DateTime.now();
    final climbs = route.analysis.climbs;

    final active = _active;
    if (active != null) {
      if (along > active.endDistanceMeters + exitToleranceMeters) {
        _finishActive(at, averageSpeedKmh, heartRate, powerWatts);
      } else {
        _progress = _buildProgress(active, along, at, averageSpeedKmh);
        return _progress;
      }
    }

    for (final climb in climbs) {
      if (climb.contains(along)) {
        _active = climb;
        _activeStartedAt = at;
        _activeStartDistance = along;
        _progress = _buildProgress(climb, along, at, averageSpeedKmh);
        return _progress;
      }
    }

    _progress = null;
    return null;
  }

  ClimbProgress _buildProgress(
    Climb climb,
    double along,
    DateTime at,
    double? averageSpeedKmh,
  ) {
    final startedAt = _activeStartedAt ?? at;
    final elapsed = at.difference(startedAt);
    // Średnia na tym podjeździe jest uczciwsza niż średnia całej jazdy:
    // „zostało 6 minut" po zjeździe z 40 km/h byłoby kłamstwem.
    double? climbSpeed;
    final seconds = elapsed.inMilliseconds / 1000;
    final covered = along - _activeStartDistance;
    if (seconds > 20 && covered > 50) {
      climbSpeed = covered / seconds * 3.6;
    }
    return ClimbProgress(
      climb: climb,
      alongMeters: along,
      elapsed: elapsed,
      elevationMeters: _elevationAt(along),
      currentGradientPercent: _gradientAt(along),
      averageSpeedKmh: climbSpeed ?? averageSpeedKmh,
    );
  }

  void _finishActive(
    DateTime at,
    double? averageSpeedKmh,
    int? heartRate,
    int? powerWatts,
  ) {
    final climb = _active;
    final startedAt = _activeStartedAt;
    _active = null;
    _activeStartedAt = null;
    _progress = null;
    if (climb == null || startedAt == null) return;

    final duration = at.difference(startedAt);
    if (duration.inSeconds < 10) return;
    _finished.add(
      ClimbResult(
        climb: climb,
        duration: duration,
        averageSpeedKmh: climb.lengthMeters / duration.inSeconds * 3.6,
        averageHeartRate: heartRate,
        averagePowerWatts: powerWatts,
      ),
    );
  }

  /// Wysokość odczytana z wygładzonego profilu trasy.
  double? _elevationAt(double along) {
    final profile = _route?.analysis.profile ?? const [];
    if (profile.isEmpty) return null;
    for (var i = 1; i < profile.length; i++) {
      if (profile[i].distance >= along) {
        final previous = profile[i - 1];
        final current = profile[i];
        final run = current.distance - previous.distance;
        if (run <= 0) return current.elevation;
        final t = (along - previous.distance) / run;
        return previous.elevation +
            (current.elevation - previous.elevation) * t;
      }
    }
    return profile.last.elevation;
  }

  /// Nachylenie wprost z wygładzonego profilu trasy.
  double? _gradientAt(double along) {
    final profile = _route?.analysis.profile ?? const [];
    if (profile.length < 2) return null;
    for (var i = 1; i < profile.length; i++) {
      if (profile[i].distance >= along) {
        final previous = profile[i - 1];
        final current = profile[i];
        final run = current.distance - previous.distance;
        if (run <= 1) return null;
        return (current.elevation - previous.elevation) / run * 100;
      }
    }
    return null;
  }
}
