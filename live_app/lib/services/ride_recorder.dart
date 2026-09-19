import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../core/ride_metrics_accumulator.dart';
import '../models/navigation_plan.dart';
import '../models/ride_metrics.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import 'heart_rate_service.dart';
import 'live_service.dart';
import 'local_store.dart';
import 'location_service.dart';
import 'profile_service.dart';
import 'ride_storage_service.dart';
import 'weather_service.dart';

enum RideState { idle, preparing, recording, paused, saving }

/// The ride computer engine.
///
/// It is created once for the whole app and outlives every screen, so a
/// rebuild, a tab switch or a navigation push can never drop an active ride.
/// Screens only read [metrics], [state] and [progress].
class RideRecorder extends ChangeNotifier {
  RideRecorder({
    required this.location,
    required this.storage,
    required this.heartRate,
    required this.live,
    required this.weather,
    required this.profile,
  });

  final LocationService location;
  final RideStorageService storage;
  final HeartRateService heartRate;
  final LiveSessionController live;
  final WeatherService weather;
  final ProfileService profile;

  final RideMetricsAccumulator _accumulator = RideMetricsAccumulator();
  final List<RecordedRidePoint> _points = [];

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<int>? _heartRateSub;
  Timer? _ticker;

  RideState _state = RideState.idle;
  RideMetrics _metrics = RideMetrics.empty;
  GeoPoint? _position;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;
  RideRoute? _route;
  NavigationPlan? _plan;
  NavigationProgress? _progress;
  String? _error;
  bool _liveTelemetryFailed = false;

  RideState get state => _state;
  RideMetrics get metrics => _metrics;
  GeoPoint? get position => _position;
  DateTime? get startedAt => _startedAt;
  RideRoute? get route => _route;
  NavigationPlan? get plan => _plan;
  NavigationProgress? get progress => _progress;
  String? get error => _error;
  bool get liveTelemetryFailed => _liveTelemetryFailed;
  List<RecordedRidePoint> get points => List.unmodifiable(_points);

  bool get isActive =>
      _state == RideState.recording || _state == RideState.paused;
  bool get isNavigating => _plan != null;

