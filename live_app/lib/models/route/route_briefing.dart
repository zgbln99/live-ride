import '../../core/formatters.dart';
import 'route_analysis.dart';
import 'route_preferences.dart';
import 'route_weather.dart';

/// Rodzaj wiersza briefingu — decyduje o ikonie i kolorze.
enum BriefingTone { neutral, good, warning }

/// Jedno zdanie briefingu.
class BriefingLine {
  const BriefingLine(this.text, {this.tone = BriefingTone.neutral});

  final String text;
  final BriefingTone tone;
}

/// Briefing przed jazdą.
///
/// Zasada jest jedna: żadnego zdania bez pokrycia w danych. Jeśli trasa nie
/// ma wysokości, nie ma zdań o podjazdach; jeśli prognoza nie doszła, nie ma
/// zdań o pogodzie. Pusty briefing jest lepszy od wymyślonego.
class RouteBriefing {
  const RouteBriefing({
    required this.headline,
    required this.lines,
    required this.analysis,
    required this.estimatedDuration,
    this.forecast,
    this.estimatedEnergyKj,
    this.suggestedStops = const [],
  });

  /// Najważniejsze liczby: dystans, przewyższenie, podjazdy, czas.
  final List<String> headline;

  final List<BriefingLine> lines;
  final RouteAnalysis analysis;
  final Duration estimatedDuration;
  final RouteForecast? forecast;
  final double? estimatedEnergyKj;

  /// Sugerowane postoje jako dystans od startu.
  final List<double> suggestedStops;

  bool get isEmpty => lines.isEmpty;

