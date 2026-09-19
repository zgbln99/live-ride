import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../data/ride_dao.dart';
import '../data/settings_dao.dart';
import '../models/ride_record.dart';

/// Stan połączenia z Apple Health / Health Connect.
enum HealthStatus {
  /// Jeszcze nie sprawdzono.
  unknown,

  /// Platforma nie ma tego API (desktop, web).
  unsupported,

  /// Health Connect nie jest zainstalowany na tym Androidzie.
  notInstalled,

  /// Jest, ale zawodnik nie dał zgody.
  denied,

  /// Gotowe do zapisu.
  ready,
}

/// Zapis przejazdów do Apple Health i Health Connect.
///
/// Zapis jest jednostronny i wyłącznie na żądanie: Live Ride nie czyta
/// niczego z Health i nic nie wysyła sam z siebie. To dane zdrowotne —
/// domyślne włączenie synchronizacji byłoby nadużyciem zaufania.
class HealthService extends ChangeNotifier {
  HealthService({Health? health, SettingsDao? settings, RideDao? rides})
    : _health = health ?? Health(),
      _settings = settings,
      _rides = rides;

  static const String settingsKey = 'health_export';

  /// Typy, o które prosimy. Tylko zapis — nigdy odczyt.
  static const List<HealthDataType> writeTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  final Health _health;
  final SettingsDao? _settings;
  final RideDao? _rides;

  HealthStatus _status = HealthStatus.unknown;
  bool _autoExport = false;
  String? _lastError;
  bool _configured = false;

  HealthStatus get status => _status;
  bool get autoExport => _autoExport;
  String? get lastError => _lastError;
  bool get isReady => _status == HealthStatus.ready;

  Future<void> restore() async {
    final stored = await _settings?.readJson(settingsKey);
    _autoExport = stored?['auto'] as bool? ?? false;
    notifyListeners();
    await refreshStatus();
  }

  Future<void> setAutoExport(bool value) async {
    _autoExport = value;
    notifyListeners();
    await _settings?.writeJson(settingsKey, {'auto': value});
    if (value) await requestPermission();
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthStatus> refreshStatus() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return _set(HealthStatus.unsupported);
    }
    try {
      await _configure();
      if (Platform.isAndroid) {
        final sdkStatus = await _health.getHealthConnectSdkStatus();
        if (sdkStatus != HealthConnectSdkStatus.sdkAvailable) {
          return _set(HealthStatus.notInstalled);
        }
      }
      final granted = await _health.hasPermissions(
        writeTypes,
        permissions: List.filled(writeTypes.length, HealthDataAccess.WRITE),
      );
      return _set(granted == true ? HealthStatus.ready : HealthStatus.denied);
    } on PlatformException catch (e) {
      _lastError = e.message;
      return _set(HealthStatus.unsupported);
    } on MissingPluginException {
      return _set(HealthStatus.unsupported);
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      _set(HealthStatus.unsupported);
      return false;
    }
    try {
      await _configure();
      final granted = await _health.requestAuthorization(
        writeTypes,
        permissions: List.filled(writeTypes.length, HealthDataAccess.WRITE),
      );
      _set(granted ? HealthStatus.ready : HealthStatus.denied);
      return granted;
    } on PlatformException catch (e) {
      _lastError = e.message;
      _set(HealthStatus.denied);
      return false;
    } on MissingPluginException {
      _set(HealthStatus.unsupported);
      return false;
    }
  }

  /// Zapisuje przejazd jako trening.
  ///
  /// Zwraca false, gdy zgoda nie została wydana albo platforma odmówiła —
  /// przejazd zostaje wtedy nieoznaczony i da się spróbować ponownie.
  Future<bool> exportRide(RecordedRide ride) async {
    if (ride.distanceMeters <= 0) return false;
    if (_status != HealthStatus.ready) {
      final granted = await requestPermission();
      if (!granted) return false;
    }
    try {
      final written = await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.BIKING,
        start: ride.startedAt,
        end: ride.endedAt,
        totalDistance: ride.distanceMeters.round(),
        totalEnergyBurned: ride.calories,
        title: ride.name,
      );
      if (written) {
        await _rides?.markHealthExported(ride.id);
        _lastError = null;
      }
      notifyListeners();
      return written;
    } on PlatformException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    } on MissingPluginException {
      _set(HealthStatus.unsupported);
      return false;
    }
  }

  /// Wołane po zapisaniu przejazdu. Nic nie robi, dopóki zawodnik sam nie
  /// włączy automatycznego zapisu.
  Future<void> exportIfEnabled(RecordedRide ride) async {
    if (!_autoExport) return;
    await exportRide(ride);
  }

  HealthStatus _set(HealthStatus status) {
    if (_status != status) {
      _status = status;
      notifyListeners();
    }
    return status;
  }
}
