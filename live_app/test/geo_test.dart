import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';

void main() {
  group('haversineMeters', () {
    test('measures a known distance', () {
      const berlin = GeoPoint(lat: 52.5200, lon: 13.4050);
      const potsdam = GeoPoint(lat: 52.3906, lon: 13.0645);
      final distance = haversineMeters(berlin, potsdam);
      expect(distance, closeTo(27190, 300));
    });

    test('is zero for the same point', () {
      const point = GeoPoint(lat: 48.1, lon: 11.5);
      expect(haversineMeters(point, point), 0);
    });
  });

  group('projectOnPolyline', () {
    final line = <GeoPoint>[
      const GeoPoint(lat: 52.0, lon: 13.0),
      const GeoPoint(lat: 52.0, lon: 13.01),
      const GeoPoint(lat: 52.0, lon: 13.02),
    ];
    final cumulative = cumulativeDistances(line);

    test('projects onto a segment rather than snapping to a vertex', () {
      // Half way along the first segment, not at either end.
      final projection = projectOnPolyline(
        const GeoPoint(lat: 52.0, lon: 13.005),
        line,
        cumulative,
      );
      expect(projection, isNotNull);
      expect(projection!.segmentIndex, 0);
      expect(projection.alongMeters, closeTo(cumulative[1] / 2, 5));
      expect(projection.offRouteMeters, lessThan(5));
    });

    test('reports the perpendicular distance when off route', () {
      final projection = projectOnPolyline(
        const GeoPoint(lat: 52.0018, lon: 13.005),
        line,
        cumulative,
      );
      expect(projection!.offRouteMeters, closeTo(200, 40));
    });

    test('recovers when the rider is far outside the search window', () {
      final projection = projectOnPolyline(
        const GeoPoint(lat: 52.0, lon: 13.0005),
        line,
        cumulative,
        fromIndex: 2,
      );
      expect(projection!.segmentIndex, 0);
    });
  });

  group('ElevationAccumulator', () {
    test('ignores jitter below the threshold', () {
      final accumulator = ElevationAccumulator();
      for (final altitude in [100.0, 101.0, 99.5, 100.5, 100.0, 99.0]) {
        accumulator.add(altitude);
      }
      expect(accumulator.gainMeters, 0);
    });

    test('counts a sustained climb', () {
      final accumulator = ElevationAccumulator();
      for (var i = 0; i < 120; i++) {
        accumulator.add(100 + i.toDouble());
      }
      expect(accumulator.gainMeters, greaterThan(90));
      expect(accumulator.gainMeters, lessThan(125));
    });

    test('rejects impossible altitudes', () {
      final accumulator = ElevationAccumulator()
        ..add(100)
        ..add(99999)
        ..add(100);
      expect(accumulator.gainMeters, 0);
    });
  });

  group('simplifyPolyline', () {
    test('drops collinear points but keeps the ends', () {
      final points = <GeoPoint>[
        const GeoPoint(lat: 52.0, lon: 13.0),
        const GeoPoint(lat: 52.0, lon: 13.001),
        const GeoPoint(lat: 52.0, lon: 13.002),
        const GeoPoint(lat: 52.0, lon: 13.003),
      ];
      final simplified = simplifyPolyline(points, 20);
      expect(simplified.length, 2);
      expect(simplified.first.lon, 13.0);
      expect(simplified.last.lon, 13.003);
    });
  });

  group('samplePolyline', () {
    test('keeps the first and last sample', () {
      final points = [
        for (var i = 0; i < 1000; i++) GeoPoint(lat: 52 + i / 100000, lon: 13),
      ];
      final sampled = samplePolyline(points, 50);
      expect(sampled.length, 50);
      expect(sampled.first.lat, points.first.lat);
      expect(sampled.last.lat, points.last.lat);
    });
  });
}
