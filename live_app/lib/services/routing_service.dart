import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/geo.dart';
import '../models/navigation_plan.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';

/// Błąd trasowania w formie, którą można pokazać użytkownikowi.
///
/// [waypointIndex] wskazuje punkt, przez który trasa nie przechodzi — po to,
/// żeby kreator mógł go podświetlić zamiast kazać zgadywać, który z sześciu
/// postawionych punktów jest nie tak.
class RoutingException implements Exception {
  const RoutingException(this.message, {this.waypointIndex});

  final String message;
  final int? waypointIndex;

  @override
  String toString() => message;
}

/// Wynik trasowania: geometria plus to, co router o niej wie.
class RoutedPath {
  const RoutedPath({
    required this.points,
    required this.maneuvers,
    required this.distanceMeters,
    required this.duration,
    this.mapMatched = true,
    this.snappedWaypoints = const <int>[],
  });

  final List<GeoPoint> points;
  final List<NavManeuver> maneuvers;
  final double distanceMeters;
  final Duration duration;

  /// Fałsz, gdy router zawiódł i jedziemy po linii prostej między punktami.
  final bool mapMatched;

  /// Indeksy punktów, które trzeba było dosunąć do drogi.
  ///
  /// Kreator pokazuje to delikatnie, zamiast kazać przesuwać punkt ręcznie
  /// o pięć metrów. Pusta lista znaczy „wszystkie punkty leżały tam, gdzie
  /// je postawiono".
  final List<int> snappedWaypoints;

  bool get isEmpty => points.length < 2;

  static const RoutedPath empty = RoutedPath(
    points: [],
    maneuvers: [],
    distanceMeters: 0,
    duration: Duration.zero,
  );
}

/// Trasowanie przez Valhallę na własnym serwerze.
///
/// Wszystko, czego potrzebuje kreator tras: policz trasę między punktami,
/// przyklej narysowany szkic do dróg, dołóż wysokość do geometrii.
class RoutingService {
  RoutingService(this._api);

  final ApiClient _api;

  /// Valhalla przyjmuje najwyżej tyle punktów w trace_route.
  static const int maxTracePoints = 500;

  /// Ile punktów dostaje żądanie wysokości naraz.
  static const int elevationChunk = 400;

  final Map<String, RoutedPath> _cache = {};

  /// Promienie wyszukiwania, po kolei, dla kolejnych prób.
  ///
  /// Promień mówi Valhalli, jak daleko od podanej współrzędnej wolno jej
  /// szukać drogi. Domyślnie szuka bardzo blisko, więc punkt postawiony
  /// palcem dziesięć metrów obok ścieżki potrafi nie skorelować się z niczym
  /// i cała trasa kończy się błędem — mimo że człowiek widzi na mapie, gdzie
  /// chciał jechać.
  ///
  /// Sto metrów to granica. Powyżej niej „najbliższa droga" przestaje być tą,
  /// którą użytkownik miał na myśli, i trasa zaczyna prowadzić gdzie indziej.
  static const List<int> searchRadiiMeters = [0, 25, 50, 100];

  /// Ile najwyżej odcinków składamy osobno, gdy całość nie przechodzi.
  ///
  /// Każdy odcinek to osobne żądanie; przy dużej liczbie punktów lepiej
  /// powiedzieć, że się nie udało, niż zasypać router setką zapytań.
  static const int maxSegmentedLegs = 24;

  /// Od ilu metrów mówimy użytkownikowi, że punkt został dosunięty.
  ///
  /// Poniżej tego to korekta w granicach dokładności dotknięcia palcem —
  /// informowanie o niej byłoby szumem, a nie informacją.
  static const double reportSnapAboveMeters = 8;

