class RecordedRidePoint {
  const RecordedRidePoint({
    required this.lat,
    required this.lon,
    required this.altitude,
    required this.speed,
    required this.recordedAt,
    this.heartRate,
  });

  final double lat;
  final double lon;
  final double altitude;
  final double speed;
  final DateTime recordedAt;
  final int? heartRate;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'altitude': altitude,
        'speed': speed,
        'recorded_at': recordedAt.toIso8601String(),
        if (heartRate != null) 'heart_rate': heartRate,
      };

  factory RecordedRidePoint.fromJson(Map<String, dynamic> json) => RecordedRidePoint(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        altitude: (json['altitude'] as num?)?.toDouble() ?? 0,
        speed: (json['speed'] as num?)?.toDouble() ?? 0,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        heartRate: (json['heart_rate'] as num?)?.toInt(),
      );
}

class RecordedRide {
  const RecordedRide({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.movingSeconds,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.points,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final int movingSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final List<RecordedRidePoint> points;

  double get averageSpeedKmh => movingSeconds <= 0
      ? 0
      : (distanceMeters / movingSeconds) * 3.6;

  int? get averageHeartRate {
    final values = points
        .map((p) => p.heartRate)
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'moving_seconds': movingSeconds,
        'distance_meters': distanceMeters,
        'elevation_gain_meters': elevationGainMeters,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory RecordedRide.fromJson(Map<String, dynamic> json) => RecordedRide(
        id: json['id'] as String,
        name: json['name'] as String,
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: DateTime.parse(json['ended_at'] as String),
        movingSeconds: (json['moving_seconds'] as num).toInt(),
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        elevationGainMeters: (json['elevation_gain_meters'] as num).toDouble(),
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((item) => RecordedRidePoint.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
      );
}
