import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_analysis.dart';
import 'package:live_ride/models/route/route_briefing.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_weather.dart';
import 'package:live_ride/models/weather.dart';

/// Punkty co [stepMeters] na wschód od startu, z profilem wysokości z funkcji.
List<GeoPoint> _line({
  required int count,
  double stepMeters = 100,
  double Function(int index)? elevation,
}) {
  const lat = 52.0;
  final degPerMeter = 1 / (111320 * math.cos(lat * math.pi / 180));
  return List.generate(count, (i) {
    return GeoPoint(
      lat: lat,
      lon: 21.0 + i * stepMeters * degPerMeter,
      elevation: elevation?.call(i),
    );
  });
}

RouteWeatherPoint _weather({
  required double distanceMeters,
  required DateTime arrivalAt,
  double travelBearing = 90,
  double windFromDegrees = 90,
  double windSpeedKmh = 25,
  int? precipitationProbability,
  WeatherCondition condition = WeatherCondition.clear,
}) {
  return RouteWeatherPoint(
    distanceMeters: distanceMeters,
    point: const GeoPoint(lat: 52.0, lon: 21.0),
    arrivalAt: arrivalAt,
    travelBearing: travelBearing,
    temperatureCelsius: 18,
    apparentTemperatureCelsius: 18,
    windSpeedKmh: windSpeedKmh,
    windFromDegrees: windFromDegrees,
    condition: condition,
    precipitationProbability: precipitationProbability,
  );
}

String _all(RouteBriefing briefing) =>
    briefing.lines.map((line) => line.text).join('\n');

