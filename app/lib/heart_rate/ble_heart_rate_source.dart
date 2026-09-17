import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:wanderer/heart_rate/ble_heart_rate_parser.dart';
import 'package:wanderer/heart_rate/heart_rate_source.dart';

const _heartRateServiceUuid = 0x180d;
const _heartRateMeasurementUuid = 0x2a37;

class BleHeartRateDevice {
  const BleHeartRateDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

/// Generic Bluetooth SIG Heart Rate Service listener.
///
/// WHOOP can broadcast continuous heart rate over BLE and presents itself as a
/// standard heart-rate monitor, so no private WHOOP protocol is needed here.
/// The same implementation also works with Polar/Garmin/chest-strap sensors
/// that expose service 0x180D + measurement characteristic 0x2A37.
class BleHeartRateSource implements HeartRateSource {
  BleHeartRateSource({CentralManager? central})
    : _central = central ?? CentralManager();

  final CentralManager _central;
  final _bpmController = StreamController<int>.broadcast();
  final _devicesController =
      StreamController<List<BleHeartRateDevice>>.broadcast();
  final Map<String, Peripheral> _peripherals = {};
  final Map<String, BleHeartRateDevice> _devices = {};

  StreamSubscription<DiscoveredEventArgs>? _discoverySub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifySub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _connectionSub;
  Peripheral? _connectedPeripheral;
  GATTCharacteristic? _measurementCharacteristic;
  int? _latestBpm;
  bool _disposed = false;

  @override
  int? get latestBpm => _latestBpm;

  @override
  Stream<int> get bpm => _bpmController.stream;

  Stream<List<BleHeartRateDevice>> get devices => _devicesController.stream;

  String? get connectedDeviceId => _connectedPeripheral?.uuid.toString();

  Future<void> startScan() async {
    _ensureAlive();
    final authorized = await _central.authorize();
    if (!authorized) {
      throw StateError('Bluetooth permission was not granted');
    }

    _devices.clear();
    _peripherals.clear();
    _connectionSub ??= _central.connectionStateChanged.listen((event) {
      if (event.peripheral == _connectedPeripheral &&
          event.state == ConnectionState.disconnected) {
        _connectedPeripheral = null;
        _measurementCharacteristic = null;
        _latestBpm = null;
      }
    });
    await _discoverySub?.cancel();
    _discoverySub = _central.discovered.listen((event) {
      final id = event.peripheral.uuid.toString();
      _peripherals[id] = event.peripheral;
      _devices[id] = BleHeartRateDevice(
        id: id,
        name: event.advertisement.name?.trim().isNotEmpty == true
            ? event.advertisement.name!.trim()
            : 'Heart rate sensor',
        rssi: event.rssi,
      );
      final sorted = _devices.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      _devicesController.add(List.unmodifiable(sorted));
    });

    await _central.startDiscovery(
      serviceUUIDs: [UUID.short(_heartRateServiceUuid)],
    );
  }

  Future<void> stopScan() async {
    try {
      await _central.stopDiscovery();
    } catch (_) {
      // Safe when discovery was not running/already stopped by the platform.
    }
    await _discoverySub?.cancel();
    _discoverySub = null;
  }

  Future<void> connect(String deviceId) async {
    _ensureAlive();
    final peripheral = _peripherals[deviceId];
    if (peripheral == null) {
      throw StateError('Heart-rate sensor is no longer in the scan results');
    }

    await stopScan();
    await disconnect();
    await _central.connect(peripheral);

    final services = await _central.discoverGATT(peripheral);
    GATTCharacteristic? measurement;
    for (final service in services) {
      if (service.uuid != UUID.short(_heartRateServiceUuid)) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == UUID.short(_heartRateMeasurementUuid)) {
          measurement = characteristic;
          break;
        }
      }
    }
    if (measurement == null) {
      await _central.disconnect(peripheral);
      throw StateError('Device does not expose Heart Rate Measurement (0x2A37)');
    }

    _connectedPeripheral = peripheral;
    _measurementCharacteristic = measurement;
    await _notifySub?.cancel();
    _notifySub = _central.characteristicNotified.listen((event) {
      if (event.peripheral != _connectedPeripheral ||
          event.characteristic.uuid != UUID.short(_heartRateMeasurementUuid)) {
        return;
      }
      try {
        final parsed = parseBleHeartRateMeasurement(event.value);
        // Reject obviously corrupt notifications but don't enforce an athlete-
        // specific max HR. The server has its own broad safety bound as well.
        if (parsed <= 0 || parsed > 260) return;
        _latestBpm = parsed;
        _bpmController.add(parsed);
      } on FormatException {
        // Ignore malformed radio packets; the next notification will replace it.
      }
    });

    await _central.setCharacteristicNotifyState(
      peripheral,
      measurement,
      state: true,
    );
  }

  Future<void> disconnect() async {
    final peripheral = _connectedPeripheral;
    final characteristic = _measurementCharacteristic;
    _measurementCharacteristic = null;
    _connectedPeripheral = null;
    _latestBpm = null;

    if (peripheral == null) return;
    if (characteristic != null) {
      try {
        await _central.setCharacteristicNotifyState(
          peripheral,
          characteristic,
          state: false,
        );
      } catch (_) {
        // The peripheral may already be out of range/disconnected.
      }
    }
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await _central.disconnect(peripheral);
    } catch (_) {
      // Already disconnected is equivalent to the requested state.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopScan();
    await disconnect();
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _bpmController.close();
    await _devicesController.close();
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('BleHeartRateSource is disposed');
  }
}