  /// Liczy trasę przez podane waypointy.
  ///
  /// Router potrafi odmówić z powodu, który nie jest winą użytkownika: punkt
  /// postawiony kilkanaście metrów obok drogi, na parkingu, na moście albo
  /// tuż za zamkniętym przejazdem. Pierwsza odpowiedź 400 nie jest więc
  /// końcem, tylko początkiem — próbujemy po kolei coraz bardziej
  /// wyrozumiałych sposobów, a błąd pokazujemy dopiero wtedy, gdy żaden nie
  /// zadziałał.
  ///
  /// Kolejność jest celowa: od najwierniejszej intencji użytkownika do
  /// najbardziej domyślnej.
  ///
  ///  1. dokładnie te punkty, które postawił,
  ///  2. to samo z rosnącym promieniem szukania drogi (25, 50, 100 m),
  ///  3. punkty dosunięte do najbliższej drogi ROWEROWEJ przez `/locate`,
  ///  4. trasa liczona odcinkami A→B, B→C i sklejona,
  ///  5. dopiero teraz błąd — ze wskazaniem, który punkt jest problemem.
  ///
  /// Czego tu nie ma i nie będzie: prostej linii udającej trasę i objazdu
  /// drogą, na którą rower nie ma wstępu. „Zawsze znajdź trasę" znaczy
  /// „wyczerpij bezpieczne możliwości", a nie „pokaż cokolwiek".
  Future<RoutedPath> route({
    required List<RouteWaypoint> waypoints,
    required RoutePreferences preferences,
    String language = 'pl-PL',

    /// Przerywa całą serię prób, gdy wynik przestał być potrzebny.
    ///
    /// Ma znaczenie właśnie dlatego, że prób jest kilka: przeciąganie punktu
    /// po mapie unieważnia poprzednie zapytanie co kilkaset milisekund, a bez
    /// anulowania każde z nich dobijałoby router jeszcze przez dziesięć
    /// kolejnych żądań, których wynik i tak nikogo już nie obchodzi.
    CancelToken? cancelToken,
  }) async {
    final usable = waypoints.where((w) => w.point.isValid).toList();
    if (usable.length < 2) return RoutedPath.empty;

    final key = _cacheKey(usable, preferences);
    final cached = _cache[key];
    if (cached != null) return cached;

    final points = [for (final w in usable) w.point];
    var offline = false;

    // 1 i 2: te same punkty, coraz szersze szukanie drogi.
    for (final radius in searchRadiiMeters) {
      final attempt = await _attempt(
        points,
        preferences: preferences,
        language: language,
        radiusMeters: radius,
        cancelToken: cancelToken,
      );
      if (attempt.path != null) return _remember(key, attempt.path!);
      if (attempt.offline) {
        offline = true;
        break;
      }
    }

    // Bez sieci nie ma sensu próbować dalej — każdy kolejny krok to też
    // żądanie HTTP. Szkic zostaje szkicem i mówi to wprost.
    if (offline) return _straightLine(usable);

    // 3: dosuń punkty do najbliższej drogi rowerowej i spróbuj jeszcze raz.
    //
    // Warunkiem ponowienia jest JAKAKOLWIEK zmiana współrzędnych, a nie to,
    // czy warto o niej powiedzieć użytkownikowi. Przesunięcie o pięć metrów
    // bywa dokładnie tym, co odblokowuje trasę, a jednocześnie jest zbyt małe,
    // żeby zawracać nim komuś głowę.
    final snapped = await _snapToRoads(points, preferences, cancelToken);
    if (snapped != null && snapped.changed) {
      for (final radius in searchRadiiMeters) {
        final attempt = await _attempt(
          snapped.points,
          preferences: preferences,
          language: language,
          radiusMeters: radius,
          cancelToken: cancelToken,
        );
        if (attempt.path != null) {
          return _remember(
            key,
            _withSnapped(attempt.path!, snapped.movedIndices),
          );
        }
        if (attempt.offline) return _straightLine(usable);
      }
    }

    // 4: odcinkami. Jeden trudny fragment nie ma prawa przekreślać całej
    // trasy — reszta przechodzi bez zarzutu i to ją pokazujemy.
    final base = snapped?.points ?? points;
    final segmented = await _routeBySegments(
      base,
      preferences: preferences,
      language: language,
      cancelToken: cancelToken,
    );
    if (segmented != null) {
      return _remember(
        key,
        _withSnapped(segmented, snapped?.movedIndices ?? const <int>[]),
      );
    }

    // 5: naprawdę się nie da. Powiedz KTÓRY punkt i co z nim zrobić.
    final culprit = await _firstUnreachable(
      base,
      preferences,
      language,
      cancelToken,
    );
    throw RoutingException(_failureMessage(culprit), waypointIndex: culprit);
  }

