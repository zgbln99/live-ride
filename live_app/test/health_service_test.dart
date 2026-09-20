import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/services/health_service.dart';

/// Apple Health i Health Connect widziane od strony aplikacji.
///
/// Testy chodzą po atrapie wtyczki, a nie po prawdziwym HealthKicie, bo
/// sprawdzają decyzje aplikacji, nie systemu: o co prosimy, czego NIE
/// nadpisujemy bez pytania i co się dzieje, gdy zgody nie ma.

class _FakeHealth extends Health {
  _FakeHealth({
    this.writeGranted = true,
    this.authorizationResult = true,
    this.points = const {},
    this.throwOnWrite = false,
  });

  bool writeGranted;
  bool authorizationResult;
  Map<HealthDataType, List<HealthDataPoint>> points;
  bool throwOnWrite;

  final List<HealthDataType> requestedTypes = [];
  final List<HealthDataAccess> requestedAccess = [];
  int workoutWrites = 0;
  int routeStarts = 0;
  int routeFinishes = 0;
  List<WorkoutRouteLocation> routeLocations = const [];

  @override
  Future<void> configure() async {}

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => writeGranted;

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requestedTypes
      ..clear()
      ..addAll(types);
    requestedAccess
      ..clear()
      ..addAll(permissions ?? const []);
    writeGranted = authorizationResult;
    return authorizationResult;
  }

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startTime,
    required DateTime endTime,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async => [for (final type in types) ...?points[type]];

  @override
  Future<bool> writeWorkoutData({
    required HealthWorkoutActivityType activityType,
    required DateTime start,
    required DateTime end,
    int? totalEnergyBurned,
    HealthDataUnit totalEnergyBurnedUnit = HealthDataUnit.KILOCALORIE,
    int? totalDistance,
    HealthDataUnit totalDistanceUnit = HealthDataUnit.METER,
    String? title,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    if (throwOnWrite) {
      throw PlatformException(code: 'HEALTH', message: 'Zapis odrzucony');
    }
    workoutWrites++;
    return true;
  }

  @override
  Future<String> startWorkoutRoute() async {
    routeStarts++;
    return 'builder-1';
  }

  @override
  Future<bool> insertWorkoutRouteData({
    required String builderId,
    required List<WorkoutRouteLocation> locations,
  }) async {
    routeLocations = locations;
    return true;
  }

  @override
  Future<String> finishWorkoutRoute({
    required String builderId,
    required String workoutUuid,
    Map<String, dynamic>? metadata,
  }) async {
    routeFinishes++;
    return 'route-1';
  }
}

HealthDataPoint _point(
  HealthDataType type,
  num value,
  DateTime at, {
  String uuid = '',
}) => HealthDataPoint(
  uuid: uuid,
  value: NumericHealthValue(numericValue: value),
  type: type,
  unit: HealthDataUnit.NO_UNIT,
  dateFrom: at,
  dateTo: at,
  sourcePlatform: HealthPlatformType.appleHealth,
  sourceDeviceId: 'test',
  sourceId: 'test',
  sourceName: 'test',
  recordingMethod: RecordingMethod.automatic,
);

RecordedRide _ride({bool exported = false}) => RecordedRide(
  id: 'ride-1',
  name: 'Poranna jazda',
  startedAt: DateTime.utc(2026, 5, 1, 8),
  endedAt: DateTime.utc(2026, 5, 1, 10),
  elapsedSeconds: 7200,
  movingSeconds: 6600,
  distanceMeters: 42300,
  elevationGainMeters: 480,
  calories: 1240,
  points: const [],
  healthExported: exported,
);

HealthService _service(_FakeHealth health) =>
    HealthService(health: health, platformSupported: () => true);

