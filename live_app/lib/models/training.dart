import 'dart:math' as math;

/// Strefa treningowa z granicami i nazwą.
class TrainingZone {
  const TrainingZone({
    required this.index,
    required this.name,
    required this.lower,
    required this.upper,
  });

  final int index;
  final String name;

  /// Dolna granica włącznie.
  final int lower;

  /// Górna granica włącznie; [upperBound] dla ostatniej strefy.
  final int upper;

  bool contains(int value) => value >= lower && value <= upper;

  String get range => upper >= 100000 ? '$lower+' : '$lower–$upper';
}

/// Profil treningowy zawodnika.
///
/// Strefy liczone są automatycznie z HR max i FTP, chyba że użytkownik
/// wpisze własne granice.
class TrainingProfile {
  const TrainingProfile({
    this.maxHeartRate,
    this.restingHeartRate,
    this.functionalThresholdPower,
    this.customHeartRateBounds,
    this.customPowerBounds,
    this.weightKg,
  });

  final int? maxHeartRate;
  final int? restingHeartRate;

  /// FTP w watach.
  final int? functionalThresholdPower;

  /// Własne górne granice pięciu stref HR.
  final List<int>? customHeartRateBounds;

  /// Własne górne granice siedmiu stref mocy.
  final List<int>? customPowerBounds;

  final double? weightKg;

  bool get hasHeartRateZones =>
      (maxHeartRate != null && maxHeartRate! > 0) ||
      (customHeartRateBounds?.isNotEmpty ?? false);

  bool get hasPowerZones =>
      (functionalThresholdPower != null && functionalThresholdPower! > 0) ||
      (customPowerBounds?.isNotEmpty ?? false);

  double? get wattsPerKilogram {
    final ftp = functionalThresholdPower;
    final weight = weightKg;
    if (ftp == null || weight == null || weight <= 0) return null;
    return ftp / weight;
  }

  /// Pięć stref tętna.
  ///
  /// Domyślnie procenty HR max (50/60/70/80/90) — powszechnie używany podział,
  /// który przy podanym tętnie spoczynkowym przechodzi na metodę rezerwy
  /// tętna (Karvonena), bo lepiej opisuje realny wysiłek.
  List<TrainingZone> get heartRateZones {
    const names = ['Regeneracja', 'Wytrzymałość', 'Tempo', 'Próg', 'VO2 max'];
    final custom = customHeartRateBounds;
    if (custom != null && custom.length == 5) {
      return _zonesFromBounds(custom, names);
    }

    final max = maxHeartRate;
    if (max == null || max <= 0) return const [];
    final rest = restingHeartRate;
    int bound(double fraction) => rest != null && rest > 0 && rest < max
        ? (rest + (max - rest) * fraction).round()
        : (max * fraction).round();

    return _zonesFromBounds([
      bound(0.60),
      bound(0.70),
      bound(0.80),
      bound(0.90),
      max,
    ], names);
  }

  /// Siedem stref mocy według podziału Coggana, liczonych z FTP.
  List<TrainingZone> get powerZones {
    const names = [
      'Aktywna regeneracja',
      'Wytrzymałość',
      'Tempo',
      'Próg mleczanowy',
      'VO2 max',
      'Moc beztlenowa',
      'Moc neuromięśniowa',
    ];
    final custom = customPowerBounds;
    if (custom != null && custom.length == 7) {
      return _zonesFromBounds(custom, names);
    }

    final ftp = functionalThresholdPower;
    if (ftp == null || ftp <= 0) return const [];
    return _zonesFromBounds([
      (ftp * 0.55).round(),
      (ftp * 0.75).round(),
      (ftp * 0.90).round(),
      (ftp * 1.05).round(),
      (ftp * 1.20).round(),
      (ftp * 1.50).round(),
      1000000,
    ], names);
  }

  static List<TrainingZone> _zonesFromBounds(
    List<int> uppers,
    List<String> names,
  ) {
    final zones = <TrainingZone>[];
    var lower = 0;
    for (var i = 0; i < uppers.length; i++) {
      zones.add(
        TrainingZone(
          index: i + 1,
          name: i < names.length ? names[i] : 'Strefa ${i + 1}',
          lower: lower,
          upper: uppers[i],
        ),
      );
      lower = uppers[i] + 1;
    }
    return List.unmodifiable(zones);
  }

  /// Numer strefy tętna (1–5) albo null, gdy nie da się jej wyznaczyć.
  int? heartRateZoneFor(int? bpm) {
    if (bpm == null || bpm <= 0) return null;
    final zones = heartRateZones;
    if (zones.isEmpty) return null;
    for (final zone in zones) {
      if (bpm <= zone.upper) return zone.index;
    }
    return zones.last.index;
  }

  /// Numer strefy mocy (1–7) albo null.
  int? powerZoneFor(int? watts) {
    if (watts == null || watts < 0) return null;
    final zones = powerZones;
    if (zones.isEmpty) return null;
    for (final zone in zones) {
      if (watts <= zone.upper) return zone.index;
    }
    return zones.last.index;
  }