  /// The recorded track so far, for drawing on the map.
  List<GeoPoint> get track => [for (final point in _points) point.geo];

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final paused = _pausedAt == null
        ? _pausedTotal
        : _pausedTotal + DateTime.now().difference(_pausedAt!);
    final total = DateTime.now().difference(started) - paused;
    return total.isNegative ? Duration.zero : total;
  }

  /// Starts recording. Throws [LocationUnavailable] if the rider cannot be
  /// located; everything else is reported through [error].
  Future<void> start({RideRoute? route, NavigationPlan? plan}) async {
    if (isActive) return;

    _state = RideState.preparing;
    _error = null;
    notifyListeners();

    try {
      await location.ensurePermission();
    } catch (e) {
      _state = RideState.idle;
      notifyListeners();
      rethrow;
    }

    _accumulator.reset();
    _points.clear();
    _route = route;
    _plan = plan;
    _progress = null;
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _startedAt = DateTime.now();
    _state = RideState.recording;
    _metrics = _accumulator.build(
      elapsed: Duration.zero,
      pointCount: 0,
      hasFix: false,
    );
    notifyListeners();

    _heartRateSub = heartRate.bpm.listen((bpm) {
      _accumulator.addHeartRate(bpm);
    });
    final currentBpm = heartRate.latestBpm;
    if (currentBpm != null) _accumulator.addHeartRate(currentBpm);

    _positionSub = location.positionStream().listen(
      _onPosition,
      onError: _onPositionError,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != RideState.recording) return;
      _publish();
    });

    final first = await location.currentPosition();
    if (first != null) _onPosition(first);
  }

  void pause() {
    if (_state != RideState.recording) return;
    _state = RideState.paused;
    _pausedAt = DateTime.now();
    _accumulator.breakContinuity();
    _publish();
  }

  void resume() {
    if (_state != RideState.paused) return;
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedTotal += DateTime.now().difference(pausedAt);
    }
    _pausedAt = null;
    _state = RideState.recording;
    _accumulator.breakContinuity();
    _publish();
  }

  /// Ends the ride, saves it and returns the stored record.
  ///
  /// A ride with no usable track is discarded instead of littering the history
  /// with empty entries; the caller gets null.
  Future<RecordedRide?> stop({String? name}) async {
    if (!isActive) return null;
    _state = RideState.saving;
    notifyListeners();

    await _positionSub?.cancel();
    _positionSub = null;
    await _heartRateSub?.cancel();
    _heartRateSub = null;
    _ticker?.cancel();
    _ticker = null;

    final started = _startedAt ?? DateTime.now();
    final finalElapsed = elapsed;
    final finalMetrics = _accumulator.build(
      elapsed: finalElapsed,
      pointCount: _points.length,
      hasFix: _position != null,
    );

    RecordedRide? saved;
    if (_points.length >= 2 && finalMetrics.distanceMeters > 25) {
      final ride = RecordedRide(
        id: newLocalId('ride'),
        name: name?.trim().isNotEmpty == true
            ? name!.trim()
            : _defaultRideName(started),
        startedAt: started,
        endedAt: DateTime.now(),
        elapsedSeconds: finalElapsed.inSeconds,
        movingSeconds: finalMetrics.movingTime.inSeconds,
        distanceMeters: finalMetrics.distanceMeters,
        elevationGainMeters: finalMetrics.elevationGainMeters,
        elevationLossMeters: finalMetrics.elevationLossMeters,
        maxSpeedKmh: finalMetrics.maxSpeedKmh,
        averageHeartRate: finalMetrics.averageHeartRate,
        maxHeartRate: finalMetrics.maxHeartRate,
        routeName: _route?.name,
        riderName: profile.riderName,
        points: List.unmodifiable(_points),
      );
      await storage.save(ride);
      saved = ride;
    }

    _state = RideState.idle;
    _metrics = finalMetrics;
    _startedAt = null;
    _pausedAt = null;
    _pausedTotal = Duration.zero;
    _route = null;
    _plan = null;
    _progress = null;
    notifyListeners();
    return saved;
  }

  /// Ends the ride without saving anything.
  Future<void> discard() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _heartRateSub?.cancel();
    _heartRateSub = null;
    _ticker?.cancel();
    _ticker = null;
    _accumulator.reset();
    _points.clear();
    _state = RideState.idle;
    _metrics = RideMetrics.empty;
    _startedAt = null;
    _pausedAt = null;
    _pausedTotal = Duration.zero;
    _route = null;
    _plan = null;
    _progress = null;
    notifyListeners();
  }

  String _defaultRideName(DateTime started) {
    final routeName = _route?.name;
    if (routeName != null && routeName.trim().isNotEmpty) return routeName;
    final hour = started.hour;
    final part = hour < 11
        ? 'Morning ride'
        : hour < 15
        ? 'Midday ride'
        : hour < 19
        ? 'Afternoon ride'
        : 'Evening ride';
    return part;
  }

  void _onPositionError(Object error) {
    _error = error is LocationUnavailable
        ? error.message
        : 'Lost the GPS signal.';
    notifyListeners();
  }

  void _onPosition(Position position) {
    final sample = RideSample(
      lat: position.latitude,
      lon: position.longitude,
      timestamp: position.timestamp,
      altitude: position.altitude.isFinite ? position.altitude : null,
      speedMps: position.speed.isFinite ? position.speed : null,
      accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
      headingDegrees: position.heading.isFinite && position.heading >= 0
          ? position.heading
          : null,
    );
    if (!sample.isValid) return;

    // The marker always follows the raw fix so it stays geographically
    // truthful, even when the sample is not counted towards distance.
    _position = sample.point;
    _error = null;

    if (_state == RideState.paused) {
      _publish();
      return;
    }

    final verdict = _accumulator.add(sample);
    if (verdict != SampleVerdict.rejected && _state == RideState.recording) {
      _points.add(
        RecordedRidePoint(
          lat: sample.lat,
          lon: sample.lon,
          recordedAt: sample.timestamp,
          altitude: sample.altitude,
          speedMps: sample.speedMps ?? 0,
          heartRate: _accumulator.heartRate,
          distanceMeters: _accumulator.distanceMeters,
        ),
      );
    }

    _updateProgress(sample.point);
    _publish();

    unawaited(_pushTelemetry(position));
    unawaited(weather.refreshFor(sample.point));
  }

  void _updateProgress(GeoPoint point) {
    final plan = _plan;
    if (plan == null || plan.shape.length < 2) return;
    _progress = plan.progressAt(point, fromIndex: _progress?.shapeIndex ?? 0);
  }

  Future<void> _pushTelemetry(Position position) async {
    if (!live.isActive) return;
    final ok = await live.pushPosition(
      position,
      distanceMeters: _accumulator.distanceMeters,
      elevationGainMeters: _accumulator.elevationGainMeters,
    );
    final failed = !ok;
    if (_liveTelemetryFailed != failed) {
      _liveTelemetryFailed = failed;
      notifyListeners();
    }
  }

  void _publish() {
    _metrics = _accumulator.build(
      elapsed: elapsed,
      pointCount: _points.length,
      hasFix: _position != null,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _heartRateSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
