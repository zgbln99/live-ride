import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../i18n/strings.dart';
import '../core/geo.dart';
import '../core/ride_metrics_accumulator.dart';
import '../models/navigation_plan.dart';
import '../models/ride_metrics.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import 'heart_rate_service.dart';
import 'live_activity_service.dart';
import 'live_service.dart';
import 'local_store.dart';
import 'location_service.dart';
import 'profile_service.dart';
import 'ride_storage_service.dart';
import 'alert_controller.dart';
import 'alert_engine.dart';
import 'climb_tracker.dart';
import 'garage_service.dart';
import 'health_service.dart';
import 'race_mode_controller.dart';
import '../models/pace_partner.dart';
import '../models/ride_alert.dart';
import '../models/training.dart';
import 'pace_partner.dart';
import 'phone_battery.dart';
import 'segment_matcher.dart';
import 'safety_service.dart';
import 'segment_service.dart';
import 'sync_service.dart';
import 'workout_controller.dart';
import 'sensor_hub.dart';
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
    required this.sensors,
    required this.alerts,
    required this.garage,
    required this.health,
    required this.race,
    required this.safety,
    required this.segments,
    required this.workoutRunner,
    required this.pace,
    required this.sync,
    required this.live,
    required this.weather,
    required this.profile,
    required this.liveActivity,
    this.battery,
  });

  final LocationService location;
  final RideStorageService storage;
  final HeartRateService heartRate;
  final SensorHub sensors;
  final AlertController alerts;
  final GarageService garage;
  final HealthService health;
  final RaceModeController race;
  final SafetyService safety;
  final SegmentService segments;
  final WorkoutController workoutRunner;
  final PacePartnerService pace;
  final SyncService sync;

  /// Gdzie zawodnik jest względem podjazdów na trasie.
  final ClimbTracker climbs = ClimbTracker();
  final LiveSessionController live;
  final WeatherService weather;
  final ProfileService profile;
  final LiveActivityService liveActivity;

  /// Bateria telefonu dla telemetrii LIVE. Opcjonalna: testy jej nie mają.
  final PhoneBattery? battery;

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
    climbs.attach(route);
    _progress = null;
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _autoPaused = false;
    _slowSince = null;
    _rawSpeedKmh = null;
    _lastRawSample = null;
    alerts.reset();
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

    // Kadencja i moc idą prosto z sensorów do akumulatora — rejestrator jest
    // jedynym miejscem, które je zlicza, więc ekran i zapis nigdy się nie
    // rozjadą.
    sensors.addListener(_onSensors);
    _onSensors();

    _positionSub = location.positionStream().listen(
      _onPosition,
      onError: _onPositionError,
    );

    safety.startWatching();
    segments.matcher.reset();

    // Ekran blokady jest napędzany rejestratorem, a nie widokiem jazdy:
    // aktywność startuje razem z przejazdem i żyje tak długo jak on, nawet
    // gdy komputer rowerowy nie jest na wierzchu.
    unawaited(
      liveActivity.start(
        riderName: profile.riderName,
        title: _defaultRideName(_startedAt!),
        navigating: plan != null,
      ),
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _evaluateAutoPause();
      _feedWorkout();
      _publishWorkoutAlert();
      _feedAlerts();
      if (_state != RideState.recording) return;
      _publish();
    });

    final first = await location.currentPosition();
    if (first != null) _onPosition(first);
  }

  /// Prędkość prosto z fixa, liczona także na pauzie.
  ///
  /// Akumulator na pauzie nie przyjmuje próbek, więc jego prędkość zastyga na
  /// ostatniej wartości sprzed postoju — gdyby to nią decydować o wznowieniu,
  /// licznik ruszyłby natychmiast albo nie ruszył nigdy.
  double? _rawSpeedKmh;
  RideSample? _lastRawSample;

  void _trackRawSpeed(RideSample sample) {
    final reported = sample.speedMps;
    if (reported != null && reported >= 0 && reported < 35) {
      _rawSpeedKmh = reported * 3.6;
    } else {
      final previous = _lastRawSample;
      if (previous != null) {
        final seconds =
            sample.timestamp.difference(previous.timestamp).inMilliseconds /
            1000;
        if (seconds > 0.2 && seconds < 30) {
          final meters = haversineMeters(previous.point, sample.point);
          _rawSpeedKmh = meters / seconds * 3.6;
        }
      }
    }
    _lastRawSample = sample;
  }

  /// Czy licznik stoi dlatego, że zawodnik stanął — a nie dlatego, że sam
  /// nacisnął pauzę. Ręczna pauza nigdy nie wznawia się sama.
  bool _autoPaused = false;
  DateTime? _slowSince;

  bool get isAutoPaused => _autoPaused;

  void pause() {
    if (_state != RideState.recording) return;
    _autoPaused = false;
    _pauseInternal();
  }

  void _pauseInternal() {
    _state = RideState.paused;
    _pausedAt = DateTime.now();
    _accumulator.breakContinuity();
    _publish();
  }

  void resume() {
    _autoPaused = false;
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
    sensors.removeListener(_onSensors);
    _ticker?.cancel();
    _ticker = null;
    unawaited(liveActivity.end());

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
        averagePower: finalMetrics.power?.average,
        maxPower: finalMetrics.power?.maximum,
        normalizedPower: finalMetrics.power?.normalized,
        intensityFactor: finalMetrics.power?.intensityFactor,
        trainingStressScore: finalMetrics.power?.trainingStressScore,
        averageCadence: finalMetrics.averageCadenceRpm?.round(),
        // Kalorie liczone z realnej pracy, nie z szacunku po tętnie —
        // bez miernika mocy pole zostaje puste.
        calories: finalMetrics.workKj == null
            ? null
            : (finalMetrics.workKj! * 0.24).round(),
        routeId: _route?.id,
        routeName: _route?.name,
        bikeId: garage.activeBike?.id,
        riderName: profile.riderName,
        points: List.unmodifiable(_points),
      );
      await storage.save(ride);
      saved = ride;
      // Licznik roweru rośnie razem z przejazdem, żeby przypomnienia
      // serwisowe miały się na czym oprzeć.
      await garage.recordRide(
        bikeId: ride.bikeId,
        distanceMeters: ride.distanceMeters,
      );
      // Próby na segmentach zapisują się razem z przejazdem, żeby rekord
      // i przejazd, w którym padł, zawsze wskazywały na siebie nawzajem.
      await segments.storeRuns(segments.matcher.finished, rideId: ride.id);
    }

    // Tryb wyścigu nie ma prawa przeżyć przejazdu i zostawić telefonu
    // z podkręconą jasnością.
    unawaited(race.reset());
    safety.stopWatching();
    pace.stop();
    workoutRunner.stop();

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
    sensors.removeListener(_onSensors);
    _ticker?.cancel();
    _ticker = null;
    unawaited(liveActivity.end());
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
    if (hour < 11) return S.rideMorning;
    if (hour < 15) return S.rideMidday;
    if (hour < 19) return S.rideAfternoon;
    return S.rideEvening;
  }

  void _onPositionError(Object error) {
    _error = error is LocationUnavailable ? error.message : S.lostGpsSignal;
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
    _trackRawSpeed(sample);
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
          cadence: _accumulator.cadenceRpm?.round(),
          power: sensors.snapshot.powerWatts,
          distanceMeters: _accumulator.distanceMeters,
        ),
      );
    }

    _updateProgress(sample.point);
    _updateClimb(sample.point);
    segments.matcher.update(sample.point, now: sample.timestamp);
    safety.updateRide(
      speedKmh: _rawSpeedKmh ?? _accumulator.speedKmh,
      position: sample.point,
      liveUrl: live.viewerUrl,
    );
    _publish();

    unawaited(_pushTelemetry(position));
    unawaited(weather.refreshFor(sample.point));
  }

  /// Stan aktualnego podjazdu albo null, gdy zawodnik na żadnym nie jest.
  ClimbProgress? get climbProgress => climbs.progress;

  /// Stan aktualnego segmentu albo null.
  SegmentProgress? get segmentProgress => segments.matcher.progress;

  /// Stan bieżącego kroku treningu albo null.
  WorkoutProgress? get workoutProgress => workoutRunner.progress;

  /// Porównanie z wirtualnym rywalem albo null, gdy żadnego nie ma.
  PaceComparison? get paceComparison =>
      pace.compare(riderMeters: _accumulator.distanceMeters, elapsed: elapsed);

  void _updateClimb(GeoPoint point) {
    if (_route == null) return;
    climbs.update(
      point,
      averageSpeedKmh: _accumulator.speedKmh,
      heartRate: _metrics.averageHeartRate,
      powerWatts: _metrics.power?.average,
    );
  }

  /// Stan, który zobaczą obserwujący.
  ///
  /// Rozróżnienie jest istotne: „POSTÓJ" to zawodnik na światłach, „PAUZA" to
  /// świadomie zatrzymany licznik. Widz, który widzi tylko „stoi", nie wie,
  /// czy czekać, czy jechać na spotkanie.
  String get _liveState {
    if (_state == RideState.paused) return _autoPaused ? 'stopped' : 'paused';
    if (_autoPaused) return 'stopped';
    return 'riding';
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
      state: _liveState,
      movingSeconds: _metrics.movingTime.inSeconds,
      maxSpeedKmh: _metrics.maxSpeedKmh,
      batteryPercent: battery?.percent ?? 0,
    );
    final failed = !ok;
    if (_liveTelemetryFailed != failed) {
      _liveTelemetryFailed = failed;
      notifyListeners();
    }
  }

  void _onSensors() {
    if (_state != RideState.recording) return;
    final snapshot = sensors.snapshot;
    final cadence = snapshot.cadenceRpm;
    if (cadence != null) _accumulator.addCadence(cadence);
    final power = snapshot.powerWatts;
    if (power != null) {
      _accumulator.addPower(
        power,
        balancePercent: snapshot.pedalBalancePercent,
      );
    }
    _accumulator
      ..speedSource = sensors.sources.speed
      ..setSensorSpeed(snapshot.speedKmh);
  }

  /// Zatrzymuje i wznawia licznik na postoju.
  ///
  /// Próg i opóźnienie są w profilu, bo „stoję" znaczy co innego na światłach
  /// w mieście i co innego na podjeździe, gdzie 3 km/h to wciąż jazda.
  void _evaluateAutoPause() {
    final settings = profile.profile;
    if (!settings.autoPause) return;
    if (_position == null) return;

    final now = DateTime.now();

    if (_state == RideState.recording) {
      final speed = _accumulator.speedKmh;
      if (speed >= settings.autoPauseSpeedKmh) {
        _slowSince = null;
        return;
      }
      final since = _slowSince ??= now;
      if (now.difference(since).inSeconds >= settings.autoPauseDelaySeconds) {
        _slowSince = null;
        _autoPaused = true;
        _pauseInternal();
      }
      return;
    }

    if (_state == RideState.paused && _autoPaused) {
      // Ruszenie wznawia od razu: czekanie na potwierdzenie zabrałoby
      // zawodnikowi pierwsze metry po każdych światłach. Margines nad progiem
      // to histereza — bez niej drgania GPS na postoju mrugałyby licznikiem.
      final speed = _rawSpeedKmh ?? 0;
      if (speed >= settings.autoPauseSpeedKmh + 1) {
        _autoPaused = false;
        resume();
      }
    }
  }

  /// Karmi trening stanem jazdy raz na sekundę.
  void _feedWorkout() {
    if (_state != RideState.recording) return;
    if (!workoutRunner.isRunning) return;
    final snapshot = sensors.snapshot;
    workoutRunner.update(
      elapsed: elapsed,
      distanceMeters: _accumulator.distanceMeters,
      powerWatts: snapshot.powerWatts,
      heartRate: _metrics.heartRate,
      cadenceRpm: snapshot.cadenceRpm,
      speedKmh: _accumulator.speedKmh,
    );
  }

  /// Zamienia odchylenie od celu treningu w powiadomienie.
  void _publishWorkoutAlert() {
    final deviation = workoutRunner.takeDeviationAlert();
    final progress = workoutRunner.progress;
    if (deviation == null || progress == null) return;
    alerts.show(
      RideAlert(
        kind: switch (progress.step.target) {
          WorkoutTarget.power => AlertKind.powerHigh,
          WorkoutTarget.heartRate => AlertKind.heartRateHigh,
          WorkoutTarget.cadence => AlertKind.cadenceLow,
          _ => AlertKind.timeInterval,
        },
        message: deviation < 0
            ? '${progress.step.name}: ${S.pushHarder.toLowerCase()} '
                  '(${progress.step.targetLabel})'
            : '${progress.step.name}: ${S.easeOff.toLowerCase()} '
                  '(${progress.step.targetLabel})',
        at: DateTime.now(),
        severity: AlertSeverity.warning,
      ),
    );
  }

  /// Podaje silnikowi powiadomień stan jazdy raz na sekundę.
  ///
  /// Wszystko, czego nie da się stwierdzić, idzie jako null — silnik wtedy
  /// po prostu o tym milczy, zamiast zgadywać.
  void _feedAlerts() {
    if (!isActive) return;
    final sensorSnapshot = sensors.snapshot;
    final lowest = sensors.connected
        .map((device) => device.batteryPercent)
        .whereType<int>()
        .fold<int?>(null, (lowest, value) {
          return lowest == null || value < lowest ? value : lowest;
        });
    final lowestDevice = lowest == null
        ? null
        : sensors.connected
              .where((device) => device.batteryPercent == lowest)
              .firstOrNull;
    final forecast = weather.current;

    alerts.feed(
      AlertContext(
        now: DateTime.now(),
        elapsed: elapsed,
        distanceMeters: _accumulator.distanceMeters,
        metric: profile.profile.metricUnits,
        heartRate: _metrics.heartRate,
        powerWatts: sensorSnapshot.powerWatts,
        cadenceRpm: sensorSnapshot.cadenceRpm,
        offRoute: _progress?.offRoute ?? false,
        climbAheadMeters: climbs.metersToUpcoming,
        climbLabel: climbs.upcomingClimb?.category.label,
        lowestSensorBatteryPercent: lowest,
        lowBatterySensorName: lowestDevice?.name,
        rainProbability: forecast?.precipitationProbability,
        minutesToSunset: forecast?.minutesToSunset,
        paused: _state != RideState.recording,
      ),
    );
  }

  void _publish() {
    _metrics = _accumulator.build(
      elapsed: elapsed,
      pointCount: _points.length,
      hasFix: _position != null,
    );
    unawaited(
      liveActivity.update(
        metrics: _metrics,
        paused: _state == RideState.paused,
        live: live.isActive,
        metric: profile.profile.metricUnits,
        progress: _progress,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _heartRateSub?.cancel();
    sensors.removeListener(_onSensors);
    _ticker?.cancel();
    super.dispose();
  }
}
