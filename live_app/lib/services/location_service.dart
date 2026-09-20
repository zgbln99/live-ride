import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';

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
  /// Filtr odległości dla strumienia jazdy. Zero = „mów za każdym razem".
  ///
  /// Wystawiony jako stała, żeby test mógł sprawdzić, że nikt go po cichu
  /// nie podniesie: każda wartość powyżej zera wyłącza wykrywanie postoju
  /// i nie widać tego w żadnym istniejącym teście.
  static const int rideDistanceFilterMeters = 0;

  /// Docelowy odstęp między próbkami na Androidzie.
  static const Duration rideInterval = Duration(seconds: 1);

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

  /// Ostatnia znana pozycja jako punkt geograficzny.
  ///
  /// Kreator tras nie może czekać na świeży fix, żeby wycentrować mapę.
  Future<GeoPoint?> lastKnown() async {
    try {
      final known = await Geolocator.getLastKnownPosition();
      if (known != null) {
        return GeoPoint(lat: known.latitude, lon: known.longitude);
      }
    } catch (_) {}
    try {
      await ensurePermission();
      final position = await currentPosition();
      if (position == null) return null;
      return GeoPoint(lat: position.latitude, lon: position.longitude);
    } catch (_) {
      return null;
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

  /// Strumień pozycji dla trwającego przejazdu.
  ///
  /// [background] prosi system o dalsze aktualizacje przy zgaszonym ekranie.
  /// Zawodnik musi jeszcze przyznać lokalizację „zawsze"; bez tego nagrywanie
  /// po prostu zatrzymuje się z ekranem w kieszeni, i dlatego nic w aplikacji
  /// tego nie zakłada.
  ///
  /// `distanceFilter` jest ZEROWY i to nie jest przeoczenie. Filtr odległości
  /// znaczy „odezwij się, gdy przesuniesz się o tyle metrów", więc telefon
  /// leżący nieruchomo na światłach nie odzywa się w ogóle. Przy filtrze
  /// trzech metrów wykrywanie postoju nie dostawało ANI JEDNEJ próbki
  /// potwierdzającej, że rower stoi — a że brak danych nigdy nie zatrzymuje
  /// licznika (bo tak samo wygląda utrata zasięgu przy 25 km/h), auto-pauza
  /// nie włączała się nawet po półtorej godziny stania w miejscu.
  ///
  /// Zero kosztuje trochę baterii, bo odbiornik raportuje mniej więcej co
  /// sekundę także na postoju. To jest dokładnie ta cena, za którą kupujemy
  /// działające wykrywanie postoju — i płacimy ją wyłącznie w trakcie jazdy,
  /// bo poza nią nikt tego strumienia nie otwiera.
  Stream<Position> positionStream({bool background = true}) {
    if (Platform.isIOS || Platform.isMacOS) {
      return Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.fitness,
          distanceFilter: rideDistanceFilterMeters,
          // System potrafi sam wstrzymać aktualizacje, gdy uzna, że
          // użytkownik się nie rusza — i właśnie wtedy potrzebujemy ich
          // najbardziej, żeby stwierdzić postój.
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
          distanceFilter: rideDistanceFilterMeters,
          intervalDuration: rideInterval,
          // Bez tego Android potrafi rozciągnąć odstępy przy oszczędzaniu
          // energii i postój znów przestałby być widoczny.
          forceLocationManager: false,
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
        distanceFilter: rideDistanceFilterMeters,
      ),
    );
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}
