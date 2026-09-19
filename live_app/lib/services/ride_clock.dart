/// Księgowość czasu przejazdu.
///
/// Trzy różne czasy da się pomylić na tyle łatwo, że warto trzymać je w
/// jednym miejscu, z testami:
///
///  * **elapsed** — od startu do teraz, razem z każdym postojem. To jest
///    liczba, którą rowerzysta porównuje z zegarkiem na ręce.
///  * **recording** — elapsed bez pauz. To chodzi licznik.
///  * **paused** — suma pauz, z podziałem na te, które włączył detektor
///    postoju, i te, które wcisnął człowiek.
///
/// Podział pauz nie jest kosmetyczny. Pauzę automatyczną kończy ruch roweru;
/// ręczną kończy wyłącznie palec rowerzysty. Licznik, który sam startuje po
/// tym, jak ktoś świadomie go zatrzymał, kasuje czyjąś decyzję.
class RideClock {
  RideClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DateTime? _startedAt;
  DateTime? _pausedAt;
  bool _automatic = false;
  Duration _autoTotal = Duration.zero;
  Duration _manualTotal = Duration.zero;

  DateTime? get startedAt => _startedAt;

  bool get isStarted => _startedAt != null;
  bool get isPaused => _startedAt != null && _pausedAt != null;
  bool get isRunning => _startedAt != null && _pausedAt == null;

  /// Licznik stoi, bo stoi rower.
  bool get isAutoPaused => isPaused && _automatic;

  /// Licznik stoi, bo ktoś go zatrzymał.
  bool get isManuallyPaused => isPaused && !_automatic;

  void start() {
    reset();
    _startedAt = _now();
  }

  void reset() {
    _startedAt = null;
    _pausedAt = null;
    _automatic = false;
    _autoTotal = Duration.zero;
    _manualTotal = Duration.zero;
  }

  /// Zatrzymuje licznik. Zwraca false, gdy nie było czego zatrzymywać.
  bool pause({required bool automatic}) {
    if (_startedAt == null || _pausedAt != null) return false;
    _pausedAt = _now();
    _automatic = automatic;
    return true;
  }

  /// Wznawia licznik.
  ///
  /// [automatic] mówi, kto wznawia: true, gdy to decyzja detektora postoju.
  /// Detektor nigdy nie zdejmie pauzy wciśniętej ręcznie — dostanie false i
  /// licznik zostanie tam, gdzie go postawiono.
  bool resume({required bool automatic}) {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return false;
    if (automatic && !_automatic) return false;
    final spent = _clamp(_now().difference(pausedAt));
    if (_automatic) {
      _autoTotal += spent;
    } else {
      _manualTotal += spent;
    }
    _pausedAt = null;
    _automatic = false;
    return true;
  }

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    return _clamp(_now().difference(started));
  }

  Duration get recording => _clamp(elapsed - paused);

  Duration get paused => autoPaused + manualPaused;

  Duration get autoPaused => _autoTotal + (_automatic ? _open : Duration.zero);

  Duration get manualPaused =>
      _manualTotal + (_automatic ? Duration.zero : _open);

  /// Trwająca pauza, jeszcze nie dopisana do żadnej sumy.
  Duration get _open {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return Duration.zero;
    return _clamp(_now().difference(pausedAt));
  }

  /// Zegar systemowy potrafi cofnąć się w tle (strefa czasowa, NTP), a ujemny
  /// czas jazdy jest gorszy niż zatrzymany.
  static Duration _clamp(Duration value) =>
      value.isNegative ? Duration.zero : value;
}
