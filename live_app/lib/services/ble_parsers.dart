import 'dart:typed_data';

/// Dekodery charakterystyk Bluetooth SIG używanych przez liczniki rowerowe.
///
/// Wszystko tutaj jest czystą funkcją na bajtach, bo błąd w tym miejscu nie
/// wywala aplikacji — po prostu pokazuje zawodnikowi nieprawdziwą moc albo
/// kadencję, co jest gorsze niż brak wartości. Dlatego każdy dekoder ma test.

/// Przypisane numery Bluetooth SIG.
class BleUuids {
  static const int heartRateService = 0x180D;
  static const int heartRateMeasurement = 0x2A37;

  static const int cyclingSpeedCadenceService = 0x1816;
  static const int cscMeasurement = 0x2A5B;
  static const int cscFeature = 0x2A5C;

  static const int cyclingPowerService = 0x1818;
  static const int cyclingPowerMeasurement = 0x2A63;
  static const int cyclingPowerFeature = 0x2A65;

  static const int fitnessMachineService = 0x1826;
  static const int indoorBikeData = 0x2AD2;
  static const int fitnessMachineControlPoint = 0x2AD9;
  static const int fitnessMachineFeature = 0x2ACC;

  static const int batteryService = 0x180F;
  static const int batteryLevel = 0x2A19;

  static const int deviceInformationService = 0x180A;
}

ByteData _view(List<int> value) =>
    ByteData.sublistView(Uint8List.fromList(value));

/// Zdekodowana charakterystyka Heart Rate Measurement (0x2A37).
class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    this.sensorContact,
    this.energyExpendedKj,
    this.rrIntervalsMs = const [],
  });

  final int bpm;

  /// Null, gdy sensor nie raportuje kontaktu ze skórą.
  final bool? sensorContact;

  final int? energyExpendedKj;

  /// Odstępy RR w milisekundach — podstawa HRV, jeśli pasek je nadaje.
  final List<double> rrIntervalsMs;
}

/// Dekoduje Heart Rate Measurement (0x2A37).
///
/// Bit 0 flag wybiera wartość 8- lub 16-bitową, bity 1–2 niosą status
/// kontaktu, bit 3 wydatek energii, bit 4 odstępy RR.
HeartRateMeasurement? parseHeartRateMeasurement(List<int> value) {
  if (value.length < 2) return null;
  final data = _view(value);
  final flags = value[0];
  final wide = (flags & 0x01) != 0;

  var offset = 1;
  final int bpm;
  if (wide) {
    if (value.length < 3) return null;
    bpm = data.getUint16(offset, Endian.little);
    offset += 2;
  } else {
    bpm = value[1];
    offset += 1;
  }
  if (bpm <= 0 || bpm > 260) return null;

  bool? contact;
  if ((flags & 0x04) != 0) contact = (flags & 0x02) != 0;

  int? energy;
  if ((flags & 0x08) != 0 && value.length >= offset + 2) {
    energy = data.getUint16(offset, Endian.little);
    offset += 2;
  }

  final rr = <double>[];
  if ((flags & 0x10) != 0) {
    while (value.length >= offset + 2) {
      // Jednostka to 1/1024 sekundy.
      rr.add(data.getUint16(offset, Endian.little) * 1000 / 1024);
      offset += 2;
    }
  }

  return HeartRateMeasurement(
    bpm: bpm,
    sensorContact: contact,
    energyExpendedKj: energy,
    rrIntervalsMs: rr,
  );
}

/// Zdekodowana charakterystyka CSC Measurement (0x2A5B).
///
/// Sensor nadaje liczniki narastające, a nie prędkość i kadencję — te trzeba
/// policzyć z różnicy dwóch próbek, czym zajmuje się [RevolutionTracker].
class CscMeasurement {
  const CscMeasurement({
    this.cumulativeWheelRevolutions,
    this.lastWheelEventTime,
    this.cumulativeCrankRevolutions,
    this.lastCrankEventTime,
  });

  final int? cumulativeWheelRevolutions;

  /// Czas ostatniego zdarzenia koła w 1/1024 s, zawija się co 64 sekundy.
  final int? lastWheelEventTime;

