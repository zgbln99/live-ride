import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_waypoint.dart';
import 'package:live_ride/services/routing_service.dart';

/// Łańcuch prób trasowania.
///
/// Zgłoszenie brzmiało: „Router nie potrafi poprowadzić trasy przez te punkty.
/// Przesuń je bliżej drogi." przy zwyczajnym planowaniu. Punkt postawiony
/// palcem na telefonie ląduje kilkanaście metrów obok ścieżki i to jest
/// normalne — router ma sobie z tym poradzić, a nie odsyłać człowieka do
/// poprawiania współrzędnych.
///
/// Atrapa poniżej odmawia dokładnie tak jak Valhalla: statusem 400 i pustym
/// ciałem, bez żadnej wskazówki, który punkt jest problemem.

/// Serwer, który odpowiada według reguł podanych w teście.
class _Valhalla implements HttpClientAdapter {
  _Valhalla(this.handle);

  /// Dostaje ścieżkę i ciało żądania, oddaje odpowiedź.
  final ResponseBody Function(String path, Map<String, dynamic> body) handle;

  final List<({String path, Map<String, dynamic> body})> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = (options.data as Map).cast<String, dynamic>();
    requests.add((path: options.path, body: body));
    return handle(options.path, body);
  }

  @override
  void close({bool force = false}) {}

  /// Żądania trasowania, w kolejności.
  List<Map<String, dynamic>> get routeCalls => [
    for (final request in requests)
      if (request.path.endsWith('/route')) request.body,
  ];

  /// Promienie szukania z kolejnych prób — null, gdy próba ich nie podała.
  List<int?> get radii => [
    for (final call in routeCalls)
      ((call['locations'] as List).first as Map)['radius'] as int?,
  ];
}

