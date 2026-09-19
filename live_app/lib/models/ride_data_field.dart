import 'package:flutter/material.dart';

import '../core/formatters.dart';
import 'ride_metrics.dart';
import 'training.dart';
import 'weather.dart';

/// Ile pól danych pokazuje strona komputera rowerowego.
enum RideFieldLayout {
  one(1, '1 pole'),
  two(2, '2 pola'),
  three(3, '3 pola'),
  four(4, '4 pola'),
  six(6, '6 pól'),
  eight(8, '8 pól');

  const RideFieldLayout(this.fieldCount, this.label);

  final int fieldCount;
  final String label;

  /// Kolumny siatki. Jedno i trzy pola idą w słupku, bo przy trzech
  /// kolumnach cyfry robią się nieczytelne w ruchu.
  int get columns => switch (this) {
    RideFieldLayout.one => 1,
    RideFieldLayout.two => 1,
    RideFieldLayout.three => 1,
    RideFieldLayout.four => 2,
    RideFieldLayout.six => 2,
    RideFieldLayout.eight => 2,
  };

  int get rows => fieldCount ~/ columns;

  /// Ile miejsca chcą pola danych, zanim ekran powie swoje.
  ///
  /// Jedna liczba dla ekranu jazdy i dla testów układu, żeby nie rozjechały
  /// się przy dodaniu kolejnego układu.
  double get preferredHeight => switch (this) {
    RideFieldLayout.one => 150,
    RideFieldLayout.two => 190,
    RideFieldLayout.three => 240,
    RideFieldLayout.four => 194,
    RideFieldLayout.six => 252,
    RideFieldLayout.eight => 296,
  };

  static RideFieldLayout parse(String? value) =>
      RideFieldLayout.values.firstWhere(
        (layout) => layout.name == value,
        orElse: () => RideFieldLayout.four,
      );
}

/// Grupa, do której należy pole — porządkuje edytor pól.
enum RideFieldGroup {
  ride('Jazda'),
  elevation('Wysokość'),
  heartRate('Tętno'),
  power('Moc'),
  cadence('Kadencja'),
  navigation('Nawigacja'),
  environment('Otoczenie');

  const RideFieldGroup(this.label);

  final String label;
}

/// Everything a data field may need to render itself.
class RideFieldContext {
  const RideFieldContext({
    required this.metrics,
    required this.metric,
    this.weather,
    this.remainingMeters,
    this.etaSeconds,
    this.training,
    this.riderWeightKg,
  });

  final RideMetrics metrics;
  final bool metric;
  final WeatherSnapshot? weather;
  final double? remainingMeters;
  final int? etaSeconds;

  /// Potrzebny tylko polom stref; bez niego strefy się nie pokazują.
  final TrainingProfile? training;

  final double? riderWeightKg;
}

class RideFieldValue {
  const RideFieldValue(this.value, {this.unit = '', this.alert = false});

  final String value;
  final String unit;
  final bool alert;
}

/// Katalog pól danych, które zawodnik może ułożyć na komputerze.
///
/// Pole, którego nie da się policzyć, pokazuje „--" zamiast zera: zero to
/// konkretna informacja („stoisz"), a jej udawanie przy braku sensora jest
/// dokładnie tym rodzajem kłamstwa, którego licznik nie może popełniać.
enum RideDataField {
  speed('PRĘDKOŚĆ', RideFieldGroup.ride),
  avgSpeed('ŚR. PRĘDKOŚĆ', RideFieldGroup.ride),
  maxSpeed('MAKS. PRĘDKOŚĆ', RideFieldGroup.ride),
  sensorSpeed('PRĘDKOŚĆ Z CZUJNIKA', RideFieldGroup.ride),
  distance('DYSTANS', RideFieldGroup.ride),
  elapsed('CZAS', RideFieldGroup.ride),
  movingTime('CZAS W RUCHU', RideFieldGroup.ride),
  clock('GODZINA', RideFieldGroup.ride),
  calories('KALORIE', RideFieldGroup.ride),
  elevation('WYSOKOŚĆ', RideFieldGroup.elevation),
  elevationGain('PRZEWYŻSZENIE', RideFieldGroup.elevation),
  elevationLoss('SPADEK', RideFieldGroup.elevation),
  gradient('NACHYLENIE', RideFieldGroup.elevation),
  vam('VAM', RideFieldGroup.elevation),
  heartRate('TĘTNO', RideFieldGroup.heartRate),
  avgHeartRate('ŚR. TĘTNO', RideFieldGroup.heartRate),
  maxHeartRate('MAKS. TĘTNO', RideFieldGroup.heartRate),
  heartRateZone('STREFA TĘTNA', RideFieldGroup.heartRate),
  heartRatePercent('% HR MAX', RideFieldGroup.heartRate),
  power('MOC', RideFieldGroup.power),
  avgPower('ŚR. MOC', RideFieldGroup.power),
  maxPower('MAKS. MOC', RideFieldGroup.power),
  power3s('MOC 3 s', RideFieldGroup.power),
  power10s('MOC 10 s', RideFieldGroup.power),
  power30s('MOC 30 s', RideFieldGroup.power),
  normalizedPower('MOC NORMALIZOWANA', RideFieldGroup.power),
  intensityFactor('IF', RideFieldGroup.power),
  trainingStress('TSS', RideFieldGroup.power),
  powerZone('STREFA MOCY', RideFieldGroup.power),
  powerPerKg('W/KG', RideFieldGroup.power),
  pedalBalance('BALANS', RideFieldGroup.power),
  work('PRACA', RideFieldGroup.power),
  cadence('KADENCJA', RideFieldGroup.cadence),
  avgCadence('ŚR. KADENCJA', RideFieldGroup.cadence),
  maxCadence('MAKS. KADENCJA', RideFieldGroup.cadence),
  remaining('DO METY', RideFieldGroup.navigation),
  eta('NA MECIE', RideFieldGroup.navigation),
  gpsAccuracy('GPS', RideFieldGroup.navigation),
  temperature('TEMPERATURA', RideFieldGroup.environment),
  wind('WIATR', RideFieldGroup.environment),
  rainChance('DESZCZ', RideFieldGroup.environment);

