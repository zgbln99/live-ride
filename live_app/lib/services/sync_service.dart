import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/database.dart';
import '../data/ride_dao.dart';
import '../data/route_dao.dart';
import '../data/segment_dao.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import '../core/geo.dart';
import '../models/segment.dart';
import 'routing_service.dart';

/// Co dzieje się z synchronizacją.
enum SyncPhase { idle, running, offline, failed }

/// Dlaczego synchronizacja się nie udała.
///
/// To jest jedyne, co wychodzi z warstwy sieciowej do interfejsu. Surowy
/// `DioException` z opisem `validateStatus`, adresem dokumentacji HTTP i
/// stosem wywołań nie jest komunikatem dla zawodnika — jest komunikatem dla
/// programisty i zostaje w logu.
enum SyncFailure {
  /// Brak zasięgu, wyłączona transmisja danych, tunel.
  offline,

  /// Serwer odpowiedział błędem albo w ogóle nie odpowiedział na czas.
  server,

  /// Sesja wygasła — bez ponownego zalogowania nic nie pójdzie.
  session,

  /// Serwer nie zna tego adresu. Prawie zawsze znaczy, że wdrożona wersja
  /// backendu jest starsza niż aplikacja.
  outdatedServer,
}

/// Wysyła lokalne przejazdy i trasy na serwer.
///
/// Telefon jest źródłem prawdy. Serwer trzyma kopię, więc świeżo
/// zainstalowana aplikacja odzyska historię, ale nic w aplikacji nie czeka
/// na serwer: przejazd jest zapisany i kompletny w chwili zakończenia, a
/// wysyłka może się udać kwadrans później albo następnego dnia.
class SyncService extends ChangeNotifier {
  SyncService({
    required ApiClient api,
    required RideDao rides,
    required RouteDao routes,
    SegmentDao? segments,
  }) : _api = api,
       _rides = rides,
       _routes = routes,
       _segments = segments;

  /// Ile rekordów leci w jednym żądaniu. Serwer przyjmuje do pięćdziesięciu.
  static const int batchSize = 20;

  /// Po nieudanej próbie czekamy, zanim spróbujemy znowu — telefon bez
  /// zasięgu nie ma się czym męczyć co sekundę.
  static const Duration retryDelay = Duration(minutes: 5);

  final ApiClient _api;
  final RideDao _rides;
  final RouteDao _routes;
  final SegmentDao? _segments;

  SyncPhase _phase = SyncPhase.idle;
  DateTime? _lastSuccess;
  DateTime? _lastAttempt;
  SyncFailure? _failure;
  String? _technicalError;
  int _pendingRides = 0;
  int _pendingRoutes = 0;

  SyncPhase get phase => _phase;
  DateTime? get lastSuccess => _lastSuccess;

  /// Dlaczego ostatnia próba się nie udała — albo null, gdy się udała.
  SyncFailure? get failure => _failure;

  /// Surowy opis błędu. WYŁĄCZNIE do logu i ekranu diagnostycznego; nigdy do
  /// zwykłego interfejsu.
  @visibleForTesting
  String? get technicalError => _technicalError;

  int get pendingCount => _pendingRides + _pendingRoutes;
  bool get isRunning => _phase == SyncPhase.running;

  Future<void> refreshPending() async {
    _pendingRides = (await _rides.pendingSync()).length;
    _pendingRoutes = (await _routes.pendingSync()).length;
    notifyListeners();
  }

  /// Wysyła wszystko, co czeka.
  ///
  /// [force] pomija odczekanie po nieudanej próbie — używa go przycisk
  /// „synchronizuj teraz", bo zawodnik, który go nacisnął, wie lepiej od
  /// zegara, czy ma zasięg.
  Future<bool> flush({bool force = false}) async {
    if (isRunning) return false;
    if (!force && _shouldWait) return false;

    _phase = SyncPhase.running;
    _lastAttempt = DateTime.now();
    notifyListeners();

    try {
      await _pushRides();
      await _pushRoutes();
      await _pushSegments();
      _lastSuccess = DateTime.now();
      _failure = null;
      _technicalError = null;
      _phase = SyncPhase.idle;
      await refreshPending();
      return true;
    } on DioException catch (e, stack) {
      _fail(classify(e), e, stack);
      return false;
    } catch (e, stack) {
      _fail(SyncFailure.server, e, stack);
      return false;
    }
  }

  void _fail(SyncFailure failure, Object error, StackTrace stack) {
    _failure = failure;
    _technicalError = error.toString();
    _phase = failure == SyncFailure.offline
        ? SyncPhase.offline
        : SyncPhase.failed;
    // Szczegóły techniczne trafiają do logu deweloperskiego i nigdzie indziej.
    debugPrint('Live Ride sync failed ($failure): $error\n$stack');
    // Liczba oczekujących rekordów nie zmienia się przy błędzie: kolejka
    // zostaje nietknięta do POTWIERDZONEJ wysyłki.
    notifyListeners();
  }