  final int? cumulativeCrankRevolutions;
  final int? lastCrankEventTime;

  bool get hasWheel => cumulativeWheelRevolutions != null;
  bool get hasCrank => cumulativeCrankRevolutions != null;
}

/// Dekoduje CSC Measurement (0x2A5B).
CscMeasurement? parseCscMeasurement(List<int> value) {
  if (value.isEmpty) return null;
  final data = _view(value);
  final flags = value[0];
  final hasWheel = (flags & 0x01) != 0;
  final hasCrank = (flags & 0x02) != 0;
  if (!hasWheel && !hasCrank) return null;

  var offset = 1;
  int? wheelRevs;
  int? wheelTime;
  if (hasWheel) {
    if (value.length < offset + 6) return null;
    wheelRevs = data.getUint32(offset, Endian.little);
    wheelTime = data.getUint16(offset + 4, Endian.little);
    offset += 6;
  }

  int? crankRevs;
  int? crankTime;
  if (hasCrank) {
    if (value.length < offset + 4) return null;
    crankRevs = data.getUint16(offset, Endian.little);
    crankTime = data.getUint16(offset + 2, Endian.little);
  }

  return CscMeasurement(
    cumulativeWheelRevolutions: wheelRevs,
    lastWheelEventTime: wheelTime,
    cumulativeCrankRevolutions: crankRevs,
    lastCrankEventTime: crankTime,
  );
}

/// Zdekodowana charakterystyka Cycling Power Measurement (0x2A63).
class CyclingPowerMeasurement {
  const CyclingPowerMeasurement({
    required this.instantaneousPowerWatts,
    this.pedalPowerBalancePercent,
    this.accumulatedTorque,
    this.cumulativeWheelRevolutions,
    this.lastWheelEventTime,
    this.cumulativeCrankRevolutions,
    this.lastCrankEventTime,
  });

  final int instantaneousPowerWatts;

  /// Udział lewej nogi w procentach, gdy miernik go podaje.
  final double? pedalPowerBalancePercent;

  final double? accumulatedTorque;
  final int? cumulativeWheelRevolutions;
  final int? lastWheelEventTime;
  final int? cumulativeCrankRevolutions;
  final int? lastCrankEventTime;

  /// Kadencję z miernika mocy liczy się tak samo jak z CSC.
  CscMeasurement get asCsc => CscMeasurement(
    cumulativeWheelRevolutions: cumulativeWheelRevolutions,
    lastWheelEventTime: lastWheelEventTime,
    cumulativeCrankRevolutions: cumulativeCrankRevolutions,
    lastCrankEventTime: lastCrankEventTime,
  );
}

/// Dekoduje Cycling Power Measurement (0x2A63).
///
/// Pola opcjonalne występują w ustalonej kolejności, więc offset trzeba
/// przesuwać po kolei — pominięcie jednego przesuwa wszystkie następne.
CyclingPowerMeasurement? parseCyclingPowerMeasurement(List<int> value) {
  if (value.length < 4) return null;
  final data = _view(value);
  final flags = data.getUint16(0, Endian.little);
  final power = data.getInt16(2, Endian.little);
  if (power < -1000 || power > 4000) return null;

  var offset = 4;

  double? balance;
  if ((flags & 0x0001) != 0) {
    if (value.length < offset + 1) return null;
    // Jednostka to 1/2 %.
    balance = value[offset] / 2;
    offset += 1;
  }
  // Bit 1 to tylko referencja balansu — nie zajmuje bajtów.

  double? torque;
  if ((flags & 0x0004) != 0) {
    if (value.length < offset + 2) return null;
    torque = data.getUint16(offset, Endian.little) / 32;
    offset += 2;
  }
  // Bit 3 to źródło momentu — również bez bajtów.

  int? wheelRevs;
  int? wheelTime;
  if ((flags & 0x0010) != 0) {
    if (value.length < offset + 6) return null;
    wheelRevs = data.getUint32(offset, Endian.little);
    // Tutaj jednostka to 1/2048 s — inaczej niż w CSC.
    wheelTime = data.getUint16(offset + 4, Endian.little);
    offset += 6;
  }

  int? crankRevs;
  int? crankTime;
  if ((flags & 0x0020) != 0) {
    if (value.length < offset + 4) return null;
    crankRevs = data.getUint16(offset, Endian.little);
    crankTime = data.getUint16(offset + 2, Endian.little);
    offset += 4;
  }

  return CyclingPowerMeasurement(
    instantaneousPowerWatts: power,
    pedalPowerBalancePercent: balance,
    accumulatedTorque: torque,
    cumulativeWheelRevolutions: wheelRevs,
    lastWheelEventTime: wheelTime,
    cumulativeCrankRevolutions: crankRevs,
    lastCrankEventTime: crankTime,
  );
}