ResponseBody _json(Object body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _rejected() => _json(
  {'error_code': 171, 'error': 'No suitable edges near location'},
  status: 400,
);

/// Prawidłowa odpowiedź Valhalli z prostą geometrią między dwoma punktami.
Object _trip(List<GeoPoint> shape, {double km = 1.0}) => {
  'trip': {
    'legs': [
      {
        'shape': _encode(shape),
        'summary': {'length': km, 'time': km * 180},
        'maneuvers': [
          {
            'instruction': 'Turn left onto Polna.',
            'type': 15,
            'street_names': ['Polna'],
            'begin_shape_index': 0,
            'end_shape_index': shape.length - 1,
            'length': km,
            'time': km * 180,
          },
        ],
      },
    ],
    'summary': {'length': km, 'time': km * 180},
  },
};

/// Polilinia Valhalli — precyzja 6.
String _encode(List<GeoPoint> points) {
  final buffer = StringBuffer();
  var previousLat = 0;
  var previousLon = 0;
  for (final point in points) {
    final lat = (point.lat * 1e6).round();
    final lon = (point.lon * 1e6).round();
    _chunk(buffer, lat - previousLat);
    _chunk(buffer, lon - previousLon);
    previousLat = lat;
    previousLon = lon;
  }
  return buffer.toString();
}

void _chunk(StringBuffer buffer, int value) {
  var v = value < 0 ? ~(value << 1) : value << 1;
  while (v >= 0x20) {
    buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  buffer.writeCharCode(v + 63);
}

RoutingService _service(_Valhalla adapter) {
  final api = ApiClient();
  api.dio = Dio(BaseOptions(baseUrl: 'https://ride.example/api/v1'))
    ..httpClientAdapter = adapter;
  return RoutingService(api);
}

List<RouteWaypoint> _waypoints(List<GeoPoint> points) => [
  for (var i = 0; i < points.length; i++)
    RouteWaypoint(point: points[i]),
];

const _a = GeoPoint(lat: 52.2300, lon: 21.0100);
const _b = GeoPoint(lat: 52.2400, lon: 21.0200);
const _c = GeoPoint(lat: 52.2500, lon: 21.0300);

const _prefs = RoutePreferences();

void main() {
  group('punkt leżący na drodze', () {
    test('przechodzi za pierwszym razem, bez promienia', () async {
      final adapter = _Valhalla((path, body) => _json(_trip([_a, _b])));
      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );

      expect(path.points.length, greaterThanOrEqualTo(2));
      expect(path.mapMatched, isTrue);
      expect(path.snappedWaypoints, isEmpty);
      expect(adapter.routeCalls.length, 1, reason: 'jedna próba wystarcza');
      expect(adapter.radii, [null], reason: 'bez rozszerzania szukania');
    });
  });

  group('punkt obok drogi', () {
    /// Serwer, który przyjmuje dopiero od zadanego promienia.
    _Valhalla acceptsFrom(int minimumRadius) => _Valhalla((path, body) {
      if (!path.endsWith('/route')) return _rejected();
      final radius =
          ((body['locations'] as List).first as Map)['radius'] as int? ?? 0;
      return radius >= minimumRadius ? _json(_trip([_a, _b])) : _rejected();
    });

    test('10 m obok: druga próba z promieniem 25 m znajduje trasę', () async {
      final adapter = acceptsFrom(25);
      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );

      expect(path.mapMatched, isTrue);
      expect(adapter.radii.take(2).toList(), [null, 25]);
      expect(adapter.routeCalls.length, 2, reason: 'nie próbuj dalej po sukcesie');
    });

    test('30 m obok: trzecia próba z promieniem 50 m', () async {
      final adapter = acceptsFrom(50);
      await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );
      expect(adapter.radii, [null, 25, 50]);
    });

    test('75 m obok: czwarta próba z promieniem 100 m', () async {
      final adapter = acceptsFrom(100);
      await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );
      expect(adapter.radii, [null, 25, 50, 100]);
    });

    test('promień idzie razem z szerszym oknem korelacji', () async {
      final adapter = acceptsFrom(25);
      await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );
      final second = (adapter.routeCalls[1]['locations'] as List).first as Map;
      expect(second['radius'], 25);
      expect(second['search_cutoff'], greaterThan(25));
    });
  });

  group('dosuwanie do drogi', () {
    test('pyta Valhallę, która krawędź jest najbliżej, i ponawia', () async {
      // Trasa przechodzi dopiero po przesunięciu punktu — dokładnie tak
      // wygląda waypoint postawiony na parkingu obok ścieżki.
      const snapped = GeoPoint(lat: 52.2402, lon: 21.0203);
      var located = false;

      final adapter = _Valhalla((path, body) {
        if (path.endsWith('/locate')) {
          located = true;
          return _json([
            {
              'edges': [
                {'correlated_lat': _a.lat, 'correlated_lon': _a.lon},
              ],
            },
            {
              'edges': [
                {'correlated_lat': snapped.lat, 'correlated_lon': snapped.lon},
              ],
            },
          ]);
        }
        if (!located) return _rejected();
        final second = (body['locations'] as List)[1] as Map;
        final movedHere = (second['lat'] as num).toDouble() == snapped.lat;
        return movedHere ? _json(_trip([_a, snapped])) : _rejected();
      });

      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );

      expect(path.mapMatched, isTrue);
      // Kreator ma czym pokazać, że punkt został dosunięty.
      expect(path.snappedWaypoints, [1]);
    });

    test('dosunięcie o kilka metrów nie jest zgłaszane', () async {
      // Korekta w granicach szumu to nie jest informacja dla użytkownika.
      const nudged = GeoPoint(lat: 52.24002, lon: 21.02002);
      var located = false;
      final adapter = _Valhalla((path, body) {
        if (path.endsWith('/locate')) {
          located = true;
          return _json([
            {
              'edges': [
                {'correlated_lat': _a.lat, 'correlated_lon': _a.lon},
              ],
            },
            {
              'edges': [
                {'correlated_lat': nudged.lat, 'correlated_lon': nudged.lon},
              ],
            },
          ]);
        }
        return located ? _json(_trip([_a, nudged])) : _rejected();
      });

      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );
      expect(path.snappedWaypoints, isEmpty);
    });
  });

  group('trasowanie odcinkami', () {
    test('całość odmawia, a odcinki parami przechodzą', () async {
      final adapter = _Valhalla((path, body) {
        if (path.endsWith('/locate')) return _rejected();
        final count = (body['locations'] as List).length;
        // Trzy punkty naraz — nie. Dwa punkty — proszę bardzo.
        if (count > 2) return _rejected();
        return _json(_trip([_a, _b]));
      });

      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b, _c]),
        preferences: _prefs,
      );

      expect(path.mapMatched, isTrue);
      expect(path.distanceMeters, greaterThan(0));
      // Dwa odcinki sklejone: punkt styku nie może się zdublować.
      final duplicated = <GeoPoint>{};
      for (final point in path.points) {
        expect(duplicated.add(point), isTrue, reason: 'duplikat $point');
      }
    });

    test('manewry z drugiego odcinka wskazują na właściwe miejsce', () async {
      final adapter = _Valhalla((path, body) {
        if (path.endsWith('/locate')) return _rejected();
        final locations = body['locations'] as List;
        if (locations.length > 2) return _rejected();
        return _json(_trip([_a, _b, _c]));
      });

      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b, _c]),
        preferences: _prefs,
      );

      expect(path.maneuvers.length, 2);
      // Drugi manewr nie może wskazywać na początek geometrii.
      expect(path.maneuvers[1].beginShapeIndex, greaterThan(0));
      expect(
        path.maneuvers[1].beginShapeIndex,
        lessThan(path.points.length),
      );
    });
  });

  group('kiedy naprawdę się nie da', () {
    test('błąd wskazuje konkretny punkt', () async {
      // Drugi odcinek nie istnieje dla roweru — pierwszy owszem.
      final adapter = _Valhalla((path, body) {
        if (path.endsWith('/locate')) return _rejected();
        final locations = body['locations'] as List;
        if (locations.length != 2) return _rejected();
        final to = locations[1] as Map;
        final reaches = (to['lat'] as num).toDouble() == _b.lat;
        return reaches ? _json(_trip([_a, _b])) : _rejected();
      });

      await expectLater(
        _service(adapter).route(
          waypoints: _waypoints([_a, _b, _c]),
          preferences: _prefs,
        ),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.waypointIndex, 'waypointIndex', 2)
              .having((e) => e.message, 'message', contains('punktu 3')),
        ),
      );
    });

    test('komunikat nie każe przesuwać punktu o pięć metrów', () async {
      final adapter = _Valhalla((path, body) => _rejected());
      try {
        await _service(adapter).route(
          waypoints: _waypoints([_a, _b]),
          preferences: _prefs,
        );
        fail('trasowanie powinno się nie udać');
      } on RoutingException catch (e) {
        expect(e.message, isNot(contains('Przesuń je bliżej drogi')));
        expect(e.message, contains('rower'));
      }
    });

    test('wyczerpuje wszystkie próby, zanim zgłosi błąd', () async {
      final adapter = _Valhalla((path, body) => _rejected());
      try {
        await _service(adapter).route(
          waypoints: _waypoints([_a, _b]),
          preferences: _prefs,
        );
      } on RoutingException {
        // oczekiwane
      }
      // Cztery promienie + szukanie winnego. Nigdy jedna próba.
      expect(
        adapter.routeCalls.length,
        greaterThanOrEqualTo(RoutingService.searchRadiiMeters.length),
      );
      expect(
        adapter.requests.any((r) => r.path.endsWith('/locate')),
        isTrue,
        reason: 'dosuwanie do drogi jest częścią łańcucha',
      );
    });
  });

  group('brak sieci', () {
    test('nie zamienia się w błąd trasowania ani w serię prób', () async {
      final adapter = _Valhalla((path, body) {
        throw DioException.connectionError(
          requestOptions: RequestOptions(path: path),
          reason: 'brak sieci',
        );
      });

      final path = await _service(adapter).route(
        waypoints: _waypoints([_a, _b]),
        preferences: _prefs,
      );

      // Szkic zostaje szkicem i mówi to wprost, zamiast udawać trasę.
      expect(path.mapMatched, isFalse);
      expect(path.points.length, 2);
      expect(adapter.routeCalls.length, 1, reason: 'bez ponawiania w kółko');
    });
  });

  group('profil rowerowy', () {
    test('każda próba trasuje rowerem, także dosuwanie i odcinki', () async {
      final adapter = _Valhalla((path, body) {
        if (path.endsWith('/locate')) {
          return _json([
            {'edges': []},
            {'edges': []},
          ]);
        }
        final locations = body['locations'] as List;
        return locations.length > 2 ? _rejected() : _json(_trip([_a, _b]));
      });

      await _service(adapter).route(
        waypoints: _waypoints([_a, _b, _c]),
        preferences: _prefs,
      );

      for (final request in adapter.requests) {
        expect(
          request.body['costing'],
          'bicycle',
          reason: '${request.path} trasuje czymś innym niż rowerem',
        );
      }
    });
  });
}
