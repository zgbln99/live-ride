import 'dart:math' as math;

import '../../core/geo.dart';

/// Kategoria podjazdu według skali kolarskiej.
///
/// Próg to klasyczny wynik `długość_w_metrach × średnie_nachylenie_%`,
/// ten sam, którego używa większość platform kolarskich — dzięki temu
/// „Kategoria 2” znaczy tu to samo co gdzie indziej.
enum ClimbCategory {
  uncategorised('Niekategoryzowany', 0),
  four('Kategoria 4', 8000),
  three('Kategoria 3', 16000),
  two('Kategoria 2', 32000),
  one('Kategoria 1', 64000),
  hc('HC', 128000);

  const ClimbCategory(this.label, this.minimumScore);

  final String label;
  final double minimumScore;

  /// Skrót do odznaki: „4", „3", „2", „1", „HC" albo kropka.
  String get shortLabel => switch (this) {
    ClimbCategory.uncategorised => '·',
    ClimbCategory.four => '4',
    ClimbCategory.three => '3',
    ClimbCategory.two => '2',
    ClimbCategory.one => '1',
    ClimbCategory.hc => 'HC',
  };

  static ClimbCategory fromScore(double score) {
    ClimbCategory result = ClimbCategory.uncategorised;
    for (final category in ClimbCategory.values) {
      if (score >= category.minimumScore) result = category;
    }
    return result;
  }
}

/// Jeden podjazd wykryty na trasie.
class Climb {
  const Climb({
    required this.index,
    required this.startDistanceMeters,
    required this.endDistanceMeters,
    required this.startElevation,
    required this.summitElevation,
    required this.maxGradientPercent,
    required this.points,
  });

  /// Numer podjazdu na trasie, licząc od 1.
  final int index;

  final double startDistanceMeters;
  final double endDistanceMeters;
  final double startElevation;
  final double summitElevation;
  final double maxGradientPercent;

  /// Profil podjazdu: dystans od startu trasy i wygładzona wysokość.
  final List<({double distance, double elevation})> points;

  double get lengthMeters => endDistanceMeters - startDistanceMeters;
  double get gainMeters => summitElevation - startElevation;

  double get averageGradientPercent =>
      lengthMeters <= 0 ? 0 : (gainMeters / lengthMeters) * 100;

  /// Wynik używany do kategoryzacji.
  double get score => lengthMeters * averageGradientPercent;

  ClimbCategory get category => ClimbCategory.fromScore(score);

  /// Czy podjazd jest na tyle trudny, żeby go wyróżnić w briefingu.
  bool get isNotable => gainMeters >= 80 || averageGradientPercent >= 6;

  /// Ile zostało do szczytu z podanego dystansu na trasie.
  double remainingMeters(double distanceAlongRoute) =>
      math.max(0, endDistanceMeters - distanceAlongRoute);

  /// Ile metrów w pionie zostało do szczytu.
  double remainingGain(double elevationNow) =>
      math.max(0, summitElevation - elevationNow);

  /// Postęp na podjeździe w zakresie 0–1.
  double progress(double distanceAlongRoute) {
    if (lengthMeters <= 0) return 0;
    final done = distanceAlongRoute - startDistanceMeters;
    return (done / lengthMeters).clamp(0.0, 1.0);
  }

  bool contains(double distanceAlongRoute) =>
      distanceAlongRoute >= startDistanceMeters &&
      distanceAlongRoute <= endDistanceMeters;

  Map<String, dynamic> toJson() => {
    'index': index,
    'start_m': startDistanceMeters,
    'end_m': endDistanceMeters,
    'start_ele': startElevation,
    'summit_ele': summitElevation,
    'max_gradient': maxGradientPercent,
  };
}

/// Trudność całej trasy.
enum RouteDifficulty {
  easy('Łatwa'),
  moderate('Umiarkowana'),
  hard('Trudna'),
  veryHard('Bardzo trudna');

  const RouteDifficulty(this.label);

  final String label;
}

