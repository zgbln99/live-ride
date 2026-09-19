import 'dart:math' as math;

import '../models/emergency.dart';

/// Wykrywacz upadku.
///
/// Sama logika, bez czujników i bez telefonu, żeby dało się ją przetestować
/// na sekwencjach zamiast na asfalcie.
///
/// Upadek to trzy rzeczy naraz: mocne uderzenie, nagły spadek prędkości
/// i bezruch po nim. Każda z osobna zdarza się w normalnej jeździe —
/// dziura w drodze daje uderzenie, światła dają spadek prędkości, postój
/// daje bezruch. Dopiero wszystkie trzy razem znaczą coś złego.
class CrashDetector {
  CrashDetector({this.sensitivity = CrashSensitivity.medium});

  CrashSensitivity sensitivity;

  /// Ile czasu po uderzeniu szukamy bezruchu.
  static const Duration stillnessWindow = Duration(seconds: 8);

  /// Jak długo musi trwać bezruch.
  static const Duration requiredStillness = Duration(seconds: 5);

  /// Poniżej tej prędkości zawodnik nie jedzie.
  static const double stillSpeedKmh = 4;

  /// Jak daleko wstecz patrzymy na prędkość sprzed uderzenia.
  static const Duration speedLookback = Duration(seconds: 4);

  final List<({DateTime at, double kmh})> _speeds = [];

  DateTime? _impactAt;
  double? _speedBeforeImpact;
  DateTime? _stillSince;
  bool _triggered = false;

  bool get hasPendingImpact => _impactAt != null;
  bool get triggered => _triggered;

  void reset() {
    _speeds.clear();
    _impactAt = null;
    _speedBeforeImpact = null;
    _stillSince = null;
    _triggered = false;
  }

  /// Przyspieszenie w g, bez grawitacji.
  void feedAcceleration(double magnitudeG, DateTime at) {
    if (_triggered) return;
    if (magnitudeG < sensitivity.impactG) return;
    // Kolejne uderzenie w trakcie okna nie resetuje zegara — liczy się
    // pierwsze, bo to ono było wypadkiem.
    if (_impactAt != null && at.difference(_impactAt!) < stillnessWindow) {
      return;
    }
    _impactAt = at;
    _speedBeforeImpact = _speedAt(at.subtract(speedLookback), at);
    _stillSince = null;
  }

  /// Prędkość z GPS.
  ///
  /// Zwraca true w chwili, w której wszystkie warunki są spełnione.
  bool feedSpeed(double kmh, DateTime at) {
    _speeds.add((at: at, kmh: kmh));
    while (_speeds.isNotEmpty &&
        at.difference(_speeds.first.at) > const Duration(seconds: 30)) {
      _speeds.removeAt(0);
    }
    if (_triggered) return false;

    final impact = _impactAt;
    if (impact == null) return false;

    if (at.difference(impact) > stillnessWindow) {
      // Minęło okno i zawodnik jedzie dalej — to była dziura, nie wypadek.
      _impactAt = null;
      _speedBeforeImpact = null;
      _stillSince = null;
      return false;
    }

    final before = _speedBeforeImpact ?? 0;
    // Bez rozpędu nie ma z czego spaść: uderzenie na postoju to upuszczony
    // telefon, nie wypadek.
    if (before - kmh < sensitivity.speedDropKmh) {
      _stillSince = null;
      return false;
    }

    if (kmh > stillSpeedKmh) {
      _stillSince = null;
      return false;
    }

    final since = _stillSince ??= at;
    if (at.difference(since) >= requiredStillness) {
      _triggered = true;
      return true;
    }
    return false;
  }

  /// Najwyższa prędkość w oknie przed uderzeniem.
  double? _speedAt(DateTime from, DateTime to) {
    double? best;
    for (final sample in _speeds) {
      if (sample.at.isBefore(from) || sample.at.isAfter(to)) continue;
      best = best == null ? sample.kmh : math.max(best, sample.kmh);
    }
    return best;
  }
}
