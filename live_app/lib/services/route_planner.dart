import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';
import '../models/weather.dart';
import 'geocoding_service.dart';
import 'route_generator.dart';
import 'route_intent.dart';
import 'routing_service.dart';

/// Dlaczego nie udało się wyznaczyć trasy.
enum PlannerFailure {
  /// Nie znamy pozycji, z której mielibyśmy wyruszyć.
  noStart,

  /// Geokoder nie zna takiego miejsca.
  unknownPlace,

  /// Router nie znalazł drogi dla roweru.
  noRoute,

  /// Sieć albo serwer.
  offline,
}

/// Stan planowania.
class PlannerState {
  const PlannerState({
    this.busy = false,
    this.routes = const [],
    this.failure,
    this.intent,
  });

  final bool busy;
  final List<GeneratedRoute> routes;
  final PlannerFailure? failure;
  final RouteIntent? intent;

  bool get hasResults => routes.isNotEmpty;
}

/// „Po prostu powiedz gdzie".
///
/// Zamienia jedno zdanie w gotowe propozycje tras. Trzy drogi, jedno wyjście:
/// nazwa miejsca idzie przez geokoder, sam dystans przez generator pętli,
/// a czas najpierw przez tempo zawodnika i potem tak samo jak dystans.
///
/// Wynik jest ZWYKŁĄ trasą — tą samą klasą, którą tworzy kreator ręczny.
/// Drugi format „trasy z automatu" oznaczałby, że połowa funkcji aplikacji
/// (nawigacja, LIVE, GPX, synchronizacja) działa tylko dla jednego z nich.
class RoutePlannerController extends ChangeNotifier {
  RoutePlannerController({
    required GeocodingService geocoding,
    required RoutingService routing,
    required RouteGenerator generator,
  }) : _geocoding = geocoding,
       _routing = routing,
       _generator = generator;

  final GeocodingService _geocoding;
  final RoutingService _routing;
  final RouteGenerator _generator;

  PlannerState _state = const PlannerState();
  PlannerState get state => _state;

  CancelToken? _inFlight;
  int _requestId = 0;
  bool _disposed = false;

  /// Planuje trasę z tego, co zawodnik wpisał.
  ///
  /// Każde wywołanie unieważnia poprzednie. Bez tego wynik wolniejszego,
  /// starszego zapytania potrafi dojechać PO nowszym i podmienić propozycje
  /// pod palcem — a zawodnik nie ma jak się zorientować, że patrzy na
  /// odpowiedź na pytanie, którego już nie zadaje.
  Future<void> plan({
    required String text,
    required GeoPoint? start,
    required RoutePreferences preferences,
    required double movingAverageKmh,
    WeatherSnapshot? weather,
  }) async {
    final intent = parseRouteIntent(text);
    final request = ++_requestId;
    _inFlight?.cancel('newer request');
    final cancelToken = CancelToken();
    _inFlight = cancelToken;

    _emit(PlannerState(busy: true, intent: intent));

    if (!intent.isUsable) {
      _finish(request, const PlannerState(failure: PlannerFailure.unknownPlace));
      return;
    }
    if (start == null || !start.isValid) {
      _finish(request, PlannerState(failure: PlannerFailure.noStart, intent: intent));
      return;
    }

    try {
      final applied = intent.applyTo(preferences);
      final target = _targetMeters(intent, movingAverageKmh);

      // Cel podróży wygrywa nad dystansem: „do Poczdamu, 50 km" to prośba
      // o Poczdam, a nie o pięćdziesiąt kilometrów w dowolną stronę.
      final routes = intent.destination != null
          ? await _toDestination(intent, start, applied, cancelToken)
          : await _generator.loops(
              start: start,
              targetMeters: target!,
              preferences: applied,
              intent: intent,
              weather: weather,
              cancelToken: cancelToken,
            );

      if (routes.isEmpty) {
        _finish(
          request,
          PlannerState(failure: PlannerFailure.noRoute, intent: intent),
        );
        return;
      }
      _finish(request, PlannerState(routes: routes, intent: intent));
    } on _PlaceNotFound {
      _finish(
        request,
        PlannerState(failure: PlannerFailure.unknownPlace, intent: intent),
      );
    } on RoutingException {
      _finish(request, PlannerState(failure: PlannerFailure.noRoute, intent: intent));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _finish(request, PlannerState(failure: PlannerFailure.offline, intent: intent));
    }
  }

  double? _targetMeters(RouteIntent intent, double movingAverageKmh) {
    if (intent.distanceMeters != null) return intent.distanceMeters;
    final duration = intent.duration;
    if (duration == null) return null;
    return distanceForDuration(
      duration: duration,
      movingAverageKmh: movingAverageKmh,
    );
  }

  Future<List<GeneratedRoute>> _toDestination(
    RouteIntent intent,
    GeoPoint start,
    RoutePreferences preferences,
    CancelToken cancelToken,
  ) async {
    final destination = await _resolve(intent.destination!, start);
    final via = <GeoPoint>[];
    for (final name in intent.via) {
      via.add(await _resolve(name, start));
    }

    final waypoints = <RouteWaypoint>[
      RouteWaypoint(point: start),
      for (final point in via) RouteWaypoint(point: point),
      RouteWaypoint(point: destination),
      // „i z powrotem" zamyka trasę na starcie. „Pętla" też, ale tam
      // generator dobiera własne punkty.
      if (intent.shape == RouteShape.outAndBack) RouteWaypoint(point: start),
    ];

    final path = await _routing.route(
      waypoints: waypoints,
      preferences: preferences,
      cancelToken: cancelToken,
    );
    if (path.isEmpty) return const [];
    return [
      GeneratedRoute(
        label: intent.destination!,
        path: path,
        waypoints: waypoints,
        preferences: preferences,
        reasons: const [],
      ),
    ];
  }

  /// Zamienia nazwę na punkt, próbując wariantów odmiany.
  ///
  /// „do Poczdamu" nie jest nazwą, którą zna mapa. Zamiast udawać odmianę
  /// gramatyczną, pytamy o kilka wariantów i bierzemy pierwszy, który
  /// istnieje naprawdę.
  Future<GeoPoint> _resolve(String name, GeoPoint near) async {
    for (final candidate in RouteIntent.candidatesFor(name)) {
      final places = await _geocoding.search(candidate, near: near);
      if (places.isNotEmpty) return places.first.point;
    }
    throw const _PlaceNotFound();
  }

  void _emit(PlannerState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  /// Zapisuje wynik tylko wtedy, gdy nadal jest najnowszy.
  void _finish(int request, PlannerState state) {
    if (request != _requestId) return;
    _emit(state);
  }

  void clear() => _emit(const PlannerState());

  @override
  void dispose() {
    _disposed = true;
    _inFlight?.cancel('disposed');
    super.dispose();
  }
}

class _PlaceNotFound implements Exception {
  const _PlaceNotFound();
}
