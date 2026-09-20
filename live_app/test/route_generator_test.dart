import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_waypoint.dart';
import 'package:live_ride/models/weather.dart';
import 'package:live_ride/services/route_generator.dart';
import 'package:live_ride/services/route_intent.dart';
import 'package:live_ride/services/routing_service.dart';

/// Generator pętli sprawdzany na routerze, który zachowuje się jak prawdziwy.
///
/// Sedno problemu nie jest w geometrii, tylko w tym, że drogi nie biegną
/// prosto: trójkąt o obwodzie pięćdziesięciu kilometrów w linii prostej
/// wychodzi w terenie na sześćdziesiąt kilka. Atrapa udaje dokładnie to —
/// mnoży obwód przez współczynnik krętości — więc generator musi naprawdę
/// policzyć, zmierzyć i poprawić, a nie trafić przypadkiem.
class _WindingRouter extends RoutingService {
  _WindingRouter({
    this.windiness = 1.27,
    this.failBearings = const {},
    this.elevationPerBearing = const {},
  }) : super(ApiClient());

  /// O ile dłuższa jest droga od linii prostej.
  final double windiness;

  /// Kierunki, w których „nie ma przejazdu".
  final Set<int> failBearings;

  /// Przewyższenie dokładane na kilometr, zależnie od kierunku wyjazdu.
  final Map<int, double> elevationPerBearing;

  int calls = 0;
  CancelToken? lastCancelToken;

  @override
  Future<RoutedPath> route({
    required List<RouteWaypoint> waypoints,
    required RoutePreferences preferences,
    String language = 'pl-PL',
    CancelToken? cancelToken,
  }) async {
    calls++;
    lastCancelToken = cancelToken;

    final start = waypoints.first.point;
    final bearing = waypoints.length > 1
        ? bearingDegrees(start, waypoints[1].point).round()
        : 0;
    final rounded = ((bearing + 22) ~/ 45 * 45) % 360;
    if (failBearings.contains(rounded)) {
      throw const RoutingException('Brak przejazdu');
    }

    var straight = 0.0;
    for (var i = 1; i < waypoints.length; i++) {
      straight += haversineMeters(waypoints[i - 1].point, waypoints[i].point);
    }
    final distance = straight * windiness;

    // Geometria idzie po prawdziwym obwodzie trójkąta, bo od jej kształtu
    // zależy, czy generator odróżni dwie pętle w różne strony od dwóch
    // odcieni tej samej trasy.
    final climbPerKm = elevationPerBearing[rounded] ?? 6.0;
    final points = <GeoPoint>[];
    for (var leg = 1; leg < waypoints.length; leg++) {
      final from = waypoints[leg - 1].point;
      final to = waypoints[leg].point;
      for (var step = 0; step < 8; step++) {
        final t = step / 8;
        final progress = (leg - 1 + t) / (waypoints.length - 1);
        points.add(
          GeoPoint(
            lat: from.lat + (to.lat - from.lat) * t,
            lon: from.lon + (to.lon - from.lon) * t,
            // Jedno wzniesienie w połowie trasy i zjazd z powrotem.
            elevation: 100 +
                math.sin(progress * math.pi) * climbPerKm * (distance / 1000),
          ),
        );
      }
    }
    points.add(waypoints.last.point);

    return RoutedPath(
      points: points,
      maneuvers: const [],
      distanceMeters: distance,
      duration: Duration(seconds: (distance / 6).round()),
    );
  }
}

const _start = GeoPoint(lat: 52.52, lon: 13.40);

