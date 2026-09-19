import 'package:dio/dio.dart';

import '../core/geo.dart';
import '../models/route/route_weather.dart';
import '../models/weather.dart';
import 'weather_service.dart';

/// Prognoza wzdłuż trasy, a nie tylko „tu i teraz”.
///
/// Trasa jest próbkowana co kilkanaście kilometrów, dla każdej próbki liczony
/// jest czas dojazdu, a prognoza brana jest z godziny, o której zawodnik tam
/// faktycznie będzie. Bez tego informacja „20 % szans na deszcz” nie mówi nic
/// o przejeździe, który trwa trzy godziny.
class RouteWeatherService {
  RouteWeatherService({Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  /// Maksymalna liczba punktów prognozy — Open-Meteo przyjmuje wiele
  /// współrzędnych w jednym zapytaniu, ale nie ma sensu pytać o setki.
  static const int maxSamples = 6;

  /// Co ile kilometrów próbkujemy trasę.
  static const double sampleEveryMeters = 20000;

  final Dio _dio;

  /// Liczy prognozę dla trasy.
  ///
  /// Zwraca pustą prognozę, gdy serwis nie odpowie — briefing po prostu nie
  /// pokaże pogody, zamiast pokazać wymyśloną.
  Future<RouteForecast> forecast({
    required List<GeoPoint> points,
    required Duration estimatedDuration,
    DateTime? departureAt,
  }) async {
    if (points.length < 2) {
      return RouteForecast(
        points: const [],
        departureAt: departureAt ?? DateTime.now(),
      );
    }

    final departure = departureAt ?? DateTime.now();
    final samples = _sample(points, estimatedDuration, departure);
    if (samples.isEmpty) {
      return RouteForecast(points: const [], departureAt: departure);
    }

    try {
      final response = await _dio.get<dynamic>(
        WeatherService.endpoint,
        queryParameters: {
          'latitude': samples
              .map((s) => s.point.lat.toStringAsFixed(4))
              .join(','),
          'longitude': samples
              .map((s) => s.point.lon.toStringAsFixed(4))
              .join(','),
          'hourly':
              'temperature_2m,apparent_temperature,precipitation,'
              'precipitation_probability,weather_code,wind_speed_10m,'
              'wind_direction_10m,wind_gusts_10m',
          'daily': 'sunrise,sunset',
          'forecast_days': 2,
          'timezone': 'auto',
          'wind_speed_unit': 'kmh',
          if (WeatherService.apiKey.isNotEmpty) 'apikey': WeatherService.apiKey,
        },
      );

      final data = response.data;
      if (data == null) {
        return RouteForecast(points: const [], departureAt: departure);
      }
      // Przy wielu współrzędnych Open-Meteo zwraca tablicę bloków,
      // przy jednej — pojedynczy obiekt.
      final blocks = data is List ? data : [data];
      return _parse(samples, blocks, departure);
    } catch (_) {
      return RouteForecast(points: const [], departureAt: departure);
    }
  }

  /// Punkty, o które pytamy: start, co ~20 km i meta.
  List<({double distance, GeoPoint point, double bearing, DateTime arrival})>
  _sample(List<GeoPoint> points, Duration duration, DateTime departure) {
    final cumulative = cumulativeDistances(points);
    final total = cumulative.last;
    if (total <= 0) return const [];

    final stepCount = (total / sampleEveryMeters).ceil().clamp(
      1,
      maxSamples - 1,
    );
    final step = total / stepCount;

    final samples =
        <
          ({double distance, GeoPoint point, double bearing, DateTime arrival})
        >[];
    for (var i = 0; i <= stepCount; i++) {
      final target = (i * step).clamp(0.0, total);
      final index = _indexAt(cumulative, target);
      final point = points[index];
      final next = points[(index + 1).clamp(0, points.length - 1)];
      final bearing = index + 1 < points.length
          ? bearingDegrees(point, next)
          : bearingDegrees(points[points.length - 2], points.last);

      samples.add((
        distance: target,
        point: point,
        bearing: bearing,
        // Czas dojazdu liczony proporcjonalnie do dystansu: bez danych
        // o tempie na poszczególnych odcinkach to najuczciwsze przybliżenie.
        arrival: departure.add(
          Duration(seconds: (duration.inSeconds * (target / total)).round()),
        ),
      ));
    }
    return samples;
  }

  int _indexAt(List<double> cumulative, double distance) {
    var low = 0;
    var high = cumulative.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (cumulative[middle] < distance) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  RouteForecast _parse(
    List<({double distance, GeoPoint point, double bearing, DateTime arrival})>
    samples,
    List<dynamic> blocks,
    DateTime departure,
  ) {
    final result = <RouteWeatherPoint>[];
    DateTime? sunset;
    DateTime? sunrise;

    for (var i = 0; i < samples.length; i++) {
      final block = i < blocks.length ? blocks[i] : blocks.first;
      if (block is! Map) continue;
      final hourly = block['hourly'];
      if (hourly is! Map) continue;

      final times = hourly['time'];
      if (times is! List || times.isEmpty) continue;
      final index = _hourIndex(times, samples[i].arrival);
      if (index == null) continue;

      if (sunset == null) {
        final daily = block['daily'];
        if (daily is Map) {
          final sunsets = daily['sunset'];
          final sunrises = daily['sunrise'];
          if (sunsets is List && sunsets.isNotEmpty) {
            sunset = DateTime.tryParse('${sunsets.first}');
          }
          if (sunrises is List && sunrises.isNotEmpty) {
            sunrise = DateTime.tryParse('${sunrises.first}');
          }
        }
      }

      double? at(String key) {
        final values = hourly[key];
        if (values is! List || index >= values.length) return null;
        final value = values[index];
        return value is num ? value.toDouble() : null;
      }

      final temperature = at('temperature_2m');
      if (temperature == null) continue;

      result.add(
        RouteWeatherPoint(
          distanceMeters: samples[i].distance,
          point: samples[i].point,
          arrivalAt: samples[i].arrival,
          travelBearing: samples[i].bearing,
          temperatureCelsius: temperature,
          apparentTemperatureCelsius: at('apparent_temperature') ?? temperature,
          windSpeedKmh: at('wind_speed_10m') ?? 0,
          windFromDegrees: at('wind_direction_10m') ?? 0,
          windGustKmh: at('wind_gusts_10m'),
          precipitationProbability: at('precipitation_probability')?.round(),
          precipitationMm: at('precipitation'),
          condition: conditionFromWmoCode(at('weather_code')?.round()),
        ),
      );
    }

    return RouteForecast(
      points: List.unmodifiable(result),
      departureAt: departure,
      sunset: sunset,
      sunrise: sunrise,
    );
  }

  /// Indeks godziny najbliższej podanemu czasowi.
  int? _hourIndex(List<dynamic> times, DateTime target) {
    int? best;
    Duration bestDelta = const Duration(days: 365);
    for (var i = 0; i < times.length; i++) {
      final parsed = DateTime.tryParse('${times[i]}');
      if (parsed == null) continue;
      final delta = parsed.difference(target).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = i;
      }
    }
    return best;
  }
}

/// Kod WMO na warunki, których używa reszta aplikacji.
WeatherCondition conditionFromWmoCode(int? code) {
  if (code == null) return WeatherCondition.unknown;
  if (code == 0) return WeatherCondition.clear;
  if (code == 1 || code == 2) return WeatherCondition.partlyCloudy;
  if (code == 3) return WeatherCondition.cloudy;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 51 && code <= 57) return WeatherCondition.drizzle;
  if (code >= 61 && code <= 65) {
    return code >= 65 ? WeatherCondition.heavyRain : WeatherCondition.rain;
  }
  if (code == 66 || code == 67) return WeatherCondition.rain;
  if (code >= 71 && code <= 77) return WeatherCondition.snow;
  if (code >= 80 && code <= 82) {
    return code == 82 ? WeatherCondition.heavyRain : WeatherCondition.rain;
  }
  if (code == 85 || code == 86) return WeatherCondition.snow;
  if (code >= 95) return WeatherCondition.thunderstorm;
  return WeatherCondition.unknown;
}
