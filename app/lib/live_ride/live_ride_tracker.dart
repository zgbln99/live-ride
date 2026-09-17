import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:wanderer/live_ride/live_ride_models.dart';
import 'package:wanderer/live_ride/live_ride_queue.dart';
import 'package:wanderer/provider/navigation_stats_provider.dart';

/// Adapts Wanderer's existing navigation position stream into server
/// telemetry. It deliberately does NOT open another location subscription.
class LiveRideTracker {
  LiveRideTracker({
    required this.positions,
    required this.statsSnapshot,
    required this.queue,
    this.heartRateSnapshot,
    this.uploadInterval = const Duration(seconds: 3),
  });

  final Stream<geo.Position> positions;
  final NavigationStats Function() statsSnapshot;
  final int? Function()? heartRateSnapshot;
  final LiveRideTelemetryQueue queue;
  final Duration uploadInterval;

  StreamSubscription<geo.Position>? _positionSub;
  DateTime? _lastQueuedAt;

  Future<void> start() async {
    if (_positionSub != null) return;
    // Flush anything gathered before the previous process/network loss.
    unawaited(queue.flush());
    _positionSub = positions.listen((position) {
      unawaited(_handlePosition(position));
    });
  }

  Future<void> _handlePosition(geo.Position position) async {
    final now = DateTime.now();
    if (_lastQueuedAt != null && now.difference(_lastQueuedAt!) < uploadInterval) {
      return;
    }
    _lastQueuedAt = now;

    final point = LiveRideTelemetryPoint.fromPosition(
      position: position,
      stats: statsSnapshot(),
      heartRateBpm: heartRateSnapshot?.call(),
    );

    try {
      await queue.enqueue(point);
      unawaited(queue.flush());
    } catch (_) {
      // Live sharing is optional. A storage failure must never break the
      // navigation position stream that also feeds turn-by-turn guidance.
    }
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await queue.flush();
  }
}
