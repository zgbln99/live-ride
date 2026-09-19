import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/emergency.dart';
import 'package:live_ride/services/crash_detector.dart';

final DateTime _t0 = DateTime(2026, 5, 1, 12);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

/// Jedzie równo [kmh] przez [seconds] sekund.
void _ride(
  CrashDetector detector, {
  required double kmh,
  required int from,
  required int to,
}) {
  for (var second = from; second <= to; second++) {
    detector.feedSpeed(kmh, _at(second));
  }
}

void main() {
  group('CrashDetector', () {
    test('sama jazda nigdy nie wywołuje alarmu', () {
      final detector = CrashDetector();
      for (var second = 0; second < 60; second++) {
        expect(detector.feedSpeed(30, _at(second)), isFalse);
      }
      expect(detector.triggered, isFalse);
    });

    test('dziura w drodze bez zatrzymania to nie wypadek', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 30, from: 0, to: 9);
      detector.feedAcceleration(6.0, _at(10));
      // Zawodnik jedzie dalej.
      for (var second = 10; second < 30; second++) {
        expect(detector.feedSpeed(29, _at(second)), isFalse);
      }
      expect(detector.triggered, isFalse);
      expect(detector.hasPendingImpact, isFalse, reason: 'okno się zamknęło');
    });

    test('postój na światłach bez uderzenia to nie wypadek', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 30, from: 0, to: 9);
      for (var second = 10; second < 40; second++) {
        expect(detector.feedSpeed(0, _at(second)), isFalse);
      }
      expect(detector.triggered, isFalse);
    });

    test('uderzenie na postoju to upuszczony telefon, nie wypadek', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 0, from: 0, to: 9);
      detector.feedAcceleration(8.0, _at(10));
      for (var second = 10; second < 20; second++) {
        expect(detector.feedSpeed(0, _at(second)), isFalse);
      }
      expect(detector.triggered, isFalse);
    });

    test('uderzenie, spadek prędkości i bezruch dają alarm', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 32, from: 0, to: 9);
      detector.feedAcceleration(5.0, _at(10));

      var fired = false;
      for (var second = 10; second <= 16; second++) {
        fired = detector.feedSpeed(0, _at(second)) || fired;
      }
      expect(fired, isTrue);
      expect(detector.triggered, isTrue);
    });

    test('alarm nie odpala przed upływem wymaganego bezruchu', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 32, from: 0, to: 9);
      detector.feedAcceleration(5.0, _at(10));
      for (var second = 10; second <= 13; second++) {
        expect(detector.feedSpeed(0, _at(second)), isFalse);
      }
      expect(detector.triggered, isFalse);
    });

    test('ruszenie w trakcie odliczania kasuje podejrzenie', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 32, from: 0, to: 9);
      detector.feedAcceleration(5.0, _at(10));
      detector.feedSpeed(0, _at(11));
      detector.feedSpeed(0, _at(12));
      // Zawodnik pozbierał się i jedzie.
      detector.feedSpeed(18, _at(13));
      for (var second = 14; second <= 17; second++) {
        expect(detector.feedSpeed(0, _at(second)), isFalse);
      }
      expect(detector.triggered, isFalse);
    });

    test('słabe uderzenie poniżej progu jest ignorowane', () {
      final detector = CrashDetector(sensitivity: CrashSensitivity.low);
      _ride(detector, kmh: 40, from: 0, to: 9);
      detector.feedAcceleration(4.0, _at(10));
      expect(detector.hasPendingImpact, isFalse);
      for (var second = 10; second <= 20; second++) {
        expect(detector.feedSpeed(0, _at(second)), isFalse);
      }
    });

    test('czułość zmienia próg, a nie logikę', () {
      expect(
        CrashSensitivity.high.impactG,
        lessThan(CrashSensitivity.low.impactG),
      );
      expect(
        CrashSensitivity.high.speedDropKmh,
        lessThan(CrashSensitivity.low.speedDropKmh),
      );

      final sensitive = CrashDetector(sensitivity: CrashSensitivity.high);
      _ride(sensitive, kmh: 25, from: 0, to: 9);
      sensitive.feedAcceleration(2.5, _at(10));
      expect(sensitive.hasPendingImpact, isTrue);
    });

    test('alarm odpala tylko raz, dopóki nie ma resetu', () {
      final detector = CrashDetector();
      _ride(detector, kmh: 32, from: 0, to: 9);
      detector.feedAcceleration(5.0, _at(10));
      for (var second = 10; second <= 16; second++) {
        detector.feedSpeed(0, _at(second));
      }
      expect(detector.triggered, isTrue);
      expect(detector.feedSpeed(0, _at(17)), isFalse);

      detector.reset();
      expect(detector.triggered, isFalse);
      expect(detector.hasPendingImpact, isFalse);
    });
  });

  group('ustawienia bezpieczeństwa', () {
    test('bez kontaktu alarm nie ma komu nic zgłosić', () {
      const settings = SafetySettings(crashDetectionEnabled: true);
      expect(settings.isUsable, isFalse);
    });

    test('z kontaktem staje się użyteczny', () {
      const settings = SafetySettings(
        crashDetectionEnabled: true,
        contacts: [
          EmergencyContact(id: '1', name: 'Ania', phone: '+48123456789'),
        ],
      );
      expect(settings.isUsable, isTrue);
      expect(settings.crashContacts, hasLength(1));
    });

    test('kontakt bez powiadomienia nie liczy się do alarmu', () {
      const settings = SafetySettings(
        crashDetectionEnabled: true,
        contacts: [
          EmergencyContact(
            id: '1',
            name: 'Ania',
            phone: '+48123456789',
            notifyOnCrash: false,
          ),
        ],
      );
      expect(settings.isUsable, isFalse);
    });

    test('domyślnie wykrywanie jest wyłączone', () {
      expect(const SafetySettings().crashDetectionEnabled, isFalse);
    });

    test('ustawienia przechodzą przez JSON', () {
      const settings = SafetySettings(
        crashDetectionEnabled: true,
        sensitivity: CrashSensitivity.high,
        countdownSeconds: 45,
        contacts: [
          EmergencyContact(id: '1', name: 'Ania', phone: '+48123456789'),
        ],
      );
      final restored = SafetySettings.fromJson(settings.toJson());
      expect(restored.crashDetectionEnabled, isTrue);
      expect(restored.sensitivity, CrashSensitivity.high);
      expect(restored.countdownSeconds, 45);
      expect(restored.contacts.single.name, 'Ania');
    });

    test('kontakt bez numeru nie wraca z zapisu', () {
      expect(
        EmergencyContact.fromJson({'id': '1', 'name': 'Ania', 'phone': ''}),
        isNull,
      );
    });
  });
}
