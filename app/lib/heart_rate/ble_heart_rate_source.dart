import 'dart:async';
import 'dart:io';

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
    required this.isLikelyHeartRateSensor,
  });

  final String id;
  final String name;
  final int rssi;

  /// True when the advertisement already proves this is a heart-rate sensor,
  /// or its name strongly identifies a WHOOP device. Devices without this
  /// flag are still shown as a fallback because some peripherals expose the
  /// Heart Rate Service only after connecting and omit 0x180D from advertising.
  final bool isLikelyHeartRateSensor;
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

    // bluetooth_low_energy's explicit authorize() is primarily the Android
    // runtime-permission path. On iOS CoreBluetooth presents its own system
    // authorization prompt when scanning. Treating authorize()==false as a
    // hard failure on iOS can prevent the scan before CoreBluetooth has a
    // chance to request access.
    if (Platform.isAndroid) {
      final authorized = await _central.authorize();
      if (!authorized) {
        throw StateError(
          'Bluetooth permission is disabled. Allow Nearby devices for Live Ride.',
        );
      }
    }

    _devices.clear();
    _peripherals.clear();
    _devicesController.add(const []);

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
      final advertisedName = event.advertisement.name?.trim();
      final name = advertisedName?.isNotEmpty == true
          ? advertisedName!
          : 'Bluetooth device';
      final advertisesHeartRate = event.advertisement.serviceUUIDs.contains(
        UUID.short(_heartRateServiceUuid),
      );
      final looksLikeWhoop = name.toLowerCase().contains('whoop');

      _peripherals[id] = event.peripheral;
      _devices[id] = BleHeartRateDevice(
        id: id,
        name: name,
        rssi: event.rssi,
        isLikelyHeartRateSensor: advertisesHeartRate || looksLikeWhoop,
      );
      _emitSortedDevices();
    });

    // Do NOT filter the scan by 0x180D here. WHOOP and some other sensors can
    // expose Heart Rate Service after connection without putting 0x180D in
    // every advertising packet. A CoreBluetooth service filter would make
    // those devices invisible. connect() remains strict and verifies the
    // actual GATT service + measurement characteristic before accepting one.
    await _central.startDiscovery();
  }

  void _emitSortedDevices() {
    final sorted = _devices.values.toList()
      ..sort((a, b) {
        if (a.isLikelyHeartRateSensor != b.isLikelyHeartRateSensor) {
          return a.isLikelyHeartRateSensor ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });
    _devicesController.add(List.unmodifiable(sorted));
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
      throw StateError('Sensor disappeared. Scan again and keep it close.');
    }

    await stopScan();
    await disconnect();

    try {
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
        throw StateError(
          'No live heart-rate service found. In WHOOP, enable HR Broadcast and scan again.',
        );
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
          if (parsed <= 0 || parsed > 260) return;
          _latestBpm = parsed;
          _bpmController.add(parsed);
        } on FormatException {
          // Ignore malformed radio packets; the next notification replaces it.
        }
      });

      await _central.setCharacteristicNotifyState(
        peripheral,
        measurement,
        state: true,
      );
    } catch (_) {
      _connectedPeripheral = null;
      _measurementCharacteristic = null;
      _latestBpm = null;
      try {
        await _central.disconnect(peripheral);
      } catch (_) {
        // Best-effort cleanup of a failed connection attempt.
      }
      rethrow;
    }
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