  /// Zamienia wyjątek sieciowy na powód zrozumiały dla interfejsu.
  @visibleForTesting
  static SyncFailure classify(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return SyncFailure.offline;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) return SyncFailure.session;
        // 404 na własnym endpointcie synchronizacji nie znaczy „brak
        // przejazdu", tylko „serwer nie ma tej trasy HTTP" — czyli działa
        // starsza wersja backendu, niż zakłada aplikacja.
        if (status == 404) return SyncFailure.outdatedServer;
        return SyncFailure.server;
      default:
        return SyncFailure.server;
    }
  }

  bool get _shouldWait {
    final attempt = _lastAttempt;
    if (attempt == null) return false;
    if (_phase == SyncPhase.idle) return false;
    return DateTime.now().difference(attempt) < retryDelay;
  }

  Future<void> _pushRides() async {
    final pending = await _rides.pendingSync();
    if (pending.isEmpty) return;

    for (var offset = 0; offset < pending.length; offset += batchSize) {
      final slice = pending.skip(offset).take(batchSize).toList();
      final payload = <Map<String, dynamic>>[];
      for (final summary in slice) {
        final full = await _rides.findById(summary.id) ?? summary;
        payload.add(_rideToJson(full));
      }

      final response = await _api.dio.post<Map<String, dynamic>>(
        '/live-rides/sync/rides',
        data: {'rides': payload},
      );
      await _markSynced(
        response.data,
        (id) => _rides.updateSyncStatus(id, SyncStatus.synced),
      );
    }
  }

  Future<void> _pushRoutes() async {
    final pending = await _routes.pendingSync();
    if (pending.isEmpty) return;

    for (var offset = 0; offset < pending.length; offset += batchSize) {
      final slice = pending.skip(offset).take(batchSize).toList();
      final payload = <Map<String, dynamic>>[];
      for (final summary in slice) {
        final full = await _routes.load(summary.id);
        if (full != null) payload.add(_routeToJson(full));
      }
      if (payload.isEmpty) continue;

      final response = await _api.dio.post<Map<String, dynamic>>(
        '/live-rides/sync/routes',
        data: {'routes': payload},
      );
      await _markSynced(
        response.data,
        (id) => _routes.updateSyncStatus(id, SyncStatus.synced),
      );
    }
  }

  /// Wysyła segmenty razem z próbami.
  ///
  /// Próba bez swojego segmentu byłaby czasem, którego nie ma z czym
  /// porównać, a na telefonie zawsze powstają razem.
  Future<void> _pushSegments() async {
    final dao = _segments;
    if (dao == null) return;
    final all = await dao.listSegments();
    if (all.isEmpty) return;

    for (var offset = 0; offset < all.length; offset += batchSize) {
      final slice = all.skip(offset).take(batchSize).toList();
      final payload = <Map<String, dynamic>>[];
      for (final segment in slice) {
        payload.add({
          ...segmentToJson(segment),
          'attempts': [
            for (final attempt in await dao.attempts(segment.id))
              attemptToJson(attempt),
          ],
        });
      }
      await _api.dio.post<Map<String, dynamic>>(
        '/live-rides/sync/segments',
        data: {'segments': payload},
      );
    }
  }

  @visibleForTesting
  static Map<String, dynamic> segmentToJson(Segment segment) => {
    'client_id': segment.id,
    'name': segment.name,
    'distance_m': segment.distanceMeters,
    'ascent_m': segment.ascentMeters,
    'avg_gradient': segment.averageGradientPercent,
    'polyline': encodeValhallaPolyline(segment.points),
    'privacy': 'private',
  };

  @visibleForTesting
  static Map<String, dynamic> attemptToJson(SegmentAttempt attempt) => {
    'client_id': attempt.id,
    'started_at': attempt.startedAt.toUtc().toIso8601String(),
    'duration_seconds': attempt.duration.inSeconds,
    'avg_speed_kmh': attempt.averageSpeedKmh,
    'avg_heart_rate': attempt.averageHeartRate ?? 0,
    'avg_power': attempt.averagePower ?? 0,
  };

  /// Oznacza jako zsynchronizowane tylko to, co serwer potwierdził.
  ///
  /// Gdyby oznaczać wszystko, co wysłaliśmy, przejazd odrzucony przez
  /// walidację zniknąłby z kolejki i nigdy by nie doszedł. Dlatego przy
  /// częściowym powodzeniu — osiemnaście z dwudziestu — dwa pozostałe
  /// zostają w kolejce i pojadą przy następnej próbie.
  Future<void> _markSynced(
    Map<String, dynamic>? response,
    Future<void> Function(String clientId) mark,
  ) async {
    final synced = response?['synced'];
    if (synced is! List) return;
    for (final entry in synced) {
      if (entry is! Map) continue;
      final clientId = entry['client_id'];
      if (clientId is String && clientId.isNotEmpty) await mark(clientId);
    }
  }

  @visibleForTesting
  static Map<String, dynamic> rideToJson(RecordedRide ride) =>
      _rideToJson(ride);

  static Map<String, dynamic> _rideToJson(RecordedRide ride) => {
    'client_id': ride.id,
    'name': ride.name,
    'started_at': ride.startedAt.toUtc().toIso8601String(),
    'ended_at': ride.endedAt.toUtc().toIso8601String(),
    'elapsed_seconds': ride.elapsedSeconds,
    'moving_seconds': ride.movingSeconds,
    'distance_m': ride.distanceMeters,
    'ascent_m': ride.elevationGainMeters,
    'descent_m': ride.elevationLossMeters,
    'max_speed_kmh': ride.maxSpeedKmh,
    'avg_heart_rate': ride.averageHeartRate ?? 0,
    'max_heart_rate': ride.maxHeartRate ?? 0,
    'avg_power': ride.averagePower ?? 0,
    'normalized_power': ride.normalizedPower ?? 0,
    'avg_cadence': ride.averageCadence ?? 0,
    'calories': ride.calories ?? 0,
    'track_polyline': encodeValhallaPolyline(ride.track),
    'point_count': ride.points.length,
    'privacy': 'private',
    'client_updated_at': ride.endedAt.toUtc().toIso8601String(),
  };

  @visibleForTesting
  static Map<String, dynamic> routeToJson(RideRoute route) =>
      _routeToJson(route);

  static Map<String, dynamic> _routeToJson(RideRoute route) => {
    'client_id': route.id,
    'name': route.name,
    'description': route.description,
    'tags': route.tags,
    'distance_m': route.distanceMeters,
    'ascent_m': route.ascentMeters,
    'descent_m': route.descentMeters,
    'polyline': encodeValhallaPolyline(route.points),
    'waypoints': [for (final waypoint in route.waypoints) waypoint.toJson()],
    'preferences': route.preferences.toJson(),
    // Profil i podjazdy liczy telefon. Bez nich publiczna strona trasy nie ma
    // czego narysować, a serwer nie ma skąd wziąć wysokości.
    'elevation_profile': elevationProfileJson(route),
    'climbs': climbsJson(route),
    // Serwer nazywa to „link", aplikacja „unlisted" — jedno tłumaczenie
    // w jednym miejscu zamiast dwóch nazw w całym kodzie.
    'privacy': switch (route.privacy) {
      RoutePrivacy.public => 'public',
      RoutePrivacy.unlisted => 'link',
      RoutePrivacy.private => 'private',
    },
    'client_updated_at': route.updatedAt.toUtc().toIso8601String(),
  };

  /// Ile próbek profilu wysokości wysyłamy.
  ///
  /// Wykres na stronie ma szerokość paruset pikseli — tysiąc punktów na nim
  /// nie da się odróżnić od dwustu, a rośnie o nie każde żądanie.
  static const int profileSamples = 240;

  /// Profil wysokości jako pary [dystans, wysokość].
  ///
  /// Zwraca pustą listę, gdy trasa nie ma wysokości: pusty profil znaczy
  /// „nie wiem", a wykres z samych zer wyglądałby jak idealnie płaska trasa.
  @visibleForTesting
  static List<Map<String, num>> elevationProfileJson(RideRoute route) {
    final points = route.points;
    if (points.length < 2) return const [];
    if (!points.any((point) => point.elevation != null)) return const [];

    final cumulative = cumulativeDistances(points);
    final step = points.length <= profileSamples
        ? 1
        : (points.length / profileSamples).ceil();

    final samples = <Map<String, num>>[];
    for (var i = 0; i < points.length; i += step) {
      final elevation = points[i].elevation;
      if (elevation == null) continue;
      samples.add({
        'd': cumulative[i].round(),
        'e': double.parse(elevation.toStringAsFixed(1)),
      });
    }
    // Ostatni punkt zawsze zostaje: bez niego profil kończyłby się przed metą.
    final lastElevation = points.last.elevation;
    if (lastElevation != null &&
        (samples.isEmpty || samples.last['d'] != cumulative.last.round())) {
      samples.add({
        'd': cumulative.last.round(),
        'e': double.parse(lastElevation.toStringAsFixed(1)),
      });
    }
    return samples.length < 2 ? const [] : samples;
  }

  /// Wykryte podjazdy trasy w formacie publicznej strony.
  @visibleForTesting
  static List<Map<String, Object>> climbsJson(RideRoute route) {
    final analysis = route.analysis;
    return [
      for (final climb in analysis.climbs)
        {
          'start_m': climb.startDistanceMeters.round(),
          'length_m': climb.lengthMeters.round(),
          'gain_m': climb.gainMeters.round(),
          'avg_gradient': double.parse(
            climb.averageGradientPercent.toStringAsFixed(1),
          ),
          'category': climb.category.shortLabel,
        },
    ];
  }
}
