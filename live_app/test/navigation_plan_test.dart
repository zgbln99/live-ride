import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/models/ride_route.dart';

NavigationPlan buildPlan() => NavigationPlan.fromJson({
  'shape': [
    [52.0, 13.000],
    [52.0, 13.005],
    [52.0, 13.010],
    [52.005, 13.010],
  ],
  'maneuvers': [
    {
      'instruction': 'Head east',
      'begin_shape_index': 0,
      'end_shape_index': 2,
      'type': 1,
      'length': 0.7,
      'time': 120,
      'street_names': ['Hauptstrasse'],
    },
    {
      'instruction': 'Turn left',
      'begin_shape_index': 2,
      'end_shape_index': 3,
      'type': 15,
      'length': 0.55,
      'time': 100,
    },
    {
      'instruction': 'Arrive',
      'begin_shape_index': 3,
      'end_shape_index': 3,
      'type': 4,
      'length': 0,
      'time': 0,
    },
  ],
  'summary': {'length': 1.25, 'time': 220},
});

void main() {
  group('NavigationPlan.fromJson', () {
    test('reads shape, maneuvers and summary', () {
      final plan = buildPlan();
      expect(plan.shape.length, 4);
      expect(plan.maneuvers.length, 3);
      expect(plan.totalSeconds, 220);
      expect(plan.hasTurnByTurn, isTrue);
      expect(plan.maneuvers.first.streetName, 'Hauptstrasse');
    });

    test('drops maneuvers pointing outside the shape', () {
      final plan = NavigationPlan.fromJson({
        'shape': [
          [52.0, 13.0],
          [52.0, 13.001],
        ],
        'maneuvers': [
          {'instruction': 'Ghost', 'begin_shape_index': 99, 'type': 10},
        ],
      });
      expect(plan.maneuvers, isEmpty);
      expect(plan.hasTurnByTurn, isFalse);
    });
  });

  group('progressAt', () {
    test('uses the projected position for route progress', () {
      final plan = buildPlan();
      // Half way along the first segment.
      final progress = plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.0025));
      expect(progress.alongMeters, closeTo(plan.cumulativeMeters[1] / 2, 10));
      expect(
        progress.remainingMeters,
        closeTo(plan.totalMeters - progress.alongMeters, 1),
      );
      expect(progress.offRoute, isFalse);
    });

    test('announces the next maneuver, not the one just passed', () {
      final plan = buildPlan();
      final progress = plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.006));
      expect(progress.current?.instruction, 'Head east');
      expect(progress.next?.instruction, 'Turn left');
      expect(progress.distanceToManeuver, greaterThan(0));
    });

    test('flags being off route with the perpendicular distance', () {
      final plan = buildPlan();
      final progress = plan.progressAt(
        const GeoPoint(lat: 52.004, lon: 13.002),
      );
      expect(progress.offRoute, isTrue);
      expect(progress.offRouteMeters, greaterThan(80));
    });

    test('estimates remaining time from the routed duration', () {
      final plan = buildPlan();
      final start = plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.0));
      final late = plan.progressAt(const GeoPoint(lat: 52.0049, lon: 13.010));
      expect(start.remainingSeconds, closeTo(220, 5));
      expect(late.remainingSeconds!, lessThan(start.remainingSeconds!));
    });

    test('fraction advances monotonically along the route', () {
      final plan = buildPlan();
      final early = plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.001));
      final later = plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.008));
      expect(later.fraction, greaterThan(early.fraction));
      expect(later.fraction, lessThanOrEqualTo(1));
    });
  });

  group('NavigationPlan.fromRoute', () {
    test('keeps the imported geometry and says it is not map matched', () {
      final route = RideRoute(
        id: 'r1',
        name: 'Imported',
        points: const [
          GeoPoint(lat: 52.0, lon: 13.0),
          GeoPoint(lat: 52.0, lon: 13.01),
        ],
      );
      final plan = NavigationPlan.fromRoute(route);
      expect(plan.mapMatched, isFalse);
      expect(plan.shape.length, 2);
      expect(plan.hasTurnByTurn, isFalse);
      expect(plan.totalMeters, closeTo(route.distanceMeters, 0.1));
    });
  });
}