/// Wynik analizy trasy: wszystko, co da się policzyć z samej geometrii.
class RouteAnalysis {
  const RouteAnalysis({
    required this.distanceMeters,
    required this.ascentMeters,
    required this.descentMeters,
    required this.minElevation,
    required this.maxElevation,
    required this.climbs,
    required this.steepestGradientPercent,
    required this.steepestDescentPercent,
    required this.profile,
    required this.hasElevationData,
  });

  final double distanceMeters;
  final double ascentMeters;
  final double descentMeters;
  final double minElevation;
  final double maxElevation;
  final List<Climb> climbs;
  final double steepestGradientPercent;
  final double steepestDescentPercent;

  /// Wygładzony profil wysokości: dystans i wysokość.
  final List<({double distance, double elevation})> profile;

  /// Fałsz, gdy plik nie ma wysokości — wtedy nie pokazujemy przewyższeń
  /// zamiast wymyślać liczby.
  final bool hasElevationData;

  /// Metry przewyższenia na kilometr — najuczciwsza miara „pagórkowatości”.
  double get metersPerKilometre =>
      distanceMeters <= 0 ? 0 : ascentMeters / (distanceMeters / 1000);

  List<Climb> get notableClimbs =>
      climbs.where((climb) => climb.isNotable).toList(growable: false);

  Climb? get biggestClimb {
    if (climbs.isEmpty) return null;
    return climbs.reduce((a, b) => a.gainMeters >= b.gainMeters ? a : b);
  }

  RouteDifficulty get difficulty {
    if (!hasElevationData) {
      return distanceMeters > 120000
          ? RouteDifficulty.hard
          : distanceMeters > 60000
          ? RouteDifficulty.moderate
          : RouteDifficulty.easy;
    }
    // Trudność łączy długość i pagórkowatość: 120 km po płaskim i 50 km
    // z 1200 m przewyższenia to dwa różne rodzaje ciężkiej trasy.
    final score =
        distanceMeters / 1000 * 0.35 +
        ascentMeters / 100 * 1.6 +
        metersPerKilometre * 0.8;
    if (score >= 95) return RouteDifficulty.veryHard;
    if (score >= 55) return RouteDifficulty.hard;
    if (score >= 28) return RouteDifficulty.moderate;
    return RouteDifficulty.easy;
  }

  /// Szacowany czas jazdy.
  ///
  /// Dystans dzielony przez zakładaną prędkość plus czas na przewyższenie
  /// przy ok. 600 m/h wznoszenia — prosta reguła, która na trasach
  /// rekreacyjnych trafia bliżej niż sama prędkość średnia.
  Duration estimatedDuration({required double assumedSpeedKmh}) {
    if (distanceMeters <= 0 || assumedSpeedKmh <= 0) return Duration.zero;
    final flatHours = (distanceMeters / 1000) / assumedSpeedKmh;
    final climbHours = hasElevationData ? ascentMeters / 600 : 0.0;
    return Duration(seconds: ((flatHours + climbHours) * 3600).round());
  }

  double estimatedAverageSpeedKmh({required double assumedSpeedKmh}) {
    final duration = estimatedDuration(assumedSpeedKmh: assumedSpeedKmh);
    if (duration.inSeconds <= 0) return 0;
    return (distanceMeters / duration.inSeconds) * 3.6;
  }

  /// Szacowana praca w kJ.
  ///
  /// Zwraca null bez masy zawodnika — liczba wyssana z palca jest gorsza
  /// niż jej brak.
  double? estimatedEnergyKj({
    required double? riderWeightKg,
    double bikeWeightKg = 9,
    required double assumedSpeedKmh,
  }) {
    if (riderWeightKg == null || riderWeightKg <= 0) return null;
    if (distanceMeters <= 0) return null;

    const gravity = 9.81;
    const rollingResistance = 0.005;
    const dragArea = 0.32; // CdA typowej pozycji na hamulcach
    const airDensity = 1.225;
    const drivetrainEfficiency = 0.96;

    final mass = riderWeightKg + bikeWeightKg;
    final speed = assumedSpeedKmh / 3.6;

    final climbingJoules = hasElevationData
        ? mass * gravity * ascentMeters
        : 0.0;
    final rollingJoules = rollingResistance * mass * gravity * distanceMeters;
    final airJoules =
        0.5 * airDensity * dragArea * speed * speed * distanceMeters;

    return (climbingJoules + rollingJoules + airJoules) /
        drivetrainEfficiency /
        1000;
  }