/// Zdekodowana charakterystyka Indoor Bike Data (0x2AD2) z FTMS.
class IndoorBikeData {
  const IndoorBikeData({
    this.speedKmh,
    this.averageSpeedKmh,
    this.cadenceRpm,
    this.averageCadenceRpm,
    this.totalDistanceMeters,
    this.resistanceLevel,
    this.powerWatts,
    this.averagePowerWatts,
    this.energyTotalKj,
    this.heartRateBpm,
    this.elapsed,
  });

  final double? speedKmh;
  final double? averageSpeedKmh;
  final double? cadenceRpm;
  final double? averageCadenceRpm;
  final double? totalDistanceMeters;
  final double? resistanceLevel;
  final int? powerWatts;
  final int? averagePowerWatts;
  final int? energyTotalKj;
  final int? heartRateBpm;
  final Duration? elapsed;

  bool get isEmpty =>
      speedKmh == null &&
      cadenceRpm == null &&
      powerWatts == null &&
      heartRateBpm == null;
}

/// Dekoduje Indoor Bike Data (0x2AD2).
///
/// Uwaga na bit 0: to „More Data", a jego ustawienie oznacza, że prędkości
/// chwilowej NIE MA — odwrotnie niż wszystkie pozostałe bity.
IndoorBikeData? parseIndoorBikeData(List<int> value) {
  if (value.length < 2) return null;
  final data = _view(value);
  final flags = data.getUint16(0, Endian.little);
  var offset = 2;
  var truncated = false;

  double? readU16(double scale) {
    if (value.length < offset + 2) {
      truncated = true;
      return null;
    }
    final raw = data.getUint16(offset, Endian.little);
    offset += 2;
    return raw * scale;
  }

  int? readS16() {
    if (value.length < offset + 2) {
      truncated = true;
      return null;
    }
    final raw = data.getInt16(offset, Endian.little);
    offset += 2;
    return raw;
  }

  double? speed;
  if ((flags & 0x0001) == 0) speed = readU16(0.01);

  double? averageSpeed;
  if ((flags & 0x0002) != 0) averageSpeed = readU16(0.01);

  double? cadence;
  if ((flags & 0x0004) != 0) cadence = readU16(0.5);

  double? averageCadence;
  if ((flags & 0x0008) != 0) averageCadence = readU16(0.5);

  double? distance;
  if ((flags & 0x0010) != 0) {
    if (value.length < offset + 3) return null;
    distance =
        (value[offset] | (value[offset + 1] << 8) | (value[offset + 2] << 16))
            .toDouble();
    offset += 3;
  }

  double? resistance;
  if ((flags & 0x0020) != 0) {
    final raw = readS16();
    resistance = raw?.toDouble();
  }

  int? power;
  if ((flags & 0x0040) != 0) power = readS16();

  int? averagePower;
  if ((flags & 0x0080) != 0) averagePower = readS16();

  int? energy;
  if ((flags & 0x0100) != 0) {
    // Total energy, energy per hour, energy per minute.
    if (value.length < offset + 5) return null;
    energy = data.getUint16(offset, Endian.little);
    offset += 5;
  }

  int? heartRate;
  if ((flags & 0x0200) != 0) {
    if (value.length < offset + 1) return null;
    heartRate = value[offset];
    offset += 1;
  }

  if ((flags & 0x0400) != 0) offset += 1; // Metabolic equivalent.

  Duration? elapsed;
  if ((flags & 0x0800) != 0) {
    if (value.length < offset + 2) return null;
    elapsed = Duration(seconds: data.getUint16(offset, Endian.little));
    offset += 2;
  }

  // Urwana ramka przesuwa wszystkie kolejne pola, więc lepiej nie pokazać
  // nic, niż pokazać moc odczytaną z bajtów tętna.
  if (truncated) return null;

  final result = IndoorBikeData(
    speedKmh: speed,
    averageSpeedKmh: averageSpeed,
    cadenceRpm: cadence,
    averageCadenceRpm: averageCadence,
    totalDistanceMeters: distance,
    resistanceLevel: resistance,
    powerWatts: power,
    averagePowerWatts: averagePower,
    energyTotalKj: energy,
    heartRateBpm: heartRate,
    elapsed: elapsed,
  );
  return result.isEmpty && result.totalDistanceMeters == null ? null : result;
}

