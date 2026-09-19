import 'dart:io';

import 'package:geolocator/geolocator.dart';

/// Thrown when Live Ride cannot get a position fix. The message is shown to
/// the rider as-is.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message, {this.openSettings = false});

  final String message;

  /// True when the rider has to fix this in the system settings app.
  final bool openSettings;

  @override
  String toString() => message;
}

/// Location permissions and the platform-tuned position stream.
class LocationService {
  /// Requests whatever is missing and throws [LocationUnavailable] with an
  /// actionable message if the rider cannot be located.
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(
        'Location services are switched off. Turn them on to record a ride.',
        openSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(
        'Live Ride needs location access to record your ride.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        'Location access is blocked for Live Ride. Enable it in Settings to '
        'record rides and navigate.',
        openSettings: true,
      );
    }
  }

  Future<Position?> currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // A first fix can take a while; the stream will deliver one shortly.
      return Geolocator.getLastKnownPosition();
    }
  }

  /// A navigation-grade position stream.
  ///
  /// [background] asks the platform to keep delivering updates with the screen
  /// locked. The rider still has to grant "Always"/background location for
  /// that to hold; if they do not, recording simply pauses with the screen off,
  /// which is why nothing in the app assumes it.
  Stream<Position> positionStream({bool background = true}) {
    if (Platform.isIOS || Platform.isMacOS) {
      return Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.fitness,
          distanceFilter: 3,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: background,
          allowBackgroundLocationUpdates: background,
        ),
      );
    }
    if (Platform.isAndroid) {
      return Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: background
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'Live Ride',
                  notificationText: 'Recording your ride',
                  notificationIcon: AndroidResource(
                    name: 'ic_launcher',
                    defType: 'mipmap',
                  ),
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        ),
      );
    }
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    );
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}
