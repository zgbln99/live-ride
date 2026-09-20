import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_waypoint.dart';
import 'package:live_ride/services/geocoding_service.dart';
import 'package:live_ride/services/route_generator.dart';
import 'package:live_ride/services/route_planner.dart';
import 'package:live_ride/services/routing_service.dart';

/// Planer od strony zawodnika: wpisuję zdanie, dostaję trasy.

class _FakeGeocoding extends GeocodingService {
  _FakeGeocoding({this.known = const {}, this.delay = Duration.zero})
    : super(ApiClient());

  /// Nazwy, które „istnieją" — razem z wariantami odmiany.
  final Map<String, GeoPoint> known;
  final Duration delay;
  final List<String> queries = [];

  @override
  Future<List<Place>> search(String query, {GeoPoint? near}) async {
    queries.add(query);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final point = known[query];
    return point == null ? const [] : [Place(name: query, point: point)];
  }
}

class _FakeRouting extends RoutingService {
  _FakeRouting({this.fail = false}) : super(ApiClient());

  final bool fail;
  List<RouteWaypoint>? lastWaypoints;

  @override
  Future<RoutedPath> route({
    required List<RouteWaypoint> waypoints,
    required RoutePreferences preferences,
    String language = 'pl-PL',
    CancelToken? cancelToken,
  }) async {
    lastWaypoints = waypoints;
    if (fail) throw const RoutingException('Brak przejazdu');

    var distance = 0.0;
    for (var i = 1; i < waypoints.length; i++) {
      distance += haversineMeters(waypoints[i - 1].point, waypoints[i].point);
    }
    return RoutedPath(
      points: [for (final w in waypoints) w.point],
      maneuvers: const [],
      distanceMeters: distance * 1.25,
      duration: Duration(seconds: (distance / 6).round()),
    );
  }
}

const _home = GeoPoint(lat: 52.52, lon: 13.40);
const _potsdam = GeoPoint(lat: 52.40, lon: 13.06);
const _wannsee = GeoPoint(lat: 52.42, lon: 13.17);

RoutePlannerController _planner({
  _FakeGeocoding? geocoding,
  _FakeRouting? routing,
}) {
  final router = routing ?? _FakeRouting();
  return RoutePlannerController(
    geocoding: geocoding ?? _FakeGeocoding(known: {'Potsdam': _potsdam}),
    routing: router,
    generator: RouteGenerator(router),
  );
}

Future<void> _plan(RoutePlannerController planner, String text, {GeoPoint? start = _home}) =>
    planner.plan(
      text: text,
      start: start,
      preferences: const RoutePreferences(),
      movingAverageKmh: 26,
    );