void main() {
  const preferences = RoutePreferences();

  group('RouteBriefing — tylko to, co da się policzyć', () {
    test('trasa bez wysokości nie dostaje zdań o podjazdach', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 200));
      expect(analysis.hasElevationData, isFalse);

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );

      final text = _all(briefing);
      expect(text, isNot(contains('podjazd')));
      expect(text, isNot(contains('nachyleniu')));
      expect(text, isNot(contains('zjazd')));
      expect(briefing.headline.any((h) => h.contains('↑')), isFalse);
      // Dystans i czas da się policzyć zawsze.
      expect(briefing.headline.first, '19.9 km');
      expect(text, contains('Przewidywany czas'));
    });

    test('bez prognozy nie ma ani jednego zdania o pogodzie', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 200));
      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );

      final text = _all(briefing);
      expect(text, isNot(contains('wiatr')));
      expect(text, isNot(contains('deszcz')));
      expect(text, isNot(contains('Zachód')));
      expect(briefing.forecast, isNull);
    });

    test('pusta prognoza jest traktowana jak brak prognozy', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 200));
      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        forecast: RouteForecast(
          points: const [],
          departureAt: DateTime(2026, 5, 1, 9),
        ),
      );

      expect(_all(briefing), isNot(contains('Na starcie')));
    });

    test('bez wagi zawodnika nie ma szacunku wydatku energii', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 200));
      final withoutWeight = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );
      expect(withoutWeight.estimatedEnergyKj, isNull);
      expect(_all(withoutWeight), isNot(contains('kJ')));

      final withWeight = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        riderWeightKg: 75,
      );
      expect(withWeight.estimatedEnergyKj, isNotNull);
      expect(_all(withWeight), contains('kJ'));
      expect(_all(withWeight), contains('kcal'));
    });

    test('krótka trasa nie dostaje sugerowanych postojów', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 200));
      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );
      expect(briefing.suggestedStops, isEmpty);
      expect(_all(briefing), isNot(contains('postoj')));
    });
  });

  group('RouteBriefing — treść, gdy dane są', () {
    // 8 km podjazdu po 6 %, potem 4 km płasko.
    RouteAnalysis climbRoute() => RouteAnalyzer.analyze(
      _line(
        count: 121,
        stepMeters: 100,
        elevation: (i) => i <= 80 ? 100 + i * 6.0 : 100 + 80 * 6.0,
      ),
    );

    test('największy podjazd trafia do briefingu z kategorią', () {
      final analysis = climbRoute();
      expect(analysis.climbs, isNotEmpty);

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );

      final text = _all(briefing);
      expect(text, contains('Największy podjazd'));
      expect(text, contains(analysis.biggestClimb!.category.label));
      expect(briefing.headline.any((h) => h.contains('podjazd')), isTrue);
      // 6 % średnio → zdanie o odcinkach ponad 7 % nie powinno się pojawić.
      expect(text, isNot(contains('ponad 7 %')));
    });

    test('strome fragmenty i zjazdy są zgłaszane', () {
      final analysis = RouteAnalyzer.analyze(
        _line(
          count: 121,
          elevation: (i) => i <= 60 ? 100 + i * 12.0 : 100 + (120 - i) * 12.0,
        ),
      );
      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );

      final text = _all(briefing);
      expect(text, contains('Najstromszy fragment'));
      expect(text, contains('hamulce'));
      expect(text, contains('ponad 7 %'));
    });

    test('wiatr czołowy na długim odcinku dostaje własne zdanie', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 600));
      final departure = DateTime(2026, 5, 1, 9);
      final forecast = RouteForecast(
        points: [
          for (var i = 0; i < 4; i++)
            _weather(
              distanceMeters: i * 20000,
              arrivalAt: departure.add(Duration(minutes: i * 40)),
            ),
        ],
        departureAt: departure,
      );

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        forecast: forecast,
      );

      final text = _all(briefing);
      expect(text, contains('wiatr czołowy'));
      expect(text, contains('Na starcie'));
    });

    test('wiatr w plecy przez większość trasy jest dobrą wiadomością', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 600));
      final departure = DateTime(2026, 5, 1, 9);
      final forecast = RouteForecast(
        points: [
          for (var i = 0; i < 4; i++)
            _weather(
              distanceMeters: i * 20000,
              arrivalAt: departure.add(Duration(minutes: i * 40)),
              windFromDegrees: 270,
            ),
        ],
        departureAt: departure,
      );

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        forecast: forecast,
      );

      final tail = briefing.lines.firstWhere(
        (line) => line.text.contains('w plecy'),
      );
      expect(tail.tone, BriefingTone.good);
    });

    test('pierwszy deszcz pokazuje godzinę i kilometr', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 600));
      final departure = DateTime(2026, 5, 1, 9);
      final forecast = RouteForecast(
        points: [
          _weather(distanceMeters: 0, arrivalAt: departure),
          _weather(
            distanceMeters: 20000,
            arrivalAt: departure.add(const Duration(minutes: 40)),
            precipitationProbability: 20,
          ),
          _weather(
            distanceMeters: 40000,
            arrivalAt: departure.add(const Duration(minutes: 80)),
            precipitationProbability: 70,
            condition: WeatherCondition.rain,
          ),
        ],
        departureAt: departure,
      );

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        forecast: forecast,
      );

      final rain = briefing.lines.firstWhere(
        (line) => line.text.contains('deszcz'),
      );
      expect(rain.text, contains('10:20'));
      expect(rain.text, contains('70 %'));
      expect(rain.text, contains('40'));
      expect(rain.tone, BriefingTone.warning);
    });

    test('meta po zachodzie słońca to ostrzeżenie o oświetleniu', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 600));
      final departure = DateTime(2026, 5, 1, 18);
      final forecast = RouteForecast(
        points: [
          _weather(distanceMeters: 0, arrivalAt: departure),
          _weather(
            distanceMeters: 60000,
            arrivalAt: departure.add(const Duration(hours: 3)),
          ),
        ],
        departureAt: departure,
        sunset: DateTime(2026, 5, 1, 20, 15),
      );

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        forecast: forecast,
      );

      final dusk = briefing.lines.firstWhere(
        (line) => line.text.contains('Zachód'),
      );
      expect(dusk.text, contains('20:15'));
      expect(dusk.text, contains('po zmroku'));
      expect(dusk.tone, BriefingTone.warning);
    });

    test('meta przed zachodem tylko informuje o godzinie', () {
      final analysis = RouteAnalyzer.analyze(_line(count: 600));
      final departure = DateTime(2026, 5, 1, 9);
      final forecast = RouteForecast(
        points: [
          _weather(distanceMeters: 0, arrivalAt: departure),
          _weather(
            distanceMeters: 60000,
            arrivalAt: departure.add(const Duration(hours: 3)),
          ),
        ],
        departureAt: departure,
        sunset: DateTime(2026, 5, 1, 20, 15),
      );

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
        forecast: forecast,
      );

      final dusk = briefing.lines.firstWhere(
        (line) => line.text.contains('Zachód'),
      );
      expect(dusk.text, isNot(contains('po zmroku')));
      expect(dusk.tone, BriefingTone.neutral);
    });

    test('długa trasa dostaje postoje co około 40 km', () {
      final analysis = RouteAnalyzer.analyze(
        _line(count: 900, stepMeters: 100),
      );
      expect(analysis.distanceMeters, greaterThan(85000));

      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );

      expect(briefing.suggestedStops, [40000, 80000]);
      expect(_all(briefing), contains('sugerowane postoje'));
    });

    test('bardzo długa trasa rozrzedza postoje do 50 km', () {
      final analysis = RouteAnalyzer.analyze(
        _line(count: 1600, stepMeters: 100),
      );
      final briefing = RouteBriefing.build(
        analysis: analysis,
        preferences: preferences,
      );
      expect(briefing.suggestedStops, [50000, 100000, 150000]);
    });

    test('liczba bidonów rośnie z czasem jazdy', () {
      final short = RouteBriefing.build(
        analysis: RouteAnalyzer.analyze(_line(count: 200)),
        preferences: preferences,
      );
      expect(_all(short), isNot(contains('bidon')));

      final long = RouteBriefing.build(
        analysis: RouteAnalyzer.analyze(_line(count: 900)),
        preferences: preferences,
      );
      final water = _all(long);
      expect(water, contains('bidony'));
      expect(water, contains('jedzenie na drogę'));
    });
  });
}
