import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Stan aplikacji na Apple Watch.
enum WatchState {
  /// Nie sprawdzono albo platforma nie ma zegarków.
  unknown,

  /// Ten telefon nie jest sparowany z żadnym zegarkiem.
  notPaired,

  /// Zegarek jest, ale nie ma na nim Live Ride.
  notInstalled,

  /// Aplikacja jest zainstalowana i da się ją obudzić.
  ready,

  /// Trwa sesja treningowa i lecą pomiary.
  streaming,
}

/// Jedna próbka tętna z zegarka.
class WatchHeartRate {
  const WatchHeartRate({required this.bpm, required this.at});

  final int bpm;
  final DateTime at;
}

/// Tętno na żywo z Apple Watch.
///
/// To NIE jest HealthKit. Czytanie HealthKit z telefonu daje próbki, które
/// zegarek zapisał kiedyś — z opóźnieniem liczonym w dziesiątkach sekund,
/// a przy zablokowanym ekranie w minutach. Na liczniku rowerowym taka
/// wartość nie jest tętnem, tylko wspomnieniem tętna.
///
/// Prawdziwe „teraz" daje wyłącznie `HKWorkoutSession` z `HKLiveWorkoutBuilder`
/// uruchomiony NA ZEGARKU. Ta klasa jest końcówką tamtego kanału po stronie
/// telefonu: zegarek nadaje przez WatchConnectivity, natywny most wrzuca
/// próbki tutaj, a stąd jadą tam, gdzie każde inne tętno.
///
/// Gdy mostu nie ma — Android, symulator, telefon bez zegarka, projekt
/// zbudowany bez targetu watchOS — klasa po prostu milczy. Nie udaje
/// pomiarów i nie psuje jazdy.
class AppleWatchService extends ChangeNotifier {
  AppleWatchService({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel('live_ride/watch'),
      _events = events ?? const EventChannel('live_ride/watch/heart_rate');

  final MethodChannel _channel;
  final EventChannel _events;

  StreamSubscription<dynamic>? _subscription;
  final _readings = StreamController<WatchHeartRate>.broadcast();

  WatchState _state = WatchState.unknown;
  WatchHeartRate? _latest;
  String? _lastError;

  WatchState get state => _state;
  WatchHeartRate? get latest => _latest;
  String? get lastError => _lastError;
  Stream<WatchHeartRate> get readings => _readings.stream;

  /// Czy w ogóle warto pokazywać zegarek w interfejsie.
  bool get isAvailable =>
      _state == WatchState.ready || _state == WatchState.streaming;

  /// Pyta most o stan zegarka.
  ///
  /// Brak mostu nie jest błędem — to znaczy tyle, że ta wersja aplikacji
  /// została zbudowana bez targetu watchOS.
  Future<WatchState> refresh() async {
    try {
      final reply = await _channel.invokeMapMethod<String, dynamic>('state');
      return _apply(reply);
    } on MissingPluginException {
      return _set(WatchState.unknown);
    } on PlatformException catch (e) {
      _lastError = e.message;
      return _set(WatchState.unknown);
    }
  }

  /// Prosi zegarek o rozpoczęcie sesji treningowej.
  ///
  /// Sesja jest tym, co w ogóle pozwala zegarkowi mierzyć tętno co sekundę
  /// i nadawać je przy zgaszonym ekranie. Bez niej watchOS usypia aplikację
  /// po kilkunastu sekundach.
  Future<bool> startSession() async {
    try {
      final reply = await _channel.invokeMapMethod<String, dynamic>('start');
      _apply(reply);
      _listen();
      return _state == WatchState.streaming || _state == WatchState.ready;
    } on MissingPluginException {
      _set(WatchState.unknown);
      return false;
    } on PlatformException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  Future<void> stopSession() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Nie było czego zatrzymywać.
    } on PlatformException catch (e) {
      _lastError = e.message;
    }
    _latest = null;
    _set(_state == WatchState.streaming ? WatchState.ready : _state);
  }

  void _listen() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final bpm = (event['bpm'] as num?)?.round() ?? 0;
        if (bpm < 25 || bpm > 260) return;
        final millis = (event['at'] as num?)?.toInt();
        final at = millis == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(millis);
        final reading = WatchHeartRate(bpm: bpm, at: at);
        _latest = reading;
        _readings.add(reading);
        _set(WatchState.streaming);
      },
      onError: (Object error) {
        _lastError = error.toString();
        _set(WatchState.ready);
      },
    );
  }

  WatchState _apply(Map<String, dynamic>? reply) {
    if (reply == null) return _set(WatchState.unknown);
    if (reply['paired'] != true) return _set(WatchState.notPaired);
    if (reply['installed'] != true) return _set(WatchState.notInstalled);
    return _set(reply['streaming'] == true ? WatchState.streaming : WatchState.ready);
  }

  WatchState _set(WatchState state) {
    if (_state != state) {
      _state = state;
      notifyListeners();
    }
    return state;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _readings.close();
    super.dispose();
  }
}
