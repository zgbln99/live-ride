import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../core/geo.dart';
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

  /// Część zgód jest, części nie.
  partial,

  /// Wszystko, o co prosiliśmy, działa.
  ready,
}

/// Co wiemy o odczycie danego rodzaju danych.
///
/// iOS Z ZAŁOŻENIA nie mówi, czy wolno czytać: `hasPermissions` dla odczytu
/// zwraca `null` albo „tak" niezależnie od decyzji użytkownika, bo sama
/// odpowiedź zdradzałaby, że ktoś ma w Health dane, których nie chce pokazać.
/// Dlatego nie udajemy, że znamy odpowiedź — sprawdzamy ją PRÓBĄ ODCZYTU
/// i mówimy wprost, co z niej wyszło.
enum HealthReadState {
  /// Nie prosiliśmy o nic.
  notRequested,

  /// Poprosiliśmy, ale nie wiemy, czy zgoda jest — nie było czego odczytać.
  requested,

  /// Odczyt naprawdę zwrócił dane. Jedyny stan, który możemy nazwać „działa".
  working,

  /// Platforma odmówiła wprost.
  denied,
}

/// Jeden rodzaj danych i jego stan.
class HealthScope {
  const HealthScope({
    required this.label,
    required this.state,
    this.detail = '',
  });

  final String label;
  final HealthReadState state;
  final String detail;

  bool get works => state == HealthReadState.working;
}

/// Propozycja zaczerpnięta z Health, której NIE stosujemy sami.
class HealthSuggestion {
  const HealthSuggestion({required this.kilograms, required this.measuredAt});

  final double kilograms;
  final DateTime measuredAt;
}

/// Apple Health i Health Connect: odczyt i zapis, osobno.
///
/// Dotąd ta klasa umiała wyłącznie eksportować zakończony przejazd, a plik
/// `Info.plist` deklarował wprost, że aplikacja niczego nie czyta. To nie
/// było ograniczenie biblioteki — to była decyzja, którą ten kod cofa.
///
/// Dwie zasady, których nie wolno tu złamać:
///
///  1. O KAŻDĄ daną prosimy osobno i tylko wtedy, gdy naprawdę jej używamy.
///     Okno zgody wymieniające dwadzieścia rodzajów danych zdrowotnych jest
///     powodem, dla którego ludzie klikają „nie pozwalaj" na wszystko.
///  2. Dane zdrowotne przetwarzamy na telefonie. Nic z Health nie jedzie na
///     serwer i nie trafia do publicznego LIVE.
class HealthService extends ChangeNotifier {
  HealthService({
    Health? health,
    SettingsDao? settings,
    RideDao? rides,
    bool Function()? platformSupported,
  }) : _health = health ?? Health(),
       _settings = settings,
       _rides = rides,
       _supported = platformSupported ?? _defaultSupported;

  /// Czy ta platforma ma w ogóle API zdrowia.
  ///
  /// Wstrzykiwane, bo testy chodzą na Linuksie, gdzie `Platform.isIOS` jest
  /// fałszem — bez tego szwu każdy test kończyłby się na „nieobsługiwane"
  /// i nie sprawdzałby niczego, o co w nim chodzi.
  static bool _defaultSupported() => Platform.isIOS || Platform.isAndroid;

  static const String settingsKey = 'health_export';