void main() {
  group('pętla na zadany dystans', () {
    test('„50 km pętla" wychodzi w tolerancji, a nie na 37 km', () async {
      final router = _WindingRouter();
      final generator = RouteGenerator(router);

      final intent = parseRouteIntent('50 km pętla');
      final routes = await generator.loops(
        start: _start,
        targetMeters: intent.distanceMeters!,
        preferences: intent.applyTo(const RoutePreferences()),
        intent: intent,
      );

      expect(routes, isNotEmpty);
      for (final route in routes) {
        final error = (route.distanceMeters - 50000).abs() / 50000;
        expect(
          error,
          lessThanOrEqualTo(routeDistanceMaxTolerance),
          reason: 'wyszło ${(route.distanceMeters / 1000).toStringAsFixed(1)} km',
        );
      }
      // Najlepszy wariant ma mieścić się w wąskiej tolerancji.
      final best = (routes.first.distanceMeters - 50000).abs() / 50000;
      expect(best, lessThanOrEqualTo(routeDistanceGoodTolerance));
    });

    test('dostrajanie naprawdę iteruje, zamiast zgadywać raz', () async {
      final router = _WindingRouter(windiness: 1.6);
      await RouteGenerator(router).loops(
        start: _start,
        targetMeters: 50000,
        preferences: const RoutePreferences(),
        variants: 1,
      );
      // Pierwsze przybliżenie przy krętości 1,6 musi być poprawione.
      expect(router.calls, greaterThan(1));
    });

    test('to jest pętla, a nie ta sama droga z powrotem', () async {
      final router = _WindingRouter();
      final generator = RouteGenerator(router);
      final routes = await generator.loops(
        start: _start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
        variants: 1,
      );

      final waypoints = routes.single.waypoints;
      // Start i meta w tym samym miejscu, ale po drodze DWA różne punkty
      // rozstawione w terenie — inaczej powrót byłby tą samą drogą.
      expect(waypoints.length, 4);
      expect(waypoints.first.point.lat, waypoints.last.point.lat);
      final apart = haversineMeters(waypoints[1].point, waypoints[2].point);
      expect(apart, greaterThan(1000));
    });

    test('kierunek bez przejazdu nie wywraca generatora', () async {
      // Router mówiący „nie ma drogi" jest normalnym wynikiem przy
      // zgadywaniu kierunku, a nie awarią.
      final router = _WindingRouter(failBearings: {0, 45, 90, 135});
      final routes = await RouteGenerator(router).loops(
        start: _start,
        targetMeters: 30000,
        preferences: const RoutePreferences(),
      );
      expect(routes, isNotEmpty);
    });

    test('gdy router milczy w każdą stronę, nie zmyślamy trasy', () async {
      final router = _WindingRouter(
        failBearings: {0, 45, 90, 135, 180, 225, 270, 315},
      );
      final routes = await RouteGenerator(router).loops(
        start: _start,
        targetMeters: 30000,
        preferences: const RoutePreferences(),
      );
      // Prosta linia udająca pętlę byłaby gorsza niż brak odpowiedzi.
      expect(routes, isEmpty);
    });

    test('anulowanie dociera do routera', () async {
      final router = _WindingRouter();
      final token = CancelToken();
      await RouteGenerator(router).loops(
        start: _start,
        targetMeters: 30000,
        preferences: const RoutePreferences(),
        variants: 1,
        cancelToken: token,
      );
      expect(router.lastCancelToken, same(token));
    });

    test('warianty różnią się kierunkiem, a nie odcieniem tej samej drogi', () async {
      final router = _WindingRouter();
      final routes = await RouteGenerator(router).loops(
        start: _start,
        targetMeters: 50000,
        preferences: const RoutePreferences(),
      );
      expect(routes.length, greaterThan(1));
      final bearings = {
        for (final route in routes)
          bearingDegrees(route.waypoints.first.point, route.waypoints[1].point)
              .round(),
      };
      expect(bearings.length, routes.length);
    });

    test('nazwa wariantu bierze się z policzonego przewyższenia', () async {
      final router = _WindingRouter(
        elevationPerBearing: {0: 2.0, 90: 6.0, 180: 14.0},
      );
      final routes = await RouteGenerator(router).loops(
        start: _start,
        targetMeters: 50000,
        preferences: const RoutePreferences(),
      );

      final labels = routes.map((route) => route.label).toList();
      expect(labels, contains('Spokojna'));
      expect(labels, contains('Sportowa'));
      // Każdy powód musi dać się wyprowadzić z liczby. Żadnej
      // „krajobrazowej" bez danych, które by ją uzasadniały.
      expect(labels, isNot(contains('Krajobrazowa')));
      final flat = routes.firstWhere((route) => route.label == 'Spokojna');
      final hilly = routes.firstWhere((route) => route.label == 'Sportowa');
      expect(flat.ascentMeters, lessThan(hilly.ascentMeters));
      expect(flat.reasons, isNotEmpty);
    });

    test('absurdalnie krótki cel nie generuje niczego', () async {
      final routes = await RouteGenerator(_WindingRouter()).loops(
        start: _start,
        targetMeters: 500,
        preferences: const RoutePreferences(),
      );
      expect(routes, isEmpty);
    });
  });

  group('czas zamiast kilometrów', () {
    test('dwie godziny przy 26 km/h to około 52 km', () {
      final meters = distanceForDuration(
        duration: const Duration(hours: 2),
        movingAverageKmh: 26,
      );
      expect(meters, closeTo(52000, 1));
    });

    test('bez historii bierzemy ostrożne tempo, nie chwilową prędkość', () {
      // Ktoś, kto właśnie zjeżdża z górki 45 km/h, nie przejedzie
      // dziewięćdziesięciu kilometrów w dwie godziny.
      final meters = distanceForDuration(
        duration: const Duration(hours: 2),
        movingAverageKmh: 0,
      );
      expect(meters, closeTo(40000, 1));
    });

    test('nierealne tempo z historii też jest odrzucane', () {
      final meters = distanceForDuration(
        duration: const Duration(hours: 1),
        movingAverageKmh: 120,
      );
      expect(meters, closeTo(20000, 1));
    });
  });

  _windAndRecommendation();
}

