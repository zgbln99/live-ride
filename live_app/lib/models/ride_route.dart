import '../core/geo.dart';

enum RouteShape {
  loop('Loop'),
  outAndBack('Out & back'),
  pointToPoint('Point to point');

  const RouteShape(this.label);

  final String label;
}

/// The lightweight record kept in the route library index.
///
/// Cards render from this alone so opening the Routes tab never has to parse
/// every stored GPX file.
class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.name,
    required this.fileName,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.pointCount,
    required this.createdAt,
    required this.preview,
    this.lastUsedAt,
    this.imported = true,
    this.shape = RouteShape.pointToPoint,
  });

  final String id;
  final String name;
  final String fileName;
  final double distanceMeters;
  final double elevationGainMeters;
  final int pointCount;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool imported;
  final RouteShape shape;

  /// A heavily simplified polyline used to paint map previews on cards.
  final List<GeoPoint> preview;

  RouteSummary copyWith({String? name, DateTime? lastUsedAt}) => RouteSummary(
    id: id,
    name: name ?? this.name,
    fileName: fileName,
    distanceMeters: distanceMeters,
    elevationGainMeters: elevationGainMeters,
    pointCount: pointCount,
    createdAt: createdAt,
    preview: preview,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    imported: imported,
    shape: shape,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'file_name': fileName,
    'distance_m': distanceMeters,
    'elevation_gain_m': elevationGainMeters,
    'point_count': pointCount,
    'created_at': createdAt.toIso8601String(),
    'last_used_at': lastUsedAt?.toIso8601String(),
    'imported': imported,
    'shape': shape.name,
    'preview': [
      for (final p in preview) [p.lat, p.lon],
    ],
  };

  factory RouteSummary.fromJson(Map<String, dynamic> json) => RouteSummary(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Route',
    fileName: json['file_name'] as String? ?? '',
    distanceMeters: (json['distance_m'] as num?)?.toDouble() ?? 0,
    elevationGainMeters: (json['elevation_gain_m'] as num?)?.toDouble() ?? 0,
    pointCount: (json['point_count'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    lastUsedAt: DateTime.tryParse(json['last_used_at'] as String? ?? ''),
    imported: json['imported'] as bool? ?? true,
    shape:
        RouteShape.values
            .where((value) => value.name == json['shape'])
            .firstOrNull ??
        RouteShape.pointToPoint,
    preview: [
      for (final entry in (json['preview'] as List<dynamic>? ?? const []))
        if (entry is List && entry.length >= 2)
          GeoPoint(
            lat: (entry[0] as num).toDouble(),
            lon: (entry[1] as num).toDouble(),
          ),
    ],
  );
}

/// A full route: geometry plus the metadata needed to navigate it.
class RideRoute {
  RideRoute({
    required this.id,
    required this.name,
    required this.points,
    this.fileName = '',
    this.imported = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       cumulativeMeters = cumulativeDistances(points);

  final String id;
  final String name;
  final List<GeoPoint> points;
  final String fileName;
  final bool imported;
  final DateTime createdAt;
  final List<double> cumulativeMeters;

  double get distanceMeters =>
      cumulativeMeters.isEmpty ? 0 : cumulativeMeters.last;

  double get elevationGainMeters {
    final accumulator = ElevationAccumulator();
    for (final point in points) {
      accumulator.add(point.elevation);
    }
    return accumulator.gainMeters;
  }

  GeoPoint get start =>
      points.isEmpty ? const GeoPoint(lat: 52.52, lon: 13.405) : points.first;

  GeoPoint get center =>
      GeoBounds.of(points)?.center ?? const GeoPoint(lat: 52.52, lon: 13.405);

  RouteShape get shape {
    if (points.length < 4) return RouteShape.pointToPoint;
    final closing = haversineMeters(points.first, points.last);
    if (closing < 250) return RouteShape.loop;
    final middle = points[points.length ~/ 2];
    if (haversineMeters(points.first, middle) > distanceMeters * 0.2 &&
        closing < distanceMeters * 0.08) {
      return RouteShape.outAndBack;
    }
    return RouteShape.pointToPoint;
  }

  RouteSummary toSummary() => RouteSummary(
    id: id,
    name: name,
    fileName: fileName,
    distanceMeters: distanceMeters,
    elevationGainMeters: elevationGainMeters,
    pointCount: points.length,
    createdAt: createdAt,
    preview: samplePolyline(simplifyPolyline(points, 25), 120),
    imported: imported,
    shape: shape,
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