  const RideDataField(this.label, this.group);

  final String label;
  final RideFieldGroup group;

  static RideDataField? parse(String? value) {
    for (final field in RideDataField.values) {
      if (field.name == value) return field;
    }
    return null;
  }

  /// Pola, które bez sensora pokazywałyby tylko „--".
  bool get needsPowerMeter => group == RideFieldGroup.power;
  bool get needsCadenceSensor => group == RideFieldGroup.cadence;
  bool get needsHeartRateSensor => group == RideFieldGroup.heartRate;

  IconData? get icon => switch (group) {
    RideFieldGroup.heartRate => Icons.favorite,
    RideFieldGroup.power => Icons.bolt,
    RideFieldGroup.cadence => Icons.rotate_right,
    _ => switch (this) {
      RideDataField.temperature => Icons.thermostat,
      RideDataField.wind => Icons.air,
      RideDataField.rainChance => Icons.water_drop_outlined,
      RideDataField.gpsAccuracy => Icons.gps_fixed,
      _ => null,
    },
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

      // ------------------------------------------------------------ nowe
      case RideDataField.sensorSpeed:
        final speed = m.sensorSpeedKmh;
        return RideFieldValue(
          speed == null ? '--' : Fmt.speed(speed, metric: metric),
          unit: Fmt.speedUnit(metric: metric),
        );
      case RideDataField.calories:
        // Bez miernika mocy nie ma z czego policzyć kalorii uczciwie.
        final work = m.workKj;
        return RideFieldValue(
          work == null ? '--' : (work * 0.24).round().toString(),
          unit: 'kcal',
        );
      case RideDataField.elevationLoss:
        return RideFieldValue(
          Fmt.elevation(m.elevationLossMeters, metric: metric),
          unit: Fmt.elevationUnit(metric: metric),
        );
      case RideDataField.vam:
        // Metry wzniesienia na godzinę — miara tempa na podjeździe.
        final hours = m.movingTime.inMilliseconds / 3600000;
        if (hours <= 0 || m.elevationGainMeters <= 0) {
          return const RideFieldValue('--', unit: 'm/h');
        }
        return RideFieldValue(
          (m.elevationGainMeters / hours).round().toString(),
          unit: 'm/h',
        );
      case RideDataField.heartRateZone:
        final zone = context.training?.heartRateZoneFor(m.heartRate);
        return RideFieldValue(zone == null ? '--' : 'Z$zone');
      case RideDataField.heartRatePercent:
        final max = context.training?.maxHeartRate;
        final bpm = m.heartRate;
        if (max == null || max <= 0 || bpm == null) {
          return const RideFieldValue('--', unit: '%');
        }
        return RideFieldValue((bpm / max * 100).round().toString(), unit: '%');
      case RideDataField.power:
        return _watts(m.power?.current);
      case RideDataField.avgPower:
        return _watts(m.power?.average);
      case RideDataField.maxPower:
        return _watts(m.power?.maximum);
      case RideDataField.power3s:
        return _watts(m.power?.threeSecond);
      case RideDataField.power10s:
        return _watts(m.power?.tenSecond);
      case RideDataField.power30s:
        return _watts(m.power?.thirtySecond);
      case RideDataField.normalizedPower:
        return _watts(m.power?.normalized);
      case RideDataField.intensityFactor:
        final intensity = m.power?.intensityFactor;
        return RideFieldValue(
          intensity == null ? '--' : intensity.toStringAsFixed(2),
        );
      case RideDataField.trainingStress:
        final tss = m.power?.trainingStressScore;
        return RideFieldValue(tss == null ? '--' : tss.round().toString());
      case RideDataField.powerZone:
        final zone = context.training?.powerZoneFor(m.power?.current);
        return RideFieldValue(zone == null ? '--' : 'Z$zone');
      case RideDataField.powerPerKg:
        final watts = m.power?.current;
        final weight = context.riderWeightKg;
        if (watts == null || weight == null || weight <= 0) {
          return const RideFieldValue('--', unit: 'W/kg');
        }
        return RideFieldValue(
          (watts / weight).toStringAsFixed(1),
          unit: 'W/kg',
        );
      case RideDataField.pedalBalance:
        final balance = m.power?.balancePercent;
        return RideFieldValue(
          balance == null
              ? '--'
              : '${balance.round()}/${(100 - balance).round()}',
        );
      case RideDataField.work:
        final work = m.workKj;
        return RideFieldValue(
          work == null ? '--' : work.round().toString(),
          unit: 'kJ',
        );
      case RideDataField.cadence:
        return _rpm(m.cadenceRpm);
      case RideDataField.avgCadence:
        return _rpm(m.averageCadenceRpm);
      case RideDataField.maxCadence:
        return _rpm(m.maxCadenceRpm);
    }
  }

  static RideFieldValue _watts(int? value) =>
      RideFieldValue(value?.toString() ?? '--', unit: 'W');

  static RideFieldValue _rpm(double? value) => RideFieldValue(
    value == null ? '--' : value.round().toString(),
    unit: 'rpm',
  );
}