  static const RouteAnalysis empty = RouteAnalysis(
    distanceMeters: 0,
    ascentMeters: 0,
    descentMeters: 0,
    minElevation: 0,
    maxElevation: 0,
    climbs: [],
    steepestGradientPercent: 0,
    steepestDescentPercent: 0,
    profile: [],
    hasElevationData: false,
  );
}

/// Analizator trasy: wygładza wysokość, liczy przewyższenia i wykrywa podjazdy.
///
/// Cała logika jest czysta i bez zależności od Fluttera, więc liczy się ją
/// równie dobrze w teście, jak i w izolacie.
abstract final class RouteAnalyzer {
  /// Okno wygładzania wysokości w metrach dystansu.
  static const double smoothingWindowMeters = 100;

  /// Histereza przewyższenia: dopiero taki wzrost ponad ostatni punkt
  /// odniesienia liczy się jako podjazd. Samo wygładzanie nie wystarcza —
  /// zostawia drobne oscylacje, które na 100 km sumują się w setki metrów
  /// przewyższenia, których w terenie nie ma.
  static const double elevationHysteresisMeters = 2.0;

  /// Minimalne przewyższenie, żeby wzniesienie uznać za podjazd.
  static const double minimumClimbGain = 30;

  /// Minimalne średnie nachylenie podjazdu.
  static const double minimumClimbGradient = 2.5;

  /// Przerwa (spadek/płaskie), która jeszcze nie kończy podjazdu.
  static const double climbBridgeMeters = 250;

  static RouteAnalysis analyze(List<GeoPoint> points) {
    if (points.length < 2) return RouteAnalysis.empty;

    final cumulative = cumulativeDistances(points);
    final hasElevation = points.any(
      (point) => point.elevation != null && point.elevation!.isFinite,
    );
    if (!hasElevation) {
      return RouteAnalysis(
        distanceMeters: cumulative.last,
        ascentMeters: 0,
        descentMeters: 0,
        minElevation: 0,
        maxElevation: 0,
        climbs: const [],
        steepestGradientPercent: 0,
        steepestDescentPercent: 0,
        profile: const [],
        hasElevationData: false,
      );
    }

    final profile = _smoothProfile(points, cumulative);
    if (profile.length < 3) {
      return RouteAnalysis(
        distanceMeters: cumulative.last,
        ascentMeters: 0,
        descentMeters: 0,
        minElevation: 0,
        maxElevation: 0,
        climbs: const [],
        steepestGradientPercent: 0,
        steepestDescentPercent: 0,
        profile: profile,
        hasElevationData: false,
      );
    }

    var ascent = 0.0;
    var descent = 0.0;
    var reference = profile.first.elevation;
    var minElevation = profile.first.elevation;
    var maxElevation = profile.first.elevation;
    var steepestUp = 0.0;
    var steepestDown = 0.0;

    for (var i = 1; i < profile.length; i++) {
      final elevation = profile[i].elevation;
      final change = elevation - reference;
      if (change >= elevationHysteresisMeters) {
        ascent += change;
        reference = elevation;
      } else if (change <= -elevationHysteresisMeters) {
        descent += -change;
        reference = elevation;
      }

      // Nachylenie liczymy na dłuższym odcinku, żeby jeden punkt nie zrobił
      // z trasy ściany.
      final run = profile[i].distance - profile[i - 1].distance;
      if (run > 15) {
        final gradient = (elevation - profile[i - 1].elevation) / run * 100;
        if (gradient > steepestUp) steepestUp = gradient;
        if (gradient < steepestDown) steepestDown = gradient;
      }
      minElevation = math.min(minElevation, elevation);
      maxElevation = math.max(maxElevation, elevation);
    }

    return RouteAnalysis(
      distanceMeters: cumulative.last,
      ascentMeters: ascent,
      descentMeters: descent,
      minElevation: minElevation,
      maxElevation: maxElevation,
      climbs: detectClimbs(profile),
      steepestGradientPercent: steepestUp.clamp(0, 35),
      steepestDescentPercent: steepestDown.clamp(-35, 0),
      profile: profile,
      hasElevationData: true,
    );
  }

