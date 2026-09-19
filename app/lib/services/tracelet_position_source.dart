export 'tracelet_position_source_legacy.dart' hide TraceletPositionSource;

import 'package:geolocator/geolocator.dart' as geo;
import 'package:wanderer/services/tracelet_position_source_legacy.dart' as legacy;

String _liveRideBrand(String text) => text
    .replaceAll('Wanderer', 'Live Ride')
    .replaceAll('wanderer', 'Live Ride');

/// Branding adapter around the proven Tracelet GPS engine.
///
/// Tracking configuration and the single GPS stream remain exactly upstream;
/// only user-facing notification strings are normalized to Live Ride.
class TraceletPositionSource extends legacy.TraceletPositionSource {
  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    geo.Position? seed,
  }) {
    return super.start(
      notificationTitle: 'Live Ride',
      notificationText: _liveRideBrand(notificationText),
      seed: seed,
    );
  }

  @override
  Future<void> setNotificationText(String text) {
    return super.setNotificationText(_liveRideBrand(text));
  }

  static Future<bool> isTracking() => legacy.TraceletPositionSource.isTracking();

  static Future<void> stopOrphanedTracking() =>
      legacy.TraceletPositionSource.stopOrphanedTracking();
}
