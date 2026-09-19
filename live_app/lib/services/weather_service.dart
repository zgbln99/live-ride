import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../models/weather.dart';

/// Current conditions for the rider's position.
///
/// The default provider is Open-Meteo, which needs no API key, so a fresh
/// install has working weather with nothing to configure. A different endpoint
/// and key can be supplied at build time:
///
/// ```
/// flutter run --dart-define=LIVE_RIDE_WEATHER_URL=https://example/v1/forecast \
///             --dart-define=LIVE_RIDE_WEATHER_KEY=...
/// ```
///
/// Nothing here is ever awaited on a path that matters: if weather fails, the
/// ride computer simply shows `--`.
class WeatherService extends ChangeNotifier {
  WeatherService({Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

  static const String endpoint = String.fromEnvironment(
    'LIVE_RIDE_WEATHER_URL',
    defaultValue: 'https://api.open-meteo.com/v1/forecast',
  );

  /// Optional. Open-Meteo's free tier needs no key; a paid or self-hosted
  /// deployment can be pointed at with the defines above.
  static const String apiKey = String.fromEnvironment('LIVE_RIDE_WEATHER_KEY');

  /// Refetch at most this often, and only when the rider has moved enough for
  /// the forecast cell to change.
  static const Duration refreshInterval = Duration(minutes: 15);
  static const double refreshDistanceMeters = 12000;

  /// How long to wait before trying again after a failure.
  static const Duration retryInterval = Duration(minutes: 2);

  final Dio _dio;

  WeatherSnapshot? _current;
  GeoPoint? _lastPosition;
  DateTime? _lastFetch;
  bool _inFlight = false;
  String? _lastError;

  WeatherSnapshot? get current => _current;
  String? get lastError => _lastError;
  bool get isLoading => _inFlight;

  /// Fetches if the cached snapshot is stale or the rider has moved far.
  /// Never throws.
  Future<void> refreshFor(GeoPoint position, {bool force = false}) async {
    if (_inFlight) return;
    if (!force && _shouldSkip(position)) return;

    _inFlight = true;
    try {
      final snapshot = await fetch(position);
      _current = snapshot;
      _lastError = null;
      _lastPosition = position;
      _lastFetch = DateTime.now();
      notifyListeners();
    } catch (e) {
      _lastError = _describe(e);
      // Keep the previous snapshot: slightly old weather beats none.
      _lastFetch = DateTime.now();
      notifyListeners();
    } finally {
      _inFlight = false;
    }
  }

  bool _shouldSkip(GeoPoint position) {
    final fetchedAt = _lastFetch;
    if (fetchedAt == null) return false;
    final age = DateTime.now().difference(fetchedAt);
    // Nothing cached means the last attempt failed. Positions arrive every
    // couple of seconds, so back off rather than hammering the provider.
    if (_current == null) return age < retryInterval;
    if (age >= refreshInterval) return false;
    final previous = _lastPosition;
    if (previous == null) return false;
    return haversineMeters(previous, position) < refreshDistanceMeters;
  }

  Future<WeatherSnapshot> fetch(GeoPoint position) async {
    final response = await _dio.get<Map<String, dynamic>>(
      endpoint,
      queryParameters: {
        'latitude': position.lat.toStringAsFixed(4),
        'longitude': position.lon.toStringAsFixed(4),
        'current':
            'temperature_2m,apparent_temperature,is_day,precipitation,'
            'weather_code,wind_speed_10m,wind_direction_10m',
        'hourly': 'precipitation_probability',
        'forecast_days': 1,
        'timezone': 'auto',
        'wind_speed_unit': 'kmh',
        if (apiKey.isNotEmpty) 'apikey': apiKey,
      },
    );

    final data = response.data;
    if (data == null) {
      throw const FormatException('Empty weather response');
    }
    final current = data['current'];
    if (current is! Map) {
      throw const FormatException('Weather response has no current conditions');
    }

    return WeatherSnapshot(
      temperatureCelsius: _number(current['temperature_2m']) ?? 0,
      apparentTemperatureCelsius:
          _number(current['apparent_temperature']) ??
          _number(current['temperature_2m']) ??
          0,
      windSpeedKmh: _number(current['wind_speed_10m']) ?? 0,
      windDirectionDegrees: _number(current['wind_direction_10m']) ?? 0,
      condition: _conditionFromCode(_number(current['weather_code'])?.round()),
      isDay: (_number(current['is_day']) ?? 1) > 0,
      observedAt: DateTime.now(),
      precipitationProbability: _currentProbability(data['hourly']),
      precipitationMm: _number(current['precipitation']),
    );
  }

  /// Open-Meteo reports probability hourly; pick the bucket covering now.
  int? _currentProbability(Object? hourly) {
    if (hourly is! Map) return null;
    final values = hourly['precipitation_probability'];
    final times = hourly['time'];
    if (values is! List || values.isEmpty) return null;
    var index = 0;
    if (times is List && times.length == values.length) {
      final now = DateTime.now();
      for (var i = 0; i < times.length; i++) {
        final parsed = DateTime.tryParse('${times[i]}');
        if (parsed != null && parsed.isAfter(now)) {
          index = i == 0 ? 0 : i - 1;
          break;
        }
        index = i;
      }
    }
    final value = _number(values[index.clamp(0, values.length - 1)]);
    return value?.round();
  }

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// WMO weather interpretation codes, collapsed to what a rider cares about.
  WeatherCondition _conditionFromCode(int? code) {
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

  String _describe(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'Weather service timed out',
        DioExceptionType.badResponse =>
          'Weather service returned ${error.response?.statusCode}',
        _ => 'Weather service unreachable',
      };
    }
    return 'Weather unavailable';
  }
}
