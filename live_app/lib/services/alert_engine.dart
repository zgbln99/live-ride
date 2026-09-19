import '../core/formatters.dart';
import '../models/ride_alert.dart';

/// Wszystko, co silnik powiadomień potrzebuje wiedzieć o chwili jazdy.
class AlertContext {
  const AlertContext({
    required this.now,
    required this.elapsed,
    required this.distanceMeters,
    this.metric = true,
    this.heartRate,
    this.powerWatts,
    this.cadenceRpm,
    this.offRoute = false,
    this.climbAheadMeters,
    this.climbLabel,
    this.lowestSensorBatteryPercent,
    this.lowBatterySensorName,
    this.rainProbability,
    this.minutesToSunset,
    this.paused = false,
  });

  final DateTime now;
  final Duration elapsed;
  final double distanceMeters;
  final bool metric;

  final int? heartRate;
  final int? powerWatts;
  final double? cadenceRpm;

  final bool offRoute;

  /// Ile metrów do początku najbliższego podjazdu.
  final double? climbAheadMeters;
  final String? climbLabel;

  final int? lowestSensorBatteryPercent;
  final String? lowBatterySensorName;

  final int? rainProbability;
  final int? minutesToSunset;

  final bool paused;
}

/// Decyduje, kiedy odezwać się do zawodnika.
///
/// Silnik jest czysty i ma własny stan tylko po to, żeby nie powtarzać
/// tego samego komunikatu. Reguła jest jedna: lepiej milczeć niż odzywać się
/// o czymś, czego nie da się stwierdzić — bez miernika mocy nie ma
/// powiadomień o mocy, bez paska nie ma o tętnie.
class AlertEngine {
  AlertEngine({this.settings = AlertSettings.defaults});

  /// Minimalna przerwa między dwoma powiadomieniami tego samego rodzaju,
  /// gdy warunek trwa (np. wciąż jesteś poza trasą).
  static const Duration repeatCooldown = Duration(minutes: 2);

  /// Po zjeździe z trasy nie odzywamy się od razu — sekunda pod wiaduktem
  /// nie jest pomyłką nawigacyjną.
  static const Duration offRouteGrace = Duration(seconds: 12);

  /// Reguły, po których silnik decyduje. Podmienialne w locie, bo zawodnik
  /// może zmienić ustawienia w środku jazdy.
  AlertSettings settings;

  final Map<AlertKind, DateTime> _lastFired = {};
  final Map<AlertKind, double> _lastDistance = {};
  DateTime? _offRouteSince;
  bool _sunsetAnnounced = false;
  bool _rainAnnounced = false;

  void reset() {
    _lastFired.clear();
    _lastDistance.clear();
    _offRouteSince = null;
    _sunsetAnnounced = false;
    _rainAnnounced = false;
  }

