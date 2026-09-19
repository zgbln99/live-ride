import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

/// Poziom baterii telefonu.
///
/// Jedna rzecz, o którą pyta każdy, kto śledzi czyjąś jazdę: „czy on jeszcze
/// ma baterię, czy zaraz zniknie". Odczyt jest rzadki — stan naładowania nie
/// zmienia się co sekundę, a samo pytanie o niego kosztuje.
class PhoneBattery extends ChangeNotifier {
  PhoneBattery({
    Battery? battery,
    Duration interval = const Duration(minutes: 2),
  }) : _battery = battery ?? Battery(),
       _interval = interval;

  final Battery _battery;
  final Duration _interval;

  Timer? _timer;
  int? _percent;

  /// Ostatni odczyt albo null, gdy jeszcze go nie było lub się nie udał.
  int? get percent => _percent;

  /// Zaczyna odczytywać. Wywołanie drugi raz nic nie zmienia.
  void start() {
    if (_timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(_interval, (_) => unawaited(refresh()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    try {
      final level = await _battery.batteryLevel;
      if (level < 0 || level > 100) return;
      if (_percent == level) return;
      _percent = level;
      notifyListeners();
    } catch (_) {
      // Symulator i część Androidów nie odpowiadają. Brak odczytu znaczy
      // „nie pokazuj baterii", a nie „bateria na zero".
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
