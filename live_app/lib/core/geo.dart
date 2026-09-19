import 'dart:math' as math;

/// A single geographic sample. Used for route geometry, recorded tracks and
/// anything that needs a coordinate pair inside Live Ride.
class GeoPoint {
  const GeoPoint({
    required this.lat,
    required this.lon,
    this.elevation,
    this.time,
  });

  final double lat;
  final double lon;
  final double? elevation;
  final DateTime? time;

  bool get isValid =>
      lat.isFinite &&
      lon.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

const double _earthRadiusMeters = 6371008.8;
const double _deg2rad = math.pi / 180.0;

/// Great-circle distance between two coordinates.
double haversineMeters(GeoPoint a, GeoPoint b) {
  final phi1 = a.lat * _deg2rad;
  final phi2 = b.lat * _deg2rad;
  final dPhi = (b.lat - a.lat) * _deg2rad;
  final dLambda = (b.lon - a.lon) * _deg2rad;
  final h =
      math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(dLambda / 2) *
          math.sin(dLambda / 2);
  return 2 * _earthRadiusMeters * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Initial bearing from [a] to [b] in degrees, normalised to `[0, 360)`.
double bearingDegrees(GeoPoint a, GeoPoint b) {
  final phi1 = a.lat * _deg2rad;
  final phi2 = b.lat * _deg2rad;
  final dLambda = (b.lon - a.lon) * _deg2rad;
  final y = math.sin(dLambda) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  return (math.atan2(y, x) / _deg2rad + 360) % 360;
}

/// Running distance along a polyline. `result[i]` is the distance from the
/// first point up to `points[i]`.
List<double> cumulativeDistances(List<GeoPoint> points) {
  if (points.isEmpty) return const <double>[];
  final result = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    result[i] = result[i - 1] + haversineMeters(points[i - 1], points[i]);
  }
  return result;
}

double totalDistanceMeters(List<GeoPoint> points) {
  if (points.length < 2) return 0;
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += haversineMeters(points[i - 1], points[i]);
  }
  return sum;
}

/// Where a rider sits relative to a route.
class RouteProjection {
  const RouteProjection({
    required this.segmentIndex,
    required this.alongMeters,
    required this.offRouteMeters,
    required this.snapped,
  });

  /// Index of the polyline vertex the projection starts at.
  final int segmentIndex;

  /// Cumulative distance from the route start to the projected position.
  final double alongMeters;

  /// Perpendicular distance from the rider to the route.
  final double offRouteMeters;

  /// The projected position on the route geometry.
  final GeoPoint snapped;
}

/// Projects [position] onto the polyline [line].
///
/// This is deliberately not a nearest-vertex search: progress along a route has
/// to come from the projected position on the segment, otherwise a rider
/// between two far-apart vertices jumps backwards and forwards.
///
/// [fromIndex] and [window] keep the search local while riding; when the rider
/// is far from that window the whole line is scanned once so re-routing,
/// restarts and shortcuts still resolve correctly.
RouteProjection? projectOnPolyline(
  GeoPoint position,
  List<GeoPoint> line,
  List<double> cumulative, {
  int fromIndex = 0,
  int window = 400,
  double windowAcceptMeters = 250,
}) {
  if (line.length < 2 || cumulative.length != line.length) return null;

  RouteProjection? scan(int start, int end) {
    RouteProjection? best;
    var bestDistance = double.infinity;
    final latScale = math.cos(position.lat * _deg2rad).abs().clamp(0.05, 1.0);
    for (var i = start; i < end; i++) {
      final a = line[i];
      final b = line[i + 1];
      // Local equirectangular projection in metres; exact enough over a
      // single route segment and far cheaper than a spherical solve.
      final ax = 0.0;
      final ay = 0.0;
      final bx = (b.lon - a.lon) * latScale * 111320.0;
      final by = (b.lat - a.lat) * 110540.0;
      final px = (position.lon - a.lon) * latScale * 111320.0;
      final py = (position.lat - a.lat) * 110540.0;
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      double t = 0;
      if (lengthSquared > 0) {
        t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared;
        t = t.clamp(0.0, 1.0);
      }
      final cx = ax + dx * t;
      final cy = ay + dy * t;
      final distance = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (distance < bestDistance) {
        bestDistance = distance;
        final segmentLength = cumulative[i + 1] - cumulative[i];
        best = RouteProjection(
          segmentIndex: i,
          alongMeters: cumulative[i] + segmentLength * t,
          offRouteMeters: distance,
          snapped: GeoPoint(
            lat: a.lat + (b.lat - a.lat) * t,
            lon: a.lon + (b.lon - a.lon) * t,
          ),
        );
      }
    }
    return best;
  }

  final start = math.max(0, fromIndex - 20);
  final end = math.min(line.length - 1, fromIndex + window);
  final local = scan(start, end);
  if (local != null && local.offRouteMeters <= windowAcceptMeters) return local;

  final global = scan(0, line.length - 1);
  if (global == null) return local;
  if (local == null) return global;
  return global.offRouteMeters < local.offRouteMeters ? global : local;
}

