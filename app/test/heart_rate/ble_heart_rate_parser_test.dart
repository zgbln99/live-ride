import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanderer/heart_rate/ble_heart_rate_parser.dart';

void main() {
  test('parses 8-bit Heart Rate Measurement', () {
    expect(parseBleHeartRateMeasurement(Uint8List.fromList([0x00, 154])), 154);
  });

  test('parses little-endian 16-bit Heart Rate Measurement', () {
    expect(
      parseBleHeartRateMeasurement(Uint8List.fromList([0x01, 0x2c, 0x01])),
      300,
    );
  });

  test('rejects truncated 16-bit measurement', () {
    expect(
      () => parseBleHeartRateMeasurement(Uint8List.fromList([0x01, 0x2c])),
      throwsFormatException,
    );
  });
}
