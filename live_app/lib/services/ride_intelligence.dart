import 'dart:math' as math;

import '../models/ride_metrics.dart';
import '../models/ride_record.dart';
import '../models/route/route_analysis.dart';
import '../models/weather.dart';

/// Jak pewna jest liczba, którą pokazujemy.
enum InsightConfidence {
  /// Za mało danych, żeby cokolwiek twierdzić.
  calibrating,

  /// Wystarczy na szacunek z przedziałem.
  estimate,

  /// Policzone z dostatecznej próbki.
  solid,
}

enum InsightKind { pace, climb, wind, weather, eta, battery, gps, fuel, plan }

enum InsightPriority { info, notable, urgent }

/// Jedna rzecz warta powiedzenia w trakcie jazdy.
class RideInsight {
  const RideInsight({
    required this.kind,
    required this.title,
    required this.body,
    this.priority = InsightPriority.info,
  });

  final InsightKind kind;

  /// Nagłówek wersalikami: „WIATR", „ETA", „PODJAZD".
  final String title;

  final String body;
  final InsightPriority priority;
}

/// Przewidywana godzina przyjazdu razem z tym, ile jest warta.
class EtaEstimate {
  const EtaEstimate({this.at, this.spread, required this.confidence});

  final DateTime? at;

  /// Połowa przedziału: „14:31 ±8 min".
  final Duration? spread;

  final InsightConfidence confidence;

  bool get isUsable => at != null && confidence != InsightConfidence.calibrating;
}

/// Profil zawodnika policzony z jego WŁASNYCH przejazdów.
///
/// Wszystko lokalnie, z bazy na telefonie. Żaden model w chmurze nie wie
/// o tym zawodniku nic, czego nie wie jego licznik — a dane zdrowotne nie
/// opuszczają urządzenia.
class RiderHistoryProfile {
  const RiderHistoryProfile({
    required this.rideCount,
    required this.movingAverageKmh,
    required this.typicalDistanceMeters,
    required this.typicalAscentPerKm,
    this.averageHeartRate,
  });

  final int rideCount;
  final double movingAverageKmh;
  final double typicalDistanceMeters;
  final double typicalAscentPerKm;
  final int? averageHeartRate;

  /// Ile przejazdów trzeba, żeby średnia cokolwiek znaczyła.
  ///
  /// Trzy to minimum, przy którym jeden wyjątkowo dobry albo wyjątkowo zły
  /// dzień nie przesuwa całego profilu.
  static const int minimumRides = 3;

  bool get isUsable => rideCount >= minimumRides && movingAverageKmh > 5;

  static const RiderHistoryProfile empty = RiderHistoryProfile(
    rideCount: 0,
    movingAverageKmh: 0,
    typicalDistanceMeters: 0,
    typicalAscentPerKm: 0,
  );

  /// Buduje profil z historii.
  ///
  /// Bierze pod uwagę tylko przejazdy, które w ogóle były przejazdami:
  /// dwukilometrowy dojazd do sklepu i pięciominutowy test licznika
  /// przesuwałyby średnią w stronę, która nic nie opisuje.
  factory RiderHistoryProfile.fromRides(List<RecordedRide> rides) {
    final usable = rides
        .where((ride) => ride.distanceMeters >= 5000 && ride.movingSeconds > 600)
        .toList();
    if (usable.isEmpty) return empty;

    var distance = 0.0;
    var moving = 0.0;
    var ascent = 0.0;
    var heartRateSum = 0;
    var heartRateCount = 0;
    for (final ride in usable) {
      distance += ride.distanceMeters;
      moving += ride.movingSeconds;
      ascent += ride.elevationGainMeters;
      final bpm = ride.averageHeartRate;
      if (bpm != null && bpm > 0) {
        heartRateSum += bpm;
        heartRateCount++;
      }
    }

    return RiderHistoryProfile(
      rideCount: usable.length,
      movingAverageKmh: moving <= 0 ? 0 : distance / moving * 3.6,
      typicalDistanceMeters: distance / usable.length,
      typicalAscentPerKm: distance <= 0 ? 0 : ascent / (distance / 1000),
      averageHeartRate: heartRateCount == 0
          ? null
          : (heartRateSum / heartRateCount).round(),
    );
  }
}