/// Ramer–Douglas–Peucker simplification, used for map previews and for keeping
/// uploaded/stored geometry small.
List<GeoPoint> simplifyPolyline(List<GeoPoint> points, double toleranceMeters) {
  if (points.length < 3) return List<GeoPoint>.of(points);
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  final stack = <List<int>>[
    [0, points.length - 1],
  ];
  final latScale = math.cos(points.first.lat * _deg2rad).abs().clamp(0.05, 1.0);

  double perpendicular(GeoPoint p, GeoPoint a, GeoPoint b) {
    final ax = (a.lon) * latScale * 111320.0;
    final ay = a.lat * 110540.0;
    final bx = (b.lon) * latScale * 111320.0;
    final by = b.lat * 110540.0;
    final px = (p.lon) * latScale * 111320.0;
    final py = p.lat * 110540.0;
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared;
    t = t.clamp(0.0, 1.0);
    final cx = ax + dx * t;
    final cy = ay + dy * t;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final first = range[0];
    final last = range[1];
    var index = -1;
    var maxDistance = toleranceMeters;
    for (var i = first + 1; i < last; i++) {
      final d = perpendicular(points[i], points[first], points[last]);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }
    if (index != -1) {
      keep[index] = true;
      stack.add([first, index]);
      stack.add([index, last]);
    }
  }

  final result = <GeoPoint>[];
  for (var i = 0; i < points.length; i++) {
    if (keep[i]) result.add(points[i]);
  }
  return result;
}

/// Evenly thins a list down to at most [maxPoints] entries, always keeping the
/// first and last sample.
List<GeoPoint> samplePolyline(List<GeoPoint> points, int maxPoints) {
  if (points.length <= maxPoints || maxPoints < 2) {
    return List<GeoPoint>.of(points);
  }
  final step = (points.length - 1) / (maxPoints - 1);
  final result = <GeoPoint>[];
  for (var i = 0; i < maxPoints - 1; i++) {
    result.add(points[(i * step).floor()]);
  }
  result.add(points.last);
  return result;
}

class GeoBounds {
  const GeoBounds({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  GeoPoint get center =>
      GeoPoint(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2);

  static GeoBounds? of(List<GeoPoint> points) {
    if (points.isEmpty) return null;
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLon = points.first.lon;
    var maxLon = points.first.lon;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    return GeoBounds(
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
    );
  }
}

/// Total ascent with hysteresis so GPS altitude jitter is not counted as
/// climbing. Feed it raw altitudes in metres, in chronological order.
class ElevationAccumulator {
  ElevationAccumulator({this.smoothing = 0.25, this.thresholdMeters = 3.0});

  /// Exponential smoothing factor applied to every new altitude sample.
  final double smoothing;

  /// A rider must gain this much above the last confirmed low point before the
  /// climb is counted.
  final double thresholdMeters;

  double? _smoothed;
  double? _reference;
  double _gain = 0;
  double _loss = 0;

  double get gainMeters => _gain;
  double get lossMeters => _loss;
  double? get smoothedAltitude => _smoothed;

  void add(double? altitude) {
    if (altitude == null || !altitude.isFinite) return;
    // Altitudes outside this band are sensor errors, not mountains.
    if (altitude < -500 || altitude > 9000) return;
    final previous = _smoothed;
    final value = previous == null
        ? altitude
        : previous + (altitude - previous) * smoothing;
    _smoothed = value;
    final reference = _reference;
    if (reference == null) {
      _reference = value;
      return;
    }
    final delta = value - reference;
    if (delta >= thresholdMeters) {
      _gain += delta;
      _reference = value;
    } else if (delta <= -thresholdMeters) {
      _loss += -delta;
      _reference = value;
    }
  }

  void reset() {
    _smoothed = null;
    _reference = null;
    _gain = 0;
    _loss = 0;
  }
}