  /// Zapis: dokładnie to, co powstaje z przejazdu.
  static const List<HealthDataType> writeTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  /// Odczyt podstawowy: to, czego licznik i Ride Intelligence naprawdę
  /// używają. Nic „na zapas".
  static const List<HealthDataType> readTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.WEIGHT,
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_CYCLING,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  /// Odczyt dodatkowy, wyłącznie po świadomym włączeniu.
  ///
  /// HRV i VO2max to dane, o które nie wolno prosić przy pierwszym
  /// uruchomieniu: nie są potrzebne do jazdy, a ich obecność w oknie zgody
  /// wygląda jak zbieranie wszystkiego, co się da.
  static const List<HealthDataType> optionalReadTypes = [
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  final Health _health;
  final SettingsDao? _settings;
  final RideDao? _rides;
  final bool Function() _supported;

  HealthStatus _status = HealthStatus.unknown;
  bool _autoExport = false;
  bool _readEnabled = false;
  bool _advancedEnabled = false;
  String? _lastError;
  bool _configured = false;
  bool _writeGranted = false;
  final Map<HealthDataType, HealthReadState> _readStates = {};

  HealthStatus get status => _status;
  bool get autoExport => _autoExport;

  /// Czy zawodnik pozwolił nam w ogóle CZYTAĆ z Health.
  bool get readEnabled => _readEnabled;

  /// Czy włączył dane dodatkowe (HRV).
  bool get advancedEnabled => _advancedEnabled;

  String? get lastError => _lastError;
  bool get isReady => _status == HealthStatus.ready || _status == HealthStatus.partial;
  bool get canWrite => _writeGranted;

  /// Stan odczytu danego rodzaju danych — do pokazania na ekranie integracji.
  HealthReadState readState(HealthDataType type) =>
      _readStates[type] ?? HealthReadState.notRequested;

  Future<void> restore() async {
    final stored = await _settings?.readJson(settingsKey);
    _autoExport = stored?['auto'] as bool? ?? false;
    _readEnabled = stored?['read'] as bool? ?? false;
    _advancedEnabled = stored?['advanced'] as bool? ?? false;
    notifyListeners();
    await refreshStatus();
  }

  Future<void> setAutoExport(bool value) async {
    _autoExport = value;
    await _persist();
    if (value) await requestPermission();
  }

  /// Włącza albo wyłącza odczyt z Health.
  ///
  /// Wyłączenie nie odbiera zgody w systemie — tego aplikacja nie potrafi.
  /// Przestaje natomiast pytać o cokolwiek, i to jest różnica, którą widać.
  Future<void> setReadEnabled(bool value) async {
    _readEnabled = value;
    if (!value) {
      _advancedEnabled = false;
      _readStates.clear();
    }
    await _persist();
    if (value) await requestPermission();
    await refreshStatus();
  }

  Future<void> setAdvancedEnabled(bool value) async {
    _advancedEnabled = value;
    await _persist();
    if (value) await requestPermission();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _settings?.writeJson(settingsKey, {
      'auto': _autoExport,
      'read': _readEnabled,
      'advanced': _advancedEnabled,
    });
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Typy, o które prosimy przy obecnych ustawieniach, razem z rodzajem
  /// dostępu. Kolejność obu list musi się zgadzać — biblioteka paruje je
  /// po indeksie.
  (List<HealthDataType>, List<HealthDataAccess>) _requested() {
    final types = <HealthDataType>[...writeTypes];
    final access = <HealthDataAccess>[
      for (final _ in writeTypes) HealthDataAccess.WRITE,
    ];
    if (_readEnabled) {
      for (final type in readTypes) {
        final index = types.indexOf(type);
        if (index >= 0) {
          // Ten sam typ i do zapisu, i do odczytu — prosimy raz, o oba.
          access[index] = HealthDataAccess.READ_WRITE;
          continue;
        }
        types.add(type);
        access.add(HealthDataAccess.READ);
      }
      if (_advancedEnabled) {
        for (final type in optionalReadTypes) {
          types.add(type);
          access.add(HealthDataAccess.READ);
        }
      }
    }
    return (types, access);
  }

  Future<HealthStatus> refreshStatus() async {
    if (!_supported()) {
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
      // Zapis to jedyna rzecz, o której iOS mówi prawdę.
      _writeGranted =
          await _health.hasPermissions(
            writeTypes,
            permissions: List.filled(writeTypes.length, HealthDataAccess.WRITE),
          ) ==
          true;

      if (_readEnabled) await _probeReads();

      if (!_writeGranted && !_anyReadWorks) return _set(HealthStatus.denied);
      if (_writeGranted && (!_readEnabled || _allReadsWork)) {
        return _set(HealthStatus.ready);
      }
      return _set(HealthStatus.partial);
    } on PlatformException catch (e) {
      _lastError = e.message;
      return _set(HealthStatus.unsupported);
    } on MissingPluginException {
      return _set(HealthStatus.unsupported);
    }
  }

  bool get _anyReadWorks =>
      _readStates.values.any((state) => state == HealthReadState.working);

  bool get _allReadsWork =>
      readTypes.every((type) => _readStates[type] == HealthReadState.working);

  /// Sprawdza odczyt PRÓBUJĄC czytać.
  ///
  /// To jedyny wiarygodny test na iOS. „Zwróciło pustkę" nie znaczy
  /// „odmówiono" — może po prostu nie być danych — więc taki wynik zostaje
  /// „poproszono", a nie „działa" i nie „odmówiono".
  Future<void> _probeReads() async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 180));
    for (final type in [
      ...readTypes,
      if (_advancedEnabled) ...optionalReadTypes,
    ]) {
      try {
        final points = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: from,
          endTime: now,
        );
        _readStates[type] = points.isEmpty
            ? HealthReadState.requested
            : HealthReadState.working;
      } on PlatformException {
        _readStates[type] = HealthReadState.denied;
      } on MissingPluginException {
        _readStates[type] = HealthReadState.denied;
      }
    }
  }

  Future<bool> requestPermission() async {
    if (!_supported()) {
      _set(HealthStatus.unsupported);
      return false;
    }
    try {
      await _configure();
      final (types, access) = _requested();
      final granted = await _health.requestAuthorization(
        types,
        permissions: access,
      );
      if (_readEnabled) {
        for (final type in types) {
          _readStates.putIfAbsent(type, () => HealthReadState.requested);
        }
      }
      await refreshStatus();
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

  /// Zapisuje przejazd jako trening rowerowy razem z trasą GPS.
  ///
  /// Zwraca false, gdy zgoda nie została wydana albo platforma odmówiła —
  /// przejazd zostaje wtedy nieoznaczony i da się spróbować ponownie.
  Future<bool> exportRide(RecordedRide ride, {List<GeoPoint>? track}) async {
    if (ride.distanceMeters <= 0) return false;
    // Podwójny wpis w Health jest nie do odróżnienia od dwóch przejazdów
    // i nie da się go cofnąć z aplikacji.
    if (ride.healthExported) return true;
    if (!_writeGranted) {
      final granted = await requestPermission();
      if (!granted && !_writeGranted) return false;
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
      if (!written) {
        _lastError = null;
        notifyListeners();
        return false;
      }
      await _attachRoute(ride, track);
      await _rides?.markHealthExported(ride.id);
      _lastError = null;
      notifyListeners();
      return true;
    } on PlatformException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    } on MissingPluginException {
      _set(HealthStatus.unsupported);
      return false;
    }
  }

  /// Dokłada do właśnie zapisanego treningu prawdziwą trasę GPS.
  ///
  /// `writeWorkoutData` nie oddaje identyfikatora treningu, a
  /// `finishWorkoutRoute` go wymaga — więc odczytujemy świeżo zapisany
  /// trening z powrotem. Gdy odczytu nie ma (bo zawodnik go nie włączył),
  /// trening zostaje bez trasy. To jest w porządku: trening bez trasy jest
  /// poprawnym treningiem, a proszenie o zgodę na odczyt po to, żeby
  /// domknąć zapis, byłoby wymuszeniem.
  Future<void> _attachRoute(RecordedRide ride, List<GeoPoint>? track) async {
    if (track == null || track.length < 2) return;
    if (!_supported()) return;
    if (!_readEnabled) return;

    String? builderId;
    try {
      final workouts = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: ride.startedAt.subtract(const Duration(minutes: 1)),
        endTime: ride.endedAt.add(const Duration(minutes: 1)),
      );
      final uuid = workouts.isEmpty ? '' : workouts.last.uuid;
      if (uuid.isEmpty) return;

      builderId = await _health.startWorkoutRoute();
      final span = ride.endedAt.difference(ride.startedAt);
      final locations = <WorkoutRouteLocation>[
        for (var i = 0; i < track.length; i++)
          WorkoutRouteLocation(
            latitude: track[i].lat,
            longitude: track[i].lon,
            // Ślad zapisany w telefonie nie niesie znacznika czasu przy
            // każdym punkcie, więc rozkładamy je równomiernie na czas
            // przejazdu. HealthKit wymaga rosnących znaczników i tyle
            // z nich korzysta.
            timestamp: ride.startedAt.add(span * (i / (track.length - 1))),
          ),
      ];
      await _health.insertWorkoutRouteData(
        builderId: builderId,
        locations: locations,
      );
      await _health.finishWorkoutRoute(
        builderId: builderId,
        workoutUuid: uuid,
      );
    } on PlatformException catch (e) {
      // Trening już jest zapisany. Brak trasy to strata szczegółu,
      // a nie powód, żeby cofać cały eksport.
      _lastError = e.message;
      if (builderId != null) {
        try {
          await _health.discardWorkoutRoute(builderId);
        } on PlatformException {
          // Nic więcej nie da się tu zrobić.
        }
      }
    } on MissingPluginException {
      // Starsza wersja wtyczki bez tras.
    }
  }

  /// Wołane po zapisaniu przejazdu. Nic nie robi, dopóki zawodnik sam nie
  /// włączy automatycznego zapisu.
  Future<void> exportIfEnabled(RecordedRide ride, {List<GeoPoint>? track}) async {
    if (!_autoExport) return;
    await exportRide(ride, track: track);
  }

  /// Ostatnia masa ciała z Health — jako PROPOZYCJA, nigdy jako zapis.
  ///
  /// Waga wchodzi do W/kg i do szacunku kalorii, więc różnica między 78 a 98
  /// kilogramami zmienia wszystkie te liczby. Właśnie dlatego nie wolno
  /// podmienić jej po cichu: zawodnik ma zobaczyć, skąd wzięła się nowa
  /// liczba, i sam ją przyjąć.
  Future<HealthSuggestion?> latestBodyMass() async {
    if (!_readEnabled) return null;
    if (!_supported()) return null;
    try {
      await _configure();
      final now = DateTime.now();
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: now.subtract(const Duration(days: 365)),
        endTime: now,
      );
      if (points.isEmpty) return null;
      points.sort((a, b) => a.dateTo.compareTo(b.dateTo));
      final latest = points.last;
      final value = latest.value;
      if (value is! NumericHealthValue) return null;
      final kilograms = value.numericValue.toDouble();
      if (kilograms < 30 || kilograms > 250) return null;
      return HealthSuggestion(kilograms: kilograms, measuredAt: latest.dateTo);
    } on PlatformException catch (e) {
      _lastError = e.message;
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Tętno spoczynkowe z Health — do stref i do Ride Intelligence.
  ///
  /// Wyłącznie dana HISTORYCZNA. Nigdy nie udaje pomiaru na żywo.
  Future<int?> restingHeartRate() async {
    if (!_readEnabled) return null;
    if (!_supported()) return null;
    try {
      await _configure();
      final now = DateTime.now();
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.RESTING_HEART_RATE],
        startTime: now.subtract(const Duration(days: 30)),
        endTime: now,
      );
      if (points.isEmpty) return null;
      points.sort((a, b) => a.dateTo.compareTo(b.dateTo));
      final value = points.last.value;
      if (value is! NumericHealthValue) return null;
      final bpm = value.numericValue.round();
      return bpm >= 25 && bpm <= 120 ? bpm : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  HealthStatus _set(HealthStatus status) {
    if (_status != status) {
      _status = status;
      notifyListeners();
    }
    return status;
  }
}
