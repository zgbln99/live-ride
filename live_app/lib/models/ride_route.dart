import 'dart:math' as math;

class RidePoint {
  const RidePoint({required this.lat, required this.lon, this.elevation, this.time});

  final double lat;
  final double lon;
  final double? elevation;
  final DateTime? time;
}

class RideRoute {
  RideRoute({required this.name, required this.points, required this.rawGpx, this.sourcePath})
      : totalDistanceMeters = _total(points);

  final String name;
  final List<RidePoint> points;
  final String rawGpx;
  final String? sourcePath;
  final double totalDistanceMeters;

  RidePoint get start => points.first;

  RidePoint get center {
    if (points.isEmpty) return const RidePoint(lat: 52.52, lon: 13.405);
    double lat = 0;
    double lon = 0;
    for (final p in points) {
      lat += p.lat;
      lon += p.lon;
    }
    return RidePoint(lat: lat / points.length, lon: lon / points.length);
  }

  static double _total(List<RidePoint> points) {
    double sum = 0;
    for (var i = 1; i < points.length; i++) {
      sum += distanceMeters(points[i - 1], points[i]);
    }
    return sum;
  }
}

class NavManeuver {
  const NavManeuver({
    required this.instruction,
    required this.lengthKm,
    required this.beginShapeIndex,
    required this.type,
    required this.bearing,
  });

  final String instruction;
  final double lengthKm;
  final int beginShapeIndex;
  final int type;
  final double bearing;

  factory NavManeuver.fromJson(Map<String, dynamic> json) => NavManeuver(
        instruction: json['instruction'] as String? ?? '',
        lengthKm: (json['length'] as num? ?? 0).toDouble(),
        beginShapeIndex: (json['begin_shape_index'] as num? ?? 0).toInt(),
        type: (json['type'] as num? ?? 0).toInt(),
        bearing: (json['bearing'] as num? ?? 0).toDouble(),
      );
}

class NavigationPlan {
  NavigationPlan({required this.shape, required this.maneuvers})
      : cumulativeMeters = _cumulative(shape);

  final List<RidePoint> shape;
  final List<NavManeuver> maneuvers;
  final List<double> cumulativeMeters;

  double get totalMeters => cumulativeMeters.isEmpty ? 0 : cumulativeMeters.last;

  factory NavigationPlan.fromJson(Map<String, dynamic> json) {
    final shape = (json['shape'] as List? ?? const [])
        .whereType<List>()
        .where((p) => p.length >= 2)
        .map(
          (p) => RidePoint(
            lat: (p[0] as num).toDouble(),
            lon: (p[1] as num).toDouble(),
          ),
        )
        .toList();
    final maneuvers = (json['maneuvers'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => NavManeuver.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return NavigationPlan(shape: shape, maneuvers: maneuvers);
  }

  factory NavigationPlan.fallback(RideRoute route) =>
      NavigationPlan(shape: route.points, maneuvers: const []);

  static List<double> _cumulative(List<RidePoint> points) {
    if (points.isEmpty) return const [];
    final result = <double>[0];
    for (var i = 1; i < points.length; i++) {
      result.add(result.last + distanceMeters(points[i - 1], points[i]));
    }
    return result;
  }
}

double distanceMeters(RidePoint a, RidePoint b) {
  const r = 6371000.0;
  final p1 = a.lat * math.pi / 180;
  final p2 = b.lat * math.pi / 180;
  final dp = (b.lat - a.lat) * math.pi / 180;
  final dl = (b.lon - a.lon) * math.pi / 180;
  final h = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}
