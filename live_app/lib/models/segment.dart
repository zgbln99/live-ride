import '../core/geo.dart';

/// Własny segment: fragment trasy, na którym chcesz się ścigać ze sobą.
class Segment {
  Segment({
    required this.id,
    required this.name,
    required this.points,
    required this.createdAt,
    this.sourceRouteId,
  }) : cumulative = cumulativeDistances(points);

  final String id;
  final String name;
  final List<GeoPoint> points;
  final DateTime createdAt;
  final String? sourceRouteId;
  final List<double> cumulative;

  double get distanceMeters => cumulative.isEmpty ? 0 : cumulative.last;

  double get ascentMeters {
    final accumulator = ElevationAccumulator(thresholdMeters: 2);
    for (final point in points) {
      accumulator.add(point.elevation);
    }
    return accumulator.gainMeters;
  }

  double get averageGradientPercent =>
      distanceMeters <= 0 ? 0 : ascentMeters / distanceMeters * 100;

  GeoPoint get start => points.first;
  GeoPoint get finish => points.last;

  Segment copyWith({String? name}) => Segment(
    id: id,
    name: name ?? this.name,
    points: points,
    createdAt: createdAt,
    sourceRouteId: sourceRouteId,
  );
}

/// Jedno przejechanie segmentu.
class SegmentAttempt {
  const SegmentAttempt({
    required this.id,
    required this.segmentId,
    required this.startedAt,
    required this.duration,
    this.rideId,
    this.averageSpeedKmh = 0,
    this.averageHeartRate,
    this.averagePower,
    this.averageCadence,
  });

  final String id;
  final String segmentId;
  final String? rideId;
  final DateTime startedAt;
  final Duration duration;
  final double averageSpeedKmh;
  final int? averageHeartRate;
  final int? averagePower;
  final int? averageCadence;
}

/// Stan śledzenia segmentu w czasie jazdy.
enum SegmentState { waiting, running, finished, abandoned }
