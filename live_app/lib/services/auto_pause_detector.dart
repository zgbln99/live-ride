import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/geo.dart';

/// Jedna próbka wejściowa dla wykrywania postoju.
///
/// Zbiera wszystko, co w danej chwili wiemy o ruchu: co mówi GPS, co mówi
/// czujnik prędkości na kole i gdzie jesteśmy. Decyzja zapada z całości, a
/// nie z jednej liczby.
@immutable
class AutoPauseSample {
  const AutoPauseSample({
    required this.at,
    required this.point,
    this.gpsSpeedKmh,
    this.accuracyMeters,
    this.sensorSpeedKmh,
    this.sensorAt,
  });

  final DateTime at;
  final GeoPoint point;

  /// Prędkość zgłoszona przez odbiornik GPS (z dopplera), jeśli ją podał.
  final double? gpsSpeedKmh;

  /// Deklarowana dokładność pozycji w metrach.
  final double? accuracyMeters;

  /// Prędkość z czujnika BLE na kole, jeśli jest podłączony.
  final double? sensorSpeedKmh;

  /// Kiedy czujnik podał tę wartość. Stary odczyt nie jest dowodem na nic.
  final DateTime? sensorAt;
}

/// Co wykrywacz każe zrobić licznikowi.
enum AutoPauseAction { none, pause, resume }

/// Na czym oparła się ostatnia ocena. Do diagnostyki i testów.
enum AutoPauseEvidence {
  /// Czujnik na kole — rozstrzyga, bo nie dryfuje.
  wheelSensor,

  /// Prędkość zgłoszona przez GPS.
  gpsSpeed,

  /// Samo przemieszczenie pozycji.
  displacement,

  /// Nic świeżego nie przyszło.
  noData,
}

/// Wykrywa, czy rowerzysta NAPRAWDĘ stoi.
///
/// Stary mechanizm pauzował poniżej 3 km/h po 5 sekundach i przez to gasił
/// licznik na stromym podjeździe, przy nawrotce i przy mocniejszym hamowaniu.
/// Tutaj obowiązuje odwrotna zasada: pauza tylko wtedy, gdy przez kilka
/// kolejnych sekund KAŻDY dostępny dowód mówi, że telefon został w tym samym
/// miejscu.
///
/// Kolejność źródeł:
///
///  1. czujnik prędkości BLE, jeśli ma świeży odczyt — koło się kręci albo
///     nie, bez dyskusji i bez dryfu,
///  2. prędkość z GPS (doppler) — wiarygodna także przy 1,5 km/h,
///  3. przemieszczenie pozycji — awaryjnie, gdy odbiornik nie podaje
///     prędkości.
///
/// Przemieszczenie mierzy się od KOTWICY postawionej na początku kandydata na
/// postój, a nie od poprzedniej próbki. Przy 1,5 km/h sąsiednie fixy dzieli
/// 40 centymetrów, czyli mniej niż szum — dopiero suma kilku sekund coś mówi.
class AutoPauseDetector {
  AutoPauseDetector({
    this.stationaryGpsKmh = defaultStationaryGpsKmh,
    this.resumeKmh = defaultResumeKmh,
    this.pauseAfter = defaultPauseAfter,
    this.displacementOnlyPauseAfter = const Duration(seconds: 25),
    this.minimumStandingSamples = 3,
    this.resumeSamples = 2,
    this.staleAfter = const Duration(seconds: 6),
    this.sensorFreshFor = const Duration(seconds: 4),
  });

  /// Poniżej tej prędkości uznajemy, że koła stoją.
  ///
  /// 0,7 km/h to mniej niż wolny marsz. Odbiornik jadącego roweru nie zgłasza
  /// takich wartości nawet na najwolniejszym podjeździe; stojący telefon
  /// zgłasza dokładnie zero albo szum w tych okolicach.
  static const double defaultStationaryGpsKmh = 0.7;

  /// Od tej prędkości uznajemy, że zawodnik ruszył.
  ///
  /// Wyraźnie powyżej progu postoju — ta różnica to histereza, bez której
  /// licznik mrugałby na każdym skrzyżowaniu.
  static const double defaultResumeKmh = 2.0;

  /// Ile nieprzerwanych dowodów postoju potrzeba, zanim padnie pauza.
  static const Duration defaultPauseAfter = Duration(seconds: 3);

  final double stationaryGpsKmh;
  final double resumeKmh;
  final Duration pauseAfter;

  /// Ile trzeba czekać, gdy jedynym dowodem jest brak przemieszczenia.
  ///
  /// Bez prędkości z odbiornika trzy sekundy niczego nie rozstrzygają: przy
  /// 1,5 km/h to 1,2 metra, czyli mniej niż szum pozycji. Słabszy dowód
  /// wymaga dłuższej obserwacji, zamiast udawać, że wystarczy.
  final Duration displacementOnlyPauseAfter;

