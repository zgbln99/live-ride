import 'dart:async';

/// Minimal contract consumed by Live Ride. BLE/WHOOP is only one source;
/// future ANT+/Health Connect/other sensors can implement the same interface.
abstract interface class HeartRateSource {
  int? get latestBpm;
  Stream<int> get bpm;

  Future<void> dispose();
}