  /// Jedna próba policzenia całej trasy.
  ///
  /// Zwraca ścieżkę albo powód, dla którego jej nie ma. Rozróżnienie „router
  /// odmówił" od „nie ma sieci" jest tu kluczowe: pierwsze warto ponawiać
  /// inaczej, drugiego nie warto ponawiać wcale.
  Future<_RouteAttempt> _attempt(
    List<GeoPoint> points, {
    required RoutePreferences preferences,
    required String language,
    required int radiusMeters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _api.dio.post<dynamic>(
        '/valhalla/route',
        cancelToken: cancelToken,
        data: {
          'locations': [
            for (var i = 0; i < points.length; i++)
              {
                'lat': points[i].lat,
                'lon': points[i].lon,
                // „break" każe Valhalli zatrzymać się w punkcie i pozwolić
                // na zawrotkę; „through" przejeżdża przez punkt bez przerwy.
                'type': i == 0 || i == points.length - 1 ? 'break' : 'through',
                if (radiusMeters > 0) 'radius': radiusMeters,
                if (radiusMeters > 0) 'search_cutoff': radiusMeters * 4,
              },
          ],
          'costing': 'bicycle',
          'costing_options': {'bicycle': preferences.toValhallaCosting()},
          'directions_options': {'units': 'kilometers', 'language': language},
          'elevation_interval': 30,
        },
      );

      final path = _parseRoute(response.data);
      return path.isEmpty
          ? const _RouteAttempt.rejected()
          : _RouteAttempt.found(path);
    } on DioException catch (e) {
      // Anulowanie nie jest porażką routera i nie może uruchomić kolejnych
      // prób — wynik przestał być komukolwiek potrzebny.
      if (e.type == DioExceptionType.cancel) {
        return const _RouteAttempt.offline();
      }
      final status = e.response?.statusCode;
      // 400 to „nie umiem tędy poprowadzić" i jest zaproszeniem do kolejnej
      // próby. Brak odpowiedzi to brak sieci i kończy sprawę.
      if (status == null) return const _RouteAttempt.offline();
      return const _RouteAttempt.rejected();
    } catch (_) {
      return const _RouteAttempt.rejected();
    }
  }

  /// Dosuwa punkty do najbliższej drogi, na którą rower ma wstęp.
  ///
  /// Pyta o to Valhallę (`/locate`), a nie geometrię: „najbliższa linia na
  /// mapie" bywa torem kolejowym, rzeką albo drogą z zakazem. Router wie,
  /// które krawędzie są przejezdne dla wybranego profilu, i tylko takie
  /// zwraca.
  Future<_SnappedPoints?> _snapToRoads(
    List<GeoPoint> points,
    RoutePreferences preferences, [
    CancelToken? cancelToken,
  ]) async {
    try {
      final response = await _api.dio.post<dynamic>(
        '/valhalla/locate',
        cancelToken: cancelToken,
        data: {
          'locations': [
            for (final point in points)
              {
                'lat': point.lat,
                'lon': point.lon,
                'radius': searchRadiiMeters.last,
              },
          ],
          'costing': 'bicycle',
          'costing_options': {'bicycle': preferences.toValhallaCosting()},
          'verbose': false,
        },
      );

      final data = response.data;
      if (data is! List || data.length != points.length) return null;

      final snapped = <GeoPoint>[];
      final moved = <int>[];
      var changed = false;
      for (var i = 0; i < points.length; i++) {
        final correlated = _correlatedPoint(data[i]);
        if (correlated == null) {
          snapped.add(points[i]);
          continue;
        }
        snapped.add(correlated);
        final distance = haversineMeters(points[i], correlated);
        if (distance > 0.5) changed = true;
        // Kilka metrów to normalna korekta i nie warto o niej wspominać.
        // Kilkanaście to już informacja: punkt wylądował gdzie indziej.
        if (distance > reportSnapAboveMeters) moved.add(i);
      }
      return _SnappedPoints(
        points: snapped,
        movedIndices: moved,
        changed: changed,
      );
    } catch (_) {
      return null;
    }
  }

