import 'dart:math' as math;

import '../core/geo.dart';
import '../data/database.dart';

class RecordedRidePoint {
  const RecordedRidePoint({
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.altitude,
    this.speedMps = 0,
    this.heartRate,
    this.cadence,
    this.power,
    this.distanceMeters = 0,
  });

  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? altitude;
  final double speedMps;
  final int? heartRate;
  final int? cadence;
  final int? power;

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
    if (cadence != null) 'cadence': cadence,
    if (power != null) 'power': power,
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
        cadence: (json['cadence'] as num?)?.toInt(),
        power: (json['power'] as num?)?.toInt(),
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
    this.autoPausedSeconds = 0,
    this.manualPausedSeconds = 0,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.points,
    this.elevationLossMeters = 0,
    this.maxSpeedKmh = 0,
    this.averageHeartRate,
    this.maxHeartRate,
    this.averagePower,
    this.maxPower,
    this.normalizedPower,
    this.intensityFactor,
    this.trainingStressScore,
    this.averageCadence,
    this.calories,
    this.routeId,
    this.routeName,
    this.riderName,
    this.bikeId,
    this.syncStatus = SyncStatus.local,
    this.healthExported = false,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  /// Czas zegarowy od startu do mety, razem z postojami.
  final int elapsedSeconds;
  final int movingSeconds;

  /// Czas, przez który licznik stał, bo rower stał.
  ///
  /// Przejazdy zapisane przed rozdzieleniem pauz mają tu zero — i wtedy
  /// [pausedTime] jest po prostu zerem, zamiast zmyślać podział.
  final int autoPausedSeconds;

  /// Czas, przez który licznik stał, bo rowerzysta go zatrzymał.
  final int manualPausedSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double maxSpeedKmh;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final int? averagePower;
  final int? maxPower;
  final int? normalizedPower;
  final double? intensityFactor;
  final double? trainingStressScore;
  final int? averageCadence;
  final int? calories;
  final String? routeId;
  final String? routeName;
  final String? riderName;
  final String? bikeId;

  /// Czy przejazd trafił już na serwer.
  final SyncStatus syncStatus;

  /// Czy przejazd został zapisany do Apple Health / Health Connect.
  final bool healthExported;

  final List<RecordedRidePoint> points;

  bool get hasPower => averagePower != null && averagePower! > 0;
  bool get hasCadence => averageCadence != null && averageCadence! > 0;
  bool get hasHeartRate => averageHeartRate != null && averageHeartRate! > 0;

  Duration get elapsed => Duration(seconds: elapsedSeconds);
  Duration get movingTime => Duration(seconds: movingSeconds);

  /// Pauza automatyczna i ręczna razem.
  Duration get pausedTime =>
      Duration(seconds: autoPausedSeconds + manualPausedSeconds);
  Duration get autoPausedTime => Duration(seconds: autoPausedSeconds);
  Duration get manualPausedTime => Duration(seconds: manualPausedSeconds);

  /// Czas, przez który licznik chodził.
  Duration get recordingTime {
    final seconds = elapsedSeconds - autoPausedSeconds - manualPausedSeconds;
    return Duration(seconds: seconds < 0 ? 0 : seconds);
  }

  /// Czy ten przejazd w ogóle zna podział czasu na pauzy.
  ///
  /// Stare zapisy go nie znają; ekran podsumowania nie pokazuje wtedy
  /// wiersza „Pauza" zamiast pokazywać w nim zero.
  bool get hasPauseBreakdown =>
      autoPausedSeconds > 0 || manualPausedSeconds > 0;

  double get averageSpeedKmh =>
      movingSeconds <= 0 ? 0 : (distanceMeters / movingSeconds) * 3.6;

  bool get hasTrack => points.length >= 2;

  List<GeoPoint> get track => [for (final p in points) p.geo];

  /// A thinned copy for map previews on history cards.
  List<GeoPoint> get preview =>
      samplePolyline(simplifyPolyline(track, 20), 120);

  /// `(distanceMeters, altitudeMeters)` pairs for the elevation profile,
  /// smoothed so GPS altitude noise does not turn the chart into a saw.
  List<({double distance, double elevation})> elevationProfile({
    int maxSamples = 240,
  }) {
    final withAltitude = points
        .where((p) => p.altitude != null && p.altitude!.isFinite)
        .toList(growable: false);
    if (withAltitude.length < 3) return const [];
    final step = math.max(1, withAltitude.length ~/ maxSamples);
    final result = <({double distance, double elevation})>[];
    double? smoothed;
    for (var i = 0; i < withAltitude.length; i += step) {
      final point = withAltitude[i];
      final altitude = point.altitude!;
      smoothed = smoothed == null
          ? altitude
          : smoothed + (altitude - smoothed) * 0.3;
      result.add((distance: point.distanceMeters, elevation: smoothed));
    }
    return result;
  }

