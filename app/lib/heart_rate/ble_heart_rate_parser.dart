import 'dart:typed_data';

/// Parses the Bluetooth SIG Heart Rate Measurement characteristic (0x2A37).
/// Bit 0 of the flags byte chooses 8-bit vs 16-bit heart-rate encoding.
int parseBleHeartRateMeasurement(Uint8List value) {
  if (value.length < 2) {
    throw const FormatException('Heart Rate Measurement is too short');
  }

  final isUint16 = (value[0] & 0x01) != 0;
  if (!isUint16) return value[1];
  if (value.length < 3) {
    throw const FormatException('16-bit Heart Rate Measurement is truncated');
  }
  return value[1] | (value[2] << 8);
}
