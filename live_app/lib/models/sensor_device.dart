/// Rodzaj sensora BLE, który Live Ride potrafi obsłużyć.
enum SensorKind {
  heartRate('Tętno', 0x180D),
  cadence('Kadencja', 0x1816),
  speed('Prędkość', 0x1816),
  speedAndCadence('Prędkość i kadencja', 0x1816),
  power('Moc', 0x1818),
  trainer('Trenażer', 0x1826),
  unknown('Nieznany', 0);

  const SensorKind(this.label, this.serviceUuid);

  final String label;

  /// Przypisany numer usługi Bluetooth SIG.
  final int serviceUuid;

  static SensorKind parse(String? value) => SensorKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => SensorKind.unknown,
  );
}

/// Co sensor faktycznie nadaje.
class SensorCapabilities {
  const SensorCapabilities({
    this.heartRate = false,
    this.cadence = false,
    this.speed = false,
    this.power = false,
    this.trainerControl = false,
  });

  final bool heartRate;
  final bool cadence;
  final bool speed;
  final bool power;
  final bool trainerControl;

  bool get isEmpty =>
      !heartRate && !cadence && !speed && !power && !trainerControl;

  List<SensorKind> get kinds => [
    if (heartRate) SensorKind.heartRate,
    if (speed && cadence) SensorKind.speedAndCadence,
    if (speed && !cadence) SensorKind.speed,
    if (cadence && !speed) SensorKind.cadence,
    if (power) SensorKind.power,
    if (trainerControl) SensorKind.trainer,
  ];
}

/// Stan połączenia z sensorem.
enum SensorStatus {
  idle('Niepołączony'),
  scanning('Skanowanie'),
  connecting('Łączenie'),
  connected('Połączony'),
  streaming('Nadaje'),
  reconnecting('Ponowne łączenie');

  const SensorStatus(this.label);

  final String label;
}

/// Sensor widziany podczas skanowania albo zapamiętany.
class SensorDevice {
  const SensorDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.rssi,
    this.batteryPercent,
    this.status = SensorStatus.idle,
    this.lastValueAt,
    this.autoConnect = true,
    this.isWhoop = false,
    this.capabilities = const SensorCapabilities(),
  });

  final String id;
  final String name;
  final SensorKind kind;
  final int? rssi;
  final int? batteryPercent;
  final SensorStatus status;
  final DateTime? lastValueAt;
  final bool autoConnect;
  final bool isWhoop;
  final SensorCapabilities capabilities;

  bool get isConnected =>
      status == SensorStatus.connected || status == SensorStatus.streaming;

  /// Cztery kreski zasięgu, tak jak pokazuje telefon.
  int get signalBars {
    final value = rssi;
    if (value == null) return 0;
    if (value >= -60) return 4;
    if (value >= -72) return 3;
    if (value >= -84) return 2;
    return 1;
  }

  /// Sensor jest połączony, ale od kilkunastu sekund nic nie przysłał —
  /// zwykle znaczy to, że nie jest założony albo koło stoi.
  bool get isStale {
    if (!isConnected) return false;
    final at = lastValueAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(seconds: 15);
  }

  SensorDevice copyWith({
    String? name,
    SensorKind? kind,
    int? rssi,
    int? batteryPercent,
    SensorStatus? status,
    DateTime? lastValueAt,
    bool? autoConnect,
    SensorCapabilities? capabilities,
  }) => SensorDevice(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    rssi: rssi ?? this.rssi,
    batteryPercent: batteryPercent ?? this.batteryPercent,
    status: status ?? this.status,
    lastValueAt: lastValueAt ?? this.lastValueAt,
    autoConnect: autoConnect ?? this.autoConnect,
    isWhoop: isWhoop,
    capabilities: capabilities ?? this.capabilities,
  );
}

/// Skąd bierzemy daną wielkość, gdy jest więcej niż jedno źródło.
enum MetricSource {
  auto('Automatycznie'),
  gps('GPS'),
  sensor('Sensor BLE');

  const MetricSource(this.label);

  final String label;

  static MetricSource parse(String? value) => MetricSource.values.firstWhere(
    (source) => source.name == value,
    orElse: () => MetricSource.auto,
  );
}
