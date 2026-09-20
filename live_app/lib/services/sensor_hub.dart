import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../data/settings_dao.dart';
import '../models/sensor_device.dart';
import 'ble_parsers.dart';
import 'heart_rate_service.dart';

/// Odczyt ze wszystkich podłączonych sensorów w jednym miejscu.
class SensorSnapshot {
  const SensorSnapshot({
    this.heartRateBpm,
    this.cadenceRpm,
    this.speedKmh,
    this.powerWatts,
    this.pedalBalancePercent,
    this.trainerResistance,
    this.at,
  });

  final int? heartRateBpm;
  final double? cadenceRpm;
  final double? speedKmh;
  final int? powerWatts;
  final double? pedalBalancePercent;
  final double? trainerResistance;
  final DateTime? at;

  bool get hasCadence => cadenceRpm != null;
  bool get hasPower => powerWatts != null;
  bool get hasWheelSpeed => speedKmh != null;

  SensorSnapshot copyWith({
    Object? heartRateBpm = _keep,
    Object? cadenceRpm = _keep,
    Object? speedKmh = _keep,
    Object? powerWatts = _keep,
    Object? pedalBalancePercent = _keep,
    Object? trainerResistance = _keep,
    DateTime? at,
  }) => SensorSnapshot(
    heartRateBpm: heartRateBpm == _keep
        ? this.heartRateBpm
        : heartRateBpm as int?,
    cadenceRpm: cadenceRpm == _keep ? this.cadenceRpm : cadenceRpm as double?,
    speedKmh: speedKmh == _keep ? this.speedKmh : speedKmh as double?,
    powerWatts: powerWatts == _keep ? this.powerWatts : powerWatts as int?,
    pedalBalancePercent: pedalBalancePercent == _keep
        ? this.pedalBalancePercent
        : pedalBalancePercent as double?,
    trainerResistance: trainerResistance == _keep
        ? this.trainerResistance
        : trainerResistance as double?,
    at: at ?? this.at,
  );
}

const Object _keep = Object();

/// Skąd brać poszczególne wielkości, gdy jest więcej niż jedno źródło.
class SensorSourceSettings {
  const SensorSourceSettings({
    this.speed = MetricSource.auto,
    this.wheelCircumferenceMm = 2105,
  });

  /// Skąd brać prędkość. Kadencji nie ma na tej liście, bo jej jedynym
  /// źródłem jest sensor — wybór „GPS albo czujnik" byłby wyborem
  /// pozornym.
  final MetricSource speed;

  /// Obwód koła w milimetrach — 2105 to domyślne 700×25c.
  final double wheelCircumferenceMm;

  SensorSourceSettings copyWith({
    MetricSource? speed,
    double? wheelCircumferenceMm,
  }) => SensorSourceSettings(
    speed: speed ?? this.speed,
    wheelCircumferenceMm: wheelCircumferenceMm ?? this.wheelCircumferenceMm,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed.name,
    'wheel_mm': wheelCircumferenceMm,
  };

  factory SensorSourceSettings.fromJson(Map<String, dynamic> json) =>
      SensorSourceSettings(
        speed: MetricSource.parse(json['speed'] as String?),
        wheelCircumferenceMm: (json['wheel_mm'] as num?)?.toDouble() ?? 2105,
      );
}

/// Jedno połączenie z sensorem, razem z jego stanem i licznikami obrotów.
class _Connection {
  _Connection(this.peripheral, this.device);

  Peripheral peripheral;
  SensorDevice device;
  final RevolutionTracker wheel = RevolutionTracker(revolutionBits: 32);
  final RevolutionTracker crank = RevolutionTracker();
  final List<GATTCharacteristic> notified = [];
  GATTCharacteristic? battery;
  int retryAttempt = 0;
  bool intentionalDisconnect = false;
}

