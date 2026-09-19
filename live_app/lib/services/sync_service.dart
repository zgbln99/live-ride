import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/database.dart';
import '../data/ride_dao.dart';
import '../data/route_dao.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import 'routing_service.dart';

/// Co dzieje się z synchronizacją.
enum SyncPhase { idle, running, offline, failed }

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
  }) : _api = api,
       _rides = rides,
       _routes = routes;

  /// Ile rekordów leci w jednym żądaniu. Serwer przyjmuje do pięćdziesięciu.
  static const int batchSize = 20;

  /// Po nieudanej próbie czekamy, zanim spróbujemy znowu — telefon bez
  /// zasięgu nie ma się czym męczyć co sekundę.
  static const Duration retryDelay = Duration(minutes: 5);

  final ApiClient _api;
  final RideDao _rides;
  final RouteDao _routes;

  SyncPhase _phase = SyncPhase.idle;
  DateTime? _lastSuccess;
  DateTime? _lastAttempt;
  String? _lastError;
  int _pendingRides = 0;
  int _pendingRoutes = 0;

  SyncPhase get phase => _phase;
  DateTime? get lastSuccess => _lastSuccess;
  String? get lastError => _lastError;
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
      _lastSuccess = DateTime.now();
      _lastError = null;
      _phase = SyncPhase.idle;
      await refreshPending();
      return true;
    } on DioException catch (e) {
      _lastError = e.message;
      _phase = _isOffline(e) ? SyncPhase.offline : SyncPhase.failed;
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = e.toString();
      _phase = SyncPhase.failed;
      notifyListeners();
      return false;
    }
  }

  bool get _shouldWait {
    final attempt = _lastAttempt;
    if (attempt == null) return false;
    if (_phase == SyncPhase.idle) return false;
    return DateTime.now().difference(attempt) < retryDelay;
  }

  static bool _isOffline(DioException error) => switch (error.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => true,
    _ => false,
  };

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

  /// Oznacza jako zsynchronizowane tylko to, co serwer potwierdził.
  ///
  /// Gdyby oznaczać wszystko, co wysłaliśmy, przejazd odrzucony przez
  /// walidację zniknąłby z kolejki i nigdy by nie doszedł.
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
    // Serwer nazywa to „link", aplikacja „unlisted" — jedno tłumaczenie
    // w jednym miejscu zamiast dwóch nazw w całym kodzie.
    'privacy': switch (route.privacy) {
      RoutePrivacy.public => 'public',
      RoutePrivacy.unlisted => 'link',
      RoutePrivacy.private => 'private',
    },
    'client_updated_at': route.updatedAt.toUtc().toIso8601String(),
  };
}
