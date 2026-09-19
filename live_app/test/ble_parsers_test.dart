import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/ble_parsers.dart';

List<int> _u16(int value) => [value & 0xFF, (value >> 8) & 0xFF];
List<int> _u32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

void main() {
  group('Heart Rate Measurement (0x2A37)', () {
    test('odczytuje wartość 8-bitową', () {
      final parsed = parseHeartRateMeasurement([0x00, 72]);
      expect(parsed!.bpm, 72);
      expect(parsed.sensorContact, isNull);
      expect(parsed.rrIntervalsMs, isEmpty);
    });

    test('odczytuje wartość 16-bitową', () {
      final parsed = parseHeartRateMeasurement([0x01, 0xC8, 0x00]);
      expect(parsed!.bpm, 200);
    });

    test('odrzuca wartości spoza zakresu fizjologii', () {
      expect(parseHeartRateMeasurement([0x00, 0]), isNull);
      expect(parseHeartRateMeasurement([0x01, 0x2C, 0x01]), isNull);
      expect(parseHeartRateMeasurement([0x00]), isNull);
    });

    test('czyta status kontaktu tylko gdy sensor go wspiera', () {
      expect(parseHeartRateMeasurement([0x06, 140])!.sensorContact, isTrue);
      expect(parseHeartRateMeasurement([0x04, 140])!.sensorContact, isFalse);
      expect(parseHeartRateMeasurement([0x02, 140])!.sensorContact, isNull);
    });

    test('pomija wydatek energii, żeby nie przesunąć odstępów RR', () {
      // flags: 16-bit off, contact off, energy present, RR present.
      final value = [0x18, 60, ..._u16(250), ..._u16(1024), ..._u16(512)];
      final parsed = parseHeartRateMeasurement(value)!;
      expect(parsed.bpm, 60);
      expect(parsed.energyExpendedKj, 250);
      expect(parsed.rrIntervalsMs, hasLength(2));
      expect(parsed.rrIntervalsMs.first, closeTo(1000, 0.001));
      expect(parsed.rrIntervalsMs.last, closeTo(500, 0.001));
    });
  });

  group('CSC Measurement (0x2A5B)', () {
    test('czyta same dane koła', () {
      final parsed = parseCscMeasurement([0x01, ..._u32(1234), ..._u16(2048)])!;
      expect(parsed.hasWheel, isTrue);
      expect(parsed.hasCrank, isFalse);
      expect(parsed.cumulativeWheelRevolutions, 1234);
      expect(parsed.lastWheelEventTime, 2048);
    });

    test('czyta same dane korby', () {
      final parsed = parseCscMeasurement([0x02, ..._u16(77), ..._u16(900)])!;
      expect(parsed.hasWheel, isFalse);
      expect(parsed.cumulativeCrankRevolutions, 77);
      expect(parsed.lastCrankEventTime, 900);
    });

    test('czyta oba zestawy w jednej ramce', () {
      final parsed = parseCscMeasurement([
        0x03,
        ..._u32(100000),
        ..._u16(1000),
        ..._u16(50),
        ..._u16(2000),
      ])!;
      expect(parsed.cumulativeWheelRevolutions, 100000);
      expect(parsed.lastWheelEventTime, 1000);
      expect(parsed.cumulativeCrankRevolutions, 50);
      expect(parsed.lastCrankEventTime, 2000);
    });

    test('odrzuca obcięte ramki zamiast czytać śmieci', () {
      expect(parseCscMeasurement([0x01, 0x01, 0x02]), isNull);
      expect(parseCscMeasurement([0x03, ..._u32(1), ..._u16(1), 0x05]), isNull);
      expect(parseCscMeasurement([0x00]), isNull);
      expect(parseCscMeasurement(const []), isNull);
    });
  });

  group('Cycling Power Measurement (0x2A63)', () {
    test('czyta samą moc chwilową', () {
      final parsed = parseCyclingPowerMeasurement([..._u16(0), ..._u16(250)])!;
      expect(parsed.instantaneousPowerWatts, 250);
      expect(parsed.pedalPowerBalancePercent, isNull);
      expect(parsed.cumulativeCrankRevolutions, isNull);
    });

    test('przesuwa offset o każde obecne pole opcjonalne', () {
      // flags: balance (bit0) + reference (bit1) + torque (bit2)
      //        + wheel (bit4) + crank (bit5).
      const flags = 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020;
      final parsed = parseCyclingPowerMeasurement([
        ..._u16(flags),
        ..._u16(310),
        100, // balance: 50 %
        ..._u16(320), // torque: 10 Nm
        ..._u32(5000), // wheel revolutions
        ..._u16(4096), // wheel event time
        ..._u16(1200), // crank revolutions
        ..._u16(3000), // crank event time
      ])!;
      expect(parsed.instantaneousPowerWatts, 310);
      expect(parsed.pedalPowerBalancePercent, 50);
      expect(parsed.accumulatedTorque, 10);
      expect(parsed.cumulativeWheelRevolutions, 5000);
      expect(parsed.lastWheelEventTime, 4096);
      expect(parsed.cumulativeCrankRevolutions, 1200);
      expect(parsed.lastCrankEventTime, 3000);
    });

    test('bez bitu balansu nie zjada bajtu przed korbą', () {
      final parsed = parseCyclingPowerMeasurement([
        ..._u16(0x0020),
        ..._u16(180),
        ..._u16(64),
        ..._u16(9000),
      ])!;
      expect(parsed.cumulativeCrankRevolutions, 64);
      expect(parsed.lastCrankEventTime, 9000);
    });

    test('przyjmuje moc ujemną, ale nie absurdalną', () {
      expect(
        parseCyclingPowerMeasurement([
          ..._u16(0),
          0xFF,
          0xFF,
        ])!.instantaneousPowerWatts,
        -1,
      );
      expect(parseCyclingPowerMeasurement([..._u16(0), 0x10, 0x27]), isNull);
      expect(parseCyclingPowerMeasurement([0x00, 0x00, 0x01]), isNull);
    });
  });

  group('Indoor Bike Data (0x2AD2)', () {
    test('bit More Data oznacza BRAK prędkości chwilowej', () {
      final withSpeed = parseIndoorBikeData([..._u16(0x0000), ..._u16(2550)])!;
      expect(withSpeed.speedKmh, closeTo(25.5, 0.001));

      final withoutSpeed = parseIndoorBikeData([
        ..._u16(0x0001 | 0x0004),
        ..._u16(180),
      ])!;
      expect(withoutSpeed.speedKmh, isNull);
      expect(withoutSpeed.cadenceRpm, closeTo(90, 0.001));
    });

    test('czyta pełną ramkę trenażera', () {
      const flags =
          0x0001 | // brak prędkości chwilowej
          0x0004 | // kadencja
          0x0010 | // dystans
          0x0040 | // moc
          0x0100 | // energia
          0x0200; // tętno
      final parsed = parseIndoorBikeData([
        ..._u16(flags),
        ..._u16(180), // kadencja: jednostka 0.5 rpm
        12, 0, 0, // dystans 12 m (uint24)
        ..._u16(240), // moc
        ..._u16(88), // energia total
        ..._u16(0), // energia na godzinę
        0, // energia na minutę
        145, // tętno
      ])!;
      expect(parsed.speedKmh, isNull);
      expect(parsed.cadenceRpm, closeTo(90, 0.001));
      expect(parsed.totalDistanceMeters, 12);
      expect(parsed.powerWatts, 240);
      expect(parsed.energyTotalKj, 88);
      expect(parsed.heartRateBpm, 145);
    });

    test('ucięta ramka nie daje wartości z przypadkowych bajtów', () {
      expect(parseIndoorBikeData([..._u16(0x0000)]), isNull);
      expect(parseIndoorBikeData([0x00]), isNull);
    });
  });

  group('RevolutionTracker', () {
    test('pierwsza próbka nie daje jeszcze wyniku', () {
      final tracker = RevolutionTracker();
      expect(tracker.update(10, 1024), isNull);
    });

    test('liczy kadencję z różnicy obrotów i czasu', () {
      final tracker = RevolutionTracker();
      tracker.update(10, 0);
      // Jeden obrót w 1024 tyknięcia, czyli w sekundę -> 60 rpm.
      expect(tracker.update(11, 1024), closeTo(60, 0.001));
      expect(tracker.update(13, 2048), closeTo(120, 0.001));
    });

    test('przeżywa zawinięcie czasu zdarzenia', () {
      final tracker = RevolutionTracker();
      tracker.update(100, 65000);
      // 65000 + 1024 przekracza 65535 i zawija się na 488.
      expect(tracker.update(101, 488), closeTo(60, 0.001));
    });

    test('przeżywa zawinięcie licznika obrotów korby', () {
      final tracker = RevolutionTracker();
      tracker.update(65534, 0);
      expect(tracker.update(1, 1024), closeTo(180, 0.001));
    });

    test(
      'po kilku sekundach bez ruchu pokazuje zero, nie ostatnią wartość',
      () {
        final tracker = RevolutionTracker();
        final start = DateTime(2026, 5, 1, 12);
        tracker.update(10, 0, now: start);
        tracker.update(11, 1024, now: start.add(const Duration(seconds: 1)));
        expect(tracker.revolutionsPerMinute, closeTo(60, 0.001));

        // Ten sam licznik — koło stoi.
        tracker.update(11, 2048, now: start.add(const Duration(seconds: 2)));
        expect(tracker.revolutionsPerMinute, closeTo(60, 0.001));
        tracker.update(11, 4096, now: start.add(const Duration(seconds: 6)));
        expect(tracker.revolutionsPerMinute, 0);
      },
    );

    test('zamienia obroty koła na prędkość', () {
      final tracker = RevolutionTracker();
      tracker.update(0, 0);
      tracker.update(1, 1024);
      // 2096 mm na sekundę to 7.55 km/h.
      expect(tracker.speedKmh(2096), closeTo(7.5456, 0.001));
    });

    test('odrzuca odczyty dające absurdalną kadencję', () {
      final tracker = RevolutionTracker();
      tracker.update(0, 0);
      tracker.update(1, 1024);
      final before = tracker.revolutionsPerMinute;
      // 100 obrotów w jednym tyknięciu to błąd sensora.
      tracker.update(101, 1025);
      expect(tracker.revolutionsPerMinute, before);
    });

    test('reset czyści historię', () {
      final tracker = RevolutionTracker();
      tracker.update(0, 0);
      tracker.update(1, 1024);
      tracker.reset();
      expect(tracker.revolutionsPerMinute, isNull);
      expect(tracker.update(5, 2048), isNull);
    });
  });
}
