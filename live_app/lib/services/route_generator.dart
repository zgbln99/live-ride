import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../core/geo.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';
import '../models/weather.dart';
import 'route_intent.dart';
import 'routing_service.dart';

/// Jeden wygenerowany wariant trasy.
class GeneratedRoute {
  const GeneratedRoute({
    required this.label,
    required this.path,
    required this.waypoints,
    required this.preferences,
    required this.reasons,
    this.bearing,
    this.recommended = false,
  });

  /// Nazwa wariantu: „Spokojna", „Sportowa", „Krajobrazowa".
  final String label;

  final RoutedPath path;
  final List<RouteWaypoint> waypoints;
  final RoutePreferences preferences;

  /// Dlaczego akurat ten wariant — wyłącznie z policzonych liczb.
  ///
  /// Pusta lista jest poprawna: wariant, którego niczym nie da się uzasadnić,
  /// dostaje samą nazwę zamiast wymyślonego powodu.
  final List<String> reasons;

  /// Kierunek pierwszego odcinka pętli. Potrzebny, żeby powiedzieć cokolwiek
  /// o wietrze — bez niego „z wiatrem na powrocie" byłoby zgadywaniem.
  final double? bearing;

  /// Wariant, który proponujemy jako pierwszy. Zawsze umie powiedzieć czemu:
  /// [reasons] nigdy nie jest puste dla polecanego.
  final bool recommended;

  double get distanceMeters => path.distanceMeters;

  double get ascentMeters {
    var gain = 0.0;
    for (var i = 1; i < path.points.length; i++) {
      final from = path.points[i - 1].elevation;
      final to = path.points[i].elevation;
      if (from == null || to == null) continue;
      final delta = to - from;
      if (delta > 0) gain += delta;
    }
    return gain;
  }
}

/// Jak daleko od celu wolno wylądować.
///
/// „50 km" znaczy pięćdziesiąt, a nie trzydzieści siedem. Pięć procent to
/// granica, poniżej której nikt nie zauważy różnicy; dziesięć to granica,
/// powyżej której trasa przestaje być tą, o którą proszono.
const double routeDistanceGoodTolerance = 0.05;
const double routeDistanceMaxTolerance = 0.10;

/// Generator tras z jednego zdania albo z samego dystansu.
///
/// Najtrudniejsza część nie jest w geometrii, tylko w uczciwości: prawdziwa
/// pętla na pięćdziesiąt kilometrów to NIE jest dwadzieścia pięć w jedną
/// stronę i ta sama droga z powrotem. Router liczy po prawdziwych drogach,
/// więc trójkąt o obwodzie pięćdziesięciu kilometrów w linii prostej wychodzi
/// w terenie na sześćdziesiąt trzy — i dlatego jedyny sposób, żeby trafić
/// w zadany dystans, to POLICZYĆ trasę, zmierzyć wynik i poprawić punkty.
class RouteGenerator {
  RouteGenerator(this._routing);

  final RoutingService _routing;

  /// Ile razy poprawiamy punkty, zanim uznamy wynik za najlepszy dostępny.
  ///
  /// Każda iteracja to jedno zapytanie do routera. Cztery starczają, żeby
  /// zejść z dwudziestu procent błędu do kilku; więcej byłoby kupowaniem
  /// ostatniego procenta za kolejne sekundy czekania.
  static const int maxIterations = 4;

  /// Kierunki, w które próbujemy wyjechać. Co czterdzieści pięć stopni.
  static const List<double> seedBearings = [0, 45, 90, 135, 180, 225, 270, 315];