void main() {
  test('„do Poczdamu" geokoduje cel i liczy trasę z bieżącej pozycji', () async {
    // Dopełniacza nie zna żaden geokoder — planer próbuje wariantów.
    final geocoding = _FakeGeocoding(known: {'Poczdam': _potsdam});
    final routing = _FakeRouting();
    final planner = _planner(geocoding: geocoding, routing: routing);

    await _plan(planner, 'do Poczdamu');

    expect(planner.state.hasResults, isTrue);
    expect(geocoding.queries, contains('Poczdamu'));
    expect(geocoding.queries, contains('Poczdam'));
    final waypoints = routing.lastWaypoints!;
    expect(waypoints.first.point, _home);
    expect(waypoints.last.point, _potsdam);
  });

  test('„do Poczdamu przez Wannsee" daje trzy logiczne punkty', () async {
    final planner = _planner(
      geocoding: _FakeGeocoding(
        known: {'Poczdam': _potsdam, 'Wannsee': _wannsee},
      ),
      routing: _FakeRouting(),
    );
    final routing = _FakeRouting();
    final withRouting = RoutePlannerController(
      geocoding: _FakeGeocoding(
        known: {'Poczdam': _potsdam, 'Wannsee': _wannsee},
      ),
      routing: routing,
      generator: RouteGenerator(routing),
    );
    await _plan(withRouting, 'do Poczdamu przez Wannsee');
    planner.dispose();

    final waypoints = routing.lastWaypoints!;
    expect(waypoints.length, 3);
    expect(waypoints[1].point, _wannsee);
    expect(waypoints[2].point, _potsdam);
  });

  test('„do jeziora i z powrotem" zamyka trasę na starcie', () async {
    final routing = _FakeRouting();
    final planner = RoutePlannerController(
      geocoding: _FakeGeocoding(known: {'jeziora': _wannsee}),
      routing: routing,
      generator: RouteGenerator(routing),
    );
    await _plan(planner, 'do jeziora i z powrotem');

    final waypoints = routing.lastWaypoints!;
    expect(waypoints.length, 3);
    expect(waypoints.last.point, _home);
  });

  test('„50 km pętla" idzie przez generator, nie przez geokoder', () async {
    final geocoding = _FakeGeocoding();
    final routing = _FakeRouting();
    final planner = RoutePlannerController(
      geocoding: geocoding,
      routing: routing,
      generator: RouteGenerator(routing),
    );

    await _plan(planner, '50 km pętla');

    expect(geocoding.queries, isEmpty);
    expect(planner.state.hasResults, isTrue);
    for (final route in planner.state.routes) {
      final error = (route.distanceMeters - 50000).abs() / 50000;
      expect(error, lessThanOrEqualTo(routeDistanceMaxTolerance));
    }
  });

  test('„2 godziny" zamienia się w dystans z tempa zawodnika', () async {
    final routing = _FakeRouting();
    final planner = RoutePlannerController(
      geocoding: _FakeGeocoding(),
      routing: routing,
      generator: RouteGenerator(routing),
    );

    await planner.plan(
      text: 'około 2 godziny',
      start: _home,
      preferences: const RoutePreferences(),
      movingAverageKmh: 26,
    );

    expect(planner.state.hasResults, isTrue);
    // Dwie godziny przy 26 km/h to około 52 km.
    final best = planner.state.routes.first.distanceMeters;
    expect(best, inInclusiveRange(46000, 58000));
  });

  test('nieznane miejsce to komunikat, a nie zmyślona trasa', () async {
    final planner = _planner(geocoding: _FakeGeocoding());
    await _plan(planner, 'do Atlantydy');

    expect(planner.state.hasResults, isFalse);
    expect(planner.state.failure, PlannerFailure.unknownPlace);
    // Wpisany tekst zostaje, żeby dało się spróbować ponownie.
    expect(planner.state.intent!.destination, 'Atlantydy');
  });

  test('router bez przejazdu też nie produkuje fikcji', () async {
    final routing = _FakeRouting(fail: true);
    final planner = RoutePlannerController(
      geocoding: _FakeGeocoding(known: {'Potsdam': _potsdam}),
      routing: routing,
      generator: RouteGenerator(routing),
    );
    await _plan(planner, 'Potsdam');

    expect(planner.state.hasResults, isFalse);
    expect(planner.state.failure, PlannerFailure.noRoute);
  });

  test('bez pozycji startowej mówimy wprost, czego brakuje', () async {
    final planner = _planner();
    await _plan(planner, 'Potsdam', start: null);
    expect(planner.state.failure, PlannerFailure.noStart);
  });

  test('stary wynik nigdy nie nadpisuje nowszego', () async {
    // Wolniejsze, starsze zapytanie potrafi dojechać PO nowszym i podmienić
    // propozycje pod palcem. Zawodnik nie ma wtedy jak się zorientować, że
    // patrzy na odpowiedź na pytanie, którego już nie zadaje.
    final slowGeocoding = _FakeGeocoding(
      known: {'Potsdam': _potsdam},
      delay: const Duration(milliseconds: 60),
    );
    final routing = _FakeRouting();
    final planner = RoutePlannerController(
      geocoding: slowGeocoding,
      routing: routing,
      generator: RouteGenerator(routing),
    );

    final stale = _plan(planner, 'Potsdam');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final fresh = _plan(planner, '30 km pętla');
    await Future.wait([stale, fresh]);

    expect(planner.state.intent!.distanceMeters, 30000);
    expect(planner.state.intent!.destination, isNull);
    expect(planner.state.routes, isNotEmpty);
  });
}
