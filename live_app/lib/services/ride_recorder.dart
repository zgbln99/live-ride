import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../i18n/strings.dart';
import '../core/geo.dart';
import '../core/ride_metrics_accumulator.dart';
import '../core/route_preview.dart';
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
import 'auto_pause_detector.dart';
import 'ride_clock.dart';
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
  /// Co ile odpytujemy system o pozycję, gdy LIVE trwa bez jazdy.
  static const Duration liveHeartbeatInterval = Duration(seconds: 20);

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

  /// Rozstrzyga, czy zawodnik faktycznie stoi.
  AutoPauseDetector _autoPause = AutoPauseDetector();

  @visibleForTesting
  AutoPauseDetector get autoPauseDetector => _autoPause;
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

  /// Ostatni surowy fiks, taki jak przyszedł z systemu.
  ///
  /// [_position] wystarcza do rysowania, ale telemetria LIVE potrzebuje
  /// jeszcze prędkości, kursu i dokładności — a te niesie tylko oryginał.
  Position? _lastFix;

  /// Odpytywanie pozycji dla LIVE bez rozpoczętej jazdy.
  Timer? _liveHeartbeat;

  /// Cały podział czasu na jazdę i postoje — razem z zasadą, że ręcznej
  /// pauzy nie zdejmuje nikt poza rowerzystą.
  final RideClock _clock = RideClock();
  RideRoute? _route;
  NavigationPlan? _plan;
  NavigationProgress? _progress;
  String? _error;
  bool _liveTelemetryFailed = false;

  RideState get state => _state;
  RideMetrics get metrics => _metrics;
  GeoPoint? get position => _position;
  DateTime? get startedAt => _clock.startedAt;
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

  /// Czas od startu przejazdu, niezależnie od postojów.
  ///
  /// To jest ELAPSED w rozumieniu licznika rowerowego: 13:00 → 15:00 daje
  /// 2:00:00, choćby połowa tego poszła na kawę.
  Duration get elapsed => _clock.elapsed;

  /// Czas, przez który licznik chodził — bez pauz automatycznych i ręcznych.
  ///
  /// To zatrzymuje auto-pauza i to napędza kroki treningu. Nie mylić z czasem
  /// w ruchu: postój krótszy niż próg auto-pauzy wlicza się tutaj, a do czasu
  /// w ruchu nie.
  Duration get recordingTime => _clock.recording;

  /// Łączny czas pauz, licząc trwającą.
  Duration get pausedTotal => _clock.paused;

  /// Czas spędzony w pauzie automatycznej.
  Duration get autoPausedTotal => _clock.autoPaused;

  /// Czas spędzony w pauzie wciśniętej ręcznie.
  Duration get manualPausedTotal => _clock.manualPaused;

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
    _clock.start();
    _autoPause = _buildAutoPauseDetector();
    _rawSpeedKmh = null;
    _lastRawSample = null;
    alerts.reset();
    // Od tej chwili pozycje niesie strumień jazdy.
    _liveHeartbeat?.cancel();
    _liveHeartbeat = null;
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
      liveActivity
          .start(
            riderName: profile.riderName,
            title: _defaultRideName(_clock.startedAt!),
            navigating: plan != null,
          )
          // Kształt trasy idzie raz, zaraz po starcie aktywności, a nie
          // z metrykami co sekundę. Zmienia się tylko przy przeliczeniu
          // trasy, a waży kilkaset bajtów budżetu ActivityKit.
          .then((_) => publishActiveRoute()),
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _evaluateAutoPause();
      _feedWorkout();
      _publishWorkoutAlert();
      _feedAlerts();
      _ensureRoutePublished();
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
  /// nacisnął pauzę.
  bool get isAutoPaused => _state == RideState.paused && _clock.isAutoPaused;

  /// Czy zawodnik zatrzymał licznik własnym palcem.
  ///
  /// Dwa rodzaje pauzy to dwa różne stany, nie jeden z flagą: ręczna czeka na
  /// decyzję człowieka, automatyczna na ruch roweru. Mieszanie ich znaczyłoby,
  /// że licznik rusza sam po tym, jak ktoś świadomie go zatrzymał.
  bool get isManuallyPaused =>
      _state == RideState.paused && _clock.isManuallyPaused;

  void pause() {
    if (_state != RideState.recording) return;
    // Ręczna pauza wyłącza wykrywanie postoju do czasu wznowienia — inaczej
    // pierwszy ruch po niej wyglądałby dla detektora jak koniec postoju.
    _autoPause.reset();
    _pauseInternal(automatic: false);
  }

  void _pauseInternal({required bool automatic}) {
    if (!_clock.pause(automatic: automatic)) return;
    _state = RideState.paused;
    _accumulator.breakContinuity();
    _publish();
  }

  void resume() => _resumeInternal(automatic: false);

  void _resumeInternal({required bool automatic}) {
    if (_state != RideState.paused) return;
    // Detektor nie ma prawa zdjąć pauzy, którą wcisnął rowerzysta; zegar
    // sam tego pilnuje i wtedy nic się nie dzieje.
    if (!_clock.resume(automatic: automatic)) return;
    _state = RideState.recording;
    _accumulator.breakContinuity();
    _autoPause.reset();
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

    final started = _clock.startedAt ?? DateTime.now();
    final finalElapsed = elapsed;
    final finalPaused = pausedTotal;
    final finalAutoPaused = autoPausedTotal;
    final finalManualPaused = manualPausedTotal;
    final finalMetrics = _accumulator.build(
      elapsed: finalElapsed,
      recording: recordingTime,
      paused: finalPaused,
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
        autoPausedSeconds: finalAutoPaused.inSeconds,
        manualPausedSeconds: finalManualPaused.inSeconds,
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
    _clock.reset();
    _autoPause.reset();
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
    _clock.reset();
    _autoPause.reset();
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

  /// Prędkość zgłoszona przez odbiornik albo null, gdy jej nie zna.
  ///
  /// CoreLocation sygnalizuje nieznaną prędkość wartością UJEMNĄ (zwykle −1),
  /// a nie zerem ani NaN-em. Przepuszczona dalej wyglądała jak pomiar i
  /// spychała wykrywanie postoju na tor „nie mam prędkości, mierzę samo
  /// przemieszczenie", gdzie potwierdzenie trwa dwadzieścia pięć sekund
  /// zamiast trzech. `speedAccuracy` poniżej zera znaczy to samo.
  ///
  /// Null mówi prawdę: odbiornik nie wie. Zero byłoby twierdzeniem, że stoi.
  static double? _reportedSpeed(Position position) {
    final speed = position.speed;
    if (!speed.isFinite || speed < 0) return null;
    final accuracy = position.speedAccuracy;
    if (accuracy.isFinite && accuracy < 0) return null;
    return speed;
  }

  void _onPosition(Position position) {
    _lastFix = position;
    final sample = RideSample(
      lat: position.latitude,
      lon: position.longitude,
      timestamp: position.timestamp,
      altitude: position.altitude.isFinite ? position.altitude : null,
      speedMps: _reportedSpeed(position),
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

    // Detektor dostaje każdy fix, także na pauzie: to z nich rozpoznaje, że
    // zawodnik ruszył. Decyzja może przełączyć stan, więc idzie przed
    // gałęzią pauzy.
    _feedAutoPause(sample);

    if (_state == RideState.paused) {
      _publish();
      // Telemetria leci dalej, właśnie dlatego, że licznik stoi. Bez tego
      // obserwujący po siedemdziesięciu pięciu sekundach czytałby „brak
      // aktualnych danych" o kimś, kto po prostu czeka na światłach —
      // a stan „POSTÓJ" niesie ta sama próbka, która milczała.
      unawaited(_pushTelemetry(position));
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
  PaceComparison? get paceComparison => pace.compare(
    riderMeters: _accumulator.distanceMeters,
    elapsed: recordingTime,
  );

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
    if (_state == RideState.paused) {
      return _clock.isAutoPaused ? 'stopped' : 'paused';
    }
    return 'riding';
  }

  void _updateProgress(GeoPoint point) {
    final plan = _plan;
    if (plan == null || plan.shape.length < 2) return;
    _progress = plan.progressAt(point, fromIndex: _progress?.shapeIndex ?? 0);
  }

  /// Wysyła telemetrię natychmiast, nie czekając na kolejny fiks ani na
  /// upływ zwykłego okresu nadawania.
  ///
  /// Wołane w chwili udostępnienia linku. Bez tego znajomy, który otworzy go
  /// od razu, widziałby pustą mapę do momentu, aż zawodnik RUSZY — a ten
  /// właśnie stoi przed domem i wysyła mu ten link. Pierwsza rzecz, jaką
  /// robi publiczna strona, to pokazanie, gdzie ktoś jest; czekanie na ruch
  /// zamienia ją w zagadkę.
  ///
  /// Zwraca false, gdy nie ma czego wysłać — wtedy strona pokazuje
  /// „oczekiwanie na GPS" razem z całą resztą danych, które już zna.
  Future<bool> publishLiveNow() async {
    if (!live.isActive) return false;
    // Najpierw fiks, który już mamy. Dopiero gdy licznik jeszcze nie chodzi,
    // pytamy system — to jedyna ścieżka, która może potrwać.
    final position = _lastFix ?? await location.currentPosition();
    _startLiveHeartbeat();
    if (position == null) return false;
    _lastFix ??= position;
    _position ??= GeoPoint(lat: position.latitude, lon: position.longitude);
    notifyListeners();
    return _pushTelemetry(position, force: true);
  }

  /// Podtrzymuje LIVE, gdy transmisja trwa, a licznik jeszcze nie nagrywa.
  ///
  /// Zawodnik potrafi udostępnić link przed startem — i wtedy nic nie
  /// nasłuchuje pozycji, więc po siedemdziesięciu pięciu sekundach publiczna
  /// strona uznałaby go za nieobecnego. Tętno bierze ŚWIEŻY fiks z systemu,
  /// a nie powtarza ostatniego: powtórzona pozycja ze świeżą godziną
  /// wyglądałaby jak pomiar, którego nikt nie wykonał.
  ///
  /// Rzadziej niż telemetria jazdy, bo stojący telefon nie ma czego nadawać
  /// co trzy sekundy, a bateria startuje razem z zawodnikiem.
  void _startLiveHeartbeat() {
    if (_liveHeartbeat != null) return;
    _liveHeartbeat = Timer.periodic(liveHeartbeatInterval, (timer) async {
      // Jazda przejmuje nadawanie — własny strumień pozycji jest częstszy
      // i dokładniejszy od odpytywania.
      if (!live.isActive || isActive) {
        timer.cancel();
        _liveHeartbeat = null;
        return;
      }
      final position = await location.currentPosition();
      if (position == null) return;
      _lastFix = position;
      _position = GeoPoint(lat: position.latitude, lon: position.longitude);
      notifyListeners();
      unawaited(_pushTelemetry(position, force: true));
    });
  }

  Future<bool> _pushTelemetry(Position position, {bool force = false}) async {
    if (!live.isActive) return false;
    final ok = await live.pushPosition(
      position,
      distanceMeters: _accumulator.distanceMeters,
      elevationGainMeters: _accumulator.elevationGainMeters,
      state: _liveState,
      movingSeconds: _metrics.movingTime.inSeconds,
      maxSpeedKmh: _metrics.maxSpeedKmh,
      batteryPercent: battery?.percent ?? 0,
      autoPausedSeconds: autoPausedTotal.inSeconds,
      manualPausedSeconds: manualPausedTotal.inSeconds,
      elapsedSeconds: elapsed.inSeconds,
      gradientPercent: _metrics.gradientPercent,
      nav: _navTelemetry(),
      climb: _climbTelemetry(),
      // Dystans z czujnika koła celowo nie jedzie: licznik go nie prowadzi
      // osobno, a wysłanie dystansu GPS pod tą nazwą byłoby zmyśleniem
      // drugiego pomiaru.
      sensorSpeedKmh: sensors.snapshot.speedKmh,
      freshness: _freshnessTelemetry(position),
      averages: _averagesTelemetry(),
      force: force,
    );
    final failed = !ok;
    if (_liveTelemetryFailed != failed) {
      _liveTelemetryFailed = failed;
      notifyListeners();
    }
    return ok;
  }

  /// Nawigacja tak, jak widzi ją zawodnik — albo null, gdy żadnej nie ma.
  ///
  /// Null nie jest tu brakiem danych, tylko informacją: serwer na jego widok
  /// KASUJE manewr u widzów. Inaczej po dojechaniu do mety publiczna strona
  /// zostałaby ze strzałką w lewo, której na kierownicy już dawno nie ma.
  Map<String, dynamic>? _navTelemetry() {
    final progress = _progress;
    if (progress == null) return null;
    final maneuver = progress.next ?? progress.current;
    final offRoute = progress.offRoute;
    if (maneuver == null && !offRoute) return null;
    return {
      'instruction': maneuver?.instructionPl ?? '',
      'street': maneuver?.streetName ?? '',
      'maneuver_type': maneuver?.type ?? 0,
      'distance_m': progress.distanceToManeuver,
      'remaining_m': progress.remainingMeters,
      'eta_seconds': (progress.remainingSeconds ?? 0).round(),
      'off_route': offRoute,
      'off_route_m': progress.offRouteMeters,
    };
  }

  /// Aktualny podjazd, tym samym ClimbPro, który widzi zawodnik.
  ///
  /// Null za szczytem — publiczna strona ma wtedy zdjąć kafelek podjazdu,
  /// a nie zamrozić go na „100%".
  Map<String, dynamic>? _climbTelemetry() {
    final progress = climbs.progress;
    if (progress == null) return null;
    final climb = progress.climb;
    if (climb.lengthMeters <= 0) return null;
    return {
      'index': climb.index,
      'total': _route?.analysis.climbs.length ?? 0,
      'done_m': progress.doneMeters,
      'length_m': climb.lengthMeters,
      'gain_m': climb.gainMeters,
      'remaining_gain_m': progress.remainingGainMeters,
      'avg_gradient': climb.averageGradientPercent,
      'max_gradient': climb.maxGradientPercent,
      'category': climb.category.shortLabel,
    };
  }

  /// Wiek każdej danej w sekundach, liczony w chwili wysyłki.
  ///
  /// Jeden znacznik na całą próbkę kłamał: GPS potrafi nadawać co sekundę,
  /// gdy pas HR odpadł cztery minuty wcześniej, a publiczna strona pokazywała
  /// tamto tętno jako bieżące. Ujemna wartość znaczy „nie mam tej danej
  /// wcale" i serwer czyści wtedy znacznik zamiast zapisywać zero.
  Map<String, double> _freshnessTelemetry(Position position) {
    final now = DateTime.now();
    final freshness = live.sensorFreshness(now: now);
    freshness['gps_age_seconds'] =
        now.difference(position.timestamp).inMilliseconds / 1000.0;
    freshness['nav_age_seconds'] = _progress == null ? -1 : 0;
    return freshness;
  }

  /// Średnie i maksima z licznika, żeby publiczna strona nie liczyła ich
  /// drugi raz z gorszych danych.
  ///
  /// Zero znaczy „nie mam" wyłącznie dlatego, że żadna z tych wielkości nie
  /// przyjmuje zera jako pomiaru: tętno zerowe to brak pasa, nie odpoczynek.
  Map<String, int> _averagesTelemetry() => {
    'avg_heart_rate_bpm': _metrics.averageHeartRate ?? 0,
    'max_heart_rate_bpm': _metrics.maxHeartRate ?? 0,
    'avg_power_watts': _metrics.power?.average ?? 0,
    'max_power_watts': _metrics.power?.maximum ?? 0,
    'avg_cadence_rpm': _metrics.averageCadenceRpm?.round() ?? 0,
  };

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
  /// Sama decyzja siedzi w [AutoPauseDetector] — tutaj zostaje tylko
  /// podłączenie jej do licznika. Dzięki temu „czy on stoi" da się sprawdzić
  /// testem na ciągu pozycji, a nie dopiero na drodze.
  void _evaluateAutoPause() {
    if (!profile.profile.autoPause) return;

    // Ręczna pauza nie jest przedmiotem żadnej automatyki: zawodnik zatrzymał
    // licznik świadomie i tylko on go wznowi.
    if (isManuallyPaused) return;
    if (_state != RideState.recording && !_clock.isAutoPaused) return;

    final action = _autoPause.tick(DateTime.now());
    _applyAutoPause(action);
  }

  /// Buduje detektor postoju na progach z profilu.
  ///
  /// Składany na starcie przejazdu, a nie raz na życie licznika, żeby zmiana
  /// w ustawieniach zaawansowanych obowiązywała od następnej jazdy, a nie po
  /// restarcie aplikacji.
  AutoPauseDetector _buildAutoPauseDetector() {
    final settings = profile.profile;
    return AutoPauseDetector(
      stationaryGpsKmh: settings.autoPauseSpeedKmh,
      pauseAfter: Duration(seconds: settings.autoPauseDelaySeconds),
    );
  }

  /// Podaje detektorowi świeży fix i wykonuje jego decyzję.
  void _feedAutoPause(RideSample sample) {
    if (!profile.profile.autoPause) return;
    if (isManuallyPaused) return;
    if (_state != RideState.recording && !_clock.isAutoPaused) return;

    final snapshot = sensors.snapshot;
    final action = _autoPause.update(
      AutoPauseSample(
        at: sample.timestamp,
        point: sample.point,
        gpsSpeedKmh: sample.speedMps == null ? null : sample.speedMps! * 3.6,
        accuracyMeters: sample.accuracyMeters,
        sensorSpeedKmh: snapshot.speedKmh,
        sensorAt: snapshot.at,
      ),
      recording: _state == RideState.recording,
    );
    _applyAutoPause(action);
  }

  void _applyAutoPause(AutoPauseAction action) {
    switch (action) {
      case AutoPauseAction.pause:
        if (_state != RideState.recording) return;
        _pauseInternal(automatic: true);
      case AutoPauseAction.resume:
        _resumeInternal(automatic: true);
      case AutoPauseAction.none:
        break;
    }
  }

  /// Dosyła trasę, gdy poprzednia próba nie doszła.
  ///
  /// Dwa realne przypadki, w których jedno wywołanie przy starcie nie
  /// wystarcza: zawodnik włączył LIVE JUŻ w trakcie jazdy po trasie, więc
  /// w chwili startu jazdy sesji jeszcze nie było; albo doczepienie poszło
  /// w chwilowy brak zasięgu. W obu przypadkach trasa istnieje, sesja
  /// istnieje, a widz i tak nie ma czego oglądać — i nikt się o tym nie
  /// dowie, bo nic nie wygląda na zepsute.
  ///
  /// Sprawdzenie jest darmowe: doczepienie pamięta, co już wysłało, więc
  /// wywołanie na sekundę kosztuje porównanie napisu.
  void _ensureRoutePublished() {
    if (!live.isActive || _route == null) return;
    if (live.hasAttachedRoute) return;
    unawaited(publishActiveRoute());
  }

  /// Publikuje aktywną trasę wszędzie, gdzie ma się pojawić.
  ///
  /// Dwa różne odbiorniki tej samej informacji: ekran blokady dostaje sam
  /// kształt do narysowania, a publiczny LIVE całą trasę razem z profilem
  /// wysokości i podjazdami. Jedno wywołanie, bo rozjazd między nimi znaczyłby,
  /// że obserwujący widzi inną trasę niż zawodnik.
  ///
  /// Wołane przy starcie jazdy i po każdej zmianie planu — łącznie z
  /// przeliczeniem trasy po zjechaniu z niej.
  Future<void> publishActiveRoute() async {
    await _publishRouteShape();
    if (!live.isActive) return;
    final route = _route;
    await live.attachRoute(
      route == null ? null : SyncService.routeToJson(route),
    );
  }

  /// Wysyła kształt trasy na ekran blokady.
  ///
  /// Wołane przy starcie i po każdej zmianie planu. Bez trasy wysyła pusty
  /// kształt, żeby widget wiedział, że ma pokazać zwykły ekran przejazdu
  /// zamiast pustego prostokąta po poprzedniej trasie.
  Future<void> _publishRouteShape() async {
    final shape = _plan?.shape ?? const <GeoPoint>[];
    await liveActivity.setRoute(RoutePreview.fromRoute(shape));
  }

  /// Karmi trening stanem jazdy raz na sekundę.
  void _feedWorkout() {
    if (_state != RideState.recording) return;
    if (!workoutRunner.isRunning) return;
    final snapshot = sensors.snapshot;
    workoutRunner.update(
      // Krok treningu odmierza czas pracy, nie czas na trasie: postój na
      // światłach nie ma prawa przesunąć interwału.
      elapsed: recordingTime,
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
        elapsed: recordingTime,
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
      recording: recordingTime,
      paused: pausedTotal,
      pointCount: _points.length,
      hasFix: _position != null,
    );
    unawaited(
      liveActivity.update(
        metrics: _metrics,
        paused: _state == RideState.paused,
        automaticPause: isAutoPaused,
        live: live.isActive,
        metric: profile.profile.metricUnits,
        progress: _progress,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _liveHeartbeat?.cancel();
    _positionSub?.cancel();
    _heartRateSub?.cancel();
    sensors.removeListener(_onSensors);
    _ticker?.cancel();
    super.dispose();
  }
}