  /// Wyciąga skorelowaną pozycję z jednej odpowiedzi `/locate`.
  static GeoPoint? _correlatedPoint(Object? entry) {
    if (entry is! Map) return null;
    // Valhalla podaje punkt przyklejenia osobno dla każdej krawędzi; bierzemy
    // pierwszą, bo lista jest posortowana od najbliższej.
    final edges = entry['edges'];
    if (edges is List) {
      for (final edge in edges) {
        if (edge is! Map) continue;
        final at = edge['correlated_lat'];
        final on = edge['correlated_lon'];
        if (at is num && on is num) {
          final point = GeoPoint(lat: at.toDouble(), lon: on.toDouble());
          if (point.isValid) return point;
        }
      }
    }
    final nodes = entry['nodes'];
    if (nodes is List) {
      for (final node in nodes) {
        if (node is! Map) continue;
        final at = node['lat'];
        final on = node['lon'];
        if (at is num && on is num) {
          final point = GeoPoint(lat: at.toDouble(), lon: on.toDouble());
          if (point.isValid) return point;
        }
      }
    }
    return null;
  }

  /// Liczy trasę odcinek po odcinku i skleja wynik.
  ///
  /// Valhalla potrafi odmówić całości z powodu jednego przejścia, a te same
  /// punkty parami przechodzą bez problemu. Zwraca null, gdy choć jeden
  /// odcinek naprawdę nie istnieje — sklejanie trasy z dziurą byłoby gorsze
  /// niż uczciwy błąd.
  Future<RoutedPath?> _routeBySegments(
    List<GeoPoint> points, {
    required RoutePreferences preferences,
    required String language,
    CancelToken? cancelToken,
  }) async {
    if (points.length < 3 || points.length - 1 > maxSegmentedLegs) return null;

    final legs = <RoutedPath>[];
    for (var i = 0; i < points.length - 1; i++) {
      RoutedPath? leg;
      for (final radius in searchRadiiMeters) {
        final attempt = await _attempt(
          [points[i], points[i + 1]],
          preferences: preferences,
          language: language,
          radiusMeters: radius,
          cancelToken: cancelToken,
        );
        if (attempt.offline) return null;
        if (attempt.path != null) {
          leg = attempt.path;
          break;
        }
      }
      if (leg == null) return null;
      legs.add(leg);
    }
    return _join(legs);
  }

  /// Skleja odcinki w jedną trasę.
  ///
  /// Punkt styku należy do obu odcinków, więc z każdego kolejnego pomijamy
  /// pierwszą współrzędną; bez tego w geometrii zostawałyby duplikaty, a
  /// profil wysokości miałby pionowe schodki. Indeksy manewrów przesuwają
  /// się o długość tego, co już sklejone.
  static RoutedPath _join(List<RoutedPath> legs) {
    final points = <GeoPoint>[];
    final maneuvers = <NavManeuver>[];
    var distance = 0.0;
    var duration = Duration.zero;

    for (final leg in legs) {
      final offset = points.isEmpty ? 0 : points.length - 1;
      points.addAll(points.isEmpty ? leg.points : leg.points.skip(1));
      for (final maneuver in leg.maneuvers) {
        maneuvers.add(
          NavManeuver(
            instruction: maneuver.instruction,
            beginShapeIndex: maneuver.beginShapeIndex + offset,
            endShapeIndex: maneuver.endShapeIndex + offset,
            type: maneuver.type,
            lengthKm: maneuver.lengthKm,
            seconds: maneuver.seconds,
            streetNames: maneuver.streetNames,
            verbalPost: maneuver.verbalPost,
            roundaboutExit: maneuver.roundaboutExit,
          ),
        );
      }
      distance += leg.distanceMeters;
      duration += leg.duration;
    }

    return RoutedPath(
      points: points,
      maneuvers: maneuvers,
      distanceMeters: distance,
      duration: duration,
    );
  }

