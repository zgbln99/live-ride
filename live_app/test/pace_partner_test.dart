import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/pace_partner.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/models/ride_route.dart';
import 'package:live_ride/services/pace_partner.dart';

RecordedRide _ride({int points = 60, double metersPerSecond = 8}) {
  final start = DateTime(2026, 5, 1, 9);
  return RecordedRide(
    id: 'ride-1',
    name: 'Wczoraj',
    startedAt: start,
    endedAt: start.add(Duration(seconds: points)),
    elapsedSeconds: points,
    movingSeconds: points,
    distanceMeters: points * metersPerSecond,
    elevationGainMeters: 0,
    points: [
      for (var i = 0; i < points; i++)
        RecordedRidePoint(
          lat: 52.0 + i / 100000,
          lon: 21.0,
          recordedAt: start.add(Duration(seconds: i)),
          distanceMeters: i * metersPerSecond,
        ),
    ],
  );
}

void main() {
  group('cel tempa', () {
    const target = PaceTarget(
      kind: PaceTargetKind.speed,
      label: '30 km/h',
      routeDistanceMeters: 30000,
      targetSpeedKmh: 30,
    );

    test('rywal jedzie równo według zadanej prędkości', () {
      expect(target.distanceAt(const Duration(minutes: 2)), closeTo(1000, 1));
      expect(target.timeAt(15000)!.inMinutes, 30);
    });

    test('czas na trasie przelicza się na prędkość', () {
      const byTime = PaceTarget(
        kind: PaceTargetKind.time,
        label: 'godzina',
        routeDistanceMeters: 30000,
        targetDuration: Duration(hours: 1),
      );
      expect(byTime.impliedSpeedKmh, closeTo(30, 0.001));
    });

    test('bez prędkości i bez czasu rywal nie istnieje', () {
      const empty = PaceTarget(
        kind: PaceTargetKind.speed,
        label: 'nic',
        routeDistanceMeters: 30000,
      );
      expect(empty.distanceAt(const Duration(minutes: 5)), isNull);
      expect(empty.timeAt(1000), isNull);
    });
  });

  group('ghost z przejazdu', () {
    test('nie powstaje z przejazdu bez punktów', () {
      final thin = RecordedRide(
        id: 'x',
        name: 'Krótki',
        startedAt: DateTime(2026, 5, 1),
        endedAt: DateTime(2026, 5, 1),
        elapsedSeconds: 0,
        movingSeconds: 0,
        distanceMeters: 0,
        elevationGainMeters: 0,
        points: const [],
      );
      expect(PacePartnerService.fromRide(thin, label: 'x'), isNull);
    });

    test('odtwarza przebieg prawdziwej jazdy', () {
      final target = PacePartnerService.fromRide(_ride(), label: 'Wczoraj')!;
      expect(target.kind, PaceTargetKind.previousRide);
      expect(target.referenceTrack, isNotEmpty);
      expect(target.distanceAt(const Duration(seconds: 10)), closeTo(80, 1));
      expect(target.timeAt(240)!.inSeconds, 30);
    });

    test('ghost po mecie stoi na mecie, nie jedzie dalej', () {
      final target = PacePartnerService.fromRide(_ride(), label: 'Wczoraj')!;
      final finish = target.referenceTrack.last.distanceMeters;
      expect(
        target.distanceAt(const Duration(minutes: 30)),
        closeTo(finish, 0.001),
      );
    });
  });

  group('porównanie', () {
    late PacePartnerService service;

    setUp(() {
      service = PacePartnerService();
    });

    test('bez rywala nie ma porównania', () {
      expect(
        service.compare(riderMeters: 100, elapsed: const Duration(minutes: 1)),
        isNull,
      );
      expect(service.isActive, isFalse);
    });

    test('szybszy zawodnik ma przewagę i ujemną deltę', () {
      service.start(
        const PaceTarget(
          kind: PaceTargetKind.speed,
          label: '20 km/h',
          routeDistanceMeters: 10000,
          targetSpeedKmh: 20,
        ),
      );
      // Po 2 minutach rywal jest na 666 m; zawodnik na 800 m.
      final comparison = service.compare(
        riderMeters: 800,
        elapsed: const Duration(minutes: 2),
      )!;
      expect(comparison.isAhead, isTrue);
      expect(comparison.distanceDelta, greaterThan(100));
      expect(comparison.timeDelta!.isNegative, isTrue);
    });

    test('wolniejszy zawodnik traci czas', () {
      service.start(
        const PaceTarget(
          kind: PaceTargetKind.speed,
          label: '30 km/h',
          routeDistanceMeters: 10000,
          targetSpeedKmh: 30,
        ),
      );
      final comparison = service.compare(
        riderMeters: 500,
        elapsed: const Duration(minutes: 2),
      )!;
      expect(comparison.isAhead, isFalse);
      expect(comparison.timeDelta!.inSeconds, greaterThan(0));
    });

    test('z trasą ghost ma pozycję na mapie', () {
      final route = RideRoute(
        id: 'r',
        name: 'Prosta',
        points: [
          for (var i = 0; i <= 100; i++)
            GeoPoint(lat: 52.0 + i * 0.0001, lon: 21.0),
        ],
      );
      service.start(
        const PaceTarget(
          kind: PaceTargetKind.speed,
          label: '20 km/h',
          routeDistanceMeters: 1100,
          targetSpeedKmh: 20,
        ),
        route: route,
      );
      final comparison = service.compare(
        riderMeters: 300,
        elapsed: const Duration(minutes: 1),
      )!;
      expect(comparison.ghostPosition, isNotNull);
      expect(comparison.ghostPosition!.lat, greaterThan(52.0));
      expect(comparison.ghostPosition!.lat, lessThan(52.01));
    });

    test('bez trasy nie ma ghosta na mapie, ale delta zostaje', () {
      service.start(
        const PaceTarget(
          kind: PaceTargetKind.speed,
          label: '20 km/h',
          routeDistanceMeters: 1100,
          targetSpeedKmh: 20,
        ),
      );
      final comparison = service.compare(
        riderMeters: 300,
        elapsed: const Duration(minutes: 1),
      )!;
      expect(comparison.ghostPosition, isNull);
      expect(comparison.timeDelta, isNotNull);
    });

    test('zatrzymanie kasuje rywala', () {
      service.start(
        const PaceTarget(
          kind: PaceTargetKind.speed,
          label: '20 km/h',
          routeDistanceMeters: 1000,
          targetSpeedKmh: 20,
        ),
      );
      service.stop();
      expect(service.isActive, isFalse);
      expect(
        service.compare(riderMeters: 10, elapsed: const Duration(seconds: 10)),
        isNull,
      );
    });
  });
}
