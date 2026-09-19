import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/ride_alert.dart';
import 'package:live_ride/services/alert_controller.dart';
import 'package:live_ride/services/alert_engine.dart';

final DateTime _start = DateTime(2026, 5, 1, 10);

AlertContext _context({
  Duration elapsed = Duration.zero,
  Duration after = Duration.zero,
  double distanceMeters = 0,
  int? heartRate,
  int? powerWatts,
  double? cadenceRpm,
  bool offRoute = false,
  double? climbAheadMeters,
  String? climbLabel,
  int? battery,
  int? rain,
  int? minutesToSunset,
  bool paused = false,
}) => AlertContext(
  now: _start.add(after),
  elapsed: elapsed,
  distanceMeters: distanceMeters,
  heartRate: heartRate,
  powerWatts: powerWatts,
  cadenceRpm: cadenceRpm,
  offRoute: offRoute,
  climbAheadMeters: climbAheadMeters,
  climbLabel: climbLabel,
  lowestSensorBatteryPercent: battery,
  lowBatterySensorName: battery == null ? null : 'Miernik mocy',
  rainProbability: rain,
  minutesToSunset: minutesToSunset,
  paused: paused,
);

Set<AlertKind> _kinds(List<RideAlert> alerts) =>
    alerts.map((alert) => alert.kind).toSet();