  static RouteBriefing build({
    required RouteAnalysis analysis,
    required RoutePreferences preferences,
    RouteForecast? forecast,
    double? riderWeightKg,
    bool metric = true,
  }) {
    final duration = analysis.estimatedDuration(
      assumedSpeedKmh: preferences.assumedSpeedKmh,
    );
    final lines = <BriefingLine>[];
    final headline = <String>[
      '${Fmt.distance(analysis.distanceMeters, metric: metric)} '
          '${Fmt.distanceUnit(metric: metric)}',
    ];

    if (analysis.hasElevationData) {
      headline.add(
        '${Fmt.elevation(analysis.ascentMeters, metric: metric)} '
        '${Fmt.elevationUnit(metric: metric)} ↑',
      );
    }
    final climbs = analysis.climbs;
    if (climbs.isNotEmpty) {
      headline.add('${climbs.length} ${_podjazdy(climbs.length)}');
    }
    if (duration > Duration.zero) {
      headline.add('około ${Fmt.durationCompact(duration)}');
    }

    // --- trudność -------------------------------------------------------
    lines.add(
      BriefingLine(
        'Trudność: ${analysis.difficulty.label.toLowerCase()}'
        '${analysis.hasElevationData ? ' · ${analysis.metersPerKilometre.toStringAsFixed(0)} m/km' : ''}',
        tone: switch (analysis.difficulty) {
          RouteDifficulty.easy => BriefingTone.good,
          RouteDifficulty.moderate => BriefingTone.neutral,
          RouteDifficulty.hard ||
          RouteDifficulty.veryHard => BriefingTone.warning,
        },
      ),
    );

    if (duration > Duration.zero) {
      final average = analysis.estimatedAverageSpeedKmh(
        assumedSpeedKmh: preferences.assumedSpeedKmh,
      );
      lines.add(
        BriefingLine(
          'Przewidywany czas ${Fmt.durationCompact(duration)}, '
          'średnia około ${Fmt.speed(average, metric: metric)} '
          '${Fmt.speedUnit(metric: metric)}.',
        ),
      );
    }

    // --- podjazdy -------------------------------------------------------
    final biggest = analysis.biggestClimb;
    if (biggest != null) {
      lines.add(
        BriefingLine(
          'Największy podjazd: '
          '${Fmt.distance(biggest.lengthMeters, metric: metric)} '
          '${Fmt.distanceUnit(metric: metric)} '
          'przy ${biggest.averageGradientPercent.toStringAsFixed(1)} % '
          '(${Fmt.elevation(biggest.gainMeters, metric: metric)} '
          '${Fmt.elevationUnit(metric: metric)}, ${biggest.category.label}), '
          'od ${Fmt.distance(biggest.startDistanceMeters, metric: metric)} '
          '${Fmt.distanceUnit(metric: metric)}.',
          tone: biggest.category.index >= ClimbCategory.two.index
              ? BriefingTone.warning
              : BriefingTone.neutral,
        ),
      );
    }

    final hard = climbs
        .where((climb) => climb.averageGradientPercent >= 7)
        .length;
    if (hard > 0) {
      lines.add(
        BriefingLine(
          '$hard ${_odcinki(hard)} o średnim nachyleniu ponad 7 %.',
          tone: BriefingTone.warning,
        ),
      );
    }

    if (analysis.hasElevationData && analysis.steepestGradientPercent >= 10) {
      lines.add(
        BriefingLine(
          'Najstromszy fragment: '
          '${analysis.steepestGradientPercent.toStringAsFixed(0)} %.',
          tone: BriefingTone.warning,
        ),
      );
    }

    if (analysis.hasElevationData && analysis.steepestDescentPercent <= -10) {
      lines.add(
        BriefingLine(
          'Najdłuższy zjazd sięga '
          '${analysis.steepestDescentPercent.abs().toStringAsFixed(0)} % — '
          'sprawdź hamulce.',
        ),
      );
    }

    // --- pogoda ---------------------------------------------------------
    if (forecast != null && !forecast.isEmpty) {
      final start = forecast.start!;
      lines.add(
        BriefingLine(
          'Na starcie ${Fmt.temperature(start.temperatureCelsius, metric: metric)}'
          '${(start.apparentTemperatureCelsius - start.temperatureCelsius).abs() >= 2 ? ' (odczuwalna ${Fmt.temperature(start.apparentTemperatureCelsius, metric: metric)})' : ''}, '
          '${start.condition.label.toLowerCase()}.',
        ),
      );

      final headwind = forecast.longestHeadwindStretch;
      if (headwind != null) {
        final length = headwind.toMeters - headwind.fromMeters;
        lines.add(
          BriefingLine(
            'Przez około ${Fmt.distance(length, metric: metric)} '
            '${Fmt.distanceUnit(metric: metric)} wiatr czołowy '
            '(od ${Fmt.distance(headwind.fromMeters, metric: metric)} '
            '${Fmt.distanceUnit(metric: metric)}).',
            tone: BriefingTone.warning,
          ),
        );
      } else {
        final tail = forecast.points
            .where((point) => point.windRelation == WindRelation.tail)
            .length;
        if (tail > forecast.points.length / 2) {
          lines.add(
            const BriefingLine(
              'Wiatr przez większość trasy wieje w plecy.',
              tone: BriefingTone.good,
            ),
          );
        }
      }

      final rain = forecast.firstRain;
      if (rain != null) {
        lines.add(
          BriefingLine(
            'Około ${Fmt.clock(rain.arrivalAt)} możliwy deszcz '
            '(${rain.precipitationProbability} %) '
            'na ${Fmt.distance(rain.distanceMeters, metric: metric)} '
            '${Fmt.distanceUnit(metric: metric)}.',
            tone: BriefingTone.warning,
          ),
        );
      }

      if (forecast.finishesAfterSunset && forecast.sunset != null) {
        lines.add(
          BriefingLine(
            'Zachód słońca o ${Fmt.clock(forecast.sunset!)} — meta wypada '
            'po zmroku, weź oświetlenie.',
            tone: BriefingTone.warning,
          ),
        );
      } else if (forecast.sunset != null) {
        lines.add(
          BriefingLine('Zachód słońca o ${Fmt.clock(forecast.sunset!)}.'),
        );
      }
    }

    // --- zaopatrzenie ---------------------------------------------------
    final energy = analysis.estimatedEnergyKj(
      riderWeightKg: riderWeightKg,
      assumedSpeedKmh: preferences.assumedSpeedKmh,
    );
    if (energy != null) {
      // Przy jeździe rekreacyjnej praca w kJ jest bliska spalonym kcal.
      lines.add(
        BriefingLine(
          'Szacowany wydatek około ${energy.round()} kJ '
          '(≈ ${(energy * 0.24).round()} kcal).',
        ),
      );
    }

    final hours = duration.inMinutes / 60;
    if (hours >= 1) {
      final bottles = (hours * 0.75).ceil();
      lines.add(
        BriefingLine(
          'Zabierz około $bottles ${_bidony(bottles)} wody'
          '${hours >= 2 ? ' i jedzenie na drogę' : ''}.',
        ),
      );
    }

    // --- postoje --------------------------------------------------------
    final stops = <double>[];
    if (analysis.distanceMeters > 45000) {
      // Postój co około 40 km albo przed największym podjazdem.
      final interval = analysis.distanceMeters > 120000 ? 50000.0 : 40000.0;
      for (
        var distance = interval;
        distance < analysis.distanceMeters - 8000;
        distance += interval
      ) {
        stops.add(distance);
      }
      if (biggest != null && biggest.startDistanceMeters > 15000) {
        final before = biggest.startDistanceMeters - 2000;
        if (!stops.any((stop) => (stop - before).abs() < 8000)) {
          stops
            ..add(before)
            ..sort();
        }
      }
    }
    if (stops.isNotEmpty) {
      lines.add(
        BriefingLine(
          '${stops.length} ${_postoje(stops.length)}: '
          '${stops.map((stop) => '${Fmt.distance(stop, metric: metric)} ${Fmt.distanceUnit(metric: metric)}').join(', ')}.',
        ),
      );
    }

    return RouteBriefing(
      headline: headline,
      lines: List.unmodifiable(lines),
      analysis: analysis,
      estimatedDuration: duration,
      forecast: forecast,
      estimatedEnergyKj: energy,
      suggestedStops: List.unmodifiable(stops),
    );
  }

  static String _podjazdy(int count) {
    if (count == 1) return 'podjazd';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'podjazdy';
    return 'podjazdów';
  }

  static String _odcinki(int count) {
    if (count == 1) return 'odcinek';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'odcinki';
    return 'odcinków';
  }

  static String _bidony(int count) {
    if (count == 1) return 'bidon';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) return 'bidony';
    return 'bidonów';
  }

  static String _postoje(int count) {
    if (count == 1) return 'sugerowany postój';
    final rest = count % 10;
    final teen = count % 100;
    if (rest >= 2 && rest <= 4 && (teen < 12 || teen > 14)) {
      return 'sugerowane postoje';
    }
    return 'sugerowanych postojów';
  }
}