  /// Generuje pętlę o zadanym dystansie.
  ///
  /// Zwraca pustą listę, gdy router nie umiał zbudować żadnej sensownej
  /// trasy — nigdy trasy wymyślonej. Prosta linia udająca pętlę byłaby
  /// gorsza niż komunikat o niepowodzeniu.
  Future<List<GeneratedRoute>> loops({
    required GeoPoint start,
    required double targetMeters,
    required RoutePreferences preferences,
    RouteIntent? intent,
    int variants = 3,
    WeatherSnapshot? weather,
    CancelToken? cancelToken,
  }) async {
    if (!start.isValid || targetMeters < 2000) return const [];

    final candidates = <GeneratedRoute>[];
    // Wachlarz kierunków: z każdego wychodzi inna pętla, więc trzy warianty
    // biorą się z trzech różnych stron świata, a nie z trzech odcieni tej
    // samej drogi.
    final bearings = _spreadBearings(variants, weather: weather);

    for (final bearing in bearings) {
      final tuned = await _tuneLoop(
        start: start,
        targetMeters: targetMeters,
        bearing: bearing,
        preferences: preferences,
        cancelToken: cancelToken,
      );
      if (tuned != null) candidates.add(tuned);
    }

    if (candidates.isEmpty) return const [];

    // Odrzucamy pętle, które są w praktyce tą samą trasą.
    final distinct = _distinct(candidates);
    distinct.sort(
      (a, b) => _error(a.distanceMeters, targetMeters)
          .compareTo(_error(b.distanceMeters, targetMeters)),
    );
    final usable = distinct
        .where(
          (route) =>
              _error(route.distanceMeters, targetMeters) <=
              routeDistanceMaxTolerance,
        )
        .toList();
    // Gdy nic nie trafiło w tolerancję, oddajemy najlepsze, co wyszło —
    // ale wołający musi wiedzieć, ile naprawdę ma, i to jest w `path`.
    final chosen = (usable.isEmpty ? distinct : usable).take(variants).toList();
    return _label(chosen, intent, weather, targetMeters);
  }