void main() {
  group('uprawnienia', () {
    test('bez zgody status mówi wprost, że jej nie ma', () async {
      final health = _FakeHealth(writeGranted: false, authorizationResult: false);
      final service = _service(health);

      await service.refreshStatus();

      expect(service.status, HealthStatus.denied);
      expect(service.canWrite, isFalse);
    });

    test('sam zapis wystarcza do stanu gotowego', () async {
      final service = _service(_FakeHealth());
      await service.refreshStatus();
      expect(service.status, HealthStatus.ready);
      expect(service.canWrite, isTrue);
    });

    test('prosimy tylko o to, czego naprawdę używamy', () async {
      final health = _FakeHealth();
      final service = _service(health);

      await service.requestPermission();

      // Domyślnie: sam zapis. Okno zgody wymieniające dwadzieścia rodzajów
      // danych zdrowotnych jest powodem, dla którego ludzie odmawiają
      // wszystkiego naraz.
      expect(health.requestedTypes, HealthService.writeTypes);
      expect(
        health.requestedAccess.every((a) => a == HealthDataAccess.WRITE),
        isTrue,
      );
      // I nigdy nic spoza listy — w szczególności nie HRV ani VO2max.
      expect(
        health.requestedTypes.contains(
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        ),
        isFalse,
      );
    });

    test('odczyt dokłada się do tej samej prośby, nie tworzy drugiej', () async {
      final health = _FakeHealth();
      final service = _service(health);

      await service.setReadEnabled(true);

      expect(health.requestedTypes.length, health.requestedAccess.length);
      // Trening jest i zapisywany, i czytany — prosimy o niego RAZ.
      final workoutIndexes = [
        for (var i = 0; i < health.requestedTypes.length; i++)
          if (health.requestedTypes[i] == HealthDataType.WORKOUT) i,
      ];
      expect(workoutIndexes.length, 1);
      expect(
        health.requestedAccess[workoutIndexes.single],
        HealthDataAccess.READ_WRITE,
      );
      expect(health.requestedTypes, contains(HealthDataType.WEIGHT));
      expect(
        health.requestedTypes.contains(
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        ),
        isFalse,
      );
    });

    test('dane dodatkowe wchodzą dopiero po świadomym włączeniu', () async {
      final health = _FakeHealth();
      final service = _service(health);

      await service.setReadEnabled(true);
      await service.setAdvancedEnabled(true);

      expect(
        health.requestedTypes,
        contains(HealthDataType.HEART_RATE_VARIABILITY_SDNN),
      );
    });

    test('pusty odczyt to nie jest zgoda — ani odmowa', () async {
      // iOS nie mówi aplikacjom, czy wolno im czytać. Sprawdzamy to próbą
      // odczytu i nazywamy wynik tym, czym jest.
      final health = _FakeHealth();
      final service = _service(health);

      await service.setReadEnabled(true);

      expect(
        service.readState(HealthDataType.HEART_RATE),
        HealthReadState.requested,
      );
      expect(service.status, HealthStatus.partial);
    });

    test('odczyt, który zwrócił dane, jest jedynym „działa"', () async {
      final now = DateTime.now();
      final health = _FakeHealth(
        points: {
          for (final type in HealthService.readTypes)
            type: [_point(type, 100, now)],
        },
      );
      final service = _service(health);

      await service.setReadEnabled(true);

      expect(
        service.readState(HealthDataType.HEART_RATE),
        HealthReadState.working,
      );
      expect(service.status, HealthStatus.ready);
    });
  });

  group('eksport przejazdu', () {
    test('zapisuje trening i oznacza przejazd', () async {
      final health = _FakeHealth();
      final service = _service(health);
      await service.refreshStatus();

      expect(await service.exportRide(_ride()), isTrue);
      expect(health.workoutWrites, 1);
    });

    test('nie zapisuje drugi raz tego samego przejazdu', () async {
      // Podwójny wpis w Health jest nie do odróżnienia od dwóch przejazdów
      // i nie da się go cofnąć z aplikacji.
      final health = _FakeHealth();
      final service = _service(health);
      await service.refreshStatus();

      expect(await service.exportRide(_ride(exported: true)), isTrue);
      expect(health.workoutWrites, 0);
    });

    test('nieudany zapis zostawia przejazd do ponowienia', () async {
      final health = _FakeHealth(throwOnWrite: true);
      final service = _service(health);
      await service.refreshStatus();

      expect(await service.exportRide(_ride()), isFalse);
      expect(service.lastError, 'Zapis odrzucony');
    });

    test('trasa GPS dokleja się do treningu, gdy odczyt jest włączony', () async {
      final now = DateTime.now();
      final health = _FakeHealth(
        points: {
          HealthDataType.WORKOUT: [
            _point(HealthDataType.WORKOUT, 1, now, uuid: 'workout-1'),
          ],
        },
      );
      final service = _service(health);
      await service.setReadEnabled(true);

      await service.exportRide(
        _ride(),
        track: const [
          GeoPoint(lat: 52.0, lon: 21.0),
          GeoPoint(lat: 52.1, lon: 21.1),
          GeoPoint(lat: 52.2, lon: 21.2),
        ],
      );

      expect(health.routeStarts, 1);
      expect(health.routeFinishes, 1);
      expect(health.routeLocations.length, 3);
      // Znaczniki muszą rosnąć — HealthKit odrzuca trasę, w której czas się
      // cofa.
      for (var i = 1; i < health.routeLocations.length; i++) {
        expect(
          health.routeLocations[i].timestamp.isAfter(
            health.routeLocations[i - 1].timestamp,
          ),
          isTrue,
        );
      }
    });

    test('bez zgody na odczyt trening zapisuje się bez trasy', () async {
      // Proszenie o odczyt tylko po to, żeby domknąć zapis, byłoby
      // wymuszeniem zgody na coś zupełnie innego.
      final health = _FakeHealth();
      final service = _service(health);
      await service.refreshStatus();

      await service.exportRide(
        _ride(),
        track: const [
          GeoPoint(lat: 52.0, lon: 21.0),
          GeoPoint(lat: 52.1, lon: 21.1),
        ],
      );

      expect(health.workoutWrites, 1);
      expect(health.routeStarts, 0);
    });
  });

  group('odczyt profilu', () {
    test('masa ciała wraca jako propozycja, nie jako zapis', () async {
      final measured = DateTime.now().subtract(const Duration(days: 2));
      final health = _FakeHealth(
        points: {
          HealthDataType.WEIGHT: [
            _point(HealthDataType.WEIGHT, 81.2, measured.subtract(const Duration(days: 30))),
            _point(HealthDataType.WEIGHT, 98.4, measured),
          ],
        },
      );
      final service = _service(health);
      await service.setReadEnabled(true);

      final suggestion = await service.latestBodyMass();

      expect(suggestion, isNotNull);
      expect(suggestion!.kilograms, 98.4);
      expect(suggestion.measuredAt, measured);
    });

    test('bez zgody na odczyt nie proponujemy niczego', () async {
      final service = _service(_FakeHealth());
      expect(await service.latestBodyMass(), isNull);
      expect(await service.restingHeartRate(), isNull);
    });

    test('bzdurna waga jest odrzucana zamiast trafiać do profilu', () async {
      final health = _FakeHealth(
        points: {
          HealthDataType.WEIGHT: [
            _point(HealthDataType.WEIGHT, 4.2, DateTime.now()),
          ],
        },
      );
      final service = _service(health);
      await service.setReadEnabled(true);
      expect(await service.latestBodyMass(), isNull);
    });

    test('tętno spoczynkowe czytamy, ale nigdy jako tętno bieżące', () async {
      final health = _FakeHealth(
        points: {
          HealthDataType.RESTING_HEART_RATE: [
            _point(HealthDataType.RESTING_HEART_RATE, 48, DateTime.now()),
          ],
        },
      );
      final service = _service(health);
      await service.setReadEnabled(true);
      expect(await service.restingHeartRate(), 48);
    });
  });
}