  /// Zwraca powiadomienia, które powinny się teraz pokazać.
  List<RideAlert> evaluate(AlertContext context) {
    final alerts = <RideAlert>[];
    if (context.paused) {
      _offRouteSince = null;
      return alerts;
    }

    void fire(AlertKind kind, String message, AlertSeverity severity) {
      _lastFired[kind] = context.now;
      alerts.add(
        RideAlert(
          kind: kind,
          message: message,
          at: context.now,
          severity: severity,
        ),
      );
    }

    bool cooledDown(AlertKind kind) {
      final last = _lastFired[kind];
      return last == null || context.now.difference(last) >= repeatCooldown;
    }

    // --- rytmiczne: picie, jedzenie, czas -------------------------------
    for (final kind in [
      AlertKind.drink,
      AlertKind.eat,
      AlertKind.timeInterval,
    ]) {
      final rule = settings.ruleFor(kind);
      final minutes = rule.everyMinutes;
      if (!rule.enabled || minutes == null || minutes <= 0) continue;
      final last = _lastFired[kind];
      final since = last == null
          ? context.elapsed
          : context.now.difference(last);
      if (since.inMinutes >= minutes) {
        fire(kind, _rhythmMessage(kind, minutes), AlertSeverity.info);
      }
    }

    // --- co ile kilometrów ----------------------------------------------
    final distanceRule = settings.ruleFor(AlertKind.distanceInterval);
    final everyKm = distanceRule.everyKilometers;
    if (distanceRule.enabled && everyKm != null && everyKm > 0) {
      final last = _lastDistance[AlertKind.distanceInterval] ?? 0;
      if (context.distanceMeters - last >= everyKm * 1000) {
        _lastDistance[AlertKind.distanceInterval] = context.distanceMeters;
        fire(
          AlertKind.distanceInterval,
          '${Fmt.distance(context.distanceMeters, metric: context.metric)} '
          '${Fmt.distanceUnit(metric: context.metric)} za tobą.',
          AlertSeverity.info,
        );
      }
    }

    // --- progi z sensorów -------------------------------------------------
    final hrRule = settings.ruleFor(AlertKind.heartRateHigh);
    final hr = context.heartRate;
    if (hrRule.enabled &&
        hr != null &&
        hrRule.threshold != null &&
        hr >= hrRule.threshold! &&
        cooledDown(AlertKind.heartRateHigh)) {
      fire(
        AlertKind.heartRateHigh,
        '$hr bpm — powyżej ${hrRule.threshold!.round()}.',
        AlertSeverity.warning,
      );
    }

    final powerRule = settings.ruleFor(AlertKind.powerHigh);
    final power = context.powerWatts;
    if (powerRule.enabled &&
        power != null &&
        powerRule.threshold != null &&
        power >= powerRule.threshold! &&
        cooledDown(AlertKind.powerHigh)) {
      fire(
        AlertKind.powerHigh,
        '$power W — powyżej ${powerRule.threshold!.round()}.',
        AlertSeverity.warning,
      );
    }

    final cadenceRule = settings.ruleFor(AlertKind.cadenceLow);
    final cadence = context.cadenceRpm;
    if (cadenceRule.enabled &&
        cadence != null &&
        cadence > 0 &&
        cadenceRule.threshold != null &&
        cadence <= cadenceRule.threshold! &&
        cooledDown(AlertKind.cadenceLow)) {
      fire(
        AlertKind.cadenceLow,
        '${cadence.round()} rpm — zrzuć przerzutkę.',
        AlertSeverity.info,
      );
    }

    // --- zjazd z trasy ----------------------------------------------------
    final offRouteRule = settings.ruleFor(AlertKind.offRoute);
    if (offRouteRule.enabled && context.offRoute) {
      final since = _offRouteSince ??= context.now;
      if (context.now.difference(since) >= offRouteGrace &&
          cooledDown(AlertKind.offRoute)) {
        fire(
          AlertKind.offRoute,
          'Zawróć albo wróć na trasę.',
          AlertSeverity.critical,
        );
      }
    } else if (!context.offRoute) {
      _offRouteSince = null;
    }

    // --- podjazd przed tobą ------------------------------------------------
    final climbRule = settings.ruleFor(AlertKind.climbAhead);
    final climbAhead = context.climbAheadMeters;
    if (climbRule.enabled &&
        climbAhead != null &&
        climbAhead <= 500 &&
        cooledDown(AlertKind.climbAhead)) {
      fire(
        AlertKind.climbAhead,
        [
          'Za ${Fmt.turnDistance(climbAhead, metric: context.metric)} '
              '${Fmt.turnDistanceUnit(climbAhead, metric: context.metric)}',
          if (context.climbLabel != null) '· ${context.climbLabel}',
        ].join(' '),
        AlertSeverity.warning,
      );
    }

    // --- bateria sensora ---------------------------------------------------
    final batteryRule = settings.ruleFor(AlertKind.sensorBattery);
    final battery = context.lowestSensorBatteryPercent;
    if (batteryRule.enabled &&
        battery != null &&
        batteryRule.threshold != null &&
        battery <= batteryRule.threshold! &&
        _lastFired[AlertKind.sensorBattery] == null) {
      fire(
        AlertKind.sensorBattery,
        '${context.lowBatterySensorName ?? 'Sensor'}: $battery %.',
        AlertSeverity.warning,
      );
    }

    // --- pogoda i zmrok ----------------------------------------------------
    final rainRule = settings.ruleFor(AlertKind.rain);
    final rain = context.rainProbability;
    if (rainRule.enabled && rain != null && !_rainAnnounced) {
      final threshold = rainRule.threshold ?? 60;
      if (rain >= threshold) {
        _rainAnnounced = true;
        fire(AlertKind.rain, '$rain % szans na opady.', AlertSeverity.warning);
      }
    }

    final sunsetRule = settings.ruleFor(AlertKind.sunset);
    final toSunset = context.minutesToSunset;
    if (sunsetRule.enabled && toSunset != null && !_sunsetAnnounced) {
      final threshold = sunsetRule.threshold ?? 30;
      if (toSunset <= threshold && toSunset >= 0) {
        _sunsetAnnounced = true;
        fire(
          AlertKind.sunset,
          'Słońce zajdzie za $toSunset min — włącz światła.',
          AlertSeverity.warning,
        );
      }
    }

    return alerts;
  }

  String _rhythmMessage(AlertKind kind, int minutes) => switch (kind) {
    AlertKind.drink => 'Minęło $minutes min od ostatniego przypomnienia.',
    AlertKind.eat => 'Minęło $minutes min — czas coś zjeść.',
    _ => 'Minęło $minutes min.',
  };
}
