import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/geo.dart';

/// Miejsce znalezione w wyszukiwarce.
class Place {
  const Place({
    required this.name,
    required this.point,
    this.detail = '',
    this.kind = '',
  });

  final String name;
  final String detail;
  final String kind;
  final GeoPoint point;

  String get label => detail.isEmpty ? name : '$name · $detail';
}

/// Wyszukiwanie adresów przez Nominatim na własnym serwerze.
///
/// Nominatim prosi o nieprzesadzanie z liczbą zapytań, więc wyniki dla tej
/// samej frazy są zapamiętywane, a wpisywanie jest dławione po stronie UI.
class GeocodingService {
  GeocodingService(this._api);

  final ApiClient _api;
  final Map<String, List<Place>> _cache = {};

  Future<List<Place>> search(String query, {GeoPoint? near}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    final cached = _cache[trimmed.toLowerCase()];
    if (cached != null) return cached;

    try {
      final response = await _api.dio.get<dynamic>(
        '/geocoding/search',
        queryParameters: {'q': trimmed, 'limit': 8},
      );
      final places = _parse(response.data);
      if (near != null && places.length > 1) {
        // Nominatim nie zna kontekstu jazdy; najbliższy wynik zwykle jest
        // tym, o który chodziło.
        places.sort(
          (a, b) => haversineMeters(
            near,
            a.point,
          ).compareTo(haversineMeters(near, b.point)),
        );
      }
      _remember(trimmed.toLowerCase(), places);
      return places;
    } on DioException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Nazwa miejsca dla współrzędnych — używana przy nazywaniu waypointów.
  Future<String?> describe(GeoPoint point) async {
    try {
      final response = await _api.dio.get<dynamic>(
        '/geocoding/reverse',
        queryParameters: {
          'lat': point.lat.toStringAsFixed(6),
          'lon': point.lon.toStringAsFixed(6),
        },
      );
      final places = _parse(response.data);
      return places.isEmpty ? null : places.first.name;
    } catch (_) {
      return null;
    }
  }

  List<Place> _parse(dynamic data) {
    if (data is! Map) return [];
    final features = data['features'];
    if (features is! List) return [];

    final places = <Place>[];
    for (final feature in features.whereType<Map>()) {
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) continue;

      final point = GeoPoint(
        lat: (coordinates[1] as num).toDouble(),
        lon: (coordinates[0] as num).toDouble(),
      );
      if (!point.isValid) continue;

      final display = properties['display_name'] as String? ?? '';
      final parts = display.split(',').map((part) => part.trim()).toList();
      places.add(
        Place(
          name:
              properties['name'] as String? ??
              (parts.isEmpty ? display : parts.first),
          detail: parts.length > 1 ? parts.skip(1).take(2).join(', ') : '',
          kind: properties['type'] as String? ?? '',
          point: point,
        ),
      );
    }
    return places;
  }

  void _remember(String key, List<Place> places) {
    if (_cache.length > 40) _cache.remove(_cache.keys.first);
    _cache[key] = places;
  }
}