/// Wszystko, czego Ride Intelligence potrzebuje, żeby coś powiedzieć.
class RideContext {
  const RideContext({
    required this.metrics,
    required this.profile,
    this.remainingMeters,
    this.routeAscentAheadMeters,
    this.upcomingClimb,
    this.metersToUpcomingClimb,
    this.activeClimb,
    this.climbRemainingMeters,
    this.weather,
    this.batteryPercent,
    this.gpsAccuracyMeters,
    this.plannedDistanceMeters,
    this.plannedDuration,
    this.now,
  });

  final RideMetrics metrics;
  final RiderHistoryProfile profile;

  /// Ile zostało do mety planu. Null przy wolnej jeździe.
  final double? remainingMeters;

  final double? routeAscentAheadMeters;
  final Climb? upcomingClimb;
  final double? metersToUpcomingClimb;
  final Climb? activeClimb;
  final double? climbRemainingMeters;
  final WeatherSnapshot? weather;
  final int? batteryPercent;
  final double? gpsAccuracyMeters;
  final double? plannedDistanceMeters;
  final Duration? plannedDuration;
  final DateTime? now;

  DateTime get moment => now ?? DateTime.now();
}

/// Warstwa, która patrzy na jazdę i mówi to, co warto powiedzieć.
///
/// Nie jest asystentem i nie prowadzi rozmowy. Jest przyrządem: bierze liczby,
/// które i tak już mamy, i zamienia je w zdania, których nie da się odczytać
/// z samego pulpitu — „za siedem kilometrów skręcisz pod wiatr" nie stoi na
/// żadnym z pól danych.
///
/// Trzy zasady:
///
///  1. NIC BEZ PRÓBKI. Każda przepowiednia ma próg, poniżej którego mówimy
///     „kalibruję", a nie zmyśloną liczbę z dwucyfrową precyzją.
///  2. TO NIE JEST PORADA MEDYCZNA. Tętno rosnące przy tym samym wysiłku jest
///     obserwacją, nie diagnozą, i tak jest nazwane.
///  3. BEZ SPAMU. Ta sama rzecz mówiona co minutę przestaje być informacją.
class RideIntelligence {
  /// Ile trzeba jechać, żeby ETA przestała być zgadywaniem.
  static const Duration etaWarmup = Duration(minutes: 10);

  /// …i ile kilometrów.
  static const double etaWarmupMeters = 2000;

  /// Powyżej tej dokładności GPS przestajemy ufać pozycji.
  static const double poorGpsAccuracyMeters = 25;

  /// Przewidywany czas przyjazdu.
  ///
  /// Liczony z tempa CAŁEJ jazdy, nie z prędkości chwilowej: ETA skaczące
  /// od czterdziestu minut do czterech godzin przy każdym podjeździe jest
  /// gorsze niż jego brak. Przedział bierze się z tego, ile jeszcze
  /// przewyższenia zostało — teren przed nami jest największym źródłem
  /// niepewności, jakie znamy.
  static EtaEstimate eta(RideContext context) {
    final remaining = context.remainingMeters;
    if (remaining == null || remaining <= 0) {
      return const EtaEstimate(confidence: InsightConfidence.calibrating);
    }

    final moving = context.metrics.movingTime;
    final ridden = context.metrics.distanceMeters;
    if (moving < etaWarmup || ridden < etaWarmupMeters) {
      // Trzy minuty jazdy nie wystarczą, żeby podać godzinę co do minuty.
      return const EtaEstimate(confidence: InsightConfidence.calibrating);
    }

    final paceKmh = ridden / moving.inSeconds * 3.6;
    if (paceKmh < 4 || paceKmh > 70) {
      return const EtaEstimate(confidence: InsightConfidence.calibrating);
    }

    final seconds = remaining / 1000 / paceKmh * 3600;
    // Przewyższenie przed nami spowalnia: każde sto metrów w pionie to
    // mniej więcej dodatkowa minuta i kilkanaście sekund.
    final ascent = context.routeAscentAheadMeters ?? 0;
    final penalty = ascent / 100 * 75;
    final total = seconds + penalty;

    // Przedział zwęża się razem z przejechanym dystansem i rozszerza z
    // przewyższeniem, którego jeszcze nie znamy z doświadczenia.
    final base = total * 0.12;
    final settled = moving > const Duration(minutes: 30) ? 0.6 : 1.0;
    final spread = Duration(
      seconds: math.max(120, (base * settled + penalty * 0.5).round()),
    );

    return EtaEstimate(
      at: context.moment.add(Duration(seconds: total.round())),
      spread: spread,
      confidence: moving > const Duration(minutes: 30)
          ? InsightConfidence.solid
          : InsightConfidence.estimate,
    );
  }