  /// Ile próbek musi złożyć się na okno postoju.
  ///
  /// Jeden fix z zerem w środku jazdy zdarza się w tunelu, pod wiaduktem i
  /// między budynkami. Sam z siebie nie może zatrzymać licznika.
  final int minimumStandingSamples;

  /// Ile kolejnych próbek musi pokazać ruch, zanim wznowimy.
  final int resumeSamples;

  /// Po tylu sekundach bez próbki przestajemy cokolwiek twierdzić.
  final Duration staleAfter;

  /// Jak długo odczyt z czujnika koła jest dowodem.
  final Duration sensorFreshFor;

  AutoPauseSample? _previous;

  /// Pozycja, od której mierzymy, czy telefon się ruszył.
  GeoPoint? _anchor;
  DateTime? _standingSince;
  int _standingSamples = 0;
  int _movingSamples = 0;
  bool _windowHadSpeedEvidence = false;
  double _lastAnchorDistance = 0;
  AutoPauseEvidence _evidence = AutoPauseEvidence.noData;

  AutoPauseEvidence get evidence => _evidence;

  /// Jak długo trwa obecny kandydat na postój, albo null.
  Duration? standingFor(DateTime now) {
    final since = _standingSince;
    return since == null ? null : now.difference(since);
  }

  /// Czyści stan — na starcie przejazdu, po ręcznej pauzie i po wznowieniu.
  void reset() {
    _previous = null;
    _anchor = null;
    _standingSince = null;
    _standingSamples = 0;
    _movingSamples = 0;
    _windowHadSpeedEvidence = false;
    _lastAnchorDistance = 0;
    _evidence = AutoPauseEvidence.noData;
  }

  /// Przyjmuje próbkę i mówi, co zrobić.
  ///
  /// [recording] rozróżnia dwa pytania: „czy zatrzymać licznik" i „czy go
  /// wznowić". Ręczna pauza tu nie trafia — tamtej nie wolno wznowić
  /// automatycznie, więc licznik o to nie pyta.
  AutoPauseAction update(AutoPauseSample sample, {required bool recording}) {
    final previous = _previous;
    _previous = sample;

    // Przerwa w próbkach znaczy, że przez ten czas nic nie wiedzieliśmy. Okno
    // postoju musi być ciągłe, więc zaczyna się od nowa.
    if (previous != null && sample.at.difference(previous.at) > staleAfter) {
      _clearWindows();
    }

    return recording
        ? _whileRecording(sample, previous)
        : _whileAutoPaused(sample, previous);
  }

  /// Wywoływane, gdy mija czas, a próbka nie przyszła.
  ///
  /// Utrata sygnału przy 25 km/h wygląda z zewnątrz tak samo jak postój: nic
  /// nie przychodzi. Różnica jest taka, że o postoju wiemy z danych, a o
  /// utracie sygnału — z ich braku. Brak danych nigdy nie zatrzymuje licznika.
  AutoPauseAction tick(DateTime now) {
    final previous = _previous;
    if (previous == null || now.difference(previous.at) <= staleAfter) {
      return AutoPauseAction.none;
    }
    _clearWindows();
    _evidence = AutoPauseEvidence.noData;
    return AutoPauseAction.none;
  }

  void _clearWindows() {
    _standingSince = null;
    _standingSamples = 0;
    _movingSamples = 0;
    _windowHadSpeedEvidence = false;
    _anchor = null;
    _lastAnchorDistance = 0;
  }

  AutoPauseAction _whileRecording(
    AutoPauseSample sample,
    AutoPauseSample? previous,
  ) {
    _movingSamples = 0;
    final moving = _isMoving(sample, previous, threshold: stationaryGpsKmh);

    if (moving) {
      _standingSince = null;
      _standingSamples = 0;
      _windowHadSpeedEvidence = false;
      _anchor = null;
      return AutoPauseAction.none;
    }

    if (_anchor == null) {
      _anchor = sample.point;
      _lastAnchorDistance = 0;
    }
    _standingSince ??= sample.at;
    _standingSamples++;
    if (_evidence == AutoPauseEvidence.wheelSensor ||
        _evidence == AutoPauseEvidence.gpsSpeed) {
      _windowHadSpeedEvidence = true;
    }

    final required = _windowHadSpeedEvidence
        ? pauseAfter
        : displacementOnlyPauseAfter;
    final standingFor = sample.at.difference(_standingSince!);
    if (standingFor < required || _standingSamples < minimumStandingSamples) {
      return AutoPauseAction.none;
    }

    // Kotwica ZOSTAJE: od niej mierzymy, czy zawodnik naprawdę odjechał.
    _standingSince = null;
    _standingSamples = 0;
    _windowHadSpeedEvidence = false;
    _lastAnchorDistance = 0;
    return AutoPauseAction.pause;
  }

