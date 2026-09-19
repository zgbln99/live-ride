import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api_client.dart';
import 'heart_rate_service.dart';
import 'profile_service.dart';

/// Owns the LIVE session: creating it, joining one, publishing telemetry and
/// exposing the spectator link.
class LiveSessionController extends ChangeNotifier {
  LiveSessionController(this.api, this.heartRate, this.profile);

  /// Telemetry cadence. Fast enough for a spectator map, slow enough not to
  /// drain a phone that is also navigating.
  static const Duration telemetryInterval = Duration(seconds: 3);

  final ApiClient api;
  final HeartRateService heartRate;
  final ProfileService profile;

  LiveSession? _session;
  DateTime? _lastSentAt;
  DateTime? _lastAcceptedAt;
  bool _lastPushFailed = false;
  String? _title;

  LiveSession? get session => _session;
  bool get isActive => _session != null;
  String? get title => _title;
  String? get joinCode => _session?.joinToken;
  String? get viewerUrl =>
      _session == null ? null : api.viewerUrl(_session!.shareToken);
  DateTime? get lastAcceptedAt => _lastAcceptedAt;
  bool get lastPushFailed => _lastPushFailed;

  Future<LiveSession> create({String? title}) async {
    final resolved = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : '${profile.riderName} · Live Ride';
    final created = await api.createLive(
      title: resolved,
      displayName: profile.riderName,
    );
    _session = created;
    _title = resolved;
    _lastSentAt = null;
    _lastAcceptedAt = null;
    _lastPushFailed = false;
    notifyListeners();
    return created;
  }

  Future<LiveSession> join(String code) async {
    final joined = await api.joinLive(code, displayName: profile.riderName);
    _session = joined;
    _title = 'Joined LIVE';
    _lastSentAt = null;
    _lastAcceptedAt = null;
    _lastPushFailed = false;
    notifyListeners();
    return joined;
  }

  Future<void> stop() async {
    final active = _session;
    _session = null;
    _title = null;
    _lastSentAt = null;
    _lastAcceptedAt = null;
    _lastPushFailed = false;
    notifyListeners();
    if (active != null) {
      // Best effort: the session also expires server-side, and a failed stop
      // must never block ending a ride.
      try {
        await api.stopLive(active.id);
      } catch (_) {}
    }
  }

  /// Publishes one telemetry sample. Returns false when the upload failed or
  /// was skipped; navigation and recording never depend on the result.
  Future<bool> pushPosition(
    Position position, {
    required double distanceMeters,
    double elevationGainMeters = 0,
  }) async {
    final active = _session;
    if (active == null) return true;

    final now = DateTime.now();
    final last = _lastSentAt;
    if (last != null && now.difference(last) < telemetryInterval) return true;
    _lastSentAt = now;

    try {
      await api.sendTelemetry(active.id, {
        'recorded_at': position.timestamp.toUtc().toIso8601String(),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speed_kmh': _clamp(
          (position.speed.isFinite ? position.speed : 0) * 3.6,
          0,
          200,
        ),
        'altitude_m': position.altitude.isFinite ? position.altitude : 0,
        'heading_deg': position.heading.isFinite && position.heading >= 0
            ? position.heading
            : 0,
        'accuracy_m': _clamp(
          position.accuracy.isFinite ? position.accuracy : 0,
          0,
          5000,
        ),
        'heart_rate_bpm': heartRate.latestBpm ?? 0,
        'distance_m': distanceMeters,
        'elevation_gain_m': elevationGainMeters,
      });
      _lastAcceptedAt = now;
      _lastPushFailed = false;
      return true;
    } catch (_) {
      _lastPushFailed = true;
      return false;
    }
  }

  double _clamp(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max);
  }
}
