import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/weather.dart';
import 'package:live_ride/services/weather_service.dart';

/// Answers every request with a canned payload, or an error.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.failure});

  final Map<String, dynamic> body;
  final Object? failure;
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
    final error = failure;
    if (error != null) throw error;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> openMeteoBody({int weatherCode = 3}) => {
  'current': {
    'temperature_2m': 18.4,
    'apparent_temperature': 17.2,
    'is_day': 1,
    'precipitation': 0.2,
    'weather_code': weatherCode,
    'wind_speed_10m': 14.3,
    'wind_direction_10m': 268,
  },
  'hourly': {
    'time': [
      DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    ],
    'precipitation_probability': [20, 65],
  },
};

Dio dioWith(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  const berlin = GeoPoint(lat: 52.52, lon: 13.405);

  test('maps an Open-Meteo response onto the snapshot', () async {
    final service = WeatherService(
      client: dioWith(_StubAdapter(openMeteoBody())),
    );
    final snapshot = await service.fetch(berlin);

    expect(snapshot.temperatureCelsius, 18.4);
    expect(snapshot.apparentTemperatureCelsius, 17.2);
    expect(snapshot.windSpeedKmh, 14.3);
    expect(snapshot.windDirectionDegrees, 268);
    expect(snapshot.condition, WeatherCondition.cloudy);
    expect(snapshot.isDay, isTrue);
    // The bucket covering "now" is the one that started in the past.
    expect(snapshot.precipitationProbability, 20);
  });

  test('translates WMO codes', () async {
    Future<WeatherCondition> conditionFor(int code) async {
      final service = WeatherService(
        client: dioWith(_StubAdapter(openMeteoBody(weatherCode: code))),
      );
      return (await service.fetch(berlin)).condition;
    }

    expect(await conditionFor(0), WeatherCondition.clear);
    expect(await conditionFor(2), WeatherCondition.partlyCloudy);
    expect(await conditionFor(45), WeatherCondition.fog);
    expect(await conditionFor(53), WeatherCondition.drizzle);
    expect(await conditionFor(63), WeatherCondition.rain);
    expect(await conditionFor(75), WeatherCondition.snow);
    expect(await conditionFor(95), WeatherCondition.thunderstorm);
  });

  test('a failure leaves the service usable and records the reason', () async {
    final service = WeatherService(
      client: dioWith(
        _StubAdapter(
          const {},
          failure: DioException.connectionError(
            requestOptions: RequestOptions(),
            reason: 'offline',
          ),
        ),
      ),
    );

    await service.refreshFor(berlin);

    expect(service.current, isNull);
    expect(service.lastError, isNotNull);
  });

  test('keeps the previous snapshot when a later fetch fails', () async {
    final good = _StubAdapter(openMeteoBody());
    final service = WeatherService(client: dioWith(good));
    await service.refreshFor(berlin);
    expect(service.current, isNotNull);

    service.dispose();
    final failing = WeatherService(
      client: dioWith(
        _StubAdapter(
          const {},
          failure: DioException.connectionError(
            requestOptions: RequestOptions(),
            reason: 'offline',
          ),
        ),
      ),
    );
    await failing.refreshFor(berlin);
    expect(failing.lastError, isNotNull);
  });

  test('does not refetch for a nearby position within the interval', () async {
    final adapter = _StubAdapter(openMeteoBody());
    final service = WeatherService(client: dioWith(adapter));

    await service.refreshFor(berlin);
    await service.refreshFor(const GeoPoint(lat: 52.525, lon: 13.41));

    expect(adapter.calls, 1);
  });

  test('backs off after a failure instead of retrying on every fix', () async {
    final adapter = _StubAdapter(
      const {},
      failure: DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'offline',
      ),
    );
    final service = WeatherService(client: dioWith(adapter));

    await service.refreshFor(berlin);
    await service.refreshFor(berlin);
    await service.refreshFor(const GeoPoint(lat: 52.53, lon: 13.41));

    expect(adapter.calls, 1);
  });

  test('refetches when the rider has moved to another region', () async {
    final adapter = _StubAdapter(openMeteoBody());
    final service = WeatherService(client: dioWith(adapter));

    await service.refreshFor(berlin);
    await service.refreshFor(const GeoPoint(lat: 48.13, lon: 11.58));

    expect(adapter.calls, 2);
  });
}
