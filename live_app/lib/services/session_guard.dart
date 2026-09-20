/// Decyduje, kiedy wygasła sesja może wyrzucić rowerzystę na ekran logowania.
///
/// Odpowiedź brzmi: nigdy w trakcie jazdy. Przejazd nie ma z kontem nic
/// wspólnego — GPS, licznik i zapis lokalny działają bez serwera — a ekran
/// logowania w środku trasy oznacza zgubiony ślad, którego nie da się
/// powtórzyć. Więc wygaśnięcie jest zapamiętywane i realizuje się dopiero,
/// gdy przejazd się skończy.
///
/// Klasa jest osobno od widżetu, bo to jedyny sposób, żeby ta obietnica
/// miała test. Widżet tylko oddaje jej dwa pytania i dostaje jedną decyzję.
class SessionGuard {
  SessionGuard({required this.isRiding, required this.signOut});

  /// Czy licznik właśnie nagrywa (albo stoi na pauzie w trakcie przejazdu).
  final bool Function() isRiding;

  /// Wywoływane, gdy wolno już pokazać ekran logowania.
  final void Function() signOut;

  bool _expired = false;
  bool _waitingForRide = false;

  /// Czy serwer odrzucił już naszą sesję.
  ///
  /// Prawda także wtedy, gdy jazda jeszcze trwa i nikogo nie wylogowaliśmy —
  /// to ona sprawia, że ekran logowania wie, co napisać nad formularzem.
  bool get expired => _expired;

  /// Czy wylogowanie czeka na koniec przejazdu.
  bool get deferred => _waitingForRide;

  /// Serwer odrzucił żądanie z powodu wygasłej sesji.
  void onExpired() {
    if (_expired) return;
    _expired = true;
    if (isRiding()) {
      _waitingForRide = true;
      return;
    }
    signOut();
  }

  /// Wołane przy każdej zmianie stanu licznika.
  void onRideStateChanged() {
    if (!_waitingForRide || isRiding()) return;
    _waitingForRide = false;
    signOut();
  }

  /// Rowerzysta zalogował się albo wylogował ręcznie — zaczynamy od nowa.
  void reset() {
    _expired = false;
    _waitingForRide = false;
  }
}
