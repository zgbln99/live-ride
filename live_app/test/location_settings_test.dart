import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/location_service.dart';

/// Ustawienia strumienia pozycji dla trwającego przejazdu.
///
/// Ten test istnieje z powodu usterki, której nie dało się zobaczyć w żadnym
/// teście logiki. Filtr odległości ustawiony na trzy metry znaczy „odezwij
/// się, gdy przesuniesz się o trzy metry", więc telefon stojący na światłach
/// nie odzywał się wcale. Wykrywanie postoju nie dostawało ANI JEDNEJ próbki
/// mówiącej, że rower stoi, a że brak danych nigdy nie zatrzymuje licznika —
/// bo tak samo wygląda utrata zasięgu przy 25 km/h — auto-pauza nie włączała
/// się nawet po półtorej godziny bezruchu.
///
/// Cały detektor działał poprawnie. Po prostu nikt go o nic nie pytał.
void main() {
  group('strumień pozycji w trakcie jazdy', () {
    test('filtr odległości jest zerowy', () {
      expect(
        LocationService.rideDistanceFilterMeters,
        0,
        reason:
            'każda wartość powyżej zera wycisza stojący telefon i wyłącza '
            'wykrywanie postoju',
      );
    });

    test('próbki przychodzą mniej więcej raz na sekundę', () {
      // Trzy sekundy potwierdzania postoju wymagają kilku próbek w tym
      // czasie. Rzadszy strumień przesunąłby pauzę poza okno, w którym
      // rowerzysta jeszcze uzna ją za reakcję, a nie za zawieszenie.
      expect(
        LocationService.rideInterval.inSeconds,
        lessThanOrEqualTo(1),
      );
    });

    test('system nie ma prawa sam wstrzymać aktualizacji', () {
      // iOS potrafi wstrzymać strumień, gdy uzna, że użytkownik się nie
      // rusza — czyli dokładnie w chwili, w której potrzebujemy go
      // najbardziej. To jest ustawienie, nie logika, więc jedyne miejsce,
      // w którym da się je sprawdzić, to źródło.
      final source = File('lib/services/location_service.dart').readAsStringSync();
      expect(source, contains('pauseLocationUpdatesAutomatically: false'));
      expect(source, contains('activityType: ActivityType.fitness'));
      // I żeby nikt nie wpisał liczby z powrotem obok stałej.
      expect(
        RegExp(r'distanceFilter:\s*[1-9]').hasMatch(source),
        isFalse,
        reason: 'filtr odległości musi iść ze stałej, nie z liczby w miejscu',
      );
    });

  });
}