  RecordedRide copyWith({
    String? name,
    SyncStatus? syncStatus,
    bool? healthExported,
    String? bikeId,
  }) => RecordedRide(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt,
    endedAt: endedAt,
    elapsedSeconds: elapsedSeconds,
    movingSeconds: movingSeconds,
    autoPausedSeconds: autoPausedSeconds,
    manualPausedSeconds: manualPausedSeconds,
    distanceMeters: distanceMeters,
    elevationGainMeters: elevationGainMeters,
    elevationLossMeters: elevationLossMeters,
    maxSpeedKmh: maxSpeedKmh,
    averageHeartRate: averageHeartRate,
    maxHeartRate: maxHeartRate,
    averagePower: averagePower,
    maxPower: maxPower,
    normalizedPower: normalizedPower,
    intensityFactor: intensityFactor,
    trainingStressScore: trainingStressScore,
    averageCadence: averageCadence,
    calories: calories,
    routeId: routeId,
    routeName: routeName,
    riderName: riderName,
    bikeId: bikeId ?? this.bikeId,
    syncStatus: syncStatus ?? this.syncStatus,
    healthExported: healthExported ?? this.healthExported,
    points: points,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt.toIso8601String(),
    'elapsed_seconds': elapsedSeconds,
    'moving_seconds': movingSeconds,
    'auto_paused_seconds': autoPausedSeconds,
    'manual_paused_seconds': manualPausedSeconds,
    'distance_meters': distanceMeters,
    'elevation_gain_meters': elevationGainMeters,
    'elevation_loss_meters': elevationLossMeters,
    'max_speed_kmh': maxSpeedKmh,
    if (averageHeartRate != null) 'avg_heart_rate': averageHeartRate,
    if (maxHeartRate != null) 'max_heart_rate': maxHeartRate,
    if (averagePower != null) 'avg_power': averagePower,
    if (maxPower != null) 'max_power': maxPower,
    if (normalizedPower != null) 'normalized_power': normalizedPower,
    if (intensityFactor != null) 'intensity_factor': intensityFactor,
    if (trainingStressScore != null) 'tss': trainingStressScore,
    if (averageCadence != null) 'avg_cadence': averageCadence,
    if (calories != null) 'calories': calories,
    if (routeId != null) 'route_id': routeId,
    if (routeName != null) 'route_name': routeName,
    if (riderName != null) 'rider_name': riderName,
    if (bikeId != null) 'bike_id': bikeId,
    'sync_status': syncStatus.name,
    'health_exported': healthExported,
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
      autoPausedSeconds:
          (json['auto_paused_seconds'] as num?)?.toInt() ?? 0,
      manualPausedSeconds:
          (json['manual_paused_seconds'] as num?)?.toInt() ?? 0,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0,
      elevationGainMeters:
          (json['elevation_gain_meters'] as num?)?.toDouble() ?? 0,
      elevationLossMeters:
          (json['elevation_loss_meters'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (json['max_speed_kmh'] as num?)?.toDouble() ?? 0,
      averageHeartRate: (json['avg_heart_rate'] as num?)?.toInt(),
      maxHeartRate: (json['max_heart_rate'] as num?)?.toInt(),
      averagePower: (json['avg_power'] as num?)?.toInt(),
      maxPower: (json['max_power'] as num?)?.toInt(),
      normalizedPower: (json['normalized_power'] as num?)?.toInt(),
      intensityFactor: (json['intensity_factor'] as num?)?.toDouble(),
      trainingStressScore: (json['tss'] as num?)?.toDouble(),
      averageCadence: (json['avg_cadence'] as num?)?.toInt(),
      calories: (json['calories'] as num?)?.toInt(),
      routeId: json['route_id'] as String?,
      routeName: json['route_name'] as String?,
      riderName: json['rider_name'] as String?,
      bikeId: json['bike_id'] as String?,
      syncStatus: SyncStatus.parse(json['sync_status'] as String?),
      healthExported: json['health_exported'] as bool? ?? false,
      points: points,
    );
  }
}