  TrainingProfile copyWith({
    int? maxHeartRate,
    int? restingHeartRate,
    int? functionalThresholdPower,
    List<int>? customHeartRateBounds,
    List<int>? customPowerBounds,
    double? weightKg,
  }) => TrainingProfile(
    maxHeartRate: maxHeartRate ?? this.maxHeartRate,
    restingHeartRate: restingHeartRate ?? this.restingHeartRate,
    functionalThresholdPower:
        functionalThresholdPower ?? this.functionalThresholdPower,
    customHeartRateBounds: customHeartRateBounds ?? this.customHeartRateBounds,
    customPowerBounds: customPowerBounds ?? this.customPowerBounds,
    weightKg: weightKg ?? this.weightKg,
  );

  Map<String, dynamic> toJson() => {
    'max_hr': maxHeartRate,
    'resting_hr': restingHeartRate,
    'ftp': functionalThresholdPower,
    'hr_bounds': customHeartRateBounds,
    'power_bounds': customPowerBounds,
    'weight_kg': weightKg,
  };

  factory TrainingProfile.fromJson(Map<String, dynamic> json) =>
      TrainingProfile(
        maxHeartRate: (json['max_hr'] as num?)?.toInt(),
        restingHeartRate: (json['resting_hr'] as num?)?.toInt(),
        functionalThresholdPower: (json['ftp'] as num?)?.toInt(),
        customHeartRateBounds: (json['hr_bounds'] as List<dynamic>?)
            ?.map((value) => (value as num).toInt())
            .toList(),
        customPowerBounds: (json['power_bounds'] as List<dynamic>?)
            ?.map((value) => (value as num).toInt())
            .toList(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
      );
}

/// Rodzaj kroku treningu.
enum WorkoutStepKind {
  warmUp('Rozgrzewka'),
  work('Praca'),
  recovery('Odpoczynek'),
  coolDown('Schłodzenie'),
  rest('Przerwa');

  const WorkoutStepKind(this.label);

  final String label;

  static WorkoutStepKind parse(String? value) =>
      WorkoutStepKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => WorkoutStepKind.work,
      );
}

/// Czym sterowany jest krok treningu.
enum WorkoutTarget {
  none('Bez celu'),
  power('Moc'),
  heartRate('Tętno'),
  cadence('Kadencja'),
  speed('Prędkość');

  const WorkoutTarget(this.label);

  final String label;

  static WorkoutTarget parse(String? value) => WorkoutTarget.values.firstWhere(
    (target) => target.name == value,
    orElse: () => WorkoutTarget.none,
  );
}

/// Jeden krok treningu.
class WorkoutStep {
  const WorkoutStep({
    required this.kind,
    this.name = '',
    this.duration,
    this.distanceMeters,
    this.target = WorkoutTarget.none,
    this.targetLow,
    this.targetHigh,
  });

  final WorkoutStepKind kind;
  final String name;
  final Duration? duration;
  final double? distanceMeters;
  final WorkoutTarget target;
  final double? targetLow;
  final double? targetHigh;

  bool get hasTarget =>
      target != WorkoutTarget.none && (targetLow != null || targetHigh != null);

  /// Czy podana wartość mieści się w celu kroku.
  bool isOnTarget(num? value) {
    if (value == null || !hasTarget) return true;
    if (targetLow != null && value < targetLow!) return false;
    if (targetHigh != null && value > targetHigh!) return false;
    return true;
  }

  /// „za nisko” / „za wysoko” / null gdy w normie.
  int? deviation(num? value) {
    if (value == null || !hasTarget) return null;
    if (targetLow != null && value < targetLow!) return -1;
    if (targetHigh != null && value > targetHigh!) return 1;
    return null;
  }

  String get targetLabel {
    if (!hasTarget) return '';
    final unit = switch (target) {
      WorkoutTarget.power => 'W',
      WorkoutTarget.heartRate => 'bpm',
      WorkoutTarget.cadence => 'rpm',
      WorkoutTarget.speed => 'km/h',
      WorkoutTarget.none => '',
    };
    if (targetLow != null && targetHigh != null) {
      return '${targetLow!.round()}–${targetHigh!.round()} $unit';
    }
    final single = targetLow ?? targetHigh!;
    return '${single.round()} $unit';
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'name': name,
    'duration_s': duration?.inSeconds,
    'distance_m': distanceMeters,
    'target': target.name,
    'target_low': targetLow,
    'target_high': targetHigh,
  };

  factory WorkoutStep.fromJson(Map<String, dynamic> json) => WorkoutStep(
    kind: WorkoutStepKind.parse(json['kind'] as String?),
    name: json['name'] as String? ?? '',
    duration: json['duration_s'] == null
        ? null
        : Duration(seconds: (json['duration_s'] as num).toInt()),
    distanceMeters: (json['distance_m'] as num?)?.toDouble(),
    target: WorkoutTarget.parse(json['target'] as String?),
    targetLow: (json['target_low'] as num?)?.toDouble(),
    targetHigh: (json['target_high'] as num?)?.toDouble(),
  );
}