/// Wiatr i rekomendacja.
///
/// Dwie rzeczy łatwo tu udać: obiecać „z wiatrem na powrocie" bez patrzenia
/// w kierunek wiatru i wskazać „polecaną" bez żadnego powodu. Oba są tu
/// zablokowane testem.
void _windAndRecommendation() {
  WeatherSnapshot wind({
    required double fromDegrees,
    required double speedKmh,
  }) => WeatherSnapshot(
    temperatureCelsius: 18,
    apparentTemperatureCelsius: 18,
    windSpeedKmh: speedKmh,
    windDirectionDegrees: fromDegrees,
    condition: WeatherCondition.clear,
    isDay: true,
    observedAt: DateTime.utc(2026, 5, 1, 9),
  );

  const start = GeoPoint(lat: 52.2297, lon: 21.0122);

  group('wiatr', () {
    test('wyjazd prosto pod wiatr to pełne dopasowanie', () {
      expect(
        RouteGenerator.windAlignment(bearing: 270, windFromDegrees: 270),
        closeTo(1, 0.001),
      );
    });

    test('wyjazd z wiatrem w plecy to dopasowanie ujemne', () {
      expect(
        RouteGenerator.windAlignment(bearing: 90, windFromDegrees: 270),
        closeTo(-1, 0.001),
      );
    });

    test('słaby wiatr nie zmienia planu', () {
      expect(RouteGenerator.windMatters(wind(fromDegrees: 270, speedKmh: 8)),
          isFalse);
      expect(RouteGenerator.windMatters(null), isFalse);
      expect(RouteGenerator.windMatters(wind(fromDegrees: 270, speedKmh: 24)),
          isTrue);
    });

    test('przy silnym wietrze pierwszy wariant wyjeżdża pod wiatr', () async {
      final router = _WindingRouter();
      final routes = await RouteGenerator(router).loops(
        start: start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
        weather: wind(fromDegrees: 270, speedKmh: 28),
      );
      expect(routes, isNotEmpty);
      // Wachlarz jest obrócony na zachód, więc jeden z wariantów naprawdę
      // startuje pod wiatr — nie deklaratywnie, tylko w bearingu.
      expect(
        routes.any(
          (route) =>
              route.bearing != null &&
              RouteGenerator.windAlignment(
                    bearing: route.bearing!,
                    windFromDegrees: 270,
                  ) >
                  0.9,
        ),
        isTrue,
      );
    });

    test('bez wiatru nikt nie obiecuje wiatru na powrocie', () async {
      final router = _WindingRouter();
      final routes = await RouteGenerator(router).loops(
        start: start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
        weather: wind(fromDegrees: 270, speedKmh: 6),
      );
      for (final route in routes) {
        for (final reason in route.reasons) {
          expect(reason.toLowerCase(), isNot(contains('wiatr')));
        }
      }
    });

    test('wariant pod wiatr mówi o tym wprost', () async {
      final router = _WindingRouter();
      final routes = await RouteGenerator(router).loops(
        start: start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
        weather: wind(fromDegrees: 270, speedKmh: 28),
      );
      final upwind = routes.firstWhere(
        (route) =>
            route.bearing != null &&
            RouteGenerator.windAlignment(
                  bearing: route.bearing!,
                  windFromDegrees: 270,
                ) >
                0.9,
      );
      expect(
        upwind.reasons.any((r) => r.contains('z wiatrem na powrocie')),
        isTrue,
      );
      expect(upwind.reasons.any((r) => r.contains('28 km/h')), isTrue);
    });
  });

  group('rekomendacja', () {
    test('polecana jest najwyżej jedna', () async {
      final routes = await RouteGenerator(_WindingRouter()).loops(
        start: start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
        weather: wind(fromDegrees: 270, speedKmh: 28),
      );
      expect(routes.where((route) => route.recommended).length,
          lessThanOrEqualTo(1));
    });

    test('polecana zawsze umie powiedzieć dlaczego', () async {
      final routes = await RouteGenerator(_WindingRouter()).loops(
        start: start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
        weather: wind(fromDegrees: 270, speedKmh: 28),
      );
      for (final route in routes.where((route) => route.recommended)) {
        expect(route.reasons, isNotEmpty);
      }
    });

    test('trafiony dystans jest wymieniony jako powód', () async {
      final routes = await RouteGenerator(_WindingRouter()).loops(
        start: start,
        targetMeters: 40000,
        preferences: const RoutePreferences(),
      );
      final onTarget = routes.where(
        (route) => (route.distanceMeters - 40000).abs() / 40000 <= 0.05,
      );
      expect(onTarget, isNotEmpty);
      for (final route in onTarget) {
        expect(
          route.reasons.any((r) => r.contains('ile prosiłeś')),
          isTrue,
          reason: 'wariant ${route.distanceMeters} m nie tłumaczy dystansu',
        );
      }
    });
  });
}
