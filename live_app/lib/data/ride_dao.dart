import 'package:sqflite/sqflite.dart';

import '../core/geo.dart';
import '../models/ride_record.dart';
import '../models/ride_statistics.dart';
import 'database.dart';

/// Dostęp do przejazdów w bazie.
///
/// Punkty przejazdu leżą w osobnej tabeli i wczytuje się je tylko wtedy, gdy
/// są naprawdę potrzebne — lista historii nie może ciągnąć pół miliona
/// wierszy, żeby narysować dwadzieścia kafelków.
class RideDao {
  RideDao(this._database);

  final LiveRideDatabase _database;

  /// Ile punktów wrzucamy do jednej transakcji przy zapisie.
  static const int _insertChunk = 500;

  Future<void> save(RecordedRide ride) async {
    final db = await _database.open();
    await db.transaction((txn) async {
      await txn.insert(
        'rides',
        _rideToRow(ride),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'ride_points',
        where: 'ride_id = ?',
        whereArgs: [ride.id],
      );
      for (var start = 0; start < ride.points.length; start += _insertChunk) {
        final batch = txn.batch();
        final end = (start + _insertChunk).clamp(0, ride.points.length);
        for (var i = start; i < end; i++) {
          batch.insert('ride_points', _pointToRow(ride.id, i, ride.points[i]));
        }
        await batch.commit(noResult: true);
      }
    });
  }

