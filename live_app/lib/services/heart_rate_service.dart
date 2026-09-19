import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// Standard Bluetooth SIG assigned numbers.
const int _hrServiceUuid = 0x180D;
const int _hrMeasurementUuid = 0x2A37;
const int _batteryServiceUuid = 0x180F;
const int _batteryLevelUuid = 0x2A19;

/// A sensor seen while scanning.
class HeartRateDevice {
  const HeartRateDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.advertisesHeartRate,
    required this.isWhoop,
  });

  final String id;
  final String name;
  final int rssi;

  /// The device advertises the Heart Rate service outright.
  final bool advertisesHeartRate;

  /// A WHOOP strap, which only exposes heart rate after connecting and only
  /// while Broadcast Heart Rate is switched on in the WHOOP app.
  final bool isWhoop;

  bool get likelyHeartRate => advertisesHeartRate || isWhoop;

  /// Four coarse bars, which is all a rider can act on.
  int get signalBars {
    if (rssi >= -60) return 4;
    if (rssi >= -72) return 3;
    if (rssi >= -84) return 2;
    return 1;
  }
}

enum HeartRateStatus {
  /// Nothing connected and nothing being attempted.
  idle,
  scanning,
  connecting,

  /// Connected and receiving measurements.
  streaming,

  /// Connected but no measurement has arrived yet.
  waiting,

  /// The strap dropped out and Live Ride is trying to get it back.
  reconnecting,
}

/// Bluetooth heart-rate sensors, including WHOOP.
///
/// The service owns the connection for the whole app lifetime, so a ride keeps
/// its heart rate when the rider moves between screens, and it comes back by
/// itself after the strap briefly drops out — which straps do, constantly.
class HeartRateService extends ChangeNotifier {
  HeartRateService({CentralManager? central})
    : _central = central ?? CentralManager();

  /// How many samples the sensor screen plots.
  static const int historyLength = 120;

  /// Reconnection backoff, capped so a strap left at home does not spin the
  /// radio forever.
  static const List<Duration> _retryBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final CentralManager _central;
  final LocalStore _store = LocalStore('sensors');

  final Map<String, HeartRateDevice> _devices = {};
  final Map<String, Peripheral> _peripherals = {};
  final List<int> _history = [];
  final _bpmController = StreamController<int>.broadcast();

  StreamSubscription<DiscoveredEventArgs>? _discoverySub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifySub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _stateSub;
  Timer? _scanTimeout;
  Timer? _retryTimer;
  Timer? _vitalsTimer;

  Peripheral? _connected;
  GATTCharacteristic? _measurement;
  GATTCharacteristic? _battery;

  HeartRateStatus _status = HeartRateStatus.idle;
  String? _connectedName;
  String? _rememberedId;
  String? _rememberedName;
  String? _lastError;
  int? _latestBpm;
  int? _batteryPercent;
  int? _rssi;
  bool? _sensorContact;
  DateTime? _lastSampleAt;
  int _retryAttempt = 0;
  bool _intentionalDisconnect = false;

  // ---------------------------------------------------------------- getters

  Stream<int> get bpm => _bpmController.stream;
  HeartRateStatus get status => _status;
  int? get latestBpm => _latestBpm;
  int? get batteryPercent => _batteryPercent;
  int? get rssi => _rssi;
  bool? get sensorContact => _sensorContact;
  DateTime? get lastSampleAt => _lastSampleAt;
  String? get lastError => _lastError;
  String? get connectedId => _connected?.uuid.toString();
  String? get connectedName => _connectedName;
  String? get rememberedId => _rememberedId;
  String? get rememberedName => _rememberedName;
  List<int> get history => List.unmodifiable(_history);
  BluetoothLowEnergyState get adapterState => _central.state;

  bool get isConnected =>
      _status == HeartRateStatus.streaming ||
      _status == HeartRateStatus.waiting;

  bool get isBusy =>
      _status == HeartRateStatus.connecting ||
      _status == HeartRateStatus.reconnecting;