  /// Iteracyjnie dostraja pętlę, aż trafi w dystans.
  Future<GeneratedRoute?> _tuneLoop({
    required GeoPoint start,
    required double targetMeters,
    required double bearing,
    required RoutePreferences preferences,
    CancelToken? cancelToken,
  }) async {
    // Pierwsze przybliżenie: trójkąt równoboczny o obwodzie równym celowi.
    // Drogi nie biegną prosto, więc wyjdzie za długo — i o to chodzi, bo
    // skracanie jest stabilniejsze niż wydłużanie.
    var radius = targetMeters / (2 * math.pi) * 1.15;
    GeneratedRoute? best;
    var bestError = double.infinity;

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final waypoints = _triangle(start, bearing, radius);
      final path = await _safeRoute(waypoints, preferences, cancelToken);
      if (path == null || path.isEmpty) {
        // Router nie znalazł drogi w tę stronę — ściągamy pętlę bliżej
        // zamiast próbować tego samego jeszcze raz.
        radius *= 0.7;
        continue;
      }

      final error = _error(path.distanceMeters, targetMeters);
      if (error < bestError) {
        bestError = error;
        best = GeneratedRoute(
          label: '',
          path: path,
          waypoints: waypoints,
          preferences: preferences,
          reasons: const [],
          bearing: bearing,
        );
      }
      if (error <= routeDistanceGoodTolerance) break;

      // Skalujemy promień proporcjonalnie do błędu. Trasa dwa razy za
      // długa potrzebuje mniej więcej dwa razy mniejszego promienia —
      // tłumienie chroni przed przestrzeleniem w drugą stronę.
      final ratio = targetMeters / path.distanceMeters;
      radius *= 1 + (ratio - 1) * 0.8;
      if (radius < 300) break;
    }
    return best;
  }

  /// Trzy wierzchołki pętli: start, dwa punkty w terenie i powrót.
  ///
  /// Trójkąt, a nie „tam i z powrotem": punkty rozstawione co sto dwadzieścia
  /// stopni gwarantują, że droga powrotna nie może być tą samą drogą.
  List<RouteWaypoint> _triangle(GeoPoint start, double bearing, double radius) {
    final first = _offset(start, bearing, radius);
    final second = _offset(start, bearing + 120, radius);
    return [
      RouteWaypoint(point: start),
      RouteWaypoint(point: first),
      RouteWaypoint(point: second),
      RouteWaypoint(point: start),
    ];
  }

  Future<RoutedPath?> _safeRoute(
    List<RouteWaypoint> waypoints,
    RoutePreferences preferences,
    CancelToken? cancelToken,
  ) async {
    try {
      return await _routing.route(
        waypoints: waypoints,
        preferences: preferences,
        cancelToken: cancelToken,
      );
    } on RoutingException {
      // Nieosiągalny punkt to normalny wynik przy zgadywaniu kierunku —
      // nie awaria generatora.
      return null;
    } on DioException {
      return null;
    }
  }

  /// Punkt oddalony o [meters] w kierunku [bearing].
  static GeoPoint _offset(GeoPoint from, double bearing, double meters) {
    const earth = 6371008.8;
    final angular = meters / earth;
    final theta = bearing * math.pi / 180;
    final lat1 = from.lat * math.pi / 180;
    final lon1 = from.lon * math.pi / 180;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(theta),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(theta) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return GeoPoint(lat: lat2 * 180 / math.pi, lon: lon2 * 180 / math.pi);
  }

  static double _error(double actual, double target) =>
      target <= 0 ? 1 : (actual - target).abs() / target;

  List<double> _spreadBearings(int variants, {WeatherSnapshot? weather}) {
    if (variants >= seedBearings.length) return seedBearings;
    // Równomiernie po całym wachlarzu, a nie trzy sąsiednie kierunki.
    final step = seedBearings.length ~/ math.max(1, variants);
    final fan = [
      for (var i = 0; i < variants; i++)
        seedBearings[(i * step) % seedBearings.length],
    ];

    // Przy wietrze wartym uwagi obracamy CAŁY wachlarz tak, żeby pierwszy
    // kierunek szedł pod wiatr. Zmęczoną drugą połowę jazdy chcemy mieć
    // z wiatrem w plecy, a nie odwrotnie.
    if (!windMatters(weather)) return fan;
    final offset = weather!.windDirectionDegrees - fan.first;
    return [for (final bearing in fan) (bearing + offset) % 360];
  }

  /// Poniżej tej prędkości wiatr nie zmienia planu jazdy.
  static const double windMattersKmh = 15;

  /// Czy w ogóle jest o czym mówić.
  static bool windMatters(WeatherSnapshot? weather) =>
      weather != null && weather.windSpeedKmh >= windMattersKmh;

  /// Jak bardzo pierwszy odcinek idzie pod wiatr.
  ///
  /// 1 = prosto pod wiatr (czyli dobrze: powrót będzie z wiatrem),
  /// -1 = z wiatrem na starcie, a więc pod wiatr do domu.
  static double windAlignment({
    required double bearing,
    required double windFromDegrees,
  }) {
    final delta = ((bearing - windFromDegrees) % 360) * math.pi / 180;
    return math.cos(delta);
  }

  /// Odsiewa warianty, które są w praktyce tą samą pętlą.
  ///
  /// Dwie trasy o środkach ciężkości bliżej niż kilometr i podobnej długości
  /// prowadzą tymi samymi drogami. Pokazanie ich jako „dwie propozycje"
  /// byłoby udawaniem wyboru.
  List<GeneratedRoute> _distinct(List<GeneratedRoute> routes) {
    final kept = <GeneratedRoute>[];
    for (final route in routes) {
      final centre = _centroid(route.path.points);
      final duplicate = kept.any((other) {
        final gap = haversineMeters(centre, _centroid(other.path.points));
        final lengthGap =
            (route.distanceMeters - other.distanceMeters).abs() /
            math.max(route.distanceMeters, 1);
        return gap < 1000 && lengthGap < 0.08;
      });
      if (!duplicate) kept.add(route);
    }
    return kept;
  }

  static GeoPoint _centroid(List<GeoPoint> points) {
    if (points.isEmpty) return const GeoPoint(lat: 0, lon: 0);
    var lat = 0.0;
    var lon = 0.0;
    for (final point in points) {
      lat += point.lat;
      lon += point.lon;
    }
    return GeoPoint(lat: lat / points.length, lon: lon / points.length);
  }

  /// Nazywa warianty tym, czym naprawdę się różnią.
  ///
  /// Żadnej „krajobrazowej", jeśli nie mamy danych, które by to uzasadniały.
  /// Nazwa wariantu jest opisem policzonej liczby, a nie obietnicą.
  List<GeneratedRoute> _label(
    List<GeneratedRoute> routes,
    RouteIntent? intent,
    WeatherSnapshot? weather,
    double targetMeters,
  ) {
    if (routes.isEmpty) return routes;
    final byAscent = [...routes]
      ..sort((a, b) => a.ascentMeters.compareTo(b.ascentMeters));

    final labelled = <GeneratedRoute>[];
    for (final route in routes) {
      final reasons = <String>[];
      final flattest = identical(route, byAscent.first);
      final hilliest = identical(route, byAscent.last);
      // Przy jednym wariancie „najpłaszczy” i „najbardziej pagórkowaty” to
      // ta sama trasa — wtedy nie mówimy ani jednego, ani drugiego.
      final comparable = byAscent.length > 1;
      final hasElevation = route.ascentMeters > 0;

      String label;
      if (comparable && hasElevation && flattest) {
        label = 'Spokojna';
        reasons.add('najmniejsze przewyższenie z propozycji');
      } else if (comparable && hasElevation && hilliest) {
        label = 'Sportowa';
        reasons.add('najwięcej podjazdów z propozycji');
      } else {
        label = 'Zrównoważona';
      }

      // Dystans mówimy tylko wtedy, gdy naprawdę trafiliśmy w cel. Wariant
      // trzydziestosiedmiokilometrowy nie dostanie pochwały za „dokładnie
      // tyle, ile prosiłeś”.
      final error = _error(route.distanceMeters, targetMeters);
      if (error <= routeDistanceGoodTolerance) {
        final km = (route.distanceMeters / 1000)
            .toStringAsFixed(1)
            .replaceAll('.', ',');
        reasons.add('$km km, czyli tyle, ile prosiłeś');
      }

      final wind = _windReason(route, weather);
      if (wind != null) reasons.add(wind);

      if (route.preferences.avoidBusyRoads) {
        reasons.add('boczne drogi');
      }
      if (intent?.elevation == ElevationPreference.flat && flattest) {
        reasons.add('najbliżej tego, o co prosiłeś');
      }
      labelled.add(
        GeneratedRoute(
          label: label,
          path: route.path,
          waypoints: route.waypoints,
          preferences: route.preferences,
          reasons: reasons,
          bearing: route.bearing,
        ),
      );
    }

    return _recommend(labelled, weather, targetMeters);
  }

  /// „Pod wiatr na starcie, z wiatrem do domu” — albo nic.
  ///
  /// Przy słabym wietrze i bez znanego kierunku wyjazdu milczymy: obietnica
  /// o wietrze, której nie umiemy sprawdzić, jest gorsza niż jej brak.
  static String? _windReason(GeneratedRoute route, WeatherSnapshot? weather) {
    if (!windMatters(weather)) return null;
    final bearing = route.bearing;
    if (bearing == null) return null;
    final alignment = windAlignment(
      bearing: bearing,
      windFromDegrees: weather!.windDirectionDegrees,
    );
    if (alignment < 0.4) return null;
    return 'pod wiatr na starcie (${weather.windSpeedKmh.round()} km/h), '
        'z wiatrem na powrocie';
  }

  /// Wybiera wariant polecany i pilnuje, żeby umiał się wytłumaczyć.
  ///
  /// Kolejność: najpierw te, które trafiły w dystans, potem te z wiatrem po
  /// właściwej stronie. Jeśli o żadnym nie da się powiedzieć nic konkretnego,
  /// nie polecamy żadnego — trzy propozycje bez rekomendacji są uczciwsze
  /// niż rekomendacja bez powodu.
  static List<GeneratedRoute> _recommend(
    List<GeneratedRoute> routes,
    WeatherSnapshot? weather,
    double targetMeters,
  ) {
    GeneratedRoute? best;
    var bestScore = 0.0;
    for (final route in routes) {
      if (route.reasons.isEmpty) continue;
      var score = 0.0;
      if (_error(route.distanceMeters, targetMeters) <=
          routeDistanceGoodTolerance) {
        score += 2;
      }
      final bearing = route.bearing;
      if (windMatters(weather) && bearing != null) {
        score +=
            windAlignment(
              bearing: bearing,
              windFromDegrees: weather!.windDirectionDegrees,
            ) *
            1.5;
      }
      if (score > bestScore) {
        bestScore = score;
        best = route;
      }
    }
    if (best == null) return routes;
    return [
      for (final route in routes)
        if (identical(route, best))
          GeneratedRoute(
            label: route.label,
            path: route.path,
            waypoints: route.waypoints,
            preferences: route.preferences,
            reasons: route.reasons,
            bearing: route.bearing,
            recommended: true,
          )
        else
          route,
    ];
  }
}

/// Zamienia „mam dwie godziny" na dystans.
///
/// Liczone z REALNEGO tempa zawodnika, a nie z prędkości chwilowej ani
/// z założeń producenta: ktoś, kto jeździ 22 km/h, po dwóch godzinach ma
/// czterdzieści cztery kilometry, a nie pięćdziesiąt.
double distanceForDuration({
  required Duration duration,
  required double movingAverageKmh,
}) {
  final pace = movingAverageKmh > 5 && movingAverageKmh < 60
      ? movingAverageKmh
      // Bez historii bierzemy ostrożne tempo. Za krótka trasa jest
      // mniejszym problemem niż za długa.
      : 20.0;
  return pace * duration.inMinutes / 60 * 1000;
}
