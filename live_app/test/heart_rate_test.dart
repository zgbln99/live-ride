import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/heart_rate_service.dart';

void main() {
  group('parseHeartRateMeasurement', () {
    test('reads an 8-bit value', () {
      // flags 0x00: 8-bit, no contact support.
      final parsed = parseHeartRateMeasurement([0x00, 72]);
      expect(parsed!.bpm, 72);
      expect(parsed.sensorContact, isNull);
    });

    test('reads a 16-bit value, little endian', () {
      // flags 0x01: 16-bit. 0x2C 0x01 = 300 is out of range, so use 0x96 0x00.
      final parsed = parseHeartRateMeasurement([0x01, 0x96, 0x00]);
      expect(parsed!.bpm, 150);
    });

    test('reports skin contact when the sensor supports it', () {
      // Bit 2 set: contact supported. Bit 1 set: contact detected.
      expect(parseHeartRateMeasurement([0x06, 88])!.sensorContact, isTrue);
      expect(parseHeartRateMeasurement([0x04, 88])!.sensorContact, isFalse);
    });

    test('ignores contact bits when the sensor does not support them', () {
      // WHOOP reports 0x00 here; reading bit 1 would claim "not worn".
      expect(parseHeartRateMeasurement([0x00, 88])!.sensorContact, isNull);
      expect(parseHeartRateMeasurement([0x02, 88])!.sensorContact, isNull);
    });

    test('rejects impossible and truncated readings', () {
      expect(parseHeartRateMeasurement([]), isNull);
      expect(parseHeartRateMeasurement([0x00]), isNull);
      expect(parseHeartRateMeasurement([0x01, 0x96]), isNull);
      expect(parseHeartRateMeasurement([0x00, 0]), isNull);
      expect(parseHeartRateMeasurement([0x01, 0xFF, 0xFF]), isNull);
    });
  });

  group('HeartRateDevice', () {
    test('treats a WHOOP strap as a heart-rate sensor', () {
      const whoop = HeartRateDevice(
        id: '1',
        name: 'WHOOP 4.0',
        rssi: -60,
        advertisesHeartRate: false,
        isWhoop: true,
      );
      // WHOOP never advertises 0x180D, so the name is the only clue.
      expect(whoop.likelyHeartRate, isTrue);
    });

    test('maps signal strength onto four bars', () {
      int bars(int rssi) => HeartRateDevice(
        id: '1',
        name: 'x',
        rssi: rssi,
        advertisesHeartRate: true,
        isWhoop: false,
      ).signalBars;

      expect(bars(-40), 4);
      expect(bars(-65), 3);
      expect(bars(-80), 2);
      expect(bars(-100), 1);
    });
  });
}