/// Trening złożony z kroków.
class Workout {
  const Workout({
    required this.id,
    required this.name,
    required this.steps,
    required this.createdAt,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
  final List<WorkoutStep> steps;
  final DateTime createdAt;

  Duration get totalDuration => steps.fold(
    Duration.zero,
    (sum, step) => sum + (step.duration ?? Duration.zero),
  );

  int get workSteps =>
      steps.where((step) => step.kind == WorkoutStepKind.work).length;

  /// Krótki opis do listy, np. „10 min rozgrzewki · 5 × 4 min · 10 min”.
  String get summary {
    if (steps.isEmpty) return 'Pusty trening';
    final minutes = totalDuration.inMinutes;
    return '$minutes min · $workSteps × praca';
  }
}

/// Metryki mocy liczone na bieżąco.
///
/// Wszystko tutaj jest policzone z prawdziwych próbek; jeśli miernika mocy
/// nie ma, wartości są nullem i UI nie pokazuje niczego.
class PowerMetrics {
  const PowerMetrics({
    this.current,
    this.average,
    this.maximum,
    this.threeSecond,
    this.tenSecond,
    this.thirtySecond,
    this.normalized,
    this.intensityFactor,
    this.trainingStressScore,
  });

  final int? current;
  final int? average;
  final int? maximum;
  final int? threeSecond;
  final int? tenSecond;
  final int? thirtySecond;
  final int? normalized;
  final double? intensityFactor;
  final double? trainingStressScore;

  bool get hasData => current != null || average != null;

  static const PowerMetrics empty = PowerMetrics();
}

/// Akumulator metryk mocy.
///
/// Normalized Power liczona jest kanonicznie: średnia krocząca 30 s,
/// podniesiona do czwartej potęgi, uśredniona i spierwiastkowana.
class PowerAccumulator {
  PowerAccumulator({this.ftp});

  final int? ftp;

  final List<({DateTime at, int watts})> _window = [];
  final List<double> _rollingFourthPowers = [];

  int _sum = 0;
  int _count = 0;
  int _max = 0;
  int? _current;
  DateTime? _startedAt;
  DateTime? _lastRolling;

  void add(int watts, {DateTime? at}) {
    if (watts < 0 || watts > 2500) return;
    final now = at ?? DateTime.now();
    _startedAt ??= now;
    _current = watts;
    _sum += watts;
    _count++;
    if (watts > _max) _max = watts;

    _window.add((at: now, watts: watts));
    // Trzymamy 30 s próbek: dłuższe okna liczymy z tego samego bufora.
    while (_window.isNotEmpty &&
        now.difference(_window.first.at) > const Duration(seconds: 30)) {
      _window.removeAt(0);
    }

    // Normalized Power próbkuje średnią 30-sekundową raz na sekundę.
    if (_lastRolling == null ||
        now.difference(_lastRolling!) >= const Duration(seconds: 1)) {
      _lastRolling = now;
      final rolling = _averageOver(const Duration(seconds: 30));
      if (rolling != null) {
        _rollingFourthPowers.add(math.pow(rolling, 4).toDouble());
      }
    }
  }

  double? _averageOver(Duration window) {
    if (_window.isEmpty) return null;
    final cutoff = _window.last.at.subtract(window);
    var sum = 0;
    var count = 0;
    for (final sample in _window) {
      if (sample.at.isBefore(cutoff)) continue;
      sum += sample.watts;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  int? averageOverSeconds(int seconds) {
    final value = _averageOver(Duration(seconds: seconds));
    return value?.round();
  }

  int? get normalizedPower {
    if (_rollingFourthPowers.length < 10) return null;
    final mean =
        _rollingFourthPowers.reduce((a, b) => a + b) /
        _rollingFourthPowers.length;
    return math.pow(mean, 0.25).round();
  }

  PowerMetrics build({Duration? elapsed}) {
    if (_count == 0) return PowerMetrics.empty;
    final average = (_sum / _count).round();
    final normalized = normalizedPower;
    double? intensity;
    double? tss;
    final threshold = ftp;
    if (threshold != null && threshold > 0 && normalized != null) {
      intensity = normalized / threshold;
      final seconds = elapsed?.inSeconds ?? 0;
      if (seconds > 0) {
        tss = (seconds * normalized * intensity) / (threshold * 3600) * 100;
      }
    }
    return PowerMetrics(
      current: _current,
      average: average,
      maximum: _max,
      threeSecond: averageOverSeconds(3),
      tenSecond: averageOverSeconds(10),
      thirtySecond: averageOverSeconds(30),
      normalized: normalized,
      intensityFactor: intensity,
      trainingStressScore: tss,
    );
  }

  void reset() {
    _window.clear();
    _rollingFourthPowers.clear();
    _sum = 0;
    _count = 0;
    _max = 0;
    _current = null;
    _startedAt = null;
    _lastRolling = null;
  }
}
