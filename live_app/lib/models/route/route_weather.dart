import 'dart:math' as math;

import '../../core/geo.dart';
import '../weather.dart';

/// Jak wiatr ustawia się do kierunku jazdy.
enum WindRelation {
  head('czołowy'),
  tail('z tyłu'),
  cross('boczny');

  const WindRelation(this.label);

  final String label;
}

/// Prognoza w jednym punkcie trasy, o godzinie, o której się tam będzie.
class RouteWeatherPoint {
  const RouteWeatherPoint({
    required this.distanceMeters,
    required this.point,
    required this.arrivalAt,
    required this.travelBearing,
    required this.temperatureCelsius,
    required this.apparentTemperatureCelsius,
    required this.windSpeedKmh,
    required this.windFromDegrees,
    required this.condition,
    this.windGustKmh,
    this.precipitationProbability,
    this.precipitationMm,
  });

  final double distanceMeters;
  final GeoPoint point;

  /// Kiedy zawodnik powinien tu być.
  final DateTime arrivalAt;

  /// Kierunek jazdy w tym miejscu.
  final double travelBearing;

  final double temperatureCelsius;
  final double apparentTemperatureCelsius;
  final double windSpeedKmh;

  /// Kierunek, Z KTÓREGO wieje — tak podaje go każda prognoza.
  final double windFromDegrees;

  final double? windGustKmh;
  final int? precipitationProbability;
  final double? precipitationMm;
  final WeatherCondition condition;

  /// Kąt wiatru względem kierunku jazdy: 0° to prosto w twarz,
  /// 180° to prosto w plecy.
  double get relativeWindAngle {
    final angle = (windFromDegrees - travelBearing) % 360;
    return angle < 0 ? angle + 360 : angle;
  }

  WindRelation get windRelation {
    final angle = relativeWindAngle;
    if (angle <= 45 || angle >= 315) return WindRelation.head;
    if (angle >= 135 && angle <= 225) return WindRelation.tail;
    return WindRelation.cross;
  }

  /// Składowa wiatru wzdłuż kierunku jazdy w km/h.
  ///
  /// Dodatnia oznacza wiatr czołowy — czyli to, co realnie kosztuje.
  double get headwindComponentKmh =>
      windSpeedKmh * math.cos(relativeWindAngle * math.pi / 180);

  /// Czy wiatr jest na tyle mocny, żeby o nim mówić.
  bool get isSignificant => windSpeedKmh >= 15;

  bool get willRain => (precipitationProbability ?? 0) >= 40;
}

/// Prognoza dla całej trasy.
class RouteForecast {
  const RouteForecast({
    required this.points,
    required this.departureAt,
    this.sunset,
    this.sunrise,
  });

  final List<RouteWeatherPoint> points;
  final DateTime departureAt;
  final DateTime? sunset;
  final DateTime? sunrise;

  bool get isEmpty => points.isEmpty;

  RouteWeatherPoint? get start => points.isEmpty ? null : points.first;
  RouteWeatherPoint? get finish => points.isEmpty ? null : points.last;

  /// Najdłuższy ciągły odcinek z wiatrem czołowym.
  ///
  /// Zwraca null, gdy nie ma czego zgłaszać — zdanie „przez 0 km wiatr
  /// czołowy” nikomu nie pomaga. Każda próbka reprezentuje odcinek aż do
  /// następnej próbki, więc pojedynczy punkt też ma długość.
  ({double fromMeters, double toMeters})? get longestHeadwindStretch {
    if (points.length < 2) return null;

    ({int from, int to})? best;
    int? runStart;

    void close(int endIndex) {
      if (runStart == null) return;
      final candidate = (from: runStart!, to: endIndex);
      if (best == null || _spanOf(candidate) > _spanOf(best!)) {
        best = candidate;
      }
      runStart = null;
    }

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final blowing =
          point.windRelation == WindRelation.head && point.isSignificant;
      if (blowing) {
        runStart ??= i;
      } else {
        close(i);
      }
    }
    close(points.length - 1);

    final found = best;
    if (found == null) return null;
    final from = points[found.from].distanceMeters;
    final to = points[found.to].distanceMeters;
    if (to - from < 1000) return null;
    return (fromMeters: from, toMeters: to);
  }

  double _spanOf(({int from, int to}) range) =>
      points[range.to].distanceMeters - points[range.from].distanceMeters;

  /// Pierwszy punkt trasy, w którym prognoza widzi opady.
  RouteWeatherPoint? get firstRain {
    for (final point in points) {
      if (point.willRain) return point;
    }
    return null;
  }

  /// Czy zawodnik dojedzie po zmroku.
  bool get finishesAfterSunset {
    final end = finish;
    final dusk = sunset;
    if (end == null || dusk == null) return false;
    return end.arrivalAt.isAfter(dusk);
  }
}
