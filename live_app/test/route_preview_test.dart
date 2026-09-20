import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/core/route_preview.dart';

/// Kształt trasy dla ekranu blokady.
///
/// Widget rysuje ścieżkę w SwiftUI, a nie kafelki mapy, więc dostaje kształt
/// w kwadracie jednostkowym. Dwie rzeczy muszą się zgadzać: proporcje (trasa
/// rozciągnięta wygląda jak inna droga) i rozmiar ładunku (ActivityKit liczy
/// każdy bajt stanu aktywności).

List<GeoPoint> _line({
  double fromLat = 52.0,
  double toLat = 52.0,
  double fromLon = 21.0,
  double toLon = 21.1,
  int points = 50,
}) => [
  for (var i = 0; i < points; i++)
    GeoPoint(
      lat: fromLat + (toLat - fromLat) * i / (points - 1),
      lon: fromLon + (toLon - fromLon) * i / (points - 1),
    ),
];

void main() {
  group('rozmiar ładunku', () {
    test('trasa z tysięcy punktów schodzi do sześćdziesięciu', () {
      final preview = RoutePreview.fromRoute(_line(points: 12000));
      expect(preview.points.length, RoutePreview.maxPoints);
      // Kilkaset bajtów, a nie kilkaset kilobajtów.
      expect(preview.encode().length, lessThan(800));
    });

    test('krótka trasa nie jest sztucznie rozdmuchiwana', () {
      final preview = RoutePreview.fromRoute(_line(points: 12));
      expect(preview.points.length, 12);
    });

    test('ostatni punkt zawsze zostaje', () {
      // Bez niego ścieżka kończy się przed metą, a znacznik celu wisi
      // w powietrzu obok linii.
      final route = _line(points: 1001);
      final preview = RoutePreview.fromRoute(route);
      final last = preview.points.last;
      expect(last.x, closeTo(1.0, 0.02));
    });
  });

  group('kształt', () {
    test('trasa ze wschodu na zachód leży poziomo', () {
      final preview = RoutePreview.fromRoute(_line());
      final ys = preview.points.map((p) => p.y).toSet();
      expect(ys.length, 1, reason: 'jedna wysokość dla poziomej linii');
      expect(preview.points.first.x, closeTo(0, 0.001));
      expect(preview.points.last.x, closeTo(1, 0.001));
    });

    test('trasa z południa na północ leży pionowo, a nie na całą szerokość', () {
      final preview = RoutePreview.fromRoute(
        _line(fromLat: 52.0, toLat: 52.1, toLon: 21.0),
      );
      final xs = preview.points.map((p) => p.x).toSet();
      expect(xs.length, 1);
      // Wyśrodkowana, nie przyklejona do lewej krawędzi.
      expect(preview.points.first.x, closeTo(0.5, 0.001));
    });

    test('północ jest na górze', () {
      // Szerokość geograficzna rośnie na północ, a y na ekranie rośnie w dół.
      final preview = RoutePreview.fromRoute(
        _line(fromLat: 52.0, toLat: 52.1, toLon: 21.0),
      );
      expect(preview.points.first.y, greaterThan(preview.points.last.y));
    });

    test('kwadratowa pętla zostaje kwadratem', () {
      // Bez poprawki na szerokość geograficzną stopień długości wyszedłby
      // tak samo długi jak stopień szerokości i pętla spłaszczyłaby się
      // o jakieś czterdzieści procent.
      const latSpan = 0.01;
      final lonSpan = latSpan / 0.6157; // cos(52°)
      final loop = [
        const GeoPoint(lat: 52.0, lon: 21.0),
        GeoPoint(lat: 52.0, lon: 21.0 + lonSpan),
        GeoPoint(lat: 52.0 + latSpan, lon: 21.0 + lonSpan),
        const GeoPoint(lat: 52.0 + latSpan, lon: 21.0),
        const GeoPoint(lat: 52.0, lon: 21.0),
      ];
      final preview = RoutePreview.fromRoute(loop);

      final width = preview.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
      final height =
          1 - preview.points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      expect(width, closeTo(height, 0.05));
    });

    test('wszystko mieści się w kwadracie jednostkowym', () {
      final preview = RoutePreview.fromRoute(_line(toLat: 52.05));
      for (final point in preview.points) {
        expect(point.x, inInclusiveRange(0, 1));
        expect(point.y, inInclusiveRange(0, 1));
      }
    });
  });

  group('zapis', () {
    test('przechodzi tam i z powrotem bez utraty kształtu', () {
      final preview = RoutePreview.fromRoute(_line(toLat: 52.04, points: 40));
      final restored = RoutePreview.decode(preview.encode());

      expect(restored.points.length, preview.points.length);
      for (var i = 0; i < preview.points.length; i++) {
        expect(restored.points[i].x, closeTo(preview.points[i].x, 0.001));
        expect(restored.points[i].y, closeTo(preview.points[i].y, 0.001));
      }
    });

    test('pusty kształt zapisuje się jako pusty ciąg', () {
      // Widget poznaje po tym, że ma pokazać zwykły ekran przejazdu, a nie
      // pusty prostokąt po poprzedniej trasie.
      expect(RoutePreview.empty.encode(), isEmpty);
      expect(RoutePreview.fromRoute([]).encode(), isEmpty);
      expect(
        RoutePreview.fromRoute([const GeoPoint(lat: 52, lon: 21)]).encode(),
        isEmpty,
      );
    });

    test('uszkodzony zapis nie wywraca odczytu', () {
      expect(RoutePreview.decode('nonsens').points, isEmpty);
      expect(RoutePreview.decode('100,200;zepsute;300,400').points.length, 2);
    });
  });
}
