import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/ride_clock.dart';

/// Zegar przejazdu decyduje, co rowerzysta zobaczy w podsumowaniu, i to on
/// pilnuje, że pauza wciśnięta palcem nie zniknie sama.
void main() {
  late DateTime now;
  late RideClock clock;

  setUp(() {
    now = DateTime.utc(2026, 5, 1, 13);
    clock = RideClock(now: () => now);
  });

  void advance(Duration by) => now = now.add(by);

  group('trzy czasy', () {
    test('przed startem wszystko jest zerem', () {
      expect(clock.elapsed, Duration.zero);
      expect(clock.recording, Duration.zero);
      expect(clock.paused, Duration.zero);
      expect(clock.isStarted, isFalse);
    });

    test('bez postoju elapsed i recording to ta sama liczba', () {
      clock.start();
      advance(const Duration(hours: 1, minutes: 12));
      expect(clock.elapsed, const Duration(hours: 1, minutes: 12));
      expect(clock.recording, const Duration(hours: 1, minutes: 12));
      expect(clock.paused, Duration.zero);
    });

    test('elapsed liczy postoje, recording ich nie liczy', () {
      // Dwie godziny na trasie, z czego 17:42 na światłach i pod sklepem.
      clock.start();
      advance(const Duration(minutes: 40));
      clock.pause(automatic: true);
      advance(const Duration(minutes: 12, seconds: 42));
      clock.resume(automatic: true);
      advance(const Duration(minutes: 62, seconds: 18));
      clock.pause(automatic: false);
      advance(const Duration(minutes: 5));
      clock.resume(automatic: false);

      expect(clock.elapsed, const Duration(hours: 2));
      expect(clock.paused, const Duration(minutes: 17, seconds: 42));
      expect(
        clock.recording,
        const Duration(hours: 1, minutes: 42, seconds: 18),
      );
    });

    test('pauza automatyczna i ręczna liczą się osobno', () {
      clock.start();
      advance(const Duration(minutes: 10));
      clock.pause(automatic: true);
      advance(const Duration(minutes: 3));
      clock.resume(automatic: true);
      clock.pause(automatic: false);
      advance(const Duration(minutes: 7));
      clock.resume(automatic: false);

      expect(clock.autoPaused, const Duration(minutes: 3));
      expect(clock.manualPaused, const Duration(minutes: 7));
      expect(clock.paused, const Duration(minutes: 10));
    });

    test('trwająca pauza już się liczy, jeszcze zanim się skończy', () {
      clock.start();
      advance(const Duration(minutes: 5));
      clock.pause(automatic: true);
      advance(const Duration(minutes: 2));

      expect(clock.elapsed, const Duration(minutes: 7));
      expect(clock.autoPaused, const Duration(minutes: 2));
      expect(clock.recording, const Duration(minutes: 5));
    });
  });

  group('D — ręczna pauza nie wznawia się sama', () {
    test('detektor nie zdejmuje pauzy wciśniętej ręcznie', () {
      clock.start();
      advance(const Duration(minutes: 20));
      clock.pause(automatic: false);
      advance(const Duration(minutes: 30));

      expect(clock.resume(automatic: true), isFalse);
      expect(clock.isManuallyPaused, isTrue);
      expect(clock.isPaused, isTrue);

      advance(const Duration(minutes: 30));
      expect(clock.resume(automatic: true), isFalse);
      expect(clock.manualPaused, const Duration(hours: 1));
      expect(clock.recording, const Duration(minutes: 20));
    });

    test('rowerzysta zdejmuje ją sam i licznik rusza', () {
      clock.start();
      advance(const Duration(minutes: 20));
      clock.pause(automatic: false);
      advance(const Duration(minutes: 10));

      expect(clock.resume(automatic: false), isTrue);
      expect(clock.isPaused, isFalse);
      advance(const Duration(minutes: 5));
      expect(clock.recording, const Duration(minutes: 25));
    });

    test('pauzę automatyczną wolno zdjąć jednemu i drugiemu', () {
      clock.start();
      clock.pause(automatic: true);
      expect(clock.resume(automatic: true), isTrue);

      clock.pause(automatic: true);
      expect(clock.resume(automatic: false), isTrue);
    });

    test('rodzaj pauzy to osobny stan, nie flaga na boku', () {
      clock.start();
      clock.pause(automatic: true);
      expect(clock.isAutoPaused, isTrue);
      expect(clock.isManuallyPaused, isFalse);

      clock.resume(automatic: true);
      clock.pause(automatic: false);
      expect(clock.isAutoPaused, isFalse);
      expect(clock.isManuallyPaused, isTrue);
    });
  });

  group('sytuacje brzegowe', () {
    test('druga pauza z rzędu niczego nie nadpisuje', () {
      clock.start();
      clock.pause(automatic: false);
      advance(const Duration(minutes: 4));
      // Gdyby to przeszło, ręczna pauza zamieniłaby się w automatyczną
      // i detektor mógłby ją zdjąć.
      expect(clock.pause(automatic: true), isFalse);
      expect(clock.isManuallyPaused, isTrue);
    });

    test('wznowienie bez pauzy nic nie robi', () {
      clock.start();
      expect(clock.resume(automatic: false), isFalse);
      expect(clock.isRunning, isTrue);
    });

    test('pauza przed startem nie zatrzymuje niczego', () {
      expect(clock.pause(automatic: true), isFalse);
      expect(clock.isPaused, isFalse);
    });

    test('cofnięty zegar systemowy nie robi ujemnego czasu', () {
      clock.start();
      now = now.subtract(const Duration(minutes: 5));
      expect(clock.elapsed, Duration.zero);
      expect(clock.recording, Duration.zero);
    });

    test('start czyści poprzedni przejazd', () {
      clock.start();
      advance(const Duration(minutes: 30));
      clock.pause(automatic: true);
      advance(const Duration(minutes: 5));

      clock.start();
      expect(clock.elapsed, Duration.zero);
      expect(clock.paused, Duration.zero);
      expect(clock.isPaused, isFalse);
    });
  });
}
