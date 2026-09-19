import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/spotify_service.dart';

/// `bootstrap.sh` writes the iOS configuration that the Dart code depends on.
/// A mismatch between the two is invisible until a device refuses to come back
/// from Spotify or silently drops the Live Activity, so it is checked here.
void main() {
  final bootstrap = File('bootstrap.sh').readAsStringSync();

  test('the Spotify callback scheme is registered on iOS', () {
    final scheme = Uri.parse(SpotifyService.redirectUri).scheme;
    expect(scheme, SpotifyService.callbackScheme);
    expect(
      bootstrap.contains("'CFBundleURLSchemes': ['$scheme']"),
      isTrue,
      reason: 'bootstrap.sh does not register the $scheme:// callback',
    );
  });

  test('Live Activities are declared', () {
    expect(bootstrap.contains("p['NSSupportsLiveActivities'] = True"), isTrue);
  });

  test('background location and Bluetooth stay configured', () {
    expect(bootstrap.contains("'location'"), isTrue);
    expect(bootstrap.contains("'bluetooth-central'"), isTrue);
    expect(
      bootstrap.contains('NSLocationAlwaysAndWhenInUseUsageDescription'),
      isTrue,
    );
    expect(bootstrap.contains('NSBluetoothAlwaysUsageDescription'), isTrue);
  });

  test('the app does not claim a background mode it does not use', () {
    // Live Ride never plays audio itself; Spotify does, in its own app.
    expect(
      bootstrap.contains("'audio'"),
      isFalse,
      reason:
          'declaring the audio background mode without playing audio is '
          'an App Store rejection',
    );
  });

  test('the native sources are copied into the generated project', () {
    for (final name in [
      'LiveRideWidgetBundle.swift',
      'RideLiveActivity.swift',
      'RideActivityAttributes.swift',
      'LiveRideActivityBridge.swift',
    ]) {
      expect(
        bootstrap.contains(name),
        isTrue,
        reason: '$name is never copied into ios/',
      );
    }
  });

  test('the widget target script is run and can be skipped', () {
    expect(bootstrap.contains('add_live_activity_target.rb'), isTrue);
    expect(bootstrap.contains('--no-live-activity'), isTrue);
    expect(
      bootstrap.contains('gem install xcodeproj'),
      isTrue,
      reason: 'a missing gem should tell the rider how to fix it',
    );
  });

  test('the bridge is registered in AppDelegate whichever template ships', () {
    // Flutter has two AppDelegate shapes in the wild; both are patched.
    expect(bootstrap.contains('didInitializeImplicitFlutterEngine'), isTrue);
    expect(bootstrap.contains('didFinishLaunchingWithOptions'), isTrue);
    expect(bootstrap.contains('LiveRideActivityBridge.register'), isTrue);
  });
}
