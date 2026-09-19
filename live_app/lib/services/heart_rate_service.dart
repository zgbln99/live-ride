import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

const _hrServiceUuid = 0x180d;
const _hrMeasurementUuid = 0x2a37;

class HeartRateDevice {
  const HeartRateDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.likelyHeartRate,
  });

  final String id;
  final String name;
  final int rssi;
  final bool likelyHeartRate;
}

class HeartRateService {
  final CentralManager _central = CentralManager();
  final _devices = <String, HeartRateDevice>{};
  final _peripherals = <String, Peripheral>{};
  final _devicesController = StreamController<List<HeartRateDevice>>.broadcast();
  final _bpmController = StreamController<int>.broadcast();

  StreamSubscription<DiscoveredEventArgs>? _discoverySub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifySub;
  Peripheral? _connected;
  GATTCharacteristic? _measurement;
  int? _latestBpm;

  Stream<List<HeartRateDevice>> get devices => _devicesController.stream;
  Stream<int> get bpm => _bpmController.stream;
  int? get latestBpm => _latestBpm;
  String? get connectedId => _connected?.uuid.toString();

  Future<void> startScan() async {
    if (Platform.isAndroid) {
      final ok = await _central.authorize();
      if (!ok) throw StateError('Brak uprawnienia Bluetooth.');
    }

    await stopScan();
    _devices.clear();
    _peripherals.clear();
    _devicesController.add(const []);

    _discoverySub = _central.discovered.listen((event) {
      final id = event.peripheral.uuid.toString();
      final advertised = event.advertisement.name?.trim();
      final name = advertised?.isNotEmpty == true ? advertised! : 'Urządzenie Bluetooth';
      final advertisesHr = event.advertisement.serviceUUIDs.contains(
        UUID.short(_hrServiceUuid),
      );
      final whoop = name.toLowerCase().contains('whoop');
      _peripherals[id] = event.peripheral;
      _devices[id] = HeartRateDevice(
        id: id,
        name: name,
        rssi: event.rssi,
        likelyHeartRate: advertisesHr || whoop,
      );
      final sorted = _devices.values.toList()
        ..sort((a, b) {
          if (a.likelyHeartRate != b.likelyHeartRate) {
            return a.likelyHeartRate ? -1 : 1;
          }
          return b.rssi.compareTo(a.rssi);
        });
      _devicesController.add(List.unmodifiable(sorted));
    });

    // No service filter: WHOOP can expose 0x180D only after connecting.
    await _central.startDiscovery();
  }

  Future<void> stopScan() async {
    try {
      await _central.stopDiscovery();
    } catch (_) {}
    await _discoverySub?.cancel();
    _discoverySub = null;
  }

  Future<void> connect(String id) async {
    final peripheral = _peripherals[id];
    if (peripheral == null) throw StateError('Urządzenie zniknęło. Skanuj ponownie.');

    await stopScan();
    await disconnect();
    await _central.connect(peripheral);

    try {
      final services = await _central.discoverGATT(peripheral);
      GATTCharacteristic? measurement;
      for (final service in services) {
        if (service.uuid != UUID.short(_hrServiceUuid)) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == UUID.short(_hrMeasurementUuid)) {
            measurement = characteristic;
            break;
          }
        }
      }
      if (measurement == null) {
        throw StateError('Brak Heart Rate Service. W WHOOP włącz HR Broadcast.');
      }

      _connected = peripheral;
      _measurement = measurement;
      _notifySub = _central.characteristicNotified.listen((event) {
        if (event.peripheral != _connected ||
            event.characteristic.uuid != UUID.short(_hrMeasurementUuid)) {
          return;
        }
        try {
          final value = event.value;
          if (value.length < 2) return;
          final flags = value[0];
          final is16 = (flags & 0x01) != 0;
          final bpm = is16
              ? (value.length >= 3 ? value[1] | (value[2] << 8) : 0)
              : value[1];
          if (bpm <= 0 || bpm > 260) return;
          _latestBpm = bpm;
          _bpmController.add(bpm);
        } catch (_) {}
      });
      await _central.setCharacteristicNotifyState(
        peripheral,
        measurement,
        state: true,
      );
    } catch (_) {
      try {
        await _central.disconnect(peripheral);
      } catch (_) {}
      _connected = null;
      _measurement = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final peripheral = _connected;
    final characteristic = _measurement;
    _connected = null;
    _measurement = null;
    _latestBpm = null;
    await _notifySub?.cancel();
    _notifySub = null;
    if (peripheral == null) return;
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

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    await _devicesController.close();
    await _bpmController.close();
  }
}
