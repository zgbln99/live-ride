import 'dart:math' as math;

import '../core/geo.dart';

class RecordedRidePoint {
  const RecordedRidePoint({
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.altitude,
    this.speedMps = 0,
    this.heartRate,
    this.distanceMeters = 0,
  });

  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? altitude;
  final double speedMps;
  final int? heartRate;

  /// Cumulative ride distance at this sample. Stored so the elevation profile
  /// and the summary map do not have to re-integrate the track.
  final double distanceMeters;

  GeoPoint get geo =>
      GeoPoint(lat: lat, lon: lon, elevation: altitude, time: recordedAt);

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    'recorded_at': recordedAt.toIso8601String(),
    if (altitude != null) 'altitude': altitude,
    'speed': speedMps,
    if (heartRate != null) 'heart_rate': heartRate,
    'distance_m': distanceMeters,
  };

  factory RecordedRidePoint.fromJson(Map<String, dynamic> json) =>
      RecordedRidePoint(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        recordedAt:
            DateTime.tryParse(json['recorded_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        altitude: (json['altitude'] as num?)?.toDouble(),
        speedMps: (json['speed'] as num?)?.toDouble() ?? 0,
        heartRate: (json['heart_rate'] as num?)?.toInt(),
        distanceMeters: (json['distance_m'] as num?)?.toDouble() ?? 0,
      );
}

/// A finished ride, stored locally and exportable as GPX.
class RecordedRide {
  RecordedRide({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.elapsedSeconds,
    required this.movingSeconds,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.points,
    this.elevationLossMeters = 0,
    this.maxSpeedKmh = 0,
    this.averageHeartRate,
    this.maxHeartRate,
    this.routeName,
    this.riderName,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final int elapsedSeconds;
  final int movingSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double maxSpeedKmh;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final String? routeName;
  final String? riderName;
  final List<RecordedRidePoint> points;

  Duration get elapsed => Duration(seconds: elapsedSeconds);
  Duration get movingTime => Duration(seconds: movingSeconds);

  double get averageSpeedKmh =>
      movingSeconds <= 0 ? 0 : (distanceMeters / movingSeconds) * 3.6;

  bool get hasTrack => points.length >= 2;

  List<GeoPoint> get track => [for (final p in points) p.geo];

  /// A thinned copy for map previews on history cards.
  List<GeoPoint> get preview =>
      samplePolyline(simplifyPolyline(track, 20), 120);

  /// `(distanceMeters, altitudeMeters)` pairs for the elevation profile,
  /// smoothed so GPS altitude noise does not turn the chart into a saw.
  List<({double distance, double altitude})> elevationProfile({
    int maxSamples = 240,
  }) {
    final withAltitude = points
        .where((p) => p.altitude != null && p.altitude!.isFinite)
        .toList(growable: false);
    if (withAltitude.length < 3) return const [];
    final step = math.max(1, withAltitude.length ~/ maxSamples);
    final result = <({double distance, double altitude})>[];
    double? smoothed;
    for (var i = 0; i < withAltitude.length; i += step) {
      final point = withAltitude[i];
      final altitude = point.altitude!;
      smoothed = smoothed == null
          ? altitude
          : smoothed + (altitude - smoothed) * 0.3;
      result.add((distance: point.distanceMeters, altitude: smoothed));
    }
    return result;
  }

  RecordedRide copyWith({String? name}) => RecordedRide(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt,
    endedAt: endedAt,
    elapsedSeconds: elapsedSeconds,
    movingSeconds: movingSeconds,
    distanceMeters: distanceMeters,
    elevationGainMeters: elevationGainMeters,
    elevationLossMeters: elevationLossMeters,
    maxSpeedKmh: maxSpeedKmh,
    averageHeartRate: averageHeartRate,
    maxHeartRate: maxHeartRate,
    routeName: routeName,
    riderName: riderName,
    points: points,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt.toIso8601String(),
    'elapsed_seconds': elapsedSeconds,
    'moving_seconds': movingSeconds,
    'distance_meters': distanceMeters,
    'elevation_gain_meters': elevationGainMeters,
    'elevation_loss_meters': elevationLossMeters,
    'max_speed_kmh': maxSpeedKmh,
    if (averageHeartRate != null) 'avg_heart_rate': averageHeartRate,
    if (maxHeartRate != null) 'max_heart_rate': maxHeartRate,
    if (routeName != null) 'route_name': routeName,
    if (riderName != null) 'rider_name': riderName,
    'points': [for (final p in points) p.toJson()],
  };

  factory RecordedRide.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => RecordedRidePoint.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
    final moving = (json['moving_seconds'] as num?)?.toInt() ?? 0;
    return RecordedRide(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Ride',
      startedAt:
          DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now(),
      endedAt:
          DateTime.tryParse(json['ended_at'] as String? ?? '') ??
          DateTime.now(),
      // Rides written before elapsed time was tracked separately fall back to
      // their moving time rather than showing zero.
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toInt() ?? moving,
      movingSeconds: moving,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0,
      elevationGainMeters:
          (json['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
      elevationLossMeters:
          (json['elevation_loss_meters'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (json['max_speed_kmh'] as num?)?.toDouble() ?? 0,
      averageHeartRate: (json['avg_heart_rate'] as num?)?.toInt(),
      maxHeartRate: (json['max_heart_rate'] as num?)?.toInt(),
      routeName: json['route_name'] as String?,
      riderName: json['rider_name'] as String?,
      points: points,
    );
  }
}
