import 'package:flutter/material.dart';

import '../i18n/strings.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../models/weather.dart';

IconData weatherIcon(WeatherCondition condition, {bool isDay = true}) =>
    switch (condition) {
      WeatherCondition.clear =>
        isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
      WeatherCondition.partlyCloudy => Icons.wb_cloudy_outlined,
      WeatherCondition.cloudy => Icons.cloud_outlined,
      WeatherCondition.fog => Icons.foggy,
      WeatherCondition.drizzle => Icons.grain,
      WeatherCondition.rain => Icons.water_drop_outlined,
      WeatherCondition.heavyRain => Icons.water_drop,
      WeatherCondition.snow => Icons.ac_unit,
      WeatherCondition.thunderstorm => Icons.thunderstorm_outlined,
      WeatherCondition.unknown => Icons.help_outline,
    };

/// The compact weather readout shown over the map while riding.
///
/// It is deliberately unobtrusive and shows `--` when the forecast is
/// unavailable: weather never interrupts a ride.
class WeatherField extends StatelessWidget {
  const WeatherField({
    super.key,
    required this.weather,
    required this.metric,
    this.onTap,
  });

  final WeatherSnapshot? weather;
  final bool metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final snapshot = weather;
    return Material(
      color: LR.surface,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: LR.lineStrong),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                snapshot == null
                    ? Icons.cloud_off_outlined
                    : weatherIcon(snapshot.condition, isDay: snapshot.isDay),
                size: 18,
                color: LR.inkSoft,
              ),
              const SizedBox(width: 8),
              if (snapshot == null)
                Text('--', style: LR.fieldValue(16))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Fmt.temperature(
                        snapshot.temperatureCelsius,
                        metric: metric,
                      ),
                      style: LR.fieldValue(17),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.compass(snapshot.windDirectionDegrees)} '
                      '${Fmt.speed(snapshot.windSpeedKmh, metric: metric).split('.').first} '
                      '${Fmt.speedUnit(metric: metric)}'
                      '${snapshot.precipitationProbability == null ? '' : ' · ${snapshot.precipitationProbability}%'}',
                      style: LR.fieldLabel.copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The larger weather card used on the Ride tab.
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    required this.weather,
    required this.metric,
    this.error,
  });

  final WeatherSnapshot? weather;
  final bool metric;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final snapshot = weather;
    if (snapshot == null) {
      return Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 20, color: LR.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(error ?? S.weatherAppearsWithPosition, style: LR.body),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          weatherIcon(snapshot.condition, isDay: snapshot.isDay),
          size: 34,
          color: LR.ink,
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Fmt.temperature(snapshot.temperatureCelsius, metric: metric),
                  style: LR.fieldValue(30),
                ),
                const SizedBox(width: 8),
                Text(
                  'feels ${Fmt.temperature(snapshot.apparentTemperatureCelsius, metric: metric)}',
                  style: LR.body.copyWith(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              snapshot.condition.label,
              style: LR.body.copyWith(fontSize: 13),
            ),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${Fmt.compass(snapshot.windDirectionDegrees)} '
              '${Fmt.speed(snapshot.windSpeedKmh, metric: metric).split('.').first} '
              '${Fmt.speedUnit(metric: metric)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: LR.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              snapshot.precipitationProbability == null
                  ? 'no rain data'
                  : '${snapshot.precipitationProbability}% rain',
              style: LR.fieldLabel.copyWith(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