  /// Czy naprawdę zjechaliśmy z trasy, czy to tylko GPS.
  ///
  /// Trzydzieści metrów błędu pomiaru wygląda dokładnie tak samo jak
  /// trzydzieści metrów objazdu. Pod drzewami i między blokami fałszywy
  /// alarm potrafi wyskakiwać co kilkanaście sekund, więc próg rośnie razem
  /// z niepewnością pozycji: przy dokładności ±4 m wystarczy osiemdziesiąt
  /// metrów, przy ±40 m trzeba już prawie dwustu.
  static bool offRouteConfident({
    required double offRouteMeters,
    double? gpsAccuracyMeters,
    double baseThresholdMeters = 80,
  }) {
    final accuracy = gpsAccuracyMeters ?? 0;
    final threshold = baseThresholdMeters + accuracy * 3;
    return offRouteMeters > threshold;
  }

  /// Insighty warte pokazania TERAZ.
  ///
  /// Kolejność jest ważniejsza niż liczba: panel pokazuje pierwsze dwa albo
  /// trzy, więc pilne muszą być na górze.
  static List<RideInsight> during(RideContext context) {
    final insights = <RideInsight>[
      ...?_gps(context),
      ...?_climb(context),
      ...?_pace(context),
      ...?_weather(context),
      ...?_plan(context),
      ...?_battery(context),
    ];
    insights.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    return insights;
  }

  static List<RideInsight>? _gps(RideContext context) {
    final accuracy = context.gpsAccuracyMeters;
    if (accuracy == null || accuracy <= poorGpsAccuracyMeters) return null;
    return [
      RideInsight(
        kind: InsightKind.gps,
        title: 'GPS',
        body: 'Słaby sygnał, ±${accuracy.round()} m. '
            'Dystans i pozycja mogą być niedokładne.',
        priority: InsightPriority.notable,
      ),
    ];
  }

  static List<RideInsight>? _climb(RideContext context) {
    final active = context.activeClimb;
    final remaining = context.climbRemainingMeters;
    if (active != null && remaining != null && remaining > 50) {
      final gainLeft = active.gainMeters *
          (remaining / math.max(active.lengthMeters, 1)).clamp(0.0, 1.0);
      return [
        RideInsight(
          kind: InsightKind.climb,
          title: 'PODJAZD',
          body: '${_km(remaining)} pozostało, '
              'średnio ${active.averageGradientPercent.toStringAsFixed(1)}%'
              '${gainLeft >= 20 ? ', +${gainLeft.round()} m' : ''}',
          priority: InsightPriority.notable,
        ),
      ];
    }

    final upcoming = context.upcomingClimb;
    final distance = context.metersToUpcomingClimb;
    if (upcoming != null && distance != null && distance > 0) {
      return [
        RideInsight(
          kind: InsightKind.climb,
          title: 'PODJAZD',
          body: 'Za ${_km(distance)}: ${_km(upcoming.lengthMeters)}, '
              '${upcoming.averageGradientPercent.toStringAsFixed(1)}%, '
              '+${upcoming.gainMeters.round()} m',
        ),
      ];
    }
    return null;
  }

