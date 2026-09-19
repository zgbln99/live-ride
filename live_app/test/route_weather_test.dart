import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_weather.dart';
import 'package:live_ride/models/weather.dart';
import 'package:live_ride/services/route_weather_service.dart';

RouteWeatherPoint point({
  required double bearing,
  required double windFrom,
  double windSpeed = 25,
  double distance = 0,
  int? rain,
  DateTime? arrival,
}) => RouteWeatherPoint(
  distanceMeters: distance,
  point: const GeoPoint(lat: 52, lon: 21),
  arrivalAt: arrival ?? DateTime(2026, 6, 1, 12),
  travelBearing: bearing,
  temperatureCelsius: 18,
  apparentTemperatureCelsius: 17,
  windSpeedKmh: windSpeed,
  windFromDegrees: windFrom,
  condition: WeatherCondition.clear,
  precipitationProbability: rain,
);

void main() {
  group('wiatr względem kierunku jazdy', () {
    test('wiatr z północy przy jeździe na północ jest czołowy', () {
      // wind_direction_10m to kierunek, Z KTÓREGO wieje.
      final sample = point(bearing: 0, windFrom: 0);
      expect(sample.windRelation, WindRelation.head);
      expect(sample.headwindComponentKmh, closeTo(25, 0.1));
    });

    test('wiatr z południa przy jeździe na północ jest z tyłu', () {
      final sample = point(bearing: 0, windFrom: 180);
      expect(sample.windRelation, WindRelation.tail);
      expect(sample.headwindComponentKmh, closeTo(-25, 0.1));
    });

    test('wiatr z boku jest boczny i prawie nie kosztuje', () {
      final sample = point(bearing: 0, windFrom: 90);
      expect(sample.windRelation, WindRelation.cross);
      expect(sample.headwindComponentKmh.abs(), lessThan(1));
    });

    test('działa po obrocie kierunku jazdy', () {
      // Jadąc na zachód, wiatr z zachodu jest czołowy.
      expect(
        point(bearing: 270, windFrom: 270).windRelation,
        WindRelation.head,
      );
      expect(point(bearing: 270, windFrom: 90).windRelation, WindRelation.tail);
      expect(point(bearing: 90, windFrom: 0).windRelation, WindRelation.cross);
    });

    test('radzi sobie z przejściem przez zero', () {
      final sample = point(bearing: 350, windFrom: 10);
      expect(sample.relativeWindAngle, closeTo(20, 0.001));
      expect(sample.windRelation, WindRelation.head);
    });

    test('ukośny wiatr ma pośrednią składową', () {
      final sample = point(bearing: 0, windFrom: 45, windSpeed: 20);
      expect(sample.headwindComponentKmh, closeTo(14.14, 0.1));
      expect(sample.windRelation, WindRelation.head);
    });

    test('słaby wiatr nie jest istotny', () {
      expect(
        point(bearing: 0, windFrom: 0, windSpeed: 8).isSignificant,
        isFalse,
      );
      expect(
        point(bearing: 0, windFrom: 0, windSpeed: 22).isSignificant,
        isTrue,
      );
    });
  });

  group('prognoza trasy', () {
    RouteForecast forecastWith(List<RouteWeatherPoint> points) => RouteForecast(
      points: points,
      departureAt: DateTime(2026, 6, 1, 10),
      sunset: DateTime(2026, 6, 1, 21),
    );

    test('znajduje najdłuższy odcinek pod wiatr', () {
      final forecast = forecastWith([
        point(bearing: 0, windFrom: 180, distance: 0),
        point(bearing: 0, windFrom: 0, distance: 20000),
        point(bearing: 0, windFrom: 0, distance: 40000),
        point(bearing: 0, windFrom: 180, distance: 60000),
      ]);

      final stretch = forecast.longestHeadwindStretch;
      expect(stretch, isNotNull);
      expect(stretch!.fromMeters, 20000);
      expect(stretch.toMeters, 60000);
    });

    test('nie zgłasza odcinka, gdy wiatr jest słaby', () {
      final forecast = forecastWith([
        point(bearing: 0, windFrom: 0, windSpeed: 6, distance: 0),
        point(bearing: 0, windFrom: 0, windSpeed: 6, distance: 20000),
      ]);
      expect(forecast.longestHeadwindStretch, isNull);
    });

    test('znajduje pierwszy deszcz na trasie', () {
      final forecast = forecastWith([
        point(bearing: 0, windFrom: 90, distance: 0, rain: 10),
        point(bearing: 0, windFrom: 90, distance: 20000, rain: 70),
        point(bearing: 0, windFrom: 90, distance: 40000, rain: 80),
      ]);
      expect(forecast.firstRain!.distanceMeters, 20000);
    });

    test('brak deszczu to brak ostrzeżenia', () {
      final forecast = forecastWith([
        point(bearing: 0, windFrom: 90, rain: 5),
        point(bearing: 0, windFrom: 90, rain: 15),
      ]);
      expect(forecast.firstRain, isNull);
    });

    test('wie, że meta wypada po zmroku', () {
      final forecast = RouteForecast(
        points: [
          point(bearing: 0, windFrom: 0, arrival: DateTime(2026, 6, 1, 19)),
          point(bearing: 0, windFrom: 0, arrival: DateTime(2026, 6, 1, 22)),
        ],
        departureAt: DateTime(2026, 6, 1, 19),
        sunset: DateTime(2026, 6, 1, 21),
      );
      expect(forecast.finishesAfterSunset, isTrue);
    });
  });

  group('kody pogody WMO', () {
    test('tłumaczą się na warunki', () {
      expect(conditionFromWmoCode(0), WeatherCondition.clear);
      expect(conditionFromWmoCode(3), WeatherCondition.cloudy);
      expect(conditionFromWmoCode(61), WeatherCondition.rain);
      expect(conditionFromWmoCode(95), WeatherCondition.thunderstorm);
      expect(conditionFromWmoCode(null), WeatherCondition.unknown);
    });
  });

  group('pobieranie prognozy', () {
    test('próbkuje trasę i dopasowuje godzinę do czasu dojazdu', () async {
      final adapter = _StubAdapter();
      final service = RouteWeatherService(
        client: Dio()..httpClientAdapter = adapter,
      );

      // 60 km na wschód.
      final points = [
        for (var i = 0; i <= 600; i++) GeoPoint(lat: 52, lon: 21 + i * 0.00145),
      ];
      final forecast = await service.forecast(
        points: points,
        estimatedDuration: const Duration(hours: 3),
        departureAt: DateTime(2026, 6, 1, 10),
      );

      expect(forecast.points, isNotEmpty);
      expect(forecast.points.first.distanceMeters, 0);
      expect(forecast.points.last.arrivalAt.hour, 13);
      // Kierunek jazdy na wschód.
      expect(forecast.points.first.travelBearing, closeTo(90, 2));
      expect(adapter.calls, 1);
    });

    test('awaria prognozy nie psuje briefingu', () async {
      final service = RouteWeatherService(
        client: Dio()..httpClientAdapter = _StubAdapter(fail: true),
      );
      final forecast = await service.forecast(
        points: [
          const GeoPoint(lat: 52, lon: 21),
          const GeoPoint(lat: 52.1, lon: 21),
        ],
        estimatedDuration: const Duration(hours: 1),
      );
      expect(forecast.isEmpty, isTrue);
    });
  });
}

/// Odpowiada blokiem godzinowym dla każdej żądanej współrzędnej.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.fail = false});

  final bool fail;
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'brak sieci',
      );
    }

    final latitudes = '${options.queryParameters['latitude']}'.split(',');
    final times = [
      for (var hour = 8; hour < 20; hour++)
        DateTime(2026, 6, 1, hour).toIso8601String(),
    ];
    final blocks = [
      for (var i = 0; i < latitudes.length; i++)
        {
          'hourly': {
            'time': times,
            'temperature_2m': [for (final _ in times) 18.0],
            'apparent_temperature': [for (final _ in times) 17.0],
            'precipitation': [for (final _ in times) 0.0],
            'precipitation_probability': [for (final _ in times) 10],
            'weather_code': [for (final _ in times) 1],
            'wind_speed_10m': [for (final _ in times) 22.0],
            'wind_direction_10m': [for (final _ in times) 270.0],
            'wind_gusts_10m': [for (final _ in times) 35.0],
          },
          'daily': {
            'sunrise': ['2026-06-01T04:30'],
            'sunset': ['2026-06-01T21:00'],
          },
        },
    ];

    return ResponseBody.fromString(
      jsonEncode(blocks),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
