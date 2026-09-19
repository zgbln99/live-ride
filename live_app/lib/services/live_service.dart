import 'package:geolocator/geolocator.dart';

import '../core/api_client.dart';
import 'heart_rate_service.dart';

class LiveSessionController {
  LiveSessionController(this.api, this.heartRate);

  final ApiClient api;
  final HeartRateService heartRate;

  LiveSession? session;
  DateTime? _lastSentAt;

  bool get isActive => session != null;

  Future<LiveSession> create({required String title, String? displayName}) async {
    final created = await api.createLive(title: title, displayName: displayName);
    session = created;
    _lastSentAt = null;
    return created;
  }

  Future<LiveSession> join(String code, {String? displayName}) async {
    final joined = await api.joinLive(code, displayName: displayName);
    session = joined;
    _lastSentAt = null;
    return joined;
  }

  Future<void> stop() async {
    final active = session;
    session = null;
    _lastSentAt = null;
    if (active != null) await api.stopLive(active.id);
  }

  String? get viewerUrl => session == null ? null : api.viewerUrl(session!.shareToken);

  Future<void> pushPosition(
    Position position, {
    required double distanceMeters,
    double elevationGainMeters = 0,
  }) async {
    final active = session;
    if (active == null) return;
    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastSentAt = now;
    try {
      await api.sendTelemetry(
        active.id,
        {
          'recorded_at': position.timestamp.toUtc().toIso8601String(),
          'latitude': position.latitude,
          'longitude': position.longitude,
          'speed_kmh': (position.speed.isFinite ? position.speed : 0) * 3.6,
          'altitude_m': position.altitude.isFinite ? position.altitude : 0,
          'heading_deg': position.heading.isFinite ? position.heading : 0,
          'accuracy_m': position.accuracy.isFinite ? position.accuracy : 0,
          'heart_rate_bpm': heartRate.latestBpm ?? 0,
          'distance_m': distanceMeters,
          'elevation_gain_m': elevationGainMeters,
        },
      );
    } catch (_) {
      // Navigation must keep working if telemetry upload temporarily fails.
    }
  }
}