  static List<RideInsight>? _pace(RideContext context) {
    final profile = context.profile;
    if (!profile.isUsable) return null;
    final moving = context.metrics.movingTime;
    // Kwadrans to minimum, przy którym „jedziesz szybciej niż zwykle"
    // opisuje jazdę, a nie pierwszy zjazd z górki.
    if (moving < const Duration(minutes: 15)) return null;
    final ridden = context.metrics.distanceMeters;
    if (ridden < 4000) return null;

    final pace = ridden / moving.inSeconds * 3.6;
    final difference = pace - profile.movingAverageKmh;
    if (difference.abs() < 1.0) {
      return [
        const RideInsight(
          kind: InsightKind.pace,
          title: 'TEMPO',
          body: 'Trzymasz swoje zwykłe tempo.',
        ),
      ];
    }

    // Przeliczamy różnicę na minuty, bo „o 1,8 km/h szybciej" nic nie mówi,
    // a „osiem minut szybciej niż zwykle" mówi wszystko.
    final usualSeconds = ridden / 1000 / profile.movingAverageKmh * 3600;
    final gap = Duration(seconds: (usualSeconds - moving.inSeconds).round());
    final faster = difference > 0;
    return [
      RideInsight(
        kind: InsightKind.pace,
        title: 'TEMPO',
        body: faster
            ? 'Jedziesz ~${_minutes(gap)} szybciej niż zwykle.'
            : 'Jedziesz ~${_minutes(-gap)} wolniej niż zwykle.',
      ),
    ];
  }

  static List<RideInsight>? _weather(RideContext context) {
    final weather = context.weather;
    if (weather == null) return null;
    final out = <RideInsight>[];

    final rain = weather.precipitationProbability ?? 0;
    if (rain >= 50) {
      out.add(
        RideInsight(
          kind: InsightKind.weather,
          title: 'POGODA',
          body: 'Deszcz prawdopodobny ($rain%).',
          priority: InsightPriority.notable,
        ),
      );
    }

    // Zachód słońca kontra ETA. „Wrócisz po ciemku" to jedyna informacja
    // pogodowa, która zmienia decyzję jeszcze przed wyjazdem.
    final estimate = eta(context);
    final sunset = weather.sunset;
    if (estimate.isUsable && sunset != null && estimate.at!.isAfter(sunset)) {
      out.add(
        RideInsight(
          kind: InsightKind.weather,
          title: 'ŚWIATŁO',
          body: 'Zachód ${_clock(sunset)}, przyjazd ${_clock(estimate.at!)} '
              '— ostatni odcinek po zmroku.',
          priority: InsightPriority.notable,
        ),
      );
    }

    if (weather.windSpeedKmh >= 20) {
      out.add(
        RideInsight(
          kind: InsightKind.wind,
          title: 'WIATR',
          body: '${weather.windSpeedKmh.round()} km/h '
              '${_compass(weather.windDirectionDegrees)}.',
        ),
      );
    }
    return out.isEmpty ? null : out;
  }

  static List<RideInsight>? _plan(RideContext context) {
    final planned = context.plannedDistanceMeters;
    final duration = context.plannedDuration;
    if (planned == null || duration == null || duration.inMinutes < 10) {
      return null;
    }
    final moving = context.metrics.movingTime;
    if (moving < const Duration(minutes: 10)) return null;

    final plannedPace = planned / 1000 / (duration.inSeconds / 3600);
    final actualPace =
        context.metrics.distanceMeters / moving.inSeconds * 3.6;
    final expectedSeconds =
        context.metrics.distanceMeters / 1000 / plannedPace * 3600;
    final gap = Duration(seconds: (expectedSeconds - moving.inSeconds).round());
    if (gap.inMinutes.abs() < 2) return null;

    return [
      RideInsight(
        kind: InsightKind.plan,
        title: 'PLAN',
        body: gap.isNegative
            ? '${_minutes(-gap)} za planem '
                  '(${actualPace.toStringAsFixed(1)} zamiast '
                  '${plannedPace.toStringAsFixed(1)} km/h)'
            : '${_minutes(gap)} przed planem '
                  '(${actualPace.toStringAsFixed(1)} zamiast '
                  '${plannedPace.toStringAsFixed(1)} km/h)',
      ),
    ];
  }