void main() {
  _controllerTests();
  group('rytm picia i jedzenia', () {
    test('milczy, dopóki nie minie ustawiony czas', () {
      final engine = AlertEngine();
      expect(
        engine.evaluate(_context(elapsed: const Duration(minutes: 5))),
        isEmpty,
      );
    });

    test('przypomina o piciu po dwudziestu minutach', () {
      final engine = AlertEngine();
      final alerts = engine.evaluate(
        _context(elapsed: const Duration(minutes: 20)),
      );
      expect(_kinds(alerts), contains(AlertKind.drink));
    });

    test('nie powtarza przypomnienia w kółko', () {
      final engine = AlertEngine();
      engine.evaluate(_context(elapsed: const Duration(minutes: 20)));
      final again = engine.evaluate(
        _context(
          elapsed: const Duration(minutes: 21),
          after: const Duration(minutes: 1),
        ),
      );
      expect(_kinds(again), isNot(contains(AlertKind.drink)));
    });

    test('odzywa się ponownie po kolejnym odstępie', () {
      final engine = AlertEngine();
      engine.evaluate(_context(elapsed: const Duration(minutes: 20)));
      final later = engine.evaluate(
        _context(
          elapsed: const Duration(minutes: 41),
          after: const Duration(minutes: 21),
        ),
      );
      expect(_kinds(later), contains(AlertKind.drink));
    });

    test('na pauzie milczy całkowicie', () {
      final engine = AlertEngine();
      final alerts = engine.evaluate(
        _context(elapsed: const Duration(minutes: 60), paused: true),
      );
      expect(alerts, isEmpty);
    });
  });

  group('progi z sensorów', () {
    test('bez włączonej reguły nic nie mówi o tętnie', () {
      final engine = AlertEngine();
      final alerts = engine.evaluate(_context(heartRate: 200));
      expect(_kinds(alerts), isNot(contains(AlertKind.heartRateHigh)));
    });

    test('bez sensora reguła nie odpala', () {
      final engine = AlertEngine(
        settings: AlertSettings.defaults.withRule(
          const AlertRule(
            kind: AlertKind.powerHigh,
            enabled: true,
            threshold: 300,
          ),
        ),
      );
      expect(
        _kinds(engine.evaluate(_context())),
        isNot(contains(AlertKind.powerHigh)),
      );
    });

    test('odpala przy przekroczeniu progu i nie spamuje', () {
      final engine = AlertEngine(
        settings: AlertSettings.defaults.withRule(
          const AlertRule(
            kind: AlertKind.heartRateHigh,
            enabled: true,
            threshold: 175,
          ),
        ),
      );
      expect(
        _kinds(engine.evaluate(_context(heartRate: 180))),
        contains(AlertKind.heartRateHigh),
      );
      expect(
        _kinds(
          engine.evaluate(
            _context(heartRate: 182, after: const Duration(seconds: 20)),
          ),
        ),
        isNot(contains(AlertKind.heartRateHigh)),
      );
      expect(
        _kinds(
          engine.evaluate(
            _context(heartRate: 182, after: const Duration(minutes: 3)),
          ),
        ),
        contains(AlertKind.heartRateHigh),
      );
    });

    test('niska kadencja nie odpala przy zatrzymanej korbie', () {
      final engine = AlertEngine(
        settings: AlertSettings.defaults.withRule(
          const AlertRule(
            kind: AlertKind.cadenceLow,
            enabled: true,
            threshold: 60,
          ),
        ),
      );
      expect(
        _kinds(engine.evaluate(_context(cadenceRpm: 0))),
        isNot(contains(AlertKind.cadenceLow)),
      );
      expect(
        _kinds(engine.evaluate(_context(cadenceRpm: 52))),
        contains(AlertKind.cadenceLow),
      );
    });
  });

  group('zjazd z trasy', () {
    test('sekunda poza trasą to jeszcze nie pomyłka', () {
      final engine = AlertEngine();
      expect(_kinds(engine.evaluate(_context(offRoute: true))), isEmpty);
      expect(
        _kinds(
          engine.evaluate(
            _context(offRoute: true, after: const Duration(seconds: 5)),
          ),
        ),
        isEmpty,
      );
    });

    test('po kilkunastu sekundach odzywa się z najwyższą wagą', () {
      final engine = AlertEngine();
      engine.evaluate(_context(offRoute: true));
      final alerts = engine.evaluate(
        _context(offRoute: true, after: const Duration(seconds: 15)),
      );
      expect(_kinds(alerts), contains(AlertKind.offRoute));
      expect(alerts.first.severity, AlertSeverity.critical);
    });

    test('powrót na trasę kasuje licznik cierpliwości', () {
      final engine = AlertEngine();
      engine.evaluate(_context(offRoute: true));
      engine.evaluate(
        _context(offRoute: false, after: const Duration(seconds: 5)),
      );
      expect(
        _kinds(
          engine.evaluate(
            _context(offRoute: true, after: const Duration(seconds: 15)),
          ),
        ),
        isEmpty,
      );
    });
  });

  group('podjazd, bateria, pogoda', () {
    test('podjazd zapowiadany dopiero z bliska', () {
      final engine = AlertEngine();
      expect(
        _kinds(engine.evaluate(_context(climbAheadMeters: 1500))),
        isEmpty,
      );
      final alerts = engine.evaluate(
        _context(climbAheadMeters: 400, climbLabel: 'Kategoria 3'),
      );
      expect(_kinds(alerts), contains(AlertKind.climbAhead));
      expect(alerts.first.message, contains('Kategoria 3'));
    });

    test('o słabej baterii mówi raz na jazdę', () {
      final engine = AlertEngine();
      expect(
        _kinds(engine.evaluate(_context(battery: 12))),
        contains(AlertKind.sensorBattery),
      );
      expect(
        _kinds(
          engine.evaluate(
            _context(battery: 11, after: const Duration(minutes: 30)),
          ),
        ),
        isNot(contains(AlertKind.sensorBattery)),
      );
    });

    test('deszcz i zmrok tylko przy włączonej regule', () {
      final engine = AlertEngine();
      expect(
        _kinds(engine.evaluate(_context(rain: 90, minutesToSunset: 10))),
        isEmpty,
      );

      final loud = AlertEngine(
        settings: AlertSettings.defaults
            .withRule(const AlertRule(kind: AlertKind.rain, enabled: true))
            .withRule(const AlertRule(kind: AlertKind.sunset, enabled: true)),
      );
      final alerts = loud.evaluate(_context(rain: 90, minutesToSunset: 10));
      expect(_kinds(alerts), containsAll([AlertKind.rain, AlertKind.sunset]));
    });
  });

  group('odstępy dystansowe', () {
    test('odzywa się co ustawione kilometry', () {
      final engine = AlertEngine(
        settings: AlertSettings.defaults.withRule(
          const AlertRule(
            kind: AlertKind.distanceInterval,
            enabled: true,
            everyKilometers: 10,
          ),
        ),
      );
      expect(_kinds(engine.evaluate(_context(distanceMeters: 5000))), isEmpty);
      expect(
        _kinds(engine.evaluate(_context(distanceMeters: 10100))),
        contains(AlertKind.distanceInterval),
      );
      expect(_kinds(engine.evaluate(_context(distanceMeters: 15000))), isEmpty);
      expect(
        _kinds(engine.evaluate(_context(distanceMeters: 20200))),
        contains(AlertKind.distanceInterval),
      );
    });
  });

  test('reset czyści pamięć powiadomień', () {
    final engine = AlertEngine();
    engine.evaluate(_context(elapsed: const Duration(minutes: 20)));
    engine.reset();
    expect(
      _kinds(engine.evaluate(_context(elapsed: const Duration(minutes: 20)))),
      contains(AlertKind.drink),
    );
  });

  test('ustawienia przechodzą przez JSON', () {
    final settings = AlertSettings.defaults.withRule(
      const AlertRule(kind: AlertKind.powerHigh, enabled: true, threshold: 320),
    );
    final restored = AlertSettings.fromJson(settings.toJson());
    expect(restored.isEnabled(AlertKind.powerHigh), isTrue);
    expect(restored.ruleFor(AlertKind.powerHigh).threshold, 320);
    expect(restored.ruleFor(AlertKind.drink).everyMinutes, 20);
  });
}

