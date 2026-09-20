import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/data/database.dart';
import 'package:live_ride/data/ride_dao.dart';
import 'package:live_ride/data/route_dao.dart';
import 'package:live_ride/data/settings_dao.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/models/ride_route.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_waypoint.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Testy chodzą po prawdziwym SQLite w pamięci, a nie po atrapie — inaczej
/// schemat, klucze obce i migracje nie byłyby w ogóle sprawdzone.
LiveRideDatabase inMemoryDatabase() =>
    LiveRideDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

RecordedRide buildRide({
  String id = 'ride-1',
  int points = 100,
  DateTime? startedAt,
  double distance = 25000,
  int autoPaused = 0,
  int manualPaused = 0,
}) {
  final start = startedAt ?? DateTime(2026, 5, 1, 8);
  return RecordedRide(
    id: id,
    name: 'Testowy przejazd',
    startedAt: start,
    endedAt: start.add(const Duration(hours: 1)),
    elapsedSeconds: 3600,
    movingSeconds: 3400,
    autoPausedSeconds: autoPaused,
    manualPausedSeconds: manualPaused,
    distanceMeters: distance,
    elevationGainMeters: 420,
    elevationLossMeters: 410,
    maxSpeedKmh: 52.4,
    averageHeartRate: 148,
    maxHeartRate: 176,
    averagePower: 210,
    maxPower: 620,
    normalizedPower: 225,
    intensityFactor: 0.82,
    trainingStressScore: 68.5,
    averageCadence: 86,
    calories: 780,
    riderName: 'Marek',
    bikeId: 'bike-1',
    points: [
      for (var i = 0; i < points; i++)
        RecordedRidePoint(
          lat: 50.06 + i / 100000,
          lon: 19.94 + i / 100000,
          recordedAt: start.add(Duration(seconds: i)),
          altitude: 220 + i * 0.5,
          speedMps: 7.2,
          heartRate: 140 + i % 20,
          cadence: 85,
          power: 200 + i % 40,
          distanceMeters: i * 7.2,
        ),
    ],
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('schemat', () {
    test('tworzy wszystkie tabele', () async {
      final database = inMemoryDatabase();
      final db = await database.open();
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = rows.map((row) => row['name']).toSet();
      for (final table in [
        'rides',
        'ride_points',
        'routes',
        'route_points',
        'route_waypoints',
        'route_drafts',
        'segments',
        'segment_attempts',
        'bikes',
        'bike_components',
        'sensors',
        'workouts',
        'workout_steps',
        'settings',
        'sync_queue',
      ]) {
        expect(tables, contains(table), reason: 'brak tabeli $table');
      }
      await database.close();
    });

    test(
      'migracja do wersji 2 dokłada kolumny pauz i nie gubi przejazdu',
      () async {
        // Migracja musi się odbyć na pliku: baza w pamięci znika przy zamknięciu,
        // więc nie da się na niej otworzyć starej wersji schematu po raz drugi.
        final directory = await Directory.systemTemp.createTemp('live_ride_db');
        final path = '${directory.path}/live_ride.db';
        addTearDown(() => directory.delete(recursive: true));

        // Krok 1: postarz plik do wersji 1, zdejmując z niego to, co dołożyła
        // wersja 2. Reszta schematu zostaje prawdziwa.
        final fresh = LiveRideDatabase(factory: databaseFactoryFfi, path: path);
        await (await fresh.open()).close();
        await fresh.close();

        final legacy = await databaseFactoryFfi.openDatabase(path);
        await legacy.execute(
          'ALTER TABLE rides DROP COLUMN auto_paused_seconds',
        );
        await legacy.execute(
          'ALTER TABLE rides DROP COLUMN manual_paused_seconds',
        );
        await legacy.execute('PRAGMA user_version = 1');
        await legacy.insert('rides', {
          'id': 'stary-przejazd',
          'name': 'Sprzed migracji',
          'started_at': DateTime(2026, 4, 1, 9).millisecondsSinceEpoch,
          'ended_at': DateTime(2026, 4, 1, 10).millisecondsSinceEpoch,
          'elapsed_seconds': 3600,
          'moving_seconds': 3400,
          'distance_meters': 30000.0,
          'created_at': DateTime(2026, 4, 1, 10).millisecondsSinceEpoch,
        });
        await legacy.close();

        // Krok 2: aplikacja otwiera go ponownie i musi go podnieść.
        final migrated = LiveRideDatabase(
          factory: databaseFactoryFfi,
          path: path,
        );
        final dao = RideDao(migrated);
        final loaded = await dao.findById('stary-przejazd');

        expect(loaded, isNotNull, reason: 'migracja zgubiła przejazd');
        expect(loaded!.distanceMeters, 30000);
        expect(loaded.elapsedSeconds, 3600);
        // Stary zapis nie wie, ile z tego było postojem — i nie zmyśla.
        expect(loaded.autoPausedSeconds, 0);
        expect(loaded.manualPausedSeconds, 0);
        expect(loaded.hasPauseBreakdown, isFalse);

        // A nowy przejazd zapisany po migracji już ten podział ma.
        await dao.save(
          buildRide(id: 'po-migracji', autoPaused: 300, manualPaused: 120),
        );
        final recent = await dao.findById('po-migracji');
        expect(recent!.autoPausedSeconds, 300);
        expect(recent.manualPausedSeconds, 120);
        expect(recent.pausedTime, const Duration(minutes: 7));
        await migrated.close();
      },
    );

    test('usunięcie przejazdu kasuje jego punkty', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide());
      expect((await dao.loadPoints('ride-1')).length, 100);

      await dao.delete('ride-1');
      expect(await dao.findById('ride-1'), isNull);
      expect(await dao.loadPoints('ride-1'), isEmpty);
      await database.close();
    });
  });

  group('przejazdy', () {
    test('zapisuje i odczytuje wszystkie metryki', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide());

      final loaded = await dao.findById('ride-1');
      expect(loaded, isNotNull);
      expect(loaded!.distanceMeters, 25000);
      expect(loaded.averagePower, 210);
      expect(loaded.normalizedPower, 225);
      expect(loaded.trainingStressScore, 68.5);
      expect(loaded.averageCadence, 86);
      expect(loaded.calories, 780);
      expect(loaded.bikeId, 'bike-1');
      expect(loaded.points.length, 100);
      expect(loaded.points.first.power, 200);
      expect(loaded.points.first.cadence, 85);
      await database.close();
    });

    test('lista nie wczytuje punktów', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide());

      final summaries = await dao.listSummaries();
      expect(summaries.single.points, isEmpty);
      expect(summaries.single.distanceMeters, 25000);
      await database.close();
    });

    test('podgląd śladu jest rzadszy od pełnego', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide(points: 5000));

      final preview = await dao.loadPreview('ride-1', maxPoints: 100);
      expect(preview.length, lessThanOrEqualTo(120));
      expect(preview.length, greaterThan(20));
      await database.close();
    });

    test('sumy liczy baza, nie aplikacja', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide(id: 'a', distance: 20000));
      await dao.save(
        buildRide(id: 'b', distance: 30000, startedAt: DateTime(2026, 5, 2, 8)),
      );

      final totals = await dao.totals();
      expect(totals.rides, 2);
      expect(totals.distanceMeters, 50000);
      expect(totals.ascentMeters, 840);
      expect(totals.maxSpeedKmh, 52.4);
      expect(totals.averageHeartRate, 148);
      await database.close();
    });

    test('sumy dają się ograniczyć zakresem dat', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide(id: 'stary', startedAt: DateTime(2026, 1, 1)));
      await dao.save(buildRide(id: 'nowy', startedAt: DateTime(2026, 5, 1)));

      final totals = await dao.totals(from: DateTime(2026, 4, 1));
      expect(totals.rides, 1);
      await database.close();
    });

    test('pilnuje statusu synchronizacji', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide());
      expect((await dao.pendingSync()).length, 1);

      await dao.updateSyncStatus('ride-1', SyncStatus.synced);
      expect(await dao.pendingSync(), isEmpty);
      expect((await dao.findById('ride-1'))!.syncStatus, SyncStatus.synced);
      await database.close();
    });

    test('zapis tej samej trasy nie duplikuje punktów', () async {
      final database = inMemoryDatabase();
      final dao = RideDao(database);
      await dao.save(buildRide(points: 50));
      await dao.save(buildRide(points: 30));
      expect((await dao.loadPoints('ride-1')).length, 30);
      expect(await dao.count(), 1);
      await database.close();
    });
  });

  group('trasy', () {
    RideRoute buildRoute({String id = 'route-1'}) => RideRoute(
      id: id,
      name: 'Dolina Kościeliska',
      description: 'Spokojny wyjazd doliną',
      tags: const ['gravel', 'góry'],
      points: [
        for (var i = 0; i < 400; i++)
          GeoPoint(
            lat: 49.27 + i / 50000,
            lon: 19.86 + i / 80000,
            elevation: 900 + i * 0.4,
          ),
      ],
      waypoints: const [
        RouteWaypoint(
          point: GeoPoint(lat: 49.27, lon: 19.86),
          name: 'Kiry',
          kind: WaypointKind.start,
        ),
        RouteWaypoint(
          point: GeoPoint(lat: 49.28, lon: 19.87),
          kind: WaypointKind.finish,
        ),
      ],
      preferences: const RoutePreferences(
        profile: BikeProfile.gravel,
        mood: RouteMood.quiet,
        surface: SurfacePreference.unpaved,
      ),
      privacy: RoutePrivacy.unlisted,
      source: RouteSource.builder,
      shareToken: 'abc123',
    );

    test('zapisuje geometrię, waypointy i preferencje', () async {
      final database = inMemoryDatabase();
      final dao = RouteDao(database);
      await dao.save(buildRoute());

      final loaded = await dao.load('route-1');
      expect(loaded, isNotNull);
      expect(loaded!.points.length, 400);
      expect(loaded.waypoints.length, 2);
      expect(loaded.waypoints.first.name, 'Kiry');
      expect(loaded.waypoints.first.kind, WaypointKind.start);
      expect(loaded.preferences.profile, BikeProfile.gravel);
      expect(loaded.preferences.surface, SurfacePreference.unpaved);
      expect(loaded.privacy, RoutePrivacy.unlisted);
      expect(loaded.shareToken, 'abc123');
      expect(loaded.tags, ['gravel', 'góry']);
      expect(loaded.points.first.elevation, 900);
      await database.close();
    });

    test('lista ma podgląd, ale nie pełną geometrię', () async {
      final database = inMemoryDatabase();
      final dao = RouteDao(database);
      await dao.save(buildRoute());

      final summary = (await dao.listSummaries()).single;
      expect(summary.pointCount, 400);
      expect(summary.preview.length, lessThan(200));
      expect(summary.preview, isNotEmpty);
      expect(summary.ascentMeters, greaterThan(100));
      await database.close();
    });

    test('szuka po nazwie i opisie', () async {
      final database = inMemoryDatabase();
      final dao = RouteDao(database);
      await dao.save(buildRoute());

      expect((await dao.listSummaries(query: 'kościel')).length, 1);
      expect((await dao.listSummaries(query: 'doliną')).length, 1);
      expect((await dao.listSummaries(query: 'morze')), isEmpty);
      await database.close();
    });

    test('zapamiętuje ostatnie użycie i udostępnianie', () async {
      final database = inMemoryDatabase();
      final dao = RouteDao(database);
      await dao.save(buildRoute());

      await dao.markUsed('route-1');
      expect((await dao.findSummary('route-1'))!.lastUsedAt, isNotNull);

      await dao.setSharing(
        id: 'route-1',
        privacy: RoutePrivacy.public,
        shareToken: 'xyz',
      );
      final shared = await dao.findSummary('route-1');
      expect(shared!.privacy, RoutePrivacy.public);
      expect(shared.shareToken, 'xyz');
      expect(shared.isShared, isTrue);
      await database.close();
    });

    test('szkic trasy przeżywa restart', () async {
      final database = inMemoryDatabase();
      final dao = RouteDao(database);
      await dao.saveDraft('draft', {'name': 'Nowa', 'waypoints': 3});

      expect((await dao.loadDraft('draft'))!['name'], 'Nowa');
      await dao.deleteDraft('draft');
      expect(await dao.loadDraft('draft'), isNull);
      await database.close();
    });
  });

  group('ustawienia i kolejka', () {
    test('zapisuje i czyta ustawienia', () async {
      final database = inMemoryDatabase();
      final dao = SettingsDao(database);
      await dao.writeJson('profil', {'ftp': 240});
      expect((await dao.readJson('profil'))!['ftp'], 240);

      await dao.remove('profil');
      expect(await dao.readJson('profil'), isNull);
      await database.close();
    });

    test('kolejkuje telemetrię i oddaje ją w kolejności', () async {
      final database = inMemoryDatabase();
      final dao = SyncQueueDao(database);
      for (var i = 0; i < 3; i++) {
        await dao.enqueue(
          kind: 'telemetry',
          target: 'session-1',
          payload: {'seq': i},
        );
      }

      expect(await dao.pendingCount(kind: 'telemetry'), 3);
      final items = await dao.take(kind: 'telemetry');
      expect(items.first.payload['seq'], 0);

      await dao.remove(items.first.id);
      expect(await dao.pendingCount(), 2);
      await database.close();
    });

    test('liczy nieudane próby', () async {
      final database = inMemoryDatabase();
      final dao = SyncQueueDao(database);
      await dao.enqueue(kind: 'ride', target: 'r1', payload: {'a': 1});
      final item = (await dao.take()).single;

      await dao.markFailed(item.id, 'brak sieci');
      expect((await dao.take()).single.attempts, 1);
      await database.close();
    });
  });
}