  /// Nagłówki przejazdów, bez punktów — do listy i statystyk.
  Future<List<RecordedRide>> listSummaries({
    int? limit,
    DateTime? since,
  }) async {
    final db = await _database.open();
    final rows = await db.query(
      'rides',
      where: since == null ? null : 'started_at >= ?',
      whereArgs: since == null ? null : [since.millisecondsSinceEpoch],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows
        .map((row) => _rideFromRow(row, const []))
        .toList(growable: false);
  }

  Future<RecordedRide?> findById(String id, {bool withPoints = true}) async {
    final db = await _database.open();
    final rows = await db.query(
      'rides',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final points = withPoints
        ? await loadPoints(id)
        : const <RecordedRidePoint>[];
    return _rideFromRow(rows.first, points);
  }

  Future<List<RecordedRidePoint>> loadPoints(String rideId) async {
    final db = await _database.open();
    final rows = await db.query(
      'ride_points',
      where: 'ride_id = ?',
      whereArgs: [rideId],
      orderBy: 'seq ASC',
    );
    return rows.map(_pointFromRow).toList(growable: false);
  }

  /// Rzadka wersja śladu do podglądu na karcie — nie wczytuje całości.
  Future<List<RecordedRidePoint>> loadPreview(
    String rideId, {
    int maxPoints = 120,
  }) async {
    final db = await _database.open();
    final countRow = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ride_points WHERE ride_id = ?',
      [rideId],
    );
    final total = (countRow.first['c'] as num?)?.toInt() ?? 0;
    if (total == 0) return const [];
    final step = (total / maxPoints).ceil().clamp(1, total);
    final rows = await db.rawQuery(
      'SELECT * FROM ride_points WHERE ride_id = ? AND seq % ? = 0 '
      'ORDER BY seq ASC',
      [rideId, step],
    );
    return rows.map(_pointFromRow).toList(growable: false);
  }

  Future<void> delete(String id) async {
    final db = await _database.open();
    await db.delete('rides', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await _database.open();
    await db.update(
      'rides',
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markHealthExported(String id) async {
    final db = await _database.open();
    await db.update(
      'rides',
      {'health_exported': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> rename(String id, String name) async {
    final db = await _database.open();
    await db.update('rides', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<RecordedRide>> pendingSync() async {
    final db = await _database.open();
    final rows = await db.query(
      'rides',
      where: 'sync_status IN (?, ?)',
      whereArgs: [SyncStatus.local.name, SyncStatus.pending.name],
      orderBy: 'started_at ASC',
    );
    return rows
        .map((row) => _rideFromRow(row, const []))
        .toList(growable: false);
  }

  Future<int> count() async {
    final db = await _database.open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM rides');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Sumy liczone przez SQLite zamiast wczytywania wszystkich przejazdów.
  Future<RideTotals> totals({DateTime? from, DateTime? to}) async {
    final db = await _database.open();
    final where = <String>[];
    final args = <Object>[];
    if (from != null) {
      where.add('started_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('started_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS rides,
        COALESCE(SUM(distance_meters), 0) AS distance,
        COALESCE(SUM(moving_seconds), 0) AS moving,
        COALESCE(SUM(elapsed_seconds), 0) AS elapsed,
        COALESCE(SUM(ascent_meters), 0) AS ascent,
        COALESCE(MAX(max_speed_kmh), 0) AS max_speed,
        COALESCE(SUM(calories), 0) AS calories,
        AVG(avg_heart_rate) AS avg_hr,
        AVG(avg_power) AS avg_power
      FROM rides $clause
    ''', args);
    final row = rows.first;
    return RideTotals(
      rides: (row['rides'] as num?)?.toInt() ?? 0,
      distanceMeters: (row['distance'] as num?)?.toDouble() ?? 0,
      movingSeconds: (row['moving'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (row['elapsed'] as num?)?.toInt() ?? 0,
      ascentMeters: (row['ascent'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (row['max_speed'] as num?)?.toDouble() ?? 0,
      calories: (row['calories'] as num?)?.toInt() ?? 0,
      averageHeartRate: (row['avg_hr'] as num?)?.round(),
      averagePower: (row['avg_power'] as num?)?.round(),
    );
  }

  // ---------------------------------------------------------- statystyki

  /// Statystyki okresu razem ze słupkami wykresu.
  ///
  /// Wszystko liczy SQLite jednym zapytaniem na sumy i jednym na słupki —
  /// wczytywanie tysiąca przejazdów do Dart tylko po to, żeby je zsumować,
  /// zajęłoby sekundy przy każdym wejściu w historię.
  Future<RideStatistics> statistics(StatsPeriod period, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final from = period.startOf(at);
    final totalsNow = await totals(from: from);

    RideTotals? previous;
    final previousStart = period.previousStart(at);
    if (previousStart != null) {
      previous = await totals(from: previousStart, to: from);
    }

    return RideStatistics(
      period: period,
      from: from,
      rides: totalsNow.rides,
      distanceMeters: totalsNow.distanceMeters,
      movingSeconds: totalsNow.movingSeconds,
      ascentMeters: totalsNow.ascentMeters,
      buckets: await buckets(period.bucket, from: from),
      previousDistanceMeters: previous?.distanceMeters,
      previousRides: previous?.rides,
    );
  }

  /// Słupki pogrupowane po dniu, miesiącu albo roku.
  ///
  /// Grupowanie idzie przez `strftime` po czasie lokalnym: przejazd o 23:30
  /// należy do tego dnia, w którym zawodnik go jechał, a nie do jutra w UTC.
  Future<List<StatsBucket>> buckets(
    StatsBucketKind kind, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _database.open();
    final format = switch (kind) {
      StatsBucketKind.day => '%Y-%m-%d',
      StatsBucketKind.month => '%Y-%m',
      StatsBucketKind.year => '%Y',
    };
    final where = <String>[];
    final args = <Object>[];
    if (from != null) {
      where.add('started_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('started_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT
        strftime('$format', started_at / 1000, 'unixepoch', 'localtime')
          AS bucket,
        COUNT(*) AS rides,
        COALESCE(SUM(distance_meters), 0) AS distance,
        COALESCE(SUM(moving_seconds), 0) AS moving,
        COALESCE(SUM(ascent_meters), 0) AS ascent
      FROM rides $clause
      GROUP BY bucket
      ORDER BY bucket
    ''', args);

    return [
      for (final row in rows)
        StatsBucket(
          start: _parseBucket('${row['bucket']}', kind),
          rides: (row['rides'] as num?)?.toInt() ?? 0,
          distanceMeters: (row['distance'] as num?)?.toDouble() ?? 0,
          movingSeconds: (row['moving'] as num?)?.toInt() ?? 0,
          ascentMeters: (row['ascent'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }

  static DateTime _parseBucket(String value, StatsBucketKind kind) {
    final parts = value.split('-');
    final year = int.tryParse(parts.first) ?? 1970;
    return switch (kind) {
      StatsBucketKind.year => DateTime(year),
      StatsBucketKind.month => DateTime(
        year,
        parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1,
      ),
      StatsBucketKind.day => DateTime(
        year,
        parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1,
        parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1,
      ),
    };
  }

  /// Rekordy zawodnika — po jednym najlepszym przejeździe na kategorię.
  ///
  /// Kategoria, w której nie ma danych (np. moc bez miernika), po prostu się
  /// nie pojawia.
  Future<List<RideRecord>> records({
    double minimumDistanceMeters = 3000,
  }) async {
    final db = await _database.open();
    final records = <RideRecord>[];

    Future<void> best(
      RideRecordKind kind,
      String expression, {
      String? extraWhere,
    }) async {
      final where = StringBuffer('WHERE distance_meters >= ?');
      if (extraWhere != null) where.write(' AND $extraWhere');
      final rows = await db.rawQuery(
        '''
        SELECT id, name, started_at, ($expression) AS value
        FROM rides
        $where
        ORDER BY value DESC
        LIMIT 1
      ''',
        [minimumDistanceMeters],
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final value = (row['value'] as num?)?.toDouble();
      if (value == null || value <= 0) return;
      records.add(
        RideRecord(
          kind: kind,
          value: value,
          rideId: '${row['id']}',
          rideName: '${row['name']}',
          achievedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['started_at'] as num).toInt(),
          ),
        ),
      );
    }

    await best(RideRecordKind.longestDistance, 'distance_meters');
    await best(RideRecordKind.longestTime, 'moving_seconds');
    await best(RideRecordKind.biggestAscent, 'ascent_meters');
    await best(
      RideRecordKind.fastestAverage,
      'distance_meters / NULLIF(moving_seconds, 0) * 3.6',
      extraWhere: 'moving_seconds > 600',
    );
    await best(RideRecordKind.highestSpeed, 'max_speed_kmh');
    await best(
      RideRecordKind.bestNormalizedPower,
      'normalized_power',
      extraWhere: 'normalized_power IS NOT NULL',
    );
    return records;
  }

  /// Liczba przejazdów i dystans w każdym dniu — pod kalendarz.
  Future<Map<DateTime, ({int rides, double distanceMeters})>> calendar({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      '''
      SELECT
        strftime('%Y-%m-%d', started_at / 1000, 'unixepoch', 'localtime')
          AS day,
        COUNT(*) AS rides,
        COALESCE(SUM(distance_meters), 0) AS distance
      FROM rides
      WHERE started_at >= ? AND started_at < ?
      GROUP BY day
    ''',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    final result = <DateTime, ({int rides, double distanceMeters})>{};
    for (final row in rows) {
      final day = _parseBucket('${row['day']}', StatsBucketKind.day);
      result[day] = (
        rides: (row['rides'] as num?)?.toInt() ?? 0,
        distanceMeters: (row['distance'] as num?)?.toDouble() ?? 0,
      );
    }
    return result;
  }

  /// Punkty wszystkich przejazdów, przerzedzone pod mapę cieplną.
  ///
  /// Co n-ty punkt, a nie wszystkie: heatmapa z dwustu tysięcy punktów
  /// wygląda tak samo jak z dwudziestu tysięcy i rysuje się dziesięć razy
  /// szybciej.
  Future<List<GeoPoint>> heatmapPoints({
    int step = 20,
    int limit = 40000,
  }) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      '''
      SELECT lat, lon FROM ride_points
      WHERE seq % ? = 0
      LIMIT ?
      ''',
      [step, limit],
    );
    return [
      for (final row in rows)
        GeoPoint(
          lat: (row['lat'] as num).toDouble(),
          lon: (row['lon'] as num).toDouble(),
        ),
    ];
  }

  // ------------------------------------------------------------- mapowanie

  Map<String, Object?> _rideToRow(RecordedRide ride) => {
    'id': ride.id,
    'name': ride.name,
    'started_at': ride.startedAt.millisecondsSinceEpoch,
    'ended_at': ride.endedAt.millisecondsSinceEpoch,
    'elapsed_seconds': ride.elapsedSeconds,
    'moving_seconds': ride.movingSeconds,
    'auto_paused_seconds': ride.autoPausedSeconds,
    'manual_paused_seconds': ride.manualPausedSeconds,
    'distance_meters': ride.distanceMeters,
    'ascent_meters': ride.elevationGainMeters,
    'descent_meters': ride.elevationLossMeters,
    'max_speed_kmh': ride.maxSpeedKmh,
    'avg_heart_rate': ride.averageHeartRate,
    'max_heart_rate': ride.maxHeartRate,
    'avg_power': ride.averagePower,
    'max_power': ride.maxPower,
    'normalized_power': ride.normalizedPower,
    'intensity_factor': ride.intensityFactor,
    'tss': ride.trainingStressScore,
    'avg_cadence': ride.averageCadence,
    'calories': ride.calories,
    'route_id': ride.routeId,
    'route_name': ride.routeName,
    'rider_name': ride.riderName,
    'bike_id': ride.bikeId,
    'sync_status': ride.syncStatus.name,
    'health_exported': ride.healthExported ? 1 : 0,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  };

  RecordedRide _rideFromRow(
    Map<String, Object?> row,
    List<RecordedRidePoint> points,
  ) => RecordedRide(
    id: row['id']! as String,
    name: row['name']! as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['started_at']! as num).toInt(),
    ),
    endedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['ended_at']! as num).toInt(),
    ),
    elapsedSeconds: (row['elapsed_seconds'] as num?)?.toInt() ?? 0,
    movingSeconds: (row['moving_seconds'] as num?)?.toInt() ?? 0,
    autoPausedSeconds: (row['auto_paused_seconds'] as num?)?.toInt() ?? 0,
    manualPausedSeconds: (row['manual_paused_seconds'] as num?)?.toInt() ?? 0,
    distanceMeters: (row['distance_meters'] as num?)?.toDouble() ?? 0,
    elevationGainMeters: (row['ascent_meters'] as num?)?.toDouble() ?? 0,
    elevationLossMeters: (row['descent_meters'] as num?)?.toDouble() ?? 0,
    maxSpeedKmh: (row['max_speed_kmh'] as num?)?.toDouble() ?? 0,
    averageHeartRate: (row['avg_heart_rate'] as num?)?.toInt(),
    maxHeartRate: (row['max_heart_rate'] as num?)?.toInt(),
    averagePower: (row['avg_power'] as num?)?.toInt(),
    maxPower: (row['max_power'] as num?)?.toInt(),
    normalizedPower: (row['normalized_power'] as num?)?.toInt(),
    intensityFactor: (row['intensity_factor'] as num?)?.toDouble(),
    trainingStressScore: (row['tss'] as num?)?.toDouble(),
    averageCadence: (row['avg_cadence'] as num?)?.toInt(),
    calories: (row['calories'] as num?)?.toInt(),
    routeId: row['route_id'] as String?,
    routeName: row['route_name'] as String?,
    riderName: row['rider_name'] as String?,
    bikeId: row['bike_id'] as String?,
    syncStatus: SyncStatus.parse(row['sync_status'] as String?),
    healthExported: ((row['health_exported'] as num?)?.toInt() ?? 0) == 1,
    points: points,
  );

  Map<String, Object?> _pointToRow(
    String rideId,
    int seq,
    RecordedRidePoint point,
  ) => {
    'ride_id': rideId,
    'seq': seq,
    'lat': point.lat,
    'lon': point.lon,
    'elevation': point.altitude,
    'recorded_at': point.recordedAt.millisecondsSinceEpoch,
    'speed_mps': point.speedMps,
    'heart_rate': point.heartRate,
    'cadence': point.cadence,
    'power': point.power,
    'distance_meters': point.distanceMeters,
  };

  RecordedRidePoint _pointFromRow(Map<String, Object?> row) =>
      RecordedRidePoint(
        lat: (row['lat']! as num).toDouble(),
        lon: (row['lon']! as num).toDouble(),
        recordedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['recorded_at']! as num).toInt(),
        ),
        altitude: (row['elevation'] as num?)?.toDouble(),
        speedMps: (row['speed_mps'] as num?)?.toDouble() ?? 0,
        heartRate: (row['heart_rate'] as num?)?.toInt(),
        cadence: (row['cadence'] as num?)?.toInt(),
        power: (row['power'] as num?)?.toInt(),
        distanceMeters: (row['distance_meters'] as num?)?.toDouble() ?? 0,
      );
}

/// Zsumowane statystyki z bazy.
class RideTotals {
  const RideTotals({
    required this.rides,
    required this.distanceMeters,
    required this.movingSeconds,
    required this.elapsedSeconds,
    required this.ascentMeters,
    required this.maxSpeedKmh,
    required this.calories,
    this.averageHeartRate,
    this.averagePower,
  });

  final int rides;
  final double distanceMeters;
  final int movingSeconds;
  final int elapsedSeconds;
  final double ascentMeters;
  final double maxSpeedKmh;
  final int calories;
  final int? averageHeartRate;
  final int? averagePower;

  Duration get movingTime => Duration(seconds: movingSeconds);
  Duration get elapsedTime => Duration(seconds: elapsedSeconds);

  double get averageSpeedKmh =>
      movingSeconds <= 0 ? 0 : (distanceMeters / movingSeconds) * 3.6;

  bool get isEmpty => rides == 0;

  static const RideTotals empty = RideTotals(
    rides: 0,
    distanceMeters: 0,
    movingSeconds: 0,
    elapsedSeconds: 0,
    ascentMeters: 0,
    maxSpeedKmh: 0,
    calories: 0,
  );
}
