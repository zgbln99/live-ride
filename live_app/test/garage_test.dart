import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/data/bike_dao.dart';
import 'package:live_ride/data/database.dart';
import 'package:live_ride/models/bike.dart';
import 'package:live_ride/services/garage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LiveRideDatabase _inMemory() =>
    LiveRideDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

Bike _bike({
  String id = 'bike-1',
  String name = 'Szosa',
  double odometer = 0,
  bool isDefault = false,
}) => Bike(
  id: id,
  name: name,
  kind: BikeKind.road,
  createdAt: DateTime(2026, 1, 1),
  odometerMeters: odometer,
  isDefault: isDefault,
);

void main() {
  setUpAll(sqfliteFfiInit);

  group('zużycie komponentu', () {
    final installed = DateTime(2026, 1, 1);
    final now = DateTime(2026, 6, 1);

    BikeComponent component({double? limitMeters, int? limitDays}) =>
        BikeComponent(
          id: 'c1',
          bikeId: 'bike-1',
          name: 'Łańcuch',
          kind: ComponentKind.chain,
          installedAt: installed,
          odometerAtInstallMeters: 1000000,
          limitMeters: limitMeters,
          limitDays: limitDays,
        );

    test('bez limitu nie ma zużycia, nie zero', () {
      expect(component().wear(1500000, now), isNull);
      expect(component().isDue(1500000, now), isFalse);
    });

    test('liczy zużycie po przebiegu', () {
      final chain = component(limitMeters: 3000000);
      expect(chain.usedMeters(2500000), 1500000);
      expect(chain.wear(2500000, now), closeTo(0.5, 0.001));
      expect(chain.isDue(4000001, now), isTrue);
    });

    test('bierze surowszy z dwóch limitów', () {
      // 10 % przebiegu, ale 100 % czasu.
      //
      // Data graniczna liczy się od montażu, a nie jest wpisana z palca:
      // między dwiema datami kalendarzowymi potrafi wypaść zmiana czasu i
      // wtedy `difference(...).inDays` obcina 151 dni bez godziny do 150,
      // co w strefie z DST wywracało ten test przy poprawnej produkcji.
      final sealant = component(limitMeters: 10000000, limitDays: 151);
      final dueDate = installed.add(const Duration(days: 151));
      expect(sealant.wear(2000000, dueDate), greaterThanOrEqualTo(1.0));
    });

    test('nie cofa przebiegu, gdy licznik roweru zresetowano', () {
      expect(component(limitMeters: 3000000).usedMeters(500000), 0);
    });

    test('ostrzega tuż przed terminem', () {
      final chain = component(limitMeters: 1000000);
      expect(chain.isSoon(1900000, now), isTrue);
      expect(chain.isSoon(1500000, now), isFalse);
      expect(chain.isSoon(2100000, now), isFalse, reason: 'to już po terminie');
      expect(chain.isDue(2100000, now), isTrue);
    });
  });

  group('garaż', () {
    late LiveRideDatabase database;
    late GarageService garage;

    setUp(() async {
      database = _inMemory();
      garage = GarageService(BikeDao(database));
      await garage.load();
    });

    tearDown(() => database.close());

    test('pusty garaż nie ma aktywnego roweru', () {
      expect(garage.bikes, isEmpty);
      expect(garage.activeBike, isNull);
      expect(garage.dueSoon, isEmpty);
    });

    test('pierwszy rower staje się aktywny', () async {
      await garage.saveBike(_bike());
      expect(garage.activeBike!.id, 'bike-1');
    });

    test('tylko jeden rower może być domyślny', () async {
      await garage.saveBike(_bike(id: 'a', name: 'Szosa', isDefault: true));
      await garage.saveBike(_bike(id: 'b', name: 'Gravel', isDefault: true));
      final defaults = garage.bikes.where((bike) => bike.isDefault);
      expect(defaults, hasLength(1));
      expect(defaults.single.id, 'b');
    });

    test('przejazd dolicza się do licznika roweru', () async {
      await garage.saveBike(_bike(odometer: 100000));
      await garage.recordRide(bikeId: 'bike-1', distanceMeters: 42000);
      expect(garage.activeBike!.odometerMeters, 142000);
    });

    test('przejazd bez roweru nie wywala zapisu', () async {
      await garage.recordRide(bikeId: null, distanceMeters: 42000);
      expect(garage.bikes, isEmpty);
    });

    test('komponenty po terminie trafiają na listę serwisową', () async {
      await garage.saveBike(_bike(odometer: 5000000));
      await garage.saveComponent(
        BikeComponent(
          id: 'c1',
          bikeId: 'bike-1',
          name: 'Łańcuch',
          kind: ComponentKind.chain,
          installedAt: DateTime(2026, 1, 1),
          odometerAtInstallMeters: 1000000,
          limitMeters: 3000000,
        ),
      );
      expect(garage.dueSoon, hasLength(1));
      expect(garage.dueSoon.single.component.id, 'c1');
      expect(garage.dueSoon.single.wear, greaterThan(1));
    });

    test('wymiana komponentu zeruje jego przebieg', () async {
      await garage.saveBike(_bike(odometer: 5000000));
      await garage.saveComponent(
        BikeComponent(
          id: 'c1',
          bikeId: 'bike-1',
          name: 'Łańcuch',
          kind: ComponentKind.chain,
          installedAt: DateTime(2026, 1, 1),
          odometerAtInstallMeters: 1000000,
          limitMeters: 3000000,
        ),
      );
      await garage.resetComponent(garage.componentsOf('bike-1').single);

      final refreshed = garage.componentsOf('bike-1').single;
      expect(refreshed.odometerAtInstallMeters, 5000000);
      expect(refreshed.usedMeters(5000000), 0);
      expect(garage.dueSoon, isEmpty);
    });

    test('usunięcie roweru zabiera jego komponenty', () async {
      await garage.saveBike(_bike());
      await garage.saveComponent(
        BikeComponent(
          id: 'c1',
          bikeId: 'bike-1',
          name: 'Łańcuch',
          kind: ComponentKind.chain,
          installedAt: DateTime(2026, 1, 1),
          odometerAtInstallMeters: 0,
          limitMeters: 3000000,
        ),
      );
      await garage.deleteBike('bike-1');
      expect(garage.bikes, isEmpty);
      expect(garage.componentsOf('bike-1'), isEmpty);
    });

    test('domyślne limity są sensowne i tylko tam, gdzie mają sens', () {
      expect(ComponentKind.chain.defaultLimitKm, 3000);
      expect(ComponentKind.sealant.defaultLimitKm, isNull);
      expect(ComponentKind.sealant.defaultLimitDays, 120);
      expect(ComponentKind.custom.defaultLimitKm, isNull);
    });
  });
}