/// Centrum sensorów BLE: kadencja, prędkość, moc i trenażer.
///
/// Tętno zostaje w [HeartRateService], bo pasek na klatę (w tym WHOOP) ma
/// własny ekran i własną logikę ponownego łączenia; hub czyta z niego
/// wartość, żeby migawka była kompletna.
///
/// Hub trzyma po jednym połączeniu na sparowany sensor i utrzymuje je przez
/// całe życie aplikacji, bo przejazd nie może stracić mocy tylko dlatego, że
/// zawodnik przełączył ekran.
class SensorHub extends ChangeNotifier {
  SensorHub({
    CentralManager? central,
    required HeartRateService heartRate,
    SettingsDao? settings,
  }) : _central = central ?? CentralManager(),
       _heartRate = heartRate,
       _settings = settings {
    _heartRate.addListener(_onHeartRate);
  }

  static const String settingsKey = 'sensor_sources';
  static const String pairedKey = 'paired_sensors';

  static const List<Duration> _retryBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
  ];

  final CentralManager _central;
  final HeartRateService _heartRate;
  final SettingsDao? _settings;

  final Map<String, SensorDevice> _discovered = {};
  final Map<String, Peripheral> _peripherals = {};
  final Map<String, _Connection> _connections = {};
  final Map<String, SensorDevice> _paired = {};
  final Map<String, Timer> _retryTimers = {};

  StreamSubscription<DiscoveredEventArgs>? _discoverySub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifySub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _stateSub;
  Timer? _scanTimeout;
  Timer? _vitalsTimer;

  bool _scanning = false;
  String? _lastError;
  SensorSnapshot _snapshot = const SensorSnapshot();
  SensorSourceSettings _sources = const SensorSourceSettings();

  // ---------------------------------------------------------------- gettery

  bool get isScanning => _scanning;
  String? get lastError => _lastError;
  SensorSnapshot get snapshot => _snapshot;
  SensorSourceSettings get sources => _sources;
  BluetoothLowEnergyState get adapterState => _central.state;

  /// Sparowane sensory, niezależnie od tego, czy akurat są w zasięgu.
  List<SensorDevice> get paired {
    final list = _paired.values.toList()
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return List.unmodifiable(list);
  }

  /// Znalezione w skanie, bez tych już sparowanych.
  List<SensorDevice> get discovered {
    final list =
        _discovered.values
            .where((device) => !_paired.containsKey(device.id))
            .toList()
          ..sort((a, b) => (b.rssi ?? -127).compareTo(a.rssi ?? -127));
    return List.unmodifiable(list);
  }

  List<SensorDevice> get connected =>
      List.unmodifiable(_connections.values.map((entry) => entry.device));

  /// Pierwszy połączony sensor, który umie daną wielkość.
  ///
  /// Publiczna strona i diagnostyka pytają nie tylko „ile", ale „skąd" i „jak
  /// dawno". Bez tego „moc 242 W" z miernika, który odpadł trzy minuty temu,
  /// wygląda dokładnie tak samo jak pomiar sprzed sekundy.
  SensorDevice? deviceWith(bool Function(SensorCapabilities) test) {
    for (final entry in _connections.values) {
      if (test(entry.device.capabilities)) return entry.device;
    }
    return null;
  }

  SensorDevice? get powerDevice => deviceWith((c) => c.power);
  SensorDevice? get cadenceDevice => deviceWith((c) => c.cadence);
  SensorDevice? get speedDevice => deviceWith((c) => c.speed);

  bool isConnectedTo(String id) => _connections.containsKey(id);

  // -------------------------------------------------------------- lifecycle

  Future<void> restore() async {
    final settings = _settings;
    if (settings == null) return;
    final saved = await settings.readJson(settingsKey);
    if (saved != null) {
      try {
        _sources = SensorSourceSettings.fromJson(saved);
      } catch (_) {
        _sources = const SensorSourceSettings();
      }
    }
    final storedPaired = await settings.readJson(pairedKey);
    final entries = (storedPaired?['devices'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final entry in entries) {
      final id = entry['id'] as String?;
      if (id == null) continue;
      _paired[id] = SensorDevice(
        id: id,
        name: entry['name'] as String? ?? 'Sensor',
        kind: SensorKind.parse(entry['kind'] as String?),
        autoConnect: entry['auto_connect'] as bool? ?? true,
      );
    }
    notifyListeners();
    unawaited(reconnectPaired());
  }

  Future<void> _persistPaired() async {
    await _settings?.writeJson(pairedKey, {
      'devices': [
        for (final device in _paired.values)
          {
            'id': device.id,
            'name': device.name,
            'kind': device.kind.name,
            'auto_connect': device.autoConnect,
          },
      ],
    });
  }

  Future<void> updateSources(SensorSourceSettings sources) async {
    _sources = sources;
    notifyListeners();
    await _settings?.writeJson(settingsKey, sources.toJson());
  }

  /// Łączy się z tym, co iOS trzyma już połączone, a resztę szuka skanem.
  Future<void> reconnectPaired() async {
    final wanted = _paired.values
        .where((device) => device.autoConnect && !isConnectedTo(device.id))
        .toList();
    if (wanted.isEmpty) return;

    try {
      final known = await _central.retrieveConnectedPeripherals();
      for (final peripheral in known) {
        final id = peripheral.uuid.toString();
        if (_paired.containsKey(id) && !isConnectedTo(id)) {
          _peripherals[id] = peripheral;
          await connect(id);
        }
      }
    } catch (_) {
      // Nie wszędzie dostępne — wtedy zostaje skan.
    }

    if (_paired.values.any(
      (device) => device.autoConnect && !isConnectedTo(device.id),
    )) {
      try {
        await startScan(timeout: const Duration(seconds: 15));
      } catch (_) {
        // Cicho: to próba w tle, nie akcja zawodnika.
      }
    }
  }

  // ------------------------------------------------------------------ skan

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (Platform.isAndroid) {
      final authorized = await _central.authorize();
      if (!authorized) {
        throw StateError(
          'Brak zgody na Bluetooth. Włącz ją w Ustawieniach, żeby używać '
          'sensorów.',
        );
      }
    }
    if (_central.state == BluetoothLowEnergyState.poweredOff) {
      throw StateError('Bluetooth jest wyłączony.');
    }
    if (_central.state == BluetoothLowEnergyState.unauthorized) {
      throw StateError('Live Ride nie ma dostępu do Bluetooth.');
    }

    await stopScan();
    _discovered.clear();
    _lastError = null;
    _scanning = true;
    notifyListeners();

    _discoverySub = _central.discovered.listen(_onDiscovered);
    await _central.startDiscovery();
    _scanTimeout = Timer(timeout, () => unawaited(stopScan()));
  }

  Future<void> stopScan() async {
    _scanTimeout?.cancel();
    _scanTimeout = null;
    try {
      await _central.stopDiscovery();
    } catch (_) {}
    await _discoverySub?.cancel();
    _discoverySub = null;
    if (_scanning) {
      _scanning = false;
      notifyListeners();
    }
  }

  void _onDiscovered(DiscoveredEventArgs event) {
    final id = event.peripheral.uuid.toString();
    final advertised = event.advertisement.name?.trim() ?? '';
    final services = event.advertisement.serviceUUIDs;
    final capabilities = capabilitiesFromServices(services);
    // Sensor rowerowy zawsze ogłasza swoją usługę. Bez niej jest to czyjś
    // zegarek albo głośnik i nie ma czego pokazywać.
    if (capabilities.isEmpty) return;

    _peripherals[id] = event.peripheral;
    final kind = capabilities.kinds.firstOrNull ?? SensorKind.unknown;
    final device = SensorDevice(
      id: id,
      name: advertised.isNotEmpty ? advertised : kind.label,
      kind: kind,
      rssi: event.rssi,
      capabilities: capabilities,
      status: isConnectedTo(id) ? SensorStatus.connected : SensorStatus.idle,
    );
    _discovered[id] = device;

    final remembered = _paired[id];
    if (remembered != null) {
      _paired[id] = remembered.copyWith(
        rssi: event.rssi,
        capabilities: capabilities,
      );
      if (remembered.autoConnect && !isConnectedTo(id)) {
        unawaited(connect(id));
      }
    }
    notifyListeners();
  }

  /// Mapuje ogłaszane usługi na to, co sensor potrafi.
  @visibleForTesting
  static SensorCapabilities capabilitiesFromServices(List<UUID> services) {
    bool has(int uuid) => services.contains(UUID.short(uuid));
    return SensorCapabilities(
      heartRate: has(BleUuids.heartRateService),
      // CSC ogłasza jedną usługę dla prędkości i kadencji; co naprawdę
      // nadaje, widać dopiero w ramkach.
      cadence: has(BleUuids.cyclingSpeedCadenceService),
      speed: has(BleUuids.cyclingSpeedCadenceService),
      power: has(BleUuids.cyclingPowerService),
      trainerControl: has(BleUuids.fitnessMachineService),
    );
  }

  // --------------------------------------------------------------- połącz

  Future<void> connect(String id) async {
    if (isConnectedTo(id)) return;
    final peripheral = _peripherals[id];
    if (peripheral == null) {
      throw StateError('Tego sensora nie ma już w zasięgu. Skanuj ponownie.');
    }

    final known = _discovered[id] ?? _paired[id];
    final connection = _Connection(
      peripheral,
      (known ?? SensorDevice(id: id, name: 'Sensor', kind: SensorKind.unknown))
          .copyWith(status: SensorStatus.connecting),
    );
    _connections[id] = connection;
    notifyListeners();

    try {
      await _central.connect(peripheral);
      final services = await _central.discoverGATT(peripheral);

      var capabilities = const SensorCapabilities();
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid;
          if (uuid == UUID.short(BleUuids.cscMeasurement)) {
            connection.notified.add(characteristic);
            capabilities = SensorCapabilities(
              heartRate: capabilities.heartRate,
              cadence: true,
              speed: true,
              power: capabilities.power,
              trainerControl: capabilities.trainerControl,
            );
          } else if (uuid == UUID.short(BleUuids.cyclingPowerMeasurement)) {
            connection.notified.add(characteristic);
            capabilities = SensorCapabilities(
              heartRate: capabilities.heartRate,
              cadence: capabilities.cadence,
              speed: capabilities.speed,
              power: true,
              trainerControl: capabilities.trainerControl,
            );
          } else if (uuid == UUID.short(BleUuids.indoorBikeData)) {
            connection.notified.add(characteristic);
            capabilities = SensorCapabilities(
              heartRate: capabilities.heartRate,
              cadence: true,
              speed: true,
              power: true,
              trainerControl: true,
            );
          } else if (service.uuid == UUID.short(BleUuids.batteryService) &&
              uuid == UUID.short(BleUuids.batteryLevel)) {
            connection.battery = characteristic;
          }
        }
      }

      if (connection.notified.isEmpty) {
        throw StateError(
          'Ten sensor nie udostępnia żadnej znanej usługi rowerowej.',
        );
      }

      _notifySub ??= _central.characteristicNotified.listen(_onNotified);
      _stateSub ??= _central.connectionStateChanged.listen(
        _onConnectionChanged,
      );

      for (final characteristic in connection.notified) {
        await _central.setCharacteristicNotifyState(
          peripheral,
          characteristic,
          state: true,
        );
      }

      connection.retryAttempt = 0;
      connection.device = connection.device.copyWith(
        status: SensorStatus.connected,
        capabilities: capabilities,
        kind: capabilities.kinds.firstOrNull ?? connection.device.kind,
      );
      _paired[id] = connection.device.copyWith(autoConnect: true);
      await _persistPaired();
      _startVitalsTimer();
      notifyListeners();
      unawaited(_refreshVitals());
    } catch (e) {
      _connections.remove(id);
      try {
        await _central.disconnect(peripheral);
      } catch (_) {}
      _lastError = e is StateError ? e.message : e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect(String id) async {
    final connection = _connections.remove(id);
    _retryTimers.remove(id)?.cancel();
    if (connection == null) {
      notifyListeners();
      return;
    }
    connection.intentionalDisconnect = true;
    for (final characteristic in connection.notified) {
      try {
        await _central.setCharacteristicNotifyState(
          connection.peripheral,
          characteristic,
          state: false,
        );
      } catch (_) {}
    }
    try {
      await _central.disconnect(connection.peripheral);
    } catch (_) {}
    final remembered = _paired[id];
    if (remembered != null) {
      _paired[id] = remembered.copyWith(status: SensorStatus.idle);
    }
    _recomputeSnapshot();
    if (_connections.isEmpty) {
      _vitalsTimer?.cancel();
      _vitalsTimer = null;
    }
    notifyListeners();
  }

  Future<void> forget(String id) async {
    await disconnect(id);
    _paired.remove(id);
    await _persistPaired();
    notifyListeners();
  }

  Future<void> setAutoConnect(String id, bool autoConnect) async {
    final device = _paired[id];
    if (device == null) return;
    _paired[id] = device.copyWith(autoConnect: autoConnect);
    await _persistPaired();
    notifyListeners();
  }

  // ---------------------------------------------------------------- odczyt

  void _onNotified(GATTCharacteristicNotifiedEventArgs event) {
    final id = event.peripheral.uuid.toString();
    final connection = _connections[id];
    if (connection == null) return;

    final uuid = event.characteristic.uuid;
    final now = DateTime.now();
    var changed = false;

    if (uuid == UUID.short(BleUuids.cscMeasurement)) {
      final parsed = parseCscMeasurement(event.value);
      if (parsed != null) changed = _applyCsc(connection, parsed, now);
    } else if (uuid == UUID.short(BleUuids.cyclingPowerMeasurement)) {
      final parsed = parseCyclingPowerMeasurement(event.value);
      if (parsed != null) {
        _snapshot = _snapshot.copyWith(
          powerWatts: parsed.instantaneousPowerWatts,
          pedalBalancePercent: parsed.pedalPowerBalancePercent,
          at: now,
        );
        _applyCsc(connection, parsed.asCsc, now);
        changed = true;
      }
    } else if (uuid == UUID.short(BleUuids.indoorBikeData)) {
      final parsed = parseIndoorBikeData(event.value);
      if (parsed != null) {
        _snapshot = _snapshot.copyWith(
          speedKmh: parsed.speedKmh ?? _snapshot.speedKmh,
          cadenceRpm: parsed.cadenceRpm ?? _snapshot.cadenceRpm,
          powerWatts: parsed.powerWatts ?? _snapshot.powerWatts,
          trainerResistance:
              parsed.resistanceLevel ?? _snapshot.trainerResistance,
          at: now,
        );
        changed = true;
      }
    }

    if (!changed) return;
    connection.device = connection.device.copyWith(
      status: SensorStatus.streaming,
      lastValueAt: now,
    );
    notifyListeners();
  }

  bool _applyCsc(_Connection connection, CscMeasurement parsed, DateTime now) {
    var changed = false;
    final wheelRevs = parsed.cumulativeWheelRevolutions;
    final wheelTime = parsed.lastWheelEventTime;
    if (wheelRevs != null && wheelTime != null) {
      connection.wheel.update(wheelRevs, wheelTime, now: now);
      final speed = connection.wheel.speedKmh(_sources.wheelCircumferenceMm);
      if (speed != null) {
        _snapshot = _snapshot.copyWith(speedKmh: speed, at: now);
        changed = true;
      }
    }

    final crankRevs = parsed.cumulativeCrankRevolutions;
    final crankTime = parsed.lastCrankEventTime;
    if (crankRevs != null && crankTime != null) {
      final cadence = connection.crank.update(crankRevs, crankTime, now: now);
      if (cadence != null) {
        _snapshot = _snapshot.copyWith(cadenceRpm: cadence, at: now);
        changed = true;
      }
    }
    return changed;
  }

  void _onHeartRate() {
    final bpm = _heartRate.latestBpm;
    if (bpm == _snapshot.heartRateBpm) return;
    _snapshot = _snapshot.copyWith(heartRateBpm: bpm, at: DateTime.now());
    notifyListeners();
  }

  void _onConnectionChanged(PeripheralConnectionStateChangedEventArgs event) {
    if (event.state == ConnectionState.connected) return;
    final id = event.peripheral.uuid.toString();
    final connection = _connections[id];
    if (connection == null || connection.intentionalDisconnect) return;

    _connections.remove(id);
    final remembered = _paired[id];
    if (remembered != null) {
      _paired[id] = remembered.copyWith(status: SensorStatus.reconnecting);
    }
    _recomputeSnapshot();
    notifyListeners();
    if (remembered?.autoConnect ?? false) {
      _scheduleRetry(id, connection.retryAttempt);
    }
  }

  void _scheduleRetry(String id, int attempt) {
    _retryTimers[id]?.cancel();
    final delay = _retryBackoff[attempt.clamp(0, _retryBackoff.length - 1)];
    _retryTimers[id] = Timer(delay, () async {
      if (isConnectedTo(id)) return;
      try {
        await connect(id);
      } catch (_) {
        _scheduleRetry(id, attempt + 1);
      }
    });
  }

  /// Zeruje wartości, których nie ma już kto dostarczyć.
  ///
  /// Zostawienie ostatniej mocy na ekranie po rozłączeniu miernika to
  /// dokładnie ten rodzaj kłamstwa, którego licznik nie może popełniać.
  void _recomputeSnapshot() {
    final hasPower = _connections.values.any(
      (entry) => entry.device.capabilities.power,
    );
    final hasCadence = _connections.values.any(
      (entry) => entry.device.capabilities.cadence,
    );
    final hasSpeed = _connections.values.any(
      (entry) => entry.device.capabilities.speed,
    );
    _snapshot = SensorSnapshot(
      heartRateBpm: _heartRate.latestBpm,
      powerWatts: hasPower ? _snapshot.powerWatts : null,
      pedalBalancePercent: hasPower ? _snapshot.pedalBalancePercent : null,
      cadenceRpm: hasCadence ? _snapshot.cadenceRpm : null,
      speedKmh: hasSpeed ? _snapshot.speedKmh : null,
      trainerResistance: _snapshot.trainerResistance,
      at: _snapshot.at,
    );
  }

  void _startVitalsTimer() {
    _vitalsTimer ??= Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_refreshVitals()),
    );
  }

  Future<void> _refreshVitals() async {
    for (final connection in _connections.values.toList()) {
      final battery = connection.battery;
      if (battery != null) {
        try {
          final value = await _central.readCharacteristic(
            connection.peripheral,
            battery,
          );
          if (value.isNotEmpty && value.first <= 100) {
            connection.device = connection.device.copyWith(
              batteryPercent: value.first,
            );
            final remembered = _paired[connection.device.id];
            if (remembered != null) {
              _paired[connection.device.id] = remembered.copyWith(
                batteryPercent: value.first,
              );
            }
          }
        } catch (_) {}
      }
      try {
        final rssi = await _central.readRSSI(connection.peripheral);
        connection.device = connection.device.copyWith(rssi: rssi);
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _heartRate.removeListener(_onHeartRate);
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _vitalsTimer?.cancel();
    _scanTimeout?.cancel();
    await _discoverySub?.cancel();
    await _notifySub?.cancel();
    await _stateSub?.cancel();
    for (final id in _connections.keys.toList()) {
      await disconnect(id);
    }
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
