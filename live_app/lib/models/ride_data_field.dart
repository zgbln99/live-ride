import 'package:flutter/material.dart';

import '../core/formatters.dart';
import 'ride_metrics.dart';
import 'weather.dart';

/// How many Garmin-style data fields the ride computer shows.
enum RideFieldLayout {
  two(2, '2 fields'),
  four(4, '4 fields'),
  six(6, '6 fields'),
  eight(8, '8 fields');

  const RideFieldLayout(this.fieldCount, this.label);

  final int fieldCount;
  final String label;

  /// Columns used to lay the grid out.
  int get columns => switch (this) {
    RideFieldLayout.two => 1,
    RideFieldLayout.four => 2,
    RideFieldLayout.six => 2,
    RideFieldLayout.eight => 2,
  };

  int get rows => fieldCount ~/ columns;
}

/// Everything a data field may need to render itself.
class RideFieldContext {
  const RideFieldContext({
    required this.metrics,
    required this.metric,
    this.weather,
    this.remainingMeters,
    this.etaSeconds,
  });

  final RideMetrics metrics;
  final bool metric;
  final WeatherSnapshot? weather;
  final double? remainingMeters;
  final int? etaSeconds;
}

class RideFieldValue {
  const RideFieldValue(this.value, {this.unit = '', this.alert = false});

  final String value;
  final String unit;
  final bool alert;
}

/// The catalogue of data fields a rider can place on the ride computer.
enum RideDataField {
  speed('SPEED'),
  avgSpeed('AVG SPEED'),
  maxSpeed('MAX SPEED'),
  distance('DISTANCE'),
  elapsed('ELAPSED'),
  movingTime('MOVING'),
  elevation('ELEVATION'),
  elevationGain('ASCENT'),
  gradient('GRADIENT'),
  heartRate('HEART RATE'),
  avgHeartRate('AVG HR'),
  maxHeartRate('MAX HR'),
  gpsAccuracy('GPS'),
  temperature('TEMP'),
  wind('WIND'),
  rainChance('RAIN'),
  clock('TIME OF DAY'),
  remaining('REMAINING'),
  eta('ETA');

  const RideDataField(this.label);

  final String label;

  IconData? get icon => switch (this) {
    RideDataField.heartRate ||
    RideDataField.avgHeartRate ||
    RideDataField.maxHeartRate => Icons.favorite,
    RideDataField.temperature => Icons.thermostat,
    RideDataField.wind => Icons.air,
    RideDataField.rainChance => Icons.water_drop_outlined,
    RideDataField.gpsAccuracy => Icons.gps_fixed,
    _ => null,
  };

  RideFieldValue read(RideFieldContext context) {
    final m = context.metrics;
    final metric = context.metric;
    switch (this) {
      case RideDataField.speed:
        return RideFieldValue(
          Fmt.speed(m.speedKmh, metric: metric),
          unit: Fmt.speedUnit(metric: metric),
        );
      case RideDataField.avgSpeed:
        return RideFieldValue(
          Fmt.speed(m.averageSpeedKmh, metric: metric),
          unit: Fmt.speedUnit(metric: metric),
        );
      case RideDataField.maxSpeed:
        return RideFieldValue(
          Fmt.speed(m.maxSpeedKmh, metric: metric),
          unit: Fmt.speedUnit(metric: metric),
        );
      case RideDataField.distance:
        return RideFieldValue(
          Fmt.distance(m.distanceMeters, metric: metric),
          unit: Fmt.distanceUnit(metric: metric),
        );
      case RideDataField.elapsed:
        return RideFieldValue(Fmt.duration(m.elapsed));
      case RideDataField.movingTime:
        return RideFieldValue(Fmt.duration(m.movingTime));
      case RideDataField.elevation:
        return RideFieldValue(
          m.altitudeMeters == null
              ? '--'
              : Fmt.elevation(m.altitudeMeters!, metric: metric),
          unit: Fmt.elevationUnit(metric: metric),
        );
      case RideDataField.elevationGain:
        return RideFieldValue(
          Fmt.elevation(m.elevationGainMeters, metric: metric),
          unit: Fmt.elevationUnit(metric: metric),
        );
      case RideDataField.gradient:
        return RideFieldValue(Fmt.gradient(m.gradientPercent), unit: '%');
      case RideDataField.heartRate:
        return RideFieldValue(
          m.heartRate?.toString() ?? '--',
          unit: 'bpm',
          alert: false,
        );
      case RideDataField.avgHeartRate:
        return RideFieldValue(
          m.averageHeartRate?.toString() ?? '--',
          unit: 'bpm',
        );
      case RideDataField.maxHeartRate:
        return RideFieldValue(m.maxHeartRate?.toString() ?? '--', unit: 'bpm');
      case RideDataField.gpsAccuracy:
        final accuracy = m.gpsAccuracyMeters;
        return RideFieldValue(
          accuracy == null ? '--' : '±${accuracy.round()}',
          unit: 'm',
          alert: accuracy != null && accuracy > 25,
        );
      case RideDataField.temperature:
        final weather = context.weather;
        return RideFieldValue(
          weather == null
              ? '--'
              : Fmt.temperature(weather.temperatureCelsius, metric: metric),
        );
      case RideDataField.wind:
        final weather = context.weather;
        return RideFieldValue(
          weather == null
              ? '--'
              : '${Fmt.compass(weather.windDirectionDegrees)} '
                    '${Fmt.speed(weather.windSpeedKmh, metric: metric).split('.').first}',
          unit: Fmt.speedUnit(metric: metric),
        );
      case RideDataField.rainChance:
        final weather = context.weather;
        return RideFieldValue(
          weather?.precipitationProbability == null
              ? '--'
              : '${weather!.precipitationProbability}',
          unit: '%',
        );
      case RideDataField.clock:
        return RideFieldValue(Fmt.clock(DateTime.now()));
      case RideDataField.remaining:
        final remaining = context.remainingMeters;
        return RideFieldValue(
          remaining == null ? '--' : Fmt.distance(remaining, metric: metric),
          unit: Fmt.distanceUnit(metric: metric),
        );
      case RideDataField.eta:
        final eta = context.etaSeconds;
        if (eta == null) return const RideFieldValue('--');
        final arrival = DateTime.now().add(Duration(seconds: eta));
        return RideFieldValue(Fmt.clock(arrival));
    }
  }
}
