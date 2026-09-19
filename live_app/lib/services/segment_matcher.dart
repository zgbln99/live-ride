import '../core/geo.dart';
import '../models/segment.dart';

/// Postęp na segmencie w trakcie jazdy.
class SegmentProgress {
  const SegmentProgress({
    required this.segment,
    required this.alongMeters,
    required this.elapsed,
    this.personalBest,
  });

  final Segment segment;
  final double alongMeters;
  final Duration elapsed;

  /// Najlepszy dotychczasowy czas, jeśli jakiś jest.
  final Duration? personalBest;

  double get remainingMeters =>
      (segment.distanceMeters - alongMeters).clamp(0, double.maxFinite);

  double get fraction => segment.distanceMeters <= 0
      ? 0
      : (alongMeters / segment.distanceMeters).clamp(0.0, 1.0);

  /// Ile sekund przed rekordem (ujemne) albo za nim (dodatnie).
  ///
  /// Null, gdy nie ma rekordu albo zawodnik ledwo wjechał — porównanie na
  /// pierwszych dziesięciu metrach to szum, nie informacja.
  double? get deltaSeconds {
    final best = personalBest;
    if (best == null || fraction < 0.02) return null;
    // Rekord rozłożony liniowo po dystansie. To przybliżenie, ale jedyne,
    // jakie da się zrobić bez zapisanego przebiegu prędkości rekordu.
    final expected = best.inMilliseconds / 1000 * fraction;
    return elapsed.inMilliseconds / 1000 - expected;
  }

  /// Przewidywany czas końcowy przy obecnym tempie.
  Duration? get projectedTime {
    if (fraction < 0.05) return null;
    final seconds = elapsed.inMilliseconds / 1000 / fraction;
    return Duration(seconds: seconds.round());
  }
}

/// Zakończona próba, zanim trafi do bazy.
class SegmentRun {
  const SegmentRun({
    required this.segment,
    required this.startedAt,
    required this.duration,
    required this.completed,
  });

  final Segment segment;
  final DateTime startedAt;
  final Duration duration;

  /// Czy zawodnik dojechał do końca, czy zjechał z segmentu.
  final bool completed;

  double get averageSpeedKmh => duration.inSeconds <= 0
      ? 0
      : segment.distanceMeters / duration.inSeconds * 3.6;
}

/// Wykrywa wjazd i zjazd z segmentów w trakcie jazdy.
///
/// Wjazd to nie samo „jestem blisko startu": trzeba też jechać we właściwą
/// stronę, inaczej przejazd w przeciwnym kierunku liczyłby się jako próba i
/// kończył rekordem, którego nikt nie pobił.
class SegmentMatcher {
  SegmentMatcher({
    this.entryRadiusMeters = 25,
    this.maxOffRouteMeters = 40,
    this.entryBearingToleranceDegrees = 60,
  });

  /// Jak blisko startu trzeba być, żeby próba się zaczęła.
  final double entryRadiusMeters;

  /// Jak daleko od linii segmentu wolno zjechać, zanim próba przepada.
  final double maxOffRouteMeters;

  /// O ile stopni kierunek jazdy może się różnić od kierunku segmentu.
  final double entryBearingToleranceDegrees;

  final Map<String, Segment> _segments = {};
  final Map<String, Duration> _bests = {};

  Segment? _active;
  DateTime? _startedAt;
  double _alongMeters = 0;
  int _searchIndex = 0;
  GeoPoint? _previous;

  SegmentProgress? _progress;
  final List<SegmentRun> _finished = [];

  SegmentProgress? get progress => _progress;
  Segment? get activeSegment => _active;
  List<SegmentRun> get finished => List.unmodifiable(_finished);

  void load(List<Segment> segments, {Map<String, Duration> bests = const {}}) {
    _segments
      ..clear()
      ..addEntries(segments.map((segment) => MapEntry(segment.id, segment)));
    _bests
      ..clear()
      ..addAll(bests);
    reset();
  }

  void reset() {
    _active = null;
    _startedAt = null;
    _alongMeters = 0;
    _searchIndex = 0;
    _previous = null;
    _progress = null;
    _finished.clear();
  }

  /// Podaje nową pozycję. Zwraca stan aktywnej próby albo null.
  SegmentProgress? update(GeoPoint position, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final previous = _previous;
    _previous = position;

    final active = _active;
    if (active != null) {
      final projection = projectOnPolyline(
        position,
        active.points,
        active.cumulative,
        fromIndex: _searchIndex,
      );
      if (projection == null) return _progress;

      if (projection.offRouteMeters > maxOffRouteMeters) {
        _finish(active, at, completed: false);
        return null;
      }

      _searchIndex = projection.segmentIndex;
      _alongMeters = projection.alongMeters;

      // Koniec segmentu: ostatni wierzchołek osiągnięty z zapasem na GPS.
      if (active.distanceMeters - _alongMeters <= entryRadiusMeters / 2) {
        _finish(active, at, completed: true);
        return null;
      }

      _progress = SegmentProgress(
        segment: active,
        alongMeters: _alongMeters,
        elapsed: at.difference(_startedAt ?? at),
        personalBest: _bests[active.id],
      );
      return _progress;
    }

    if (previous == null) return null;
    final travelBearing = bearingDegrees(previous, position);
    if (haversineMeters(previous, position) < 2) return null;

    for (final segment in _segments.values) {
      if (segment.points.length < 2) continue;
      if (haversineMeters(position, segment.start) > entryRadiusMeters) {
        continue;
      }
      final segmentBearing = bearingDegrees(
        segment.points.first,
        segment.points[1],
      );
      if (_angleBetween(travelBearing, segmentBearing) >
          entryBearingToleranceDegrees) {
        continue;
      }

      _active = segment;
      _startedAt = at;
      _alongMeters = 0;
      _searchIndex = 0;
      _progress = SegmentProgress(
        segment: segment,
        alongMeters: 0,
        elapsed: Duration.zero,
        personalBest: _bests[segment.id],
      );
      return _progress;
    }
    return null;
  }

  void _finish(Segment segment, DateTime at, {required bool completed}) {
    final startedAt = _startedAt;
    _active = null;
    _startedAt = null;
    _progress = null;
    _searchIndex = 0;
    if (startedAt == null) return;
    final duration = at.difference(startedAt);
    // Próba krótsza niż pięć sekund to szum GPS przy starcie, nie przejazd.
    if (completed && duration.inSeconds >= 5) {
      _finished.add(
        SegmentRun(
          segment: segment,
          startedAt: startedAt,
          duration: duration,
          completed: true,
        ),
      );
      final best = _bests[segment.id];
      if (best == null || duration < best) _bests[segment.id] = duration;
    }
  }

  static double _angleBetween(double a, double b) {
    final difference = (a - b).abs() % 360;
    return difference > 180 ? 360 - difference : difference;
  }
}