  /// Znajduje pierwszy punkt, z którego nie da się nigdzie dojechać.
  ///
  /// Sprawdza pary sąsiadów i zwraca indeks tego, który psuje odcinek.
  /// Dzięki temu komunikat wskazuje konkretny punkt, a nie całą trasę.
  Future<int?> _firstUnreachable(
    List<GeoPoint> points,
    RoutePreferences preferences,
    String language,
    CancelToken? cancelToken,
  ) async {
    for (var i = 0; i < points.length - 1; i++) {
      final attempt = await _attempt(
        [points[i], points[i + 1]],
        preferences: preferences,
        language: language,
        radiusMeters: searchRadiiMeters.last,
        cancelToken: cancelToken,
      );
      if (attempt.offline) return null;
      if (attempt.path == null) return i + 1;
    }
    return null;
  }

  static String _failureMessage(int? waypointIndex) {
    if (waypointIndex == null) {
      return 'Nie udało się poprowadzić trasy rowerowej przez te punkty. '
          'Spróbuj dodać punkt pośredni na drodze.';
    }
    return 'Do punktu ${waypointIndex + 1} nie prowadzi żadna droga '
        'dla rowerów. Przesuń go albo dodaj punkt pośredni.';
  }

  static RoutedPath _withSnapped(RoutedPath path, List<int> moved) {
    if (moved.isEmpty) return path;
    return RoutedPath(
      points: path.points,
      maneuvers: path.maneuvers,
      distanceMeters: path.distanceMeters,
      duration: path.duration,
      mapMatched: path.mapMatched,
      snappedWaypoints: moved,
    );
  }