/// Kontroler powiadomień: wibracja, mowa i historia.
void _controllerTests() {
  group('AlertController', () {
    // Wibracja i mowa sięgają po kanały platformy, więc test potrzebuje
    // zainicjowanego bindingu — inaczej wywala się na czymś, czego wcale
    // nie sprawdza.
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('bez ustawień czyta domyślne reguły', () {
      final controller = AlertController();
      expect(controller.settings.isEnabled(AlertKind.drink), isTrue);
      expect(controller.settings.isEnabled(AlertKind.powerHigh), isFalse);
      expect(controller.hapticsEnabled, isTrue);
      // Mowa domyślnie wyłączona: nagły głos w uchu podczas jazdy to
      // decyzja zawodnika, nie aplikacji.
      expect(controller.speechEnabled, isFalse);
    });

    test('najpilniejsze powiadomienie trafia na ekran, reszta do historii', () {
      final controller = AlertController(
        engine: AlertEngine(
          settings: AlertSettings.defaults.withRule(
            const AlertRule(
              kind: AlertKind.heartRateHigh,
              enabled: true,
              threshold: 150,
            ),
          ),
        ),
      );

      controller.feed(
        AlertContext(
          now: DateTime(2026, 5, 1, 10),
          elapsed: const Duration(minutes: 20),
          distanceMeters: 20000,
          heartRate: 180,
          offRoute: true,
        ),
      );

      // Zjazd z trasy potrzebuje kilkunastu sekund, więc na ekranie jest
      // ostrzeżenie o tętnie, a przypomnienie o piciu czeka w historii.
      expect(controller.current, isNotNull);
      expect(controller.current!.severity, AlertSeverity.warning);
      expect(controller.history.length, greaterThanOrEqualTo(2));
    });

    test('zamknięcie kasuje bieżące powiadomienie', () {
      final controller = AlertController();
      controller.show(
        RideAlert(
          kind: AlertKind.drink,
          message: 'Napij się',
          at: DateTime.now(),
        ),
      );
      expect(controller.current, isNotNull);
      controller.dismiss();
      expect(controller.current, isNull);
    });

    test('reset czyści historię i ekran', () {
      final controller = AlertController();
      controller.show(
        RideAlert(
          kind: AlertKind.eat,
          message: 'Zjedz coś',
          at: DateTime.now(),
        ),
      );
      controller.reset();
      expect(controller.current, isNull);
      expect(controller.history, isEmpty);
    });
  });
}