  AutoPauseAction _whileAutoPaused(
    AutoPauseSample sample,
    AutoPauseSample? previous,
  ) {
    _standingSince = null;
    _standingSamples = 0;
    final moving = _isMoving(sample, previous, threshold: resumeKmh);

    if (!moving) {
      _movingSamples = 0;
      return AutoPauseAction.none;
    }

    _movingSamples++;
    if (_movingSamples < resumeSamples) return AutoPauseAction.none;
    _movingSamples = 0;
    _anchor = null;
    _lastAnchorDistance = 0;
    return AutoPauseAction.resume;
  }

  /// Czy ta próbka jest dowodem ruchu przy zadanym progu prędkości.
  ///
  /// [anchored] mówi, czy trwa już okno postoju. Ma znaczenie, bo pojedynczy
  /// przeskok pozycji znaczy co innego w każdym z tych dwóch przypadków:
  /// w trakcie jazdy to prawdopodobnie ruch, a na postoju to prawie na pewno
  /// szum odbiornika stojącego pod drzewami.
  bool _isMoving(
    AutoPauseSample sample,
    AutoPauseSample? previous, {
    required double threshold,
  }) {
    // 1. Czujnik na kole rozstrzyga sam. Koło albo się kręci, albo nie, a GPS
    //    potrafi dryfować na stojącym rowerze i zmyślać ruch.
    final sensor = _freshSensorSpeed(sample);
    if (sensor != null) {
      _evidence = AutoPauseEvidence.wheelSensor;
      return sensor >= threshold;
    }

    // 2. Prędkość z GPS. Doppler jest wiarygodny także przy 1,5 km/h, więc to
    //    ona odróżnia bardzo wolny podjazd od stania na światłach.
    final gps = sample.gpsSpeedKmh;
    if (gps != null && gps.isFinite && gps >= 0) {
      _evidence = AutoPauseEvidence.gpsSpeed;
      if (gps >= threshold) return true;

      // Odbiornik mówi „stoję". Zanim mu nie uwierzymy, pozycja musi uciekać
      // KONSEKWENTNIE, a nie raz podskoczyć: telefon leżący pod drzewami
      // potrafi skoczyć o kilkanaście metrów i wrócić, nadal raportując
      // zero. Wcześniej taki jeden skok kasował całe okno postoju i pauza
      // nigdy nie dojrzewała — dokładnie tak wygląda postój w mieście.
      return _sustainedDisplacement(sample);
    }

    // 3. Bez prędkości zostaje samo przemieszczenie.
    _evidence = AutoPauseEvidence.displacement;
    return _displacementSaysMoving(sample, previous);
  }

  /// Czy pozycja ucieka w sposób, którego nie da się wytłumaczyć szumem.
  ///
  /// Mierzone wyłącznie od kotwicy i wyłącznie jako NARASTANIE odległości.
  /// Gdy kotwicy jeszcze nie ma, odpowiedź brzmi „nie": pierwsza próbka
  /// kandydująca na postój ma go rozpocząć, a nie rozstrzygnąć.
  bool _sustainedDisplacement(AutoPauseSample sample) {
    if (_anchor == null) return false;
    return _displacementSaysMoving(sample, null);
  }

  double? _freshSensorSpeed(AutoPauseSample sample) {
    final speed = sample.sensorSpeedKmh;
    final at = sample.sensorAt;
    if (speed == null || !speed.isFinite || speed < 0) return null;
    if (at == null) return null;
    if (sample.at.difference(at).abs() > sensorFreshFor) return null;
    return speed;
  }

  /// Czy pozycja przesunęła się bardziej, niż potrafi zmyślić szum GPS.
  ///
  /// Bez kotwicy porównujemy z poprzednią próbką. Z kotwicą liczy się nie samo
  /// oddalenie, ale to, czy ono ROŚNIE: telefon, którego pozycja przeskoczyła
  /// o piętnaście metrów i tam została, nie jedzie — on stoi piętnaście metrów
  /// obok. Bez tego warunku każdy taki skok wznawiałby licznik.
  bool _displacementSaysMoving(
    AutoPauseSample sample,
    AutoPauseSample? previous,
  ) {
    final tolerance = _driftTolerance(sample.accuracyMeters);
    final anchor = _anchor;
    if (anchor == null) {
      if (previous == null) return false;
      return haversineMeters(previous.point, sample.point) > tolerance;
    }

    final distance = haversineMeters(anchor, sample.point);
    final growth = distance - _lastAnchorDistance;
    _lastAnchorDistance = math.max(_lastAnchorDistance, distance);
    return distance > tolerance && growth > tolerance * 0.35;
  }

  /// Ile metrów potrafi „przejechać" stojący telefon.
  ///
  /// Rośnie razem z deklarowaną niepewnością pozycji: przy dokładności 30 m
  /// skok o 20 m to szum, a nie ruch. Bez tego każdy postój pod blokami
  /// wznawiałby licznik sam z siebie.
  static double _driftTolerance(double? accuracyMeters) {
    final accuracy = accuracyMeters == null || !accuracyMeters.isFinite
        ? 10.0
        : accuracyMeters.abs();
    return math.max(12.0, accuracy * 1.5);
  }
}
