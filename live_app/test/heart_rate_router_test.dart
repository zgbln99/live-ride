import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/apple_watch_service.dart';
import 'package:live_ride/services/heart_rate_router.dart';
import 'package:live_ride/services/heart_rate_service.dart';

/// Kto wygrywa, gdy tętno nadaje więcej niż jedno urządzenie.
///
/// Zawodnik potrafi mieć naraz pas WHOOP na klatce, zegarek na ręce i drugi
/// pas z poprzedniego roweru. Bez arbitrażu wygrywało to, które ostatnie
/// zawołało `notifyListeners` — czyli licznik skakał między dwiema różnymi
/// wartościami co sekundę.

class _NoRadio implements CentralManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Pas, którego odczyt da się ustawić z testu.
class _FakeStrap extends HeartRateService {
  _FakeStrap() : super(central: _NoRadio());

  int? _bpm;
  String? _name;
  DateTime? _at;

  @override
  int? get latestBpm => _bpm;

  @override
  String? get connectedName => _name;

  @override
  DateTime? get lastSampleAt => _at;

  void emit(int? bpm, {String name = 'Polar H10', DateTime? at}) {
    _bpm = bpm;
    _name = bpm == null ? null : name;
    _at = bpm == null ? null : (at ?? DateTime.now());
    notifyListeners();
  }
}

/// Zegarek, który nadaje przez ten sam strumień co prawdziwy most.
class _FakeWatch extends AppleWatchService {
  _FakeWatch() : super();

  final _controller = StreamController<WatchHeartRate>.broadcast();

  @override
  Stream<WatchHeartRate> get readings => _controller.stream;

  void emit(int bpm, {DateTime? at}) =>
      _controller.add(WatchHeartRate(bpm: bpm, at: at ?? DateTime.now()));

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}

void main() {
  late _FakeStrap strap;
  late _FakeWatch watch;
  late HeartRateRouter router;

  setUp(() {
    strap = _FakeStrap();
    watch = _FakeWatch();
    router = HeartRateRouter(ble: strap, watch: watch);
  });

  tearDown(() {
    router.dispose();
    watch.dispose();
  });

  test('bez żadnego źródła nie ma tętna — i nie ma zera', () {
    // Zero bpm to nie jest „spokojny zawodnik", tylko brak pomiaru.
    expect(router.latest, isNull);
    expect(router.latestBpm, isNull);
    expect(router.origin, HeartRateOrigin.none);
  });

  test('pas rozpoznaje WHOOP po nazwie i nazywa go po imieniu', () {
    strap.emit(143, name: 'WHOOP 4.0');
    expect(router.origin, HeartRateOrigin.whoop);
    expect(router.sourceLabel, 'WHOOP');
    expect(router.latestBpm, 143);
  });

  test('zwykły pas dostaje własną nazwę urządzenia', () {
    strap.emit(138, name: 'Polar H10');
    expect(router.origin, HeartRateOrigin.bleStrap);
    expect(router.sourceLabel, 'Polar H10');
  });

  test('pas na klatce wygrywa z zegarkiem, gdy oba nadają', () async {
    watch.emit(131);
    await pumpEventQueue();
    strap.emit(143, name: 'WHOOP 4.0');

    expect(router.latestBpm, 143);
    expect(router.origin, HeartRateOrigin.whoop);
    // Zegarek nie znika z listy — po prostu nie jest tym, co widać.
    expect(router.sources.length, 2);
  });

  test('świeżość bije priorytet: odpadły pas oddaje pole zegarkowi', () async {
    // Pas z odczytem sprzed minuty nie jest tętnem, tylko wspomnieniem.
    strap.emit(
      143,
      name: 'WHOOP 4.0',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    watch.emit(131);
    await pumpEventQueue();

    expect(router.latestBpm, 131);
    expect(router.origin, HeartRateOrigin.appleWatch);
  });

  test('gdy wszystko jest stare, nie pokazujemy niczego', () {
    strap.emit(
      143,
      at: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(router.latest, isNull);
    expect(router.sourceLabel, '');
  });

  test('wybór zawodnika wygrywa, dopóki to źródło naprawdę nadaje', () async {
    strap.emit(143, name: 'WHOOP 4.0');
    watch.emit(131);
    await pumpEventQueue();

    router.preferred = HeartRateOrigin.appleWatch;
    expect(router.latestBpm, 131);

    // …ale wyłączony zegarek nie ma prawa zabrać tętna podłączonemu pasowi.
    router.preferred = HeartRateOrigin.appleWatch;
    strap.emit(150, name: 'WHOOP 4.0');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final stale = HeartRateRouter(
      ble: strap,
      watch: watch,
      freshFor: const Duration(milliseconds: 1),
    );
    addTearDown(stale.dispose);
    stale.preferred = HeartRateOrigin.appleWatch;
    expect(stale.latest, isNull);
  });

  test('zmiana pasa nie zostawia po sobie drugiego źródła', () {
    strap.emit(143, name: 'WHOOP 4.0');
    expect(router.sources.length, 1);
    strap.emit(140, name: 'Garmin HRM');
    expect(router.sources.length, 1);
    expect(router.origin, HeartRateOrigin.bleStrap);
  });

  test('strumień oddaje tylko zmiany, a nie każdą próbkę', () async {
    final seen = <int>[];
    final subscription = router.bpm.listen(seen.add);
    strap.emit(143, name: 'WHOOP 4.0');
    strap.emit(143, name: 'WHOOP 4.0');
    strap.emit(145, name: 'WHOOP 4.0');
    await pumpEventQueue();
    await subscription.cancel();

    expect(seen, [143, 145]);
  });

  test('odłączenie pasa czyści tętno zamiast zamrażać ostatnie', () {
    strap.emit(143, name: 'WHOOP 4.0');
    strap.emit(null);
    expect(router.latest, isNull);
  });
}
