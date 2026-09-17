import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:wanderer/heart_rate/heart_rate_source.dart';
import 'package:wanderer/live_ride/live_ride_api.dart';
import 'package:wanderer/live_ride/live_ride_models.dart';
import 'package:wanderer/live_ride/live_ride_queue.dart';
import 'package:wanderer/live_ride/live_ride_tracker.dart';
import 'package:wanderer/provider/navigation_stats_provider.dart';

/// Owns one active Live Ride and glues server session state to Wanderer's
/// existing navigation GPS stream. It does not own location services itself.
class LiveRideCoordinator {
  LiveRideCoordinator({
    required this.api,
    required this.positions,
    required this.statsSnapshot,
    this.heartRate,
  });

  final LiveRideApi api;
  final Stream<geo.Position> positions;
  final NavigationStats Function() statsSnapshot;
  final HeartRateSource? heartRate;

  LiveRideSession? _session;
  LiveRideTracker? _tracker;
  bool _owner = false;

  LiveRideSession? get session => _session;
  bool get isActive => _session != null;
  bool get isOwner => _owner;

  Future<LiveRideSession> create({
    required String title,
    String? trailId,
    String? displayName,
  }) async {
    await leave(endForEveryone: _owner);
    final session = await api.create(
      title: title,
      trailId: trailId,
      displayName: displayName,
    );
    await _attach(session, owner: true);
    return session;
  }

  Future<LiveRideSession> join(
    String joinToken, {
    String? displayName,
  }) async {
    await leave(endForEveryone: _owner);
    final session = await api.join(joinToken, displayName: displayName);
    await _attach(session, owner: false);
    return session;
  }

  Future<void> _attach(LiveRideSession session, {required bool owner}) async {
    final queue = LiveRideTelemetryQueue(api: api, sessionId: session.id);
    final tracker = LiveRideTracker(
      positions: positions,
      statsSnapshot: statsSnapshot,
      queue: queue,
      heartRateSnapshot: () => heartRate?.latestBpm,
    );
    await tracker.start();
    _session = session;
    _owner = owner;
    _tracker = tracker;
  }

  /// Leaves live tracking on this phone. The owner can optionally end the
  /// entire shared session for everyone. Owner shutdown is transactional: if
  /// the server cannot acknowledge the stop (for example because LTE drops),
  /// local tracking is resumed and the session remains active so the user can
  /// retry instead of silently orphaning a public ride.
  Future<void> leave({bool endForEveryone = false}) async {
    final session = _session;
    final tracker = _tracker;
    final wasOwner = _owner;

    if (session == null) return;

    if (tracker != null) await tracker.dispose();

    if (endForEveryone && wasOwner) {
      try {
        await api.stop(session.id);
      } catch (_) {
        // We deliberately keep all coordinator state intact on failure.
        // Restart the same tracker/queue so GPS sharing can continue and the
        // owner can retry ending the ride when connectivity returns.
        if (tracker != null) await tracker.start();
        rethrow;
      }
    }

    // Leaving means this phone will no longer retry old telemetry. On the
    // successful owner-stop path the server already has everything flushable;
    // for a participant this is an explicit local leave.
    if (tracker != null) await tracker.queue.clear();
    _session = null;
    _tracker = null;
    _owner = false;
  }

  /// Disposing the navigation screen is an intentional end of this phone's
  /// live session. If this phone owns the ride, also close it for spectators.
  Future<void> dispose() => leave(endForEveryone: _owner);
}
