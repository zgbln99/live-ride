import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import 'gpx_service.dart';
import 'heart_rate_service.dart';
import 'live_activity_service.dart';
import 'live_service.dart';
import 'location_service.dart';
import 'profile_service.dart';
import 'ride_recorder.dart';
import 'ride_storage_service.dart';
import 'route_library_service.dart';
import 'spotify_service.dart';
import 'weather_service.dart';

/// The single place every long-lived service is created.
///
/// It is built once in `main()` and handed down the tree, which is what keeps
/// an active ride alive across screen rebuilds and tab switches.
class AppServices {
  AppServices._({
    required this.api,
    required this.gpx,
    required this.routes,
    required this.rides,
    required this.profile,
    required this.weather,
    required this.heartRate,
    required this.live,
    required this.location,
    required this.spotify,
    required this.liveActivity,
    required this.recorder,
  });

  factory AppServices.create(ApiClient api) {
    final gpx = GpxService();
    final profile = ProfileService();
    final heartRate = HeartRateService();
    final live = LiveSessionController(api, heartRate, profile);
    final rides = RideStorageService(gpx);
    final weather = WeatherService();
    final location = LocationService();
    final liveActivity = LiveActivityService();
    return AppServices._(
      api: api,
      gpx: gpx,
      routes: RouteLibraryService(gpx),
      rides: rides,
      profile: profile,
      weather: weather,
      heartRate: heartRate,
      live: live,
      location: location,
      spotify: SpotifyService(),
      liveActivity: liveActivity,
      recorder: RideRecorder(
        location: location,
        storage: rides,
        heartRate: heartRate,
        live: live,
        weather: weather,
        profile: profile,
        liveActivity: liveActivity,
      ),
    );
  }

  final ApiClient api;
  final GpxService gpx;
  final RouteLibraryService routes;
  final RideStorageService rides;
  final ProfileService profile;
  final WeatherService weather;
  final HeartRateService heartRate;
  final LiveSessionController live;
  final LocationService location;
  final SpotifyService spotify;
  final LiveActivityService liveActivity;
  final RideRecorder recorder;

  Future<void> warmUp() async {
    await profile.load();
    // These reach the filesystem and the Bluetooth radio, so they run in the
    // background rather than holding up the first frame.
    unawaited(spotify.restore());
    unawaited(heartRate.restore());
  }

  Future<void> dispose() async {
    recorder.dispose();
    live.dispose();
    weather.dispose();
    profile.dispose();
    spotify.dispose();
    await heartRate.dispose();
  }

  static AppServices of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppServicesScope>();
    assert(scope != null, 'AppServicesScope is missing above this widget');
    return scope!.services;
  }
}

class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      oldWidget.services != services;
}
