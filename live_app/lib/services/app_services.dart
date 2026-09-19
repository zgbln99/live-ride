import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import '../data/database.dart';
import '../data/ride_dao.dart';
import '../data/bike_dao.dart';
import '../data/route_dao.dart';
import '../data/segment_dao.dart';
import '../data/settings_dao.dart';
import 'alert_controller.dart';
import 'garage_service.dart';
import 'health_service.dart';
import 'geocoding_service.dart';
import 'gpx_service.dart';
import 'heart_rate_service.dart';
import 'live_activity_service.dart';
import 'live_service.dart';
import 'location_service.dart';
import 'profile_service.dart';
import 'race_mode_controller.dart';
import 'ride_recorder.dart';
import 'ride_storage_service.dart';
import 'pace_partner.dart';
import 'safety_service.dart';
import 'offline_map_service.dart';
import 'segment_service.dart';
import 'sync_service.dart';
import 'route_library_service.dart';
import 'route_weather_service.dart';
import 'sensor_hub.dart';
import 'routing_service.dart';
import 'spotify_service.dart';
import 'strava_service.dart';
import 'weather_service.dart';

/// The single place every long-lived service is created.
///
/// It is built once in `main()` and handed down the tree, which is what keeps
/// an active ride alive across screen rebuilds and tab switches.
class AppServices {
  AppServices._({
    required this.database,
    required this.settings,
    required this.syncQueue,
    required this.api,
    required this.gpx,
    required this.routes,
    required this.rides,
    required this.garage,
    required this.segments,
    required this.strava,
    required this.health,
    required this.sync,
    required this.offlineMaps,
    required this.pace,
    required this.profile,
    required this.weather,
    required this.routeWeather,
    required this.heartRate,
    required this.sensors,
    required this.alerts,
    required this.race,
    required this.safety,
    required this.live,
    required this.location,
    required this.routing,
    required this.geocoding,
    required this.spotify,
    required this.liveActivity,
    required this.recorder,
  });

  factory AppServices.create(ApiClient api, {LiveRideDatabase? database}) {
    final db = database ?? LiveRideDatabase();
    final gpx = GpxService();
    final profile = ProfileService();
    final heartRate = HeartRateService();
    final settings = SettingsDao(db);
    final sensors = SensorHub(heartRate: heartRate, settings: settings);
    final alerts = AlertController(settings: settings);
    final garage = GarageService(BikeDao(db));
    final race = RaceModeController(settings: settings);
    final safety = SafetyService(settings: settings);
    final segments = SegmentService(SegmentDao(db));
    final strava = StravaService(settings: settings);
    final health = HealthService(settings: settings, rides: RideDao(db));
    final sync = SyncService(
      api: api,
      rides: RideDao(db),
      routes: RouteDao(db),
    );
    final offlineMaps = OfflineMapService();
    final pace = PacePartnerService();
    final live = LiveSessionController(api, heartRate, profile);
    final rides = RideStorageService(gpx, RideDao(db));
    final weather = WeatherService();
    final location = LocationService();
    final liveActivity = LiveActivityService();
    return AppServices._(
      database: db,
      settings: settings,
      syncQueue: SyncQueueDao(db),
      api: api,
      gpx: gpx,
      routes: RouteLibraryService(gpx, RouteDao(db)),
      rides: rides,
      garage: garage,
      segments: segments,
      strava: strava,
      health: health,
      sync: sync,
      offlineMaps: offlineMaps,
      pace: pace,
      profile: profile,
      weather: weather,
      routeWeather: RouteWeatherService(),
      heartRate: heartRate,
      sensors: sensors,
      alerts: alerts,
      race: race,
      safety: safety,
      live: live,
      location: location,
      routing: RoutingService(api),
      geocoding: GeocodingService(api),
      spotify: SpotifyService(),
      liveActivity: liveActivity,
      recorder: RideRecorder(
        location: location,
        storage: rides,
        heartRate: heartRate,
        sensors: sensors,
        alerts: alerts,
        garage: garage,
        health: health,
        segments: segments,
        pace: pace,
        sync: sync,
        race: race,
        safety: safety,
        live: live,
        weather: weather,
        profile: profile,
        liveActivity: liveActivity,
      ),
    );
  }

  final LiveRideDatabase database;
  final SettingsDao settings;
  final SyncQueueDao syncQueue;
  final ApiClient api;
  final GpxService gpx;
  final RouteLibraryService routes;
  final RideStorageService rides;

  /// Garaż: rowery, liczniki i serwis.
  final GarageService garage;

  /// Segmenty i rekordy na nich.
  final SegmentService segments;

  /// Wysyłka przejazdów do Stravy.
  final StravaService strava;

  /// Apple Health / Health Connect.
  final HealthService health;

  /// Wysyłka lokalnych przejazdów i tras na serwer.
  final SyncService sync;

  /// Mapy offline wokół tras.
  final OfflineMapService offlineMaps;

  /// Wirtualny rywal.
  final PacePartnerService pace;
  final ProfileService profile;
  final WeatherService weather;

  /// Prognoza wzdłuż trasy — używana przez briefing, nie przez komputer jazdy.
  final RouteWeatherService routeWeather;
  final HeartRateService heartRate;

  /// Sensory rowerowe: kadencja, prędkość, moc, trenażer.
  final SensorHub sensors;

  /// Powiadomienia w czasie jazdy.
  final AlertController alerts;

  /// Tryb wyścigu i blokada ekranu.
  final RaceModeController race;

  /// Wykrywanie upadku, SOS i kontakty alarmowe.
  final SafetyService safety;
  final LiveSessionController live;
  final LocationService location;
  final RoutingService routing;
  final GeocodingService geocoding;
  final SpotifyService spotify;
  final LiveActivityService liveActivity;
  final RideRecorder recorder;

  Future<void> warmUp() async {
    // Migracja starych plików musi się skończyć, zanim ktokolwiek zapyta
    // o listę przejazdów, żeby historia nie mrugnęła pustką.
    await database.open();
    await rides.migrateLegacyFiles();
    await routes.migrateLegacyFiles();
    await profile.load();
    await garage.load();
    await segments.load();
    // These reach the filesystem and the Bluetooth radio, so they run in the
    // background rather than holding up the first frame.
    unawaited(spotify.restore());
    unawaited(heartRate.restore());
    unawaited(sensors.restore());
    unawaited(alerts.restore());
    unawaited(race.restore());
    unawaited(safety.restore());
    unawaited(strava.restore());
    unawaited(health.restore());
    unawaited(sync.refreshPending().then((_) => sync.flush()));
    unawaited(offlineMaps.refresh());
  }

  Future<void> dispose() async {
    recorder.dispose();
    live.dispose();
    weather.dispose();
    profile.dispose();
    spotify.dispose();
    alerts.dispose();
    race.dispose();
    safety.dispose();
    garage.dispose();
    segments.dispose();
    strava.dispose();
    health.dispose();
    sync.dispose();
    offlineMaps.dispose();
    await sensors.dispose();
    await heartRate.dispose();
    await database.close();
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
