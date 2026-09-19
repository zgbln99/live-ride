import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../models/route/route_weather.dart';
import 'weather_field.dart';

/// Pogoda wzdłuż trasy: temperatura, wiatr i opady w punktach, przez które
/// zawodnik będzie przejeżdżał, o godzinie, o której tam dotrze.
class RouteWeatherStrip extends StatelessWidget {
  const RouteWeatherStrip({
    super.key,
    required this.forecast,
    this.metric = true,
  });

  final RouteForecast forecast;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    if (forecast.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: forecast.points.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) =>
            _WeatherCard(point: forecast.points[index], metric: metric),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.point, required this.metric});

  final RouteWeatherPoint point;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final headwind = point.headwindComponentKmh;
    final windColor = switch (point.windRelation) {
      WindRelation.head => point.isSignificant ? LR.alert : LR.inkSoft,
      WindRelation.tail => LR.go,
      WindRelation.cross => LR.inkSoft,
    };

    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LR.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LR.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Fmt.distance(point.distanceMeters, metric: metric)} '
            '${Fmt.distanceUnit(metric: metric)}',
            style: LR.fieldLabel,
          ),
          Text(
            Fmt.clock(point.arrivalAt),
            style: LR.body.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(weatherIcon(point.condition), size: 20, color: LR.inkSoft),
              const SizedBox(width: 6),
              Text(
                Fmt.temperature(point.temperatureCelsius, metric: metric),
                style: LR.fieldValue(20),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            point.condition.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LR.body.copyWith(fontSize: 11),
          ),
          const Spacer(),
          Row(
            children: [
              Transform.rotate(
                // Strzałka pokazuje, dokąd wiatr wieje względem jazdy:
                // w górę to prosto w twarz.
                angle: (point.relativeWindAngle + 180) * 3.1415926535 / 180,
                child: Icon(Icons.navigation, size: 16, color: windColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${point.windSpeedKmh.round()} ${Fmt.speedUnit(metric: metric)}',
                  style: LR.body.copyWith(fontSize: 12, color: windColor),
                ),
              ),
            ],
          ),
          Text(
            point.windRelation.label +
                (headwind.abs() >= 5
                    ? ' · ${headwind.abs().round()} ${Fmt.speedUnit(metric: metric)}'
                    : ''),
            style: LR.body.copyWith(fontSize: 11, color: windColor),
          ),
          if ((point.precipitationProbability ?? 0) > 0)
            Text(
              'Opady ${point.precipitationProbability} %',
              style: LR.body.copyWith(
                fontSize: 11,
                color: point.willRain ? LR.alert : LR.muted,
              ),
            ),
        ],
      ),
    );
  }
}
