import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/ride_route.dart';
import 'package:live_ride/services/climb_tracker.dart';

const double _lat = 52.0;
final double _degPerMeter = 1 / (111320 * math.cos(_lat * math.pi / 180));

GeoPoint _at(double meters, double elevation) => GeoPoint(
  lat: _lat,
  lon: 21.0 + meters * _degPerMeter,
  elevation: elevation,
);

/// Płasko przez 4 km, 3 km podjazdu po 7 %, potem 3 km płasko.
RideRoute _route() {
  final points = <GeoPoint>[];
  for (var meters = 0; meters <= 10000; meters += 50) {
    final double elevation;
    if (meters <= 4000) {
      elevation = 100;
    } else if (meters <= 7000) {
      elevation = 100 + (meters - 4000) * 0.07;
    } else {
      elevation = 100 + 3000 * 0.07;
    }
    points.add(_at(meters.toDouble(), elevation));
  }
  return RideRoute(id: 'r1', name: 'Test', points: points);
}

void main() {
  test('trasa testowa faktycznie ma jeden podjazd', () {
    final route = _route();
    expect(route.analysis.climbs, hasLength(1));
    final climb = route.analysis.climbs.single;
    expect(climb.startDistanceMeters, closeTo(4000, 200));
    expect(climb.endDistanceMeters, closeTo(7000, 200));
    expect(climb.averageGradientPercent, closeTo(7, 0.5));
  });

  group('ClimbTracker', () {
    test('bez trasy nic nie raportuje', () {
      final tracker = ClimbTracker()..attach(null);
      expect(tracker.update(_at(4500, 135)), isNull);
      expect(tracker.hasRoute, isFalse);
    });

    test('na płaskim przed podjazdem nie ma aktywnego podjazdu', () {
      final tracker = ClimbTracker()..attach(_route());
      expect(tracker.update(_at(500, 100)), isNull);
      expect(tracker.activeClimb, isNull);
      expect(tracker.alongMeters, closeTo(500, 30));
    });

    test('zapowiada podjazd dopiero, gdy jest blisko', () {
      final tracker = ClimbTracker()..attach(_route());
      tracker.update(_at(100, 100));
      expect(tracker.upcomingClimb, isNull, reason: '3.9 km to za daleko');

      tracker.update(_at(3500, 100));
      expect(tracker.upcomingClimb, isNotNull);
      expect(tracker.metersToUpcoming, closeTo(500, 250));
    });

    test('wchodzi w podjazd i liczy, ile zostało', () {
      final tracker = ClimbTracker()..attach(_route());
      tracker.update(_at(3000, 100));
      final progress = tracker.update(_at(5000, 170));
      expect(progress, isNotNull);
      expect(tracker.activeClimb, isNotNull);
      expect(progress!.doneMeters, closeTo(1000, 250));
      expect(progress.remainingMeters, closeTo(2000, 250));
      expect(progress.remainingGainMeters, greaterThan(100));
      expect(progress.fraction, closeTo(0.33, 0.1));
      expect(progress.currentGradientPercent, closeTo(7, 1.5));
    });

    test('na szczycie zamyka podjazd i zapisuje wynik', () {
      final tracker = ClimbTracker()..attach(_route());
      final start = DateTime(2026, 5, 1, 10);
      tracker.update(_at(4100, 107), now: start);
      tracker.update(
        _at(5500, 205),
        now: start.add(const Duration(minutes: 5)),
      );
      expect(tracker.activeClimb, isNotNull);

      tracker.update(
        _at(8000, 310),
        now: start.add(const Duration(minutes: 12)),
      );
      expect(tracker.activeClimb, isNull);
      expect(tracker.progress, isNull);
      expect(tracker.finished, hasLength(1));

      final result = tracker.finished.single;
      expect(result.duration, const Duration(minutes: 12));
      expect(result.vam, isNotNull);
      expect(result.vam, closeTo(1050, 150));
    });

    test('krótkie musnięcie podjazdu nie tworzy wyniku', () {
      final tracker = ClimbTracker()..attach(_route());
      final start = DateTime(2026, 5, 1, 10);
      tracker.update(_at(4100, 107), now: start);
      tracker.update(
        _at(8000, 310),
        now: start.add(const Duration(seconds: 5)),
      );
      expect(tracker.finished, isEmpty);
    });

    test('cofnięcie GPS tuż za szczytem nie zamyka podjazdu dwa razy', () {
      final tracker = ClimbTracker()..attach(_route());
      final start = DateTime(2026, 5, 1, 10);
      tracker.update(_at(4100, 107), now: start);
      tracker.update(
        _at(6950, 306),
        now: start.add(const Duration(minutes: 9)),
      );
      // 30 m za szczytem mieści się w tolerancji.
      tracker.update(
        _at(7020, 310),
        now: start.add(const Duration(minutes: 9, seconds: 20)),
      );
      expect(tracker.activeClimb, isNotNull);
      expect(tracker.finished, isEmpty);

      tracker.update(
        _at(7400, 310),
        now: start.add(const Duration(minutes: 10)),
      );
      expect(tracker.finished, hasLength(1));
    });

    test('szacowany czas do szczytu bierze tempo z tego podjazdu', () {
      final tracker = ClimbTracker()..attach(_route());
      final start = DateTime(2026, 5, 1, 10);
      tracker.update(_at(4000, 100), now: start);
      // 500 m w 5 minut to 6 km/h.
      final progress = tracker.update(
        _at(4500, 135),
        now: start.add(const Duration(minutes: 5)),
        averageSpeedKmh: 28,
      );
      expect(progress!.averageSpeedKmh, closeTo(6, 1));
      // 2.5 km przy 6 km/h to około 25 minut, nie 5 przy średniej z jazdy.
      expect(progress.estimatedRemaining!.inMinutes, greaterThan(15));
    });

    test('podmiana trasy czyści stan', () {
      final tracker = ClimbTracker()..attach(_route());
      tracker.update(_at(5000, 170));
      expect(tracker.activeClimb, isNotNull);
      tracker.attach(RideRoute(id: 'r2', name: 'Inna', points: []));
      expect(tracker.activeClimb, isNull);
      expect(tracker.alongMeters, isNull);
      expect(tracker.finished, isEmpty);
    });
  });
}