  List<HeartRateDevice> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) {
        if (a.likelyHeartRate != b.likelyHeartRate) {
          return a.likelyHeartRate ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });
    return List.unmodifiable(list);
  }

  /// True when the strap is connected but has not produced a beat recently,
  /// which usually means it is not being worn.
  bool get isStale {
    final at = _lastSampleAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(seconds: 12);
  }

  // ------------------------------------------------------------- lifecycle

  /// Loads the remembered strap and silently reconnects to it if iOS still has
  /// it connected at the system level, which is the usual case mid-ride.
  Future<void> restore() async {
    final saved = await _store.readJson('heart_rate.json');
    _rememberedId = saved?['device_id'] as String?;
    _rememberedName = saved?['device_name'] as String?;
    notifyListeners();
    if (_rememberedId == null) return;
    await reconnectRemembered(silent: true);
  }

  Future<void> _remember(String id, String name) async {
    _rememberedId = id;
    _rememberedName = name;
    await _store.writeJson('heart_rate.json', {
      'device_id': id,
      'device_name': name,
    });
  }

  Future<void> forget() async {
    await disconnect();
    _rememberedId = null;
    _rememberedName = null;
    await _store.deleteFile('heart_rate.json');
    notifyListeners();
  }

  /// Reconnects to the remembered strap.
  ///
  /// [silent] keeps failures quiet, for the automatic attempt at launch.
  Future<void> reconnectRemembered({bool silent = false}) async {
    final id = _rememberedId;
    if (id == null || isConnected) return;

    // On iOS a strap paired earlier is often already connected to the system,
    // in which case it can be used without scanning at all.
    try {
      final known = await _central.retrieveConnectedPeripherals();
      for (final peripheral in known) {
        if (peripheral.uuid.toString() == id) {
          _peripherals[id] = peripheral;
          await connect(id);
          return;
        }
      }
    } catch (_) {
      // Not supported everywhere; fall through to a scan.
    }

    try {
      await startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      if (!silent) _fail(e);
    }
  }

  // ------------------------------------------------------------------ scan

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (Platform.isAndroid) {
      final authorized = await _central.authorize();
      if (!authorized) {
        throw StateError(
          'Bluetooth permission was denied. Allow it in Settings to use a '
          'heart-rate strap.',
        );
      }
    }
    if (_central.state == BluetoothLowEnergyState.poweredOff) {
      throw StateError('Bluetooth is switched off.');
    }
    if (_central.state == BluetoothLowEnergyState.unauthorized) {
      throw StateError(
        'Live Ride is not allowed to use Bluetooth. Enable it in Settings.',
      );
    }

    await stopScan();
    _devices.clear();
    _peripherals.removeWhere((key, _) => key != _connected?.uuid.toString());
    _lastError = null;
    _setStatus(HeartRateStatus.scanning);

    _discoverySub = _central.discovered.listen(_onDiscovered);
    // No service filter: WHOOP does not advertise 0x180D, it only exposes the
    // service once connected.
    await _central.startDiscovery();
    _scanTimeout = Timer(timeout, () => unawaited(stopScan()));
  }

  void _onDiscovered(DiscoveredEventArgs event) {
    final id = event.peripheral.uuid.toString();
    final advertised = event.advertisement.name?.trim() ?? '';
    final name = advertised.isNotEmpty ? advertised : 'Bluetooth device';
    final isWhoop = name.toLowerCase().contains('whoop');
    final advertisesHr = event.advertisement.serviceUUIDs.contains(
      UUID.short(_hrServiceUuid),
    );

    // Unnamed devices that advertise nothing useful are noise on a city
    // street; hiding them keeps the list readable.
    if (advertised.isEmpty && !advertisesHr) return;

    _peripherals[id] = event.peripheral;
    _devices[id] = HeartRateDevice(
      id: id,
      name: name,
      rssi: event.rssi,
      advertisesHeartRate: advertisesHr,
      isWhoop: isWhoop,
    );
    notifyListeners();

    // The remembered strap is reconnected the moment it shows up.
    if (id == _rememberedId && !isConnected && !isBusy) {
      unawaited(connect(id));
    }
  }

  Future<void> stopScan() async {
    _scanTimeout?.cancel();
    _scanTimeout = null;
    try {
      await _central.stopDiscovery();
    } catch (_) {}
    await _discoverySub?.cancel();
    _discoverySub = null;
    if (_status == HeartRateStatus.scanning) {
      _setStatus(isConnected ? HeartRateStatus.waiting : HeartRateStatus.idle);
    }
  }

  // --------------------------------------------------------------- connect

  Future<void> connect(String id) async {
    final peripheral = _peripherals[id];
    if (peripheral == null) {
      throw StateError('That sensor is no longer in range. Scan again.');
    }

    await stopScan();
    if (_connected != null) await disconnect();

    _intentionalDisconnect = false;
    _lastError = null;
    _setStatus(HeartRateStatus.connecting);

    try {
      await _central.connect(peripheral);
      final services = await _central.discoverGATT(peripheral);

      GATTCharacteristic? measurement;
      GATTCharacteristic? battery;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == UUID.short(_hrMeasurementUuid)) {
            measurement = characteristic;
          }
          if (service.uuid == UUID.short(_batteryServiceUuid) &&
              characteristic.uuid == UUID.short(_batteryLevelUuid)) {
            battery = characteristic;
          }
        }
      }

      if (measurement == null) {
        throw StateError(
          'This device does not expose a heart-rate service. On WHOOP, open '
          'the WHOOP app and turn on Broadcast Heart Rate first.',
        );
      }

      _connected = peripheral;
      _measurement = measurement;
      _battery = battery;
      _connectedName = _devices[id]?.name ?? _rememberedName ?? 'Heart rate';
      _retryAttempt = 0;
      _history.clear();

      _notifySub = _central.characteristicNotified.listen(_onNotified);
      _stateSub = _central.connectionStateChanged.listen(_onConnectionChanged);
      await _central.setCharacteristicNotifyState(
        peripheral,
        measurement,
        state: true,
      );

      _setStatus(HeartRateStatus.waiting);
      await _remember(id, _connectedName!);
      unawaited(_refreshVitals());
      _vitalsTimer?.cancel();
      _vitalsTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_refreshVitals()),
      );
    } catch (e) {
      await _teardown(disconnectPeripheral: true);
      _fail(e);
      rethrow;
    }
  }

  void _onNotified(GATTCharacteristicNotifiedEventArgs event) {
    if (event.peripheral != _connected) return;
    if (event.characteristic.uuid != UUID.short(_hrMeasurementUuid)) return;

    final parsed = parseHeartRateMeasurement(event.value);
    if (parsed == null) return;

    _latestBpm = parsed.bpm;
    _sensorContact = parsed.sensorContact;
    _lastSampleAt = DateTime.now();
    _history.add(parsed.bpm);
    if (_history.length > historyLength) {
      _history.removeRange(0, _history.length - historyLength);
    }
    _bpmController.add(parsed.bpm);
    _setStatus(HeartRateStatus.streaming);
  }

  void _onConnectionChanged(PeripheralConnectionStateChangedEventArgs event) {
    if (event.peripheral != _connected) return;
    if (event.state == ConnectionState.connected) return;
    if (_intentionalDisconnect) return;

    // Straps drop out on every dead spot. Get it back rather than making the
    // rider notice and fix it mid-ride.
    unawaited(_teardown(disconnectPeripheral: false));
    _setStatus(HeartRateStatus.reconnecting);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    final id = _rememberedId;
    if (id == null) return;
    _retryTimer?.cancel();
    final delay =
        _retryBackoff[_retryAttempt.clamp(0, _retryBackoff.length - 1)];
    _retryAttempt++;
    _retryTimer = Timer(delay, () async {
      if (isConnected) return;
      try {
        await reconnectRemembered(silent: true);
      } catch (_) {
        if (_status == HeartRateStatus.reconnecting) _scheduleRetry();
      }
    });
  }

  Future<void> _refreshVitals() async {
    final peripheral = _connected;
    if (peripheral == null) return;
    final battery = _battery;
    if (battery != null) {
      try {
        final value = await _central.readCharacteristic(peripheral, battery);
        if (value.isNotEmpty && value.first <= 100) {
          _batteryPercent = value.first;
        }
      } catch (_) {}
    }
    try {
      _rssi = await _central.readRSSI(peripheral);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _retryTimer?.cancel();
    await _teardown(disconnectPeripheral: true);
    _setStatus(HeartRateStatus.idle);
  }

  Future<void> _teardown({required bool disconnectPeripheral}) async {
    final peripheral = _connected;
    final characteristic = _measurement;
    _connected = null;
    _measurement = null;
    _battery = null;
    _latestBpm = null;
    _batteryPercent = null;
    _sensorContact = null;
    _lastSampleAt = null;
    _vitalsTimer?.cancel();
    _vitalsTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    if (peripheral == null) return;

    if (disconnectPeripheral) {
      if (characteristic != null) {
        try {
          await _central.setCharacteristicNotifyState(
            peripheral,
            characteristic,
            state: false,
          );
        } catch (_) {}
      }
      try {
        await _central.disconnect(peripheral);
      } catch (_) {}
    }
  }

  void _setStatus(HeartRateStatus status) {
    if (_status == status) {
      notifyListeners();
      return;
    }
    _status = status;
    notifyListeners();
  }

  void _fail(Object error) {
    _lastError = error is StateError ? error.message : error.toString();
    _setStatus(HeartRateStatus.idle);
  }

  @override
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _scanTimeout?.cancel();
    _vitalsTimer?.cancel();
    await stopScan();
    await disconnect();
    await _bpmController.close();
    super.dispose();
  }
}

/// A decoded Heart Rate Measurement characteristic.
class HeartRateMeasurement {
  const HeartRateMeasurement({required this.bpm, this.sensorContact});

  final int bpm;

  /// Null when the sensor does not report contact detection.
  final bool? sensorContact;
}

/// Decodes the Bluetooth SIG Heart Rate Measurement characteristic (0x2A37).
///
/// Bit 0 of the flags byte selects an 8- or 16-bit value; bits 1-2 carry
/// optional sensor-contact status. Exposed for testing because a misread here
/// shows the rider a wrong heart rate, which is worse than showing none.
HeartRateMeasurement? parseHeartRateMeasurement(List<int> value) {
  if (value.length < 2) return null;
  final flags = value[0];
  final wide = (flags & 0x01) != 0;

  final int bpm;
  if (wide) {
    if (value.length < 3) return null;
    bpm = value[1] | (value[2] << 8);
  } else {
    bpm = value[1];
  }
  if (bpm <= 0 || bpm > 260) return null;

  bool? contact;
  final contactSupported = (flags & 0x04) != 0;
  if (contactSupported) contact = (flags & 0x02) != 0;

  return HeartRateMeasurement(bpm: bpm, sensorContact: contact);
}