  /// Przykleja narysowany szkic do dróg.
  ///
  /// Szkic z palca to setki punktów obok siebie; najpierw jest upraszczany,
  /// potem dopasowywany do sieci dróg przez map matching.
  Future<RoutedPath> snapSketch({
    required List<GeoPoint> sketch,
    required RoutePreferences preferences,
  }) async {
    if (sketch.length < 2) return RoutedPath.empty;

    // 25 m tolerancji zostawia kształt, ale wyrzuca drżenie palca.
    final simplified = samplePolyline(
      simplifyPolyline(sketch, 25),
      maxTracePoints,
    );

    try {
      final response = await _api.dio.post<dynamic>(
        '/valhalla/trace-route',
        data: {
          'shape': [
            for (final point in simplified)
              {'lat': point.lat, 'lon': point.lon},
          ],
          'costing': 'bicycle',
        },
      );

      final data = response.data;
      if (data is! Map || data['shape'] is! List) {
        return RoutedPath(
          points: simplified,
          maneuvers: const [],
          distanceMeters: totalDistanceMeters(simplified),
          duration: Duration.zero,
          mapMatched: false,
        );
      }

      final points = <GeoPoint>[];
      for (final entry in data['shape'] as List) {
        if (entry is! Map) continue;
        final lat = (entry['lat'] as num?)?.toDouble();
        final lon = (entry['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final point = GeoPoint(lat: lat, lon: lon);
        if (point.isValid) points.add(point);
      }
      if (points.length < 2) {
        return RoutedPath(
          points: simplified,
          maneuvers: const [],
          distanceMeters: totalDistanceMeters(simplified),
          duration: Duration.zero,
          mapMatched: false,
        );
      }

      return RoutedPath(
        points: points,
        maneuvers: const [],
        distanceMeters: totalDistanceMeters(points),
        duration: Duration.zero,
      );
    } catch (_) {
      // Bez sieci szkic zostaje szkicem — użytkownik i tak widzi kształt.
      return RoutedPath(
        points: simplified,
        maneuvers: const [],
        distanceMeters: totalDistanceMeters(simplified),
        duration: Duration.zero,
        mapMatched: false,
      );
    }
  }

  /// Dokłada wysokość do geometrii, która jej nie ma.
  ///
  /// Zwraca wejście bez zmian, gdy serwis wysokości nie odpowie — profil
  /// wysokości jest wtedy po prostu niedostępny, a nie zmyślony.
  Future<List<GeoPoint>> withElevation(List<GeoPoint> points) async {
    if (points.isEmpty) return points;
    if (points.every((point) => point.elevation != null)) return points;

    final result = <GeoPoint>[];
    for (var start = 0; start < points.length; start += elevationChunk) {
      final end = (start + elevationChunk).clamp(0, points.length);
      final chunk = points.sublist(start, end);
      try {
        final response = await _api.dio.post<dynamic>(
          '/valhalla/height',
          data: {
            'shape': [
              for (final point in chunk) {'lat': point.lat, 'lon': point.lon},
            ],
            'range': false,
          },
        );
        final data = response.data;
        final heights = data is Map ? data['height'] : null;
        if (heights is List && heights.length == chunk.length) {
          for (var i = 0; i < chunk.length; i++) {
            final height = heights[i];
            result.add(
              GeoPoint(
                lat: chunk[i].lat,
                lon: chunk[i].lon,
                elevation: height is num ? height.toDouble() : null,
                time: chunk[i].time,
              ),
            );
          }
          continue;
        }
      } catch (_) {
        // Brak wysokości nie unieważnia trasy.
      }
      result.addAll(chunk);
    }
    return result;
  }

  void clearCache() => _cache.clear();

  // ------------------------------------------------------------ prywatne

  RoutedPath _parseRoute(dynamic data) {
    if (data is! Map) return RoutedPath.empty;
    final trip = data['trip'];
    if (trip is! Map) return RoutedPath.empty;
    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) return RoutedPath.empty;

    final points = <GeoPoint>[];
    final maneuvers = <NavManeuver>[];

    for (final leg in legs.whereType<Map>()) {
      final offset = points.length;
      final shape = leg['shape'];
      if (shape is String) {
        points.addAll(decodeValhallaPolyline(shape));
      }
      final legManeuvers = leg['maneuvers'];
      if (legManeuvers is! List) continue;
      for (final maneuver in legManeuvers.whereType<Map>()) {
        final begin = (maneuver['begin_shape_index'] as num? ?? 0).toInt();
        final end = (maneuver['end_shape_index'] as num? ?? begin).toInt();
        maneuvers.add(
          NavManeuver(
            instruction: (maneuver['instruction'] as String? ?? '').trim(),
            beginShapeIndex: offset + begin,
            endShapeIndex: offset + end,
            type: (maneuver['type'] as num? ?? 0).toInt(),
            lengthKm: (maneuver['length'] as num? ?? 0).toDouble(),
            seconds: (maneuver['time'] as num? ?? 0).toDouble(),
            streetNames:
                (maneuver['street_names'] as List<dynamic>? ??
                        maneuver['begin_street_names'] as List<dynamic>? ??
                        const [])
                    .whereType<String>()
                    .toList(growable: false),
            verbalPost:
                maneuver['verbal_post_transition_instruction'] as String?,
            roundaboutExit: (maneuver['roundabout_exit_count'] as num?)
                ?.toInt(),
          ),
        );
      }
    }

    if (points.length < 2) return RoutedPath.empty;
    final summary = trip['summary'];
    return RoutedPath(
      points: points,
      maneuvers: maneuvers,
      distanceMeters: summary is Map
          ? ((summary['length'] as num?)?.toDouble() ?? 0) * 1000
          : totalDistanceMeters(points),
      duration: Duration(
        seconds: summary is Map
            ? ((summary['time'] as num?)?.toDouble() ?? 0).round()
            : 0,
      ),
    );
  }

  RoutedPath _straightLine(List<RouteWaypoint> waypoints) {
    final points = [for (final waypoint in waypoints) waypoint.point];
    return RoutedPath(
      points: points,
      maneuvers: const [],
      distanceMeters: totalDistanceMeters(points),
      duration: Duration.zero,
      mapMatched: false,
    );
  }

  String _cacheKey(List<RouteWaypoint> waypoints, RoutePreferences prefs) {
    final buffer = StringBuffer(jsonEncode(prefs.toJson()));
    for (final waypoint in waypoints) {
      buffer
        ..write(waypoint.lat.toStringAsFixed(5))
        ..write(',')
        ..write(waypoint.lon.toStringAsFixed(5))
        ..write(';');
    }
    return buffer.toString();
  }

  /// Zapamiętuje trasę i oddaje ją dalej.
  ///
  /// Zwraca to, co dostała, żeby wołający mógł napisać `return _remember(...)`
  /// zamiast dwóch linijek przy każdym z pięciu wyjść z łańcucha prób.
  RoutedPath _remember(String key, RoutedPath path) {
    // Cache trzyma ostatnie kilkanaście wariantów, bo kreator liczy trasę
    // po każdym przesunięciu punktu i użytkownik często cofa zmianę.
    if (_cache.length > 24) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = path;
    return path;
  }
}

/// Dekoduje polilinię Valhalli (precyzja 6).
/// Koduje punkty do polilinii Google/Valhalla.
///
/// Ślad przejazdu w JSON-ie to setki kilobajtów na przejazd; ta sama linia
/// jako polilinia mieści się w kilkunastu, a serwer i tak nie potrzebuje
/// pełnej precyzji surowego fixa.
String encodeValhallaPolyline(List<GeoPoint> points, {int precision = 6}) {
  final factor = _powerOfTen(precision);
  final buffer = StringBuffer();
  var previousLat = 0;
  var previousLon = 0;

  void writeValue(int value) {
    var shifted = value < 0 ? ~(value << 1) : value << 1;
    while (shifted >= 0x20) {
      buffer.writeCharCode((0x20 | (shifted & 0x1f)) + 63);
      shifted >>= 5;
    }
    buffer.writeCharCode(shifted + 63);
  }

  for (final point in points) {
    final lat = (point.lat * factor).round();
    final lon = (point.lon * factor).round();
    writeValue(lat - previousLat);
    writeValue(lon - previousLon);
    previousLat = lat;
    previousLon = lon;
  }
  return buffer.toString();
}

List<GeoPoint> decodeValhallaPolyline(String encoded, {int precision = 6}) {
  final points = <GeoPoint>[];
  final factor = _powerOfTen(precision);
  var index = 0;
  var lat = 0;
  var lon = 0;

  while (index < encoded.length) {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= encoded.length) return points;
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

    result = 0;
    shift = 0;
    do {
      if (index >= encoded.length) return points;
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lon += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

    final point = GeoPoint(lat: lat / factor, lon: lon / factor);
    if (point.isValid) points.add(point);
  }
  return points;
}

/// Potęga dziesiątki bez sięgania po `dart:math` w gorącej pętli.
double _powerOfTen(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}

/// Wynik jednej próby trasowania.
///
/// Trzy stany, nie dwa: znaleziona trasa, odmowa routera i brak sieci.
/// Bez tego rozróżnienia nie da się zdecydować, czy próbować dalej.
class _RouteAttempt {
  const _RouteAttempt.found(this.path) : offline = false;
  const _RouteAttempt.rejected() : path = null, offline = false;
  const _RouteAttempt.offline() : path = null, offline = true;

  final RoutedPath? path;
  final bool offline;
}

/// Punkty po dosunięciu do dróg, z informacją, które się ruszyły.
class _SnappedPoints {
  const _SnappedPoints({
    required this.points,
    required this.movedIndices,
    required this.changed,
  });

  final List<GeoPoint> points;

  /// Punkty przesunięte na tyle, żeby powiedzieć o tym użytkownikowi.
  final List<int> movedIndices;

  /// Czy cokolwiek się w ogóle ruszyło — warunek ponowienia próby.
  final bool changed;
}
