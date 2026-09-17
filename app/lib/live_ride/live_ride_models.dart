import 'package:geolocator/geolocator.dart' as geo;
import 'package:wanderer/provider/navigation_stats_provider.dart';

class LiveRideSession {
  const LiveRideSession({
    required this.id,
    required this.participantId,
    required this.shareToken,
    required this.joinToken,
  });

  final String id;
  final String participantId;
  final String shareToken;
  final String joinToken;

  factory LiveRideSession.fromJson(Map<String, dynamic> json) {
    return LiveRideSession(
      id: json['id'] as String,
      participantId: json['participant_id'] as String,
      shareToken: json['share_token'] as String,
      joinToken: json['join_token'] as String,
    );
  }
}

class LiveRideTelemetryPoint {
  const LiveRideTelemetryPoint({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.altitudeM,
    required this.headingDeg,
    required this.accuracyM,
    required this.distanceM,
    required this.elevationGainM,
    this.heartRateBpm,
  });

  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double altitudeM;
  final double headingDeg;
  final double accuracyM;
  final double distanceM;
  final double elevationGainM;
  final int? heartRateBpm;

  factory LiveRideTelemetryPoint.fromPosition({
    required geo.Position position,
    required NavigationStats stats,
    int? heartRateBpm,
  }) {
    return LiveRideTelemetryPoint(
      recordedAt: position.timestamp.toUtc(),
      latitude: position.latitude,
      longitude: position.longitude,
      speedKmh: stats.currentSpeedKmh,
      altitudeM: position.altitude,
      headingDeg: position.heading,
      accuracyM: position.accuracy,
      distanceM: stats.distanceMeters,
      elevationGainM: stats.elevationGainMeters,
      heartRateBpm: heartRateBpm,
    );
  }

  Map<String, dynamic> toJson() => {
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'speed_kmh': speedKmh,
    'altitude_m': altitudeM,
    'heading_deg': headingDeg,
    'accuracy_m': accuracyM,
    'heart_rate_bpm': heartRateBpm ?? 0,
    'distance_m': distanceM,
    'elevation_gain_m': elevationGainM,
  };

  factory LiveRideTelemetryPoint.fromJson(Map<String, dynamic> json) {
    return LiveRideTelemetryPoint(
      recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speedKmh: (json['speed_kmh'] as num).toDouble(),
      altitudeM: (json['altitude_m'] as num).toDouble(),
      headingDeg: (json['heading_deg'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num).toDouble(),
      distanceM: (json['distance_m'] as num).toDouble(),
      elevationGainM: (json['elevation_gain_m'] as num).toDouble(),
      heartRateBpm: (json['heart_rate_bpm'] as num?)?.toInt(),
    );
  }
}
