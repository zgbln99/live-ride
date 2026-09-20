import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/session_guard.dart';

/// Najważniejsza obietnica konta: wygaśnięcie sesji nie przerywa jazdy.
///
/// Serwer może odrzucić token w dowolnej sekundzie — najczęściej przy próbie
/// wysłania telemetrii, czyli dokładnie wtedy, gdy ktoś jedzie. Ekran
/// logowania w tym momencie oznacza zgubiony ślad, którego nie da się
/// powtórzyć drugi raz tego samego dnia.
void main() {
  late bool riding;
  late int signOuts;
  late SessionGuard guard;

  setUp(() {
    riding = false;
    signOuts = 0;
    guard = SessionGuard(isRiding: () => riding, signOut: () => signOuts++);
  });

  test('poza jazdą wylogowuje od razu', () {
    guard.onExpired();
    expect(signOuts, 1);
    expect(guard.expired, isTrue);
    expect(guard.deferred, isFalse);
  });

  test('w trakcie jazdy nie wylogowuje', () {
    riding = true;
    guard.onExpired();

    expect(signOuts, 0, reason: 'jazda ma się toczyć dalej');
    expect(guard.expired, isTrue);
    expect(guard.deferred, isTrue);
  });

  test('wylogowuje dopiero po zakończeniu przejazdu', () {
    riding = true;
    guard.onExpired();

    // Licznik tyka: pauza, wznowienie, kolejne kilometry. Nic z tego nie
    // jest końcem jazdy.
    for (var i = 0; i < 50; i++) {
      guard.onRideStateChanged();
    }
    expect(signOuts, 0);

    riding = false;
    guard.onRideStateChanged();
    expect(signOuts, 1);
    expect(guard.deferred, isFalse);
  });

  test('wylogowuje raz, nie na każde tyknięcie licznika', () {
    riding = true;
    guard.onExpired();
    riding = false;
    guard.onRideStateChanged();
    guard.onRideStateChanged();
    guard.onRideStateChanged();
    expect(signOuts, 1);
  });

  test('powtórzone 401 nie mnoży wylogowań', () {
    // Synchronizacja, telemetria i pogoda potrafią dostać 401 w tej samej
    // sekundzie.
    guard.onExpired();
    guard.onExpired();
    guard.onExpired();
    expect(signOuts, 1);
  });

  test('bez wygaśnięcia koniec jazdy niczego nie robi', () {
    riding = true;
    riding = false;
    guard.onRideStateChanged();
    expect(signOuts, 0);
    expect(guard.expired, isFalse);
  });

  test('ponowne zalogowanie czyści pamięć o wygaśnięciu', () {
    guard.onExpired();
    guard.reset();
    expect(guard.expired, isFalse);
    expect(guard.deferred, isFalse);

    // I następne wygaśnięcie znowu działa.
    guard.onExpired();
    expect(signOuts, 2);
  });

  test('wygaśnięcie w trakcie jazdy, a potem ręczne wylogowanie', () {
    riding = true;
    guard.onExpired();
    guard.reset();

    riding = false;
    guard.onRideStateChanged();
    // Rowerzysta już wyszedł sam; zaległe wylogowanie nie ma czego dopełnić.
    expect(signOuts, 0);
  });
}