/// Zamienia narastające liczniki obrotów na kadencję i prędkość.
///
/// Sensory nadają licznik obrotów i czas ostatniego zdarzenia; obie wartości
/// się zawijają (czas co 64 s, obroty korby co 65 536), więc różnice trzeba
/// liczyć modulo. Gdy koło stoi, licznik się nie zmienia — wtedy po chwili
/// zwracamy zero zamiast trzymać ostatnią wartość w nieskończoność.
class RevolutionTracker {
  RevolutionTracker({
    this.timeResolution = 1024,
    this.revolutionBits = 16,
    this.zeroAfter = const Duration(seconds: 3),
  });

  /// Tyknięć na sekundę w polu czasu: 1024 dla CSC, 2048 dla koła w CPS.
  final int timeResolution;

  /// Szerokość licznika obrotów w bitach: 16 dla korby, 32 dla koła.
  final int revolutionBits;

  /// Po tym czasie bez nowego zdarzenia raportujemy zero.
  final Duration zeroAfter;

  int? _lastRevolutions;
  int? _lastEventTime;
  DateTime? _lastUpdate;
  double? _lastRate;

  /// Obroty na minutę albo null, gdy jeszcze nie ma z czego policzyć.
  double? get revolutionsPerMinute => _lastRate;

  /// Podaje nową próbkę i zwraca obroty na minutę.
  double? update(int revolutions, int eventTime, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final previousRevolutions = _lastRevolutions;
    final previousTime = _lastEventTime;
    _lastRevolutions = revolutions;
    _lastEventTime = eventTime;

    if (previousRevolutions == null || previousTime == null) {
      _lastUpdate = at;
      return null;
    }

    final revolutionModulo = 1 << revolutionBits;
    var deltaRevolutions = revolutions - previousRevolutions;
    if (deltaRevolutions < 0) deltaRevolutions += revolutionModulo;

    var deltaTime = eventTime - previousTime;
    if (deltaTime < 0) deltaTime += 65536;

    if (deltaRevolutions == 0) {
      // Koło albo korba stoi. Trzymamy ostatnią wartość przez chwilę, bo
      // sensor nadaje częściej niż się kręci, ale nie dłużej.
      final since = _lastUpdate;
      if (since != null && at.difference(since) >= zeroAfter) {
        _lastRate = 0;
      }
      return _lastRate;
    }

    _lastUpdate = at;
    if (deltaTime <= 0) return _lastRate;

    final seconds = deltaTime / timeResolution;
    final rate = deltaRevolutions / seconds * 60;
    // Ponad 250 obrotów korby na minutę to błąd odczytu, nie sprint.
    if (rate <= 0 || rate > 3000) return _lastRate;
    _lastRate = rate;
    return rate;
  }

  /// Prędkość w km/h z obwodu koła w milimetrach.
  double? speedKmh(double wheelCircumferenceMm) {
    final rpm = _lastRate;
    if (rpm == null) return null;
    return rpm * wheelCircumferenceMm * 60 / 1e6;
  }

  void reset() {
    _lastRevolutions = null;
    _lastEventTime = null;
    _lastUpdate = null;
    _lastRate = null;
  }
}
