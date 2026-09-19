/// Okres, w jakim zawodnik ogląda swoje liczby.
enum StatsPeriod {
  week('Tydzień'),
  month('Miesiąc'),
  year('Rok'),
  allTime('Wszystko');

  const StatsPeriod(this.label);

  final String label;

  /// Początek bieżącego okresu.
  DateTime startOf(DateTime now) => switch (this) {
    StatsPeriod.week => _startOfWeek(now),
    StatsPeriod.month => DateTime(now.year, now.month),
    StatsPeriod.year => DateTime(now.year),
    // Rok 2000 jest wcześniejszy niż jakikolwiek przejazd rowerowy zapisany
    // w tej aplikacji, a nie przepełnia niczego po drodze.
    StatsPeriod.allTime => DateTime(2000),
  };

  /// Początek poprzedniego okresu — do porównań „ten miesiąc vs poprzedni".
  DateTime? previousStart(DateTime now) => switch (this) {
    StatsPeriod.week => _startOfWeek(now).subtract(const Duration(days: 7)),
    StatsPeriod.month => DateTime(now.year, now.month - 1),
    StatsPeriod.year => DateTime(now.year - 1),
    StatsPeriod.allTime => null,
  };

  /// Jak grupować słupki wykresu w tym okresie.
  StatsBucketKind get bucket => switch (this) {
    StatsPeriod.week => StatsBucketKind.day,
    StatsPeriod.month => StatsBucketKind.day,
    StatsPeriod.year => StatsBucketKind.month,
    StatsPeriod.allTime => StatsBucketKind.year,
  };

  static DateTime _startOfWeek(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    // W Polsce tydzień zaczyna się w poniedziałek.
    return day.subtract(Duration(days: day.weekday - 1));
  }
}

enum StatsBucketKind { day, month, year }

/// Jeden słupek wykresu.
class StatsBucket {
  const StatsBucket({
    required this.start,
    required this.rides,
    required this.distanceMeters,
    required this.movingSeconds,
    required this.ascentMeters,
  });

  final DateTime start;
  final int rides;
  final double distanceMeters;
  final int movingSeconds;
  final double ascentMeters;

  bool get isEmpty => rides == 0;
}

/// Rekord jednej kategorii razem z przejazdem, w którym padł.
class RideRecord {
  const RideRecord({
    required this.kind,
    required this.value,
    required this.rideId,
    required this.rideName,
    required this.achievedAt,
  });

  final RideRecordKind kind;
  final double value;
  final String rideId;
  final String rideName;
  final DateTime achievedAt;
}

enum RideRecordKind {
  longestDistance('Najdłuższy przejazd'),
  longestTime('Najdłużej w siodle'),
  biggestAscent('Najwięcej w pionie'),
  fastestAverage('Najwyższa średnia'),
  highestSpeed('Najwyższa prędkość'),
  bestNormalizedPower('Najlepsza moc normalizowana');

  const RideRecordKind(this.label);

  final String label;
}

/// Komplet statystyk dla jednego okresu.
class RideStatistics {
  const RideStatistics({
    required this.period,
    required this.from,
    required this.rides,
    required this.distanceMeters,
    required this.movingSeconds,
    required this.ascentMeters,
    required this.buckets,
    this.previousDistanceMeters,
    this.previousRides,
  });

  final StatsPeriod period;
  final DateTime from;
  final int rides;
  final double distanceMeters;
  final int movingSeconds;
  final double ascentMeters;
  final List<StatsBucket> buckets;

  final double? previousDistanceMeters;
  final int? previousRides;

  Duration get movingTime => Duration(seconds: movingSeconds);

  double get averageSpeedKmh =>
      movingSeconds <= 0 ? 0 : distanceMeters / movingSeconds * 3.6;

  double get averageDistanceMeters => rides == 0 ? 0 : distanceMeters / rides;

  /// Zmiana dystansu względem poprzedniego okresu w procentach.
  ///
  /// Null, gdy nie ma z czym porównywać — „+100 %" po pierwszym przejeździe
  /// w życiu to liczba bez treści.
  double? get distanceChangePercent {
    final previous = previousDistanceMeters;
    if (previous == null || previous <= 0) return null;
    return (distanceMeters - previous) / previous * 100;
  }

  bool get isEmpty => rides == 0;

  static RideStatistics empty(StatsPeriod period, DateTime from) =>
      RideStatistics(
        period: period,
        from: from,
        rides: 0,
        distanceMeters: 0,
        movingSeconds: 0,
        ascentMeters: 0,
        buckets: const [],
      );
}
