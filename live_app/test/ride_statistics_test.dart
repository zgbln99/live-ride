import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/data/database.dart';
import 'package:live_ride/data/ride_dao.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/models/ride_statistics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LiveRideDatabase _inMemory() =>
    LiveRideDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

RecordedRide _ride({
  required String id,
  required DateTime startedAt,
  double distance = 30000,
  int movingSeconds = 3600,
  double ascent = 300,
  double maxSpeed = 45,
  int? normalizedPower,
  int points = 10,
}) => RecordedRide(
  id: id,
  name: 'Przejazd $id',
  startedAt: startedAt,
  endedAt: startedAt.add(Duration(seconds: movingSeconds)),
  elapsedSeconds: movingSeconds + 200,
  movingSeconds: movingSeconds,
  distanceMeters: distance,
  elevationGainMeters: ascent,
  maxSpeedKmh: maxSpeed,
  normalizedPower: normalizedPower,
  points: [
    for (var i = 0; i < points; i++)
      RecordedRidePoint(
        lat: 52.0 + i / 10000,
        lon: 21.0 + i / 10000,
        recordedAt: startedAt.add(Duration(seconds: i)),
        distanceMeters: i * 10,
      ),
  ],
);

void main() {
  setUpAll(sqfliteFfiInit);

  group('okresy', () {
    final wednesday = DateTime(2026, 5, 13, 15);

    test('tydzień zaczyna się w poniedziałek', () {
      final start = StatsPeriod.week.startOf(wednesday);
      expect(start.weekday, DateTime.monday);
      expect(start, DateTime(2026, 5, 11));
    });

    test('miesiąc i rok zaczynają się od pierwszego', () {
      expect(StatsPeriod.month.startOf(wednesday), DateTime(2026, 5));
      expect(StatsPeriod.year.startOf(wednesday), DateTime(2026));
    });

    test(
      'poprzedni okres cofa się o jednostkę, a „wszystko" nie ma go wcale',
      () {
        expect(StatsPeriod.week.previousStart(wednesday), DateTime(2026, 5, 4));
        expect(StatsPeriod.month.previousStart(wednesday), DateTime(2026, 4));
        expect(StatsPeriod.year.previousStart(wednesday), DateTime(2025));
        expect(StatsPeriod.allTime.previousStart(wednesday), isNull);
      },
    );

    test('grupowanie dobiera się do okresu', () {
      expect(StatsPeriod.week.bucket, StatsBucketKind.day);
      expect(StatsPeriod.year.bucket, StatsBucketKind.month);
      expect(StatsPeriod.allTime.bucket, StatsBucketKind.year);
    });
  });

  group('statystyki z bazy', () {
    late LiveRideDatabase database;
    late RideDao dao;

    setUp(() async {
      database = _inMemory();
      dao = RideDao(database);
    });

    tearDown(() => database.close());

    test('pusta baza daje zera, nie wyjątek', () async {
      final stats = await dao.statistics(
        StatsPeriod.month,
        now: DateTime(2026, 5, 13),
      );
      expect(stats.isEmpty, isTrue);
      expect(stats.distanceMeters, 0);
      expect(stats.averageSpeedKmh, 0);
      expect(stats.distanceChangePercent, isNull);
      expect(stats.buckets, isEmpty);
    });

    test('sumuje tylko przejazdy z okresu', () async {
      await dao.save(_ride(id: 'a', startedAt: DateTime(2026, 5, 2, 9)));
      await dao.save(_ride(id: 'b', startedAt: DateTime(2026, 5, 12, 9)));
      await dao.save(_ride(id: 'c', startedAt: DateTime(2026, 4, 20, 9)));

      final month = await dao.statistics(
        StatsPeriod.month,
        now: DateTime(2026, 5, 13),
      );
      expect(month.rides, 2);
      expect(month.distanceMeters, 60000);

      final week = await dao.statistics(
        StatsPeriod.week,
        now: DateTime(2026, 5, 13),
      );
      expect(week.rides, 1);
    });

    test('porównuje z poprzednim okresem', () async {
      await dao.save(
        _ride(
          id: 'kwiecien',
          startedAt: DateTime(2026, 4, 10, 9),
          distance: 20000,
        ),
      );
      await dao.save(
        _ride(id: 'maj', startedAt: DateTime(2026, 5, 10, 9), distance: 30000),
      );

      final stats = await dao.statistics(
        StatsPeriod.month,
        now: DateTime(2026, 5, 13),
      );
      expect(stats.previousDistanceMeters, 20000);
      expect(stats.distanceChangePercent, closeTo(50, 0.001));
    });

    test('słupki dzienne grupują po dacie lokalnej', () async {
      await dao.save(_ride(id: 'a', startedAt: DateTime(2026, 5, 11, 7)));
      await dao.save(_ride(id: 'b', startedAt: DateTime(2026, 5, 11, 18)));
      await dao.save(_ride(id: 'c', startedAt: DateTime(2026, 5, 13, 6)));

      final buckets = await dao.buckets(
        StatsBucketKind.day,
        from: DateTime(2026, 5, 11),
      );
      expect(buckets, hasLength(2));
      expect(buckets.first.start, DateTime(2026, 5, 11));
      expect(buckets.first.rides, 2);
      expect(buckets.first.distanceMeters, 60000);
      expect(buckets.last.start, DateTime(2026, 5, 13));
    });

    test('słupki roczne dla całej historii', () async {
      await dao.save(_ride(id: 'a', startedAt: DateTime(2024, 6, 1, 9)));
      await dao.save(_ride(id: 'b', startedAt: DateTime(2026, 6, 1, 9)));
      final buckets = await dao.buckets(StatsBucketKind.year);
      expect(buckets.map((bucket) => bucket.start.year), [2024, 2026]);
    });

    test('rekordy pokazują tylko kategorie z danymi', () async {
      await dao.save(
        _ride(
          id: 'dluga',
          startedAt: DateTime(2026, 5, 2, 9),
          distance: 120000,
          movingSeconds: 14400,
          ascent: 1800,
          maxSpeed: 61,
        ),
      );
      await dao.save(
        _ride(
          id: 'szybka',
          startedAt: DateTime(2026, 5, 6, 9),
          distance: 40000,
          movingSeconds: 3600,
          ascent: 200,
          maxSpeed: 55,
        ),
      );

      final records = await dao.records();
      final kinds = {for (final record in records) record.kind: record};

      expect(kinds[RideRecordKind.longestDistance]!.rideId, 'dluga');
      expect(kinds[RideRecordKind.longestDistance]!.value, 120000);
      expect(kinds[RideRecordKind.biggestAscent]!.rideId, 'dluga');
      expect(kinds[RideRecordKind.highestSpeed]!.value, 61);
      // 40 km w godzinę bije 120 km w cztery.
      expect(kinds[RideRecordKind.fastestAverage]!.rideId, 'szybka');
      // Żaden przejazd nie ma mocy normalizowanej.
      expect(kinds.containsKey(RideRecordKind.bestNormalizedPower), isFalse);
    });

    test('rekord mocy pojawia się dopiero z miernikiem', () async {
      await dao.save(
        _ride(
          id: 'z-moca',
          startedAt: DateTime(2026, 5, 2, 9),
          normalizedPower: 248,
        ),
      );
      final records = await dao.records();
      final power = records.firstWhere(
        (record) => record.kind == RideRecordKind.bestNormalizedPower,
      );
      expect(power.value, 248);
    });

    test('krótkie przejazdy nie zaśmiecają rekordów', () async {
      await dao.save(
        _ride(id: 'krotka', startedAt: DateTime(2026, 5, 2, 9), distance: 900),
      );
      expect(await dao.records(), isEmpty);
    });

    test('kalendarz liczy przejazdy w każdym dniu', () async {
      await dao.save(_ride(id: 'a', startedAt: DateTime(2026, 5, 4, 9)));
      await dao.save(_ride(id: 'b', startedAt: DateTime(2026, 5, 4, 17)));
      await dao.save(_ride(id: 'c', startedAt: DateTime(2026, 5, 20, 9)));

      final calendar = await dao.calendar(
        from: DateTime(2026, 5),
        to: DateTime(2026, 6),
      );
      expect(calendar[DateTime(2026, 5, 4)]!.rides, 2);
      expect(calendar[DateTime(2026, 5, 4)]!.distanceMeters, 60000);
      expect(calendar[DateTime(2026, 5, 20)]!.rides, 1);
      expect(calendar[DateTime(2026, 5, 5)], isNull);
    });

    test('mapa cieplna przerzedza punkty', () async {
      await dao.save(
        _ride(id: 'a', startedAt: DateTime(2026, 5, 4, 9), points: 100),
      );
      final dense = await dao.heatmapPoints(step: 1);
      final sparse = await dao.heatmapPoints(step: 10);
      expect(dense, hasLength(100));
      expect(sparse, hasLength(10));
      expect(sparse.first.lat, closeTo(52.0, 0.0001));
    });
  });
}