  static List<RideInsight>? _battery(RideContext context) {
    final battery = context.batteryPercent;
    if (battery == null || battery > 20) return null;
    final estimate = eta(context);
    final body = estimate.isUsable
        ? 'Telefon $battery%. Do mety jeszcze '
              '${_minutes(estimate.at!.difference(context.moment))}.'
        : 'Telefon $battery%.';
    return [
      RideInsight(
        kind: InsightKind.battery,
        title: 'BATERIA',
        body: body,
        priority: battery <= 10
            ? InsightPriority.urgent
            : InsightPriority.notable,
      ),
    ];
  }

  // ------------------------------------------------------------- po jeździe

  /// Rzeczy, które naprawdę się wydarzyły — wyłącznie z policzonych liczb.
  static List<String> highlights(
    RecordedRide ride, {
    RiderHistoryProfile? profile,
  }) {
    final out = <String>[];
    final points = ride.points;

    if (points.isNotEmpty) {
      double? highest;
      for (final point in points) {
        final elevation = point.altitude;
        if (elevation == null) continue;
        if (highest == null || elevation > highest) highest = elevation;
      }
      if (highest != null) {
        out.add('najwyższy punkt ${highest.round()} m');
      }
    }
    if (ride.maxSpeedKmh > 0) {
      out.add('maks. ${ride.maxSpeedKmh.toStringAsFixed(1)} km/h');
    }
    if (ride.elevationGainMeters >= 50) {
      out.add('przewyższenie ${ride.elevationGainMeters.round()} m');
    }

    // Druga połowa szybsza od pierwszej: liczone z sumy dystansu i czasu
    // w połówkach, a nie z wrażenia.
    final split = _negativeSplit(ride);
    if (split != null) out.add(split);

    if (profile != null && profile.isUsable && ride.movingSeconds > 0) {
      final pace = ride.distanceMeters / ride.movingSeconds * 3.6;
      final difference = pace - profile.movingAverageKmh;
      if (difference.abs() >= 0.5) {
        out.add(
          '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(1)} km/h '
          'względem podobnych przejazdów',
        );
      }
    }
    return out;
  }

  /// Porównanie połówek przejazdu albo null, gdy nie ma z czego liczyć.
  static String? _negativeSplit(RecordedRide ride) {
    final points = ride.points;
    if (points.length < 20) return null;
    final half = ride.distanceMeters / 2;
    RecordedRidePoint? middle;
    for (final point in points) {
      if (point.distanceMeters >= half) {
        middle = point;
        break;
      }
    }
    if (middle == null) return null;
    final start = points.first.recordedAt;
    final end = points.last.recordedAt;
    final firstHalf = middle.recordedAt.difference(start);
    final secondHalf = end.difference(middle.recordedAt);
    if (firstHalf.inMinutes < 5 || secondHalf.inMinutes < 5) return null;
    final gap = firstHalf - secondHalf;
    if (gap.inMinutes.abs() < 2) return null;
    return gap.isNegative
        ? 'pierwsza połowa szybsza o ${_minutes(-gap)}'
        : 'druga połowa szybsza o ${_minutes(gap)}';
  }

  // ------------------------------------------------------------ formatowanie

  static String _km(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  static String _minutes(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} godz. ${minutes % 60} min';
  }

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  static String _compass(double degrees) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return labels[(((degrees % 360) + 360) % 360 / 45).round() % 8];
  }
}
