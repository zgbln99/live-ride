import 'dart:async';

import 'package:flutter/foundation.dart';

import 'apple_watch_service.dart';
import 'heart_rate_service.dart';

/// Skąd pochodzi tętno.
///
/// Kolejność w tym wyliczeniu JEST priorytetem: wyższy [rank] wygrywa, gdy
/// dwa źródła nadają jednocześnie i oba są świeże.
enum HeartRateOrigin {
  /// Pas na klatę — najbardziej wiarygodny pomiar, jaki mamy.
  whoop('WHOOP', 40),

  /// Dowolny inny pas albo czujnik Bluetooth.
  bleStrap('Pas Bluetooth', 30),

  /// Zegarek. Mierzy z nadgarstka, więc przy mocnym chwycie kierownicy
  /// bywa niższy niż prawda — dlatego ustępuje pasowi, nie odwrotnie.
  appleWatch('Apple Watch', 20),

  /// Brak.
  none('', 0);

  const HeartRateOrigin(this.label, this.rank);

  final String label;
  final int rank;
}

/// Jeden odczyt tętna razem z tym, skąd i kiedy przyszedł.
class HeartRateReading {
  const HeartRateReading({
    required this.bpm,
    required this.origin,
    required this.at,
    this.deviceName = '',
  });

  final int bpm;
  final HeartRateOrigin origin;
  final DateTime at;

  /// Nazwa własna urządzenia, gdy ją znamy („Polar H10").
  final String deviceName;

  /// Etykieta do pokazania: nazwa urządzenia, a w jej braku rodzaj źródła.
  String get label => deviceName.isNotEmpty ? deviceName : origin.label;

  Duration ageAt(DateTime now) => now.difference(at);
}

/// Jedno miejsce, w którym rozstrzyga się, czyje tętno widzi zawodnik.
///
/// Źródeł bywa naraz kilka: pas WHOOP na klatce, zegarek na ręce i czasem
/// jeszcze drugi pas z poprzedniego roweru. Bez arbitrażu wygrywało to,
/// które akurat ostatnie zawołało `notifyListeners` — czyli licznik potrafił
/// skakać między dwiema różnymi wartościami co sekundę.
///
/// Dwie reguły:
///
///  1. ŚWIEŻOŚĆ PRZED PRIORYTETEM. Pas, który odpadł minutę temu, przegrywa
///     z zegarkiem nadającym teraz. Wysoki priorytet nie jest licencją na
///     pokazywanie starego pomiaru.
///  2. HISTORIA NIGDY NIE WCHODZI. Apple Health trafia do statystyk
///     i do stref, ale nie tutaj: próbka sprzed czterech minut pokazana jako
///     bieżące tętno jest po prostu nieprawdą.
class HeartRateRouter extends ChangeNotifier {
  HeartRateRouter({
    required HeartRateService ble,
    AppleWatchService? watch,
    this.freshFor = const Duration(seconds: 15),
  }) : _ble = ble,
       _watch = watch {
    _ble.addListener(_onBle);
    final watchService = _watch;
    if (watchService != null) {
      _watchSub = watchService.readings.listen(_onWatch);
    }
  }

  /// Po ilu sekundach odczyt przestaje być bieżący.
  ///
  /// Pas nadaje co sekundę, zegarek co jedną–pięć. Piętnaście sekund to
  /// margines na chwilowy zanik łączności, a nie na zdjęty pas.
  final Duration freshFor;

  final HeartRateService _ble;
  final AppleWatchService? _watch;
  StreamSubscription<WatchHeartRate>? _watchSub;
  final _bpm = StreamController<int>.broadcast();

  final Map<HeartRateOrigin, HeartRateReading> _readings = {};
  HeartRateOrigin? _preferred;
  HeartRateReading? _published;

  /// Strumień zgodny z tym, którego używał licznik, zanim źródeł zrobiło się
  /// więcej niż jedno.
  Stream<int> get bpm => _bpm.stream;

  /// Wybór zawodnika. Null znaczy „decyduj sam".
  HeartRateOrigin? get preferred => _preferred;

  set preferred(HeartRateOrigin? origin) {
    if (_preferred == origin) return;
    _preferred = origin;
    _publish();
  }

  /// Najlepszy ŚWIEŻY odczyt albo null.
  HeartRateReading? get latest => _fresh(DateTime.now());

  int? get latestBpm => latest?.bpm;
  DateTime? get lastSampleAt => latest?.at;
  HeartRateOrigin get origin => latest?.origin ?? HeartRateOrigin.none;
  String get sourceLabel => latest?.label ?? '';

  /// Które źródła w ogóle się odzywają — do ekranu wyboru i diagnostyki.
  List<HeartRateReading> get sources {
    final now = DateTime.now();
    final live = _readings.values
        .where((reading) => reading.ageAt(now) <= freshFor)
        .toList()
      ..sort((a, b) => b.origin.rank.compareTo(a.origin.rank));
    return List.unmodifiable(live);
  }

  HeartRateReading? _fresh(DateTime now) {
    final live = _readings.values
        .where((reading) => reading.ageAt(now) <= freshFor)
        .toList();
    if (live.isEmpty) return null;

    // Wybór zawodnika wygrywa — ale tylko dopóki to źródło naprawdę nadaje.
    // Inaczej wyłączony zegarek zabierałby tętno z podłączonego pasa.
    final chosen = _preferred;
    if (chosen != null) {
      for (final reading in live) {
        if (reading.origin == chosen) return reading;
      }
    }
    live.sort((a, b) => b.origin.rank.compareTo(a.origin.rank));
    return live.first;
  }

  void _onBle() {
    final bpm = _ble.latestBpm;
    if (bpm == null) {
      _readings.remove(HeartRateOrigin.whoop);
      _readings.remove(HeartRateOrigin.bleStrap);
      _publish();
      return;
    }
    final name = _ble.connectedName?.trim() ?? '';
    final origin = name.toLowerCase().contains('whoop')
        ? HeartRateOrigin.whoop
        : HeartRateOrigin.bleStrap;
    // Pas zmienia rodzaj źródła, gdy zawodnik przełączy urządzenie —
    // stary wpis musi zniknąć, żeby nie udawał drugiego czujnika.
    _readings
      ..remove(HeartRateOrigin.whoop)
      ..remove(HeartRateOrigin.bleStrap);
    _readings[origin] = HeartRateReading(
      bpm: bpm,
      origin: origin,
      at: _ble.lastSampleAt ?? DateTime.now(),
      deviceName: origin == HeartRateOrigin.whoop ? 'WHOOP' : name,
    );
    _publish();
  }

  void _onWatch(WatchHeartRate reading) {
    _readings[HeartRateOrigin.appleWatch] = HeartRateReading(
      bpm: reading.bpm,
      origin: HeartRateOrigin.appleWatch,
      at: reading.at,
      deviceName: HeartRateOrigin.appleWatch.label,
    );
    _publish();
  }

  void _publish() {
    final next = _fresh(DateTime.now());
    final changed =
        next?.bpm != _published?.bpm || next?.origin != _published?.origin;
    _published = next;
    if (next != null && changed) _bpm.add(next.bpm);
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _ble.removeListener(_onBle);
    _watchSub?.cancel();
    _bpm.close();
    super.dispose();
  }
}