  /// Wygładza profil wysokości oknem po dystansie.
  ///
  /// Wysokość z GPS i z modelu terenu potrafi skakać o kilka metrów między
  /// sąsiednimi punktami; bez wygładzania każdy taki skok byłby „podjazdem”.
  static List<({double distance, double elevation})> _smoothProfile(
    List<GeoPoint> points,
    List<double> cumulative,
  ) {
    final raw = <({double distance, double elevation})>[];
    double? lastElevation;
    for (var i = 0; i < points.length; i++) {
      final elevation = points[i].elevation ?? lastElevation;
      if (elevation == null || !elevation.isFinite) continue;
      if (elevation < -500 || elevation > 9000) continue;
      lastElevation = elevation;
      raw.add((distance: cumulative[i], elevation: elevation));
    }
    if (raw.length < 3) return raw;

    final smoothed = <({double distance, double elevation})>[];
    var windowStart = 0;
    for (var i = 0; i < raw.length; i++) {
      final from = raw[i].distance - smoothingWindowMeters / 2;
      final to = raw[i].distance + smoothingWindowMeters / 2;
      while (windowStart < i && raw[windowStart].distance < from) {
        windowStart++;
      }
      var sum = 0.0;
      var count = 0;
      for (var j = windowStart; j < raw.length; j++) {
        if (raw[j].distance > to) break;
        sum += raw[j].elevation;
        count++;
      }
      smoothed.add((
        distance: raw[i].distance,
        elevation: count == 0 ? raw[i].elevation : sum / count,
      ));
    }
    return smoothed;
  }

  /// Wykrywa podjazdy na wygładzonym profilu.
  static List<Climb> detectClimbs(
    List<({double distance, double elevation})> profile,
  ) {
    if (profile.length < 3) return const [];

    final candidates = <({int start, int end})>[];
    int? start;
    int? lastRising;

    for (var i = 1; i < profile.length; i++) {
      final rising = profile[i].elevation > profile[i - 1].elevation;
      if (rising) {
        start ??= i - 1;
        lastRising = i;
        continue;
      }
      if (start == null || lastRising == null) continue;

      // Krótka przerwa nie kończy podjazdu: serpentyna z chwilowym
      // spłaszczeniem to nadal jeden podjazd.
      final bridge = profile[i].distance - profile[lastRising].distance;
      if (bridge <= climbBridgeMeters) continue;

      candidates.add((start: start, end: lastRising));
      start = null;
      lastRising = null;
    }
    if (start != null && lastRising != null) {
      candidates.add((start: start, end: lastRising));
    }

    final climbs = <Climb>[];
    for (final candidate in candidates) {
      final from = profile[candidate.start];
      final to = profile[candidate.end];
      final gain = to.elevation - from.elevation;
      final length = to.distance - from.distance;
      if (gain < minimumClimbGain || length <= 0) continue;
      final gradient = gain / length * 100;
      if (gradient < minimumClimbGradient) continue;

      var maxGradient = 0.0;
      final section = <({double distance, double elevation})>[];
      for (var i = candidate.start; i <= candidate.end; i++) {
        section.add(profile[i]);
        if (i == candidate.start) continue;
        final run = profile[i].distance - profile[i - 1].distance;
        if (run < 20) continue;
        final rise = profile[i].elevation - profile[i - 1].elevation;
        maxGradient = math.max(maxGradient, rise / run * 100);
      }

      climbs.add(
        Climb(
          index: climbs.length + 1,
          startDistanceMeters: from.distance,
          endDistanceMeters: to.distance,
          startElevation: from.elevation,
          summitElevation: to.elevation,
          maxGradientPercent: maxGradient.clamp(0, 35),
          points: List.unmodifiable(section),
        ),
      );
    }
    return List.unmodifiable(climbs);
  }
}
