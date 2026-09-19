import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/geo.dart';
import '../models/navigation_plan.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';

/// Błąd trasowania w formie, którą można pokazać użytkownikowi.
class RoutingException implements Exception {
  const RoutingException(this.message);

  final String message;

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
  });

  final List<GeoPoint> points;
  final List<NavManeuver> maneuvers;
  final double distanceMeters;
  final Duration duration;

  /// Fałsz, gdy router zawiódł i jedziemy po linii prostej między punktami.
  final bool mapMatched;

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

  /// Liczy trasę przez podane waypointy.
  ///
  /// Gdy router nie odpowie, zwraca prostą linię przez waypointy z
  /// `mapMatched: false` — kreator ma nadal działać bez sieci, tylko
  /// uczciwie mówi, że to jeszcze nie jest trasa po drogach.
  Future<RoutedPath> route({
    required List<RouteWaypoint> waypoints,
    required RoutePreferences preferences,
    String language = 'pl-PL',
  }) async {
    final usable = waypoints.where((w) => w.point.isValid).toList();
    if (usable.length < 2) return RoutedPath.empty;

    final key = _cacheKey(usable, preferences);
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final response = await _api.dio.post<dynamic>(
        '/valhalla/route',
        data: {
          'locations': [
            for (var i = 0; i < usable.length; i++)
              {
                'lat': usable[i].lat,
                'lon': usable[i].lon,
                // „break” każe Valhalli zatrzymać się w punkcie i pozwolić
                // na zawrotkę; „through” przejeżdża przez punkt bez przerwy.
                'type': i == 0 || i == usable.length - 1 ? 'break' : 'through',
              },
          ],
          'costing': 'bicycle',
          'costing_options': {'bicycle': preferences.toValhallaCosting()},
          'directions_options': {'units': 'kilometers', 'language': language},
          'elevation_interval': 30,
        },
      );

      final path = _parseRoute(response.data);
      if (path.isEmpty) return _straightLine(usable);
      _remember(key, path);
      return path;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        throw const RoutingException(
          'Router nie potrafi poprowadzić trasy przez te punkty. '
          'Przesuń je bliżej drogi.',
        );
      }
      return _straightLine(usable);
    } catch (_) {
      return _straightLine(usable);
    }
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

  void _remember(String key, RoutedPath path) {
    // Cache trzyma ostatnie kilkanaście wariantów, bo kreator liczy trasę
    // po każdym przesunięciu punktu i użytkownik często cofa zmianę.
    if (_cache.length > 24) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = path;
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
