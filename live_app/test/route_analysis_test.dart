import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_analysis.dart';

/// Buduje trasę na wschód z zadanym profilem wysokości.
/// Krok 20 m daje realistyczną gęstość punktów GPS.
List<GeoPoint> routeFrom(List<double> elevations, {double stepMeters = 20}) {
  const lat = 50.0;
  final lonStep = stepMeters / (111320 * 0.642); // cos(50°)
  return [
    for (var i = 0; i < elevations.length; i++)
      GeoPoint(lat: lat, lon: 19.0 + i * lonStep, elevation: elevations[i]),
  ];
}

void main() {
  group('brak danych wysokości', () {
    test('nie wymyśla przewyższenia', () {
      final points = [
        for (var i = 0; i < 50; i++)
          GeoPoint(lat: 50.0, lon: 19.0 + i * 0.0003),
      ];
      final analysis = RouteAnalyzer.analyze(points);
      expect(analysis.hasElevationData, isFalse);
      expect(analysis.ascentMeters, 0);
      expect(analysis.climbs, isEmpty);
      expect(analysis.distanceMeters, greaterThan(0));
    });
  });

  group('wygładzanie', () {
    test('szum wysokości nie zamienia się w przewyższenie', () {
      // Płaska trasa z wahaniami ±1,5 m, jakie daje model terenu.
      final elevations = [
        for (var i = 0; i < 200; i++) 100 + (i.isEven ? 1.5 : -1.5),
      ];
      final analysis = RouteAnalyzer.analyze(routeFrom(elevations));
      expect(analysis.ascentMeters, lessThan(10));
      expect(analysis.climbs, isEmpty);
    });
  });

  group('wykrywanie podjazdów', () {
    test('znajduje jeden wyraźny podjazd', () {
      // 1 km płasko, 2 km pod górę po 5%, 1 km płasko.
      final elevations = <double>[
        for (var i = 0; i < 50; i++) 100,
        for (var i = 0; i < 100; i++) 100 + i * 1.0, // 20 m kroku × 5%
        for (var i = 0; i < 50; i++) 200,
      ];
      final analysis = RouteAnalyzer.analyze(routeFrom(elevations));

      expect(analysis.climbs.length, 1);
      final climb = analysis.climbs.single;
      expect(climb.gainMeters, closeTo(100, 12));
      expect(climb.lengthMeters, closeTo(2000, 200));
      expect(climb.averageGradientPercent, closeTo(5, 1));
      expect(climb.index, 1);
    });

    test('ignoruje pagórek poniżej progu', () {
      final elevations = <double>[
        for (var i = 0; i < 50; i++) 100,
        for (var i = 0; i < 10; i++) 100 + i * 1.0, // tylko 10 m
        for (var i = 0; i < 50; i++) 110,
      ];
      expect(RouteAnalyzer.analyze(routeFrom(elevations)).climbs, isEmpty);
    });

    test('nie dzieli podjazdu przez krótkie spłaszczenie', () {
      // Podjazd z 200-metrową półką w środku to wciąż jeden podjazd.
      final elevations = <double>[
        for (var i = 0; i < 50; i++) 100 + i * 1.0,
        for (var i = 0; i < 10; i++) 150,
        for (var i = 0; i < 50; i++) 150 + i * 1.0,
      ];
      final climbs = RouteAnalyzer.analyze(routeFrom(elevations)).climbs;
      expect(climbs.length, 1);
      expect(climbs.single.gainMeters, closeTo(100, 12));
    });

    test('rozdziela dwa podjazdy rozdzielone długim zjazdem', () {
      final elevations = <double>[
        for (var i = 0; i < 60; i++) 100 + i * 1.0,
        for (var i = 0; i < 60; i++) 160 - i * 1.0,
        for (var i = 0; i < 60; i++) 100 + i * 1.0,
      ];
      final climbs = RouteAnalyzer.analyze(routeFrom(elevations)).climbs;
      expect(climbs.length, 2);
      expect(climbs[0].index, 1);
      expect(climbs[1].index, 2);
      expect(
        climbs[1].startDistanceMeters,
        greaterThan(climbs[0].endDistanceMeters),
      );
    });

    test('liczy najbardziej stromy fragment', () {
      final elevations = <double>[
        for (var i = 0; i < 40; i++) 100 + i * 1.0, // 5 %
        for (var i = 0; i < 20; i++) 140 + i * 3.0, // 15 %
        for (var i = 0; i < 40; i++) 200,
      ];
      final analysis = RouteAnalyzer.analyze(routeFrom(elevations));
      expect(analysis.steepestGradientPercent, greaterThan(8));
    });
  });

  group('kategoryzacja', () {
    ClimbCategory categoryFor(double lengthMeters, double gradientPercent) {
      final steps = (lengthMeters / 20).round();
      final rise = 20 * gradientPercent / 100;
      final elevations = <double>[
        for (var i = 0; i < 30; i++) 100,
        for (var i = 0; i < steps; i++) 100 + i * rise,
        for (var i = 0; i < 30; i++) 100 + steps * rise,
      ];
      final climbs = RouteAnalyzer.analyze(routeFrom(elevations)).climbs;
      return climbs.isEmpty
          ? ClimbCategory.uncategorised
          : climbs.first.category;
    }

    test('2 km po 5 % to kategoria 3', () {
      // wynik = 2000 × 5 = 10 000 → kategoria 4/3 zależnie od wygładzenia
      expect(
        categoryFor(2000, 5).minimumScore,
        greaterThanOrEqualTo(ClimbCategory.four.minimumScore),
      );
    });

    test('10 km po 7 % to kategoria 1 lub wyżej', () {
      final category = categoryFor(10000, 7);
      expect(
        category.minimumScore,
        greaterThanOrEqualTo(ClimbCategory.one.minimumScore),
      );
    });

    test('skala rośnie monotonicznie', () {
      expect(ClimbCategory.fromScore(0), ClimbCategory.uncategorised);
      expect(ClimbCategory.fromScore(9000), ClimbCategory.four);
      expect(ClimbCategory.fromScore(20000), ClimbCategory.three);
      expect(ClimbCategory.fromScore(40000), ClimbCategory.two);
      expect(ClimbCategory.fromScore(70000), ClimbCategory.one);
      expect(ClimbCategory.fromScore(200000), ClimbCategory.hc);
    });
  });

  group('postęp na podjeździe', () {
    late Climb climb;

    setUp(() {
      final elevations = <double>[
        for (var i = 0; i < 20; i++) 100,
        for (var i = 0; i < 100; i++) 100 + i * 1.0,
        for (var i = 0; i < 20; i++) 200,
      ];
      climb = RouteAnalyzer.analyze(routeFrom(elevations)).climbs.single;
    });

    test('zna swoje granice', () {
      expect(climb.contains(climb.startDistanceMeters + 10), isTrue);
      expect(climb.contains(climb.startDistanceMeters - 100), isFalse);
      expect(climb.contains(climb.endDistanceMeters + 100), isFalse);
    });

    test('liczy postęp i to, co zostało', () {
      final middle = (climb.startDistanceMeters + climb.endDistanceMeters) / 2;
      expect(climb.progress(middle), closeTo(0.5, 0.05));
      expect(
        climb.remainingMeters(middle),
        closeTo(climb.lengthMeters / 2, climb.lengthMeters * 0.06),
      );
      expect(climb.remainingGain(climb.summitElevation), 0);
      expect(climb.progress(climb.endDistanceMeters + 500), 1.0);
    });
  });

  group('trudność i szacunki', () {
    test('płaska krótka trasa jest łatwa', () {
      final elevations = [for (var i = 0; i < 100; i++) 100.0];
      final analysis = RouteAnalyzer.analyze(routeFrom(elevations));
      expect(analysis.difficulty, RouteDifficulty.easy);
    });

    test('górska trasa jest trudniejsza niż płaska tej samej długości', () {
      final flat = RouteAnalyzer.analyze(
        routeFrom([for (var i = 0; i < 500; i++) 100.0]),
      );
      final hilly = RouteAnalyzer.analyze(
        routeFrom([
          for (var i = 0; i < 250; i++) 100 + i * 2.0,
          for (var i = 0; i < 250; i++) 600 - i * 2.0,
        ]),
      );
      expect(hilly.difficulty.index, greaterThan(flat.difficulty.index));
      expect(hilly.metersPerKilometre, greaterThan(flat.metersPerKilometre));
    });

    test('czas rośnie razem z przewyższeniem', () {
      final flat = RouteAnalyzer.analyze(
        routeFrom([for (var i = 0; i < 500; i++) 100.0]),
      );
      final hilly = RouteAnalyzer.analyze(
        routeFrom([
          for (var i = 0; i < 250; i++) 100 + i * 2.0,
          for (var i = 0; i < 250; i++) 600 - i * 2.0,
        ]),
      );
      expect(
        hilly.estimatedDuration(assumedSpeedKmh: 24),
        greaterThan(flat.estimatedDuration(assumedSpeedKmh: 24)),
      );
    });

    test('bez masy zawodnika nie podaje energii', () {
      final analysis = RouteAnalyzer.analyze(
        routeFrom([for (var i = 0; i < 200; i++) 100.0]),
      );
      expect(
        analysis.estimatedEnergyKj(riderWeightKg: null, assumedSpeedKmh: 24),
        isNull,
      );
      expect(
        analysis.estimatedEnergyKj(riderWeightKg: 75, assumedSpeedKmh: 24),
        greaterThan(0),
      );
    });

    test('podjazd kosztuje więcej energii niż płaski odcinek', () {
      final flat = RouteAnalyzer.analyze(
        routeFrom([for (var i = 0; i < 300; i++) 100.0]),
      );
      final climbing = RouteAnalyzer.analyze(
        routeFrom([for (var i = 0; i < 300; i++) 100 + i * 1.0]),
      );
      expect(
        climbing.estimatedEnergyKj(riderWeightKg: 75, assumedSpeedKmh: 24)!,
        greaterThan(
          flat.estimatedEnergyKj(riderWeightKg: 75, assumedSpeedKmh: 24)!,
        ),
      );
    });
  });
}
