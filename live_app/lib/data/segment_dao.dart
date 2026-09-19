import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/geo.dart';
import '../models/segment.dart';
import 'database.dart';

/// Segmenty i próby w bazie.
class SegmentDao {
  SegmentDao(this._database);

  final LiveRideDatabase _database;

  Future<List<Segment>> listSegments() async {
    final db = await _database.open();
    final rows = await db.query('segments', orderBy: 'created_at DESC');
    return [for (final row in rows) _segmentFromRow(row)];
  }

  Future<void> saveSegment(Segment segment) async {
    final db = await _database.open();
    await db.insert('segments', {
      'id': segment.id,
      'name': segment.name,
      'distance_meters': segment.distanceMeters,
      'ascent_meters': segment.ascentMeters,
      'avg_gradient': segment.averageGradientPercent,
      'points': jsonEncode([
        for (final point in segment.points)
          [point.lat, point.lon, point.elevation],
      ]),
      'source_route_id': segment.sourceRouteId,
      'created_at': segment.createdAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSegment(String id) async {
    final db = await _database.open();
    await db.delete('segments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> rename(String id, String name) async {
    final db = await _database.open();
    await db.update(
      'segments',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --------------------------------------------------------------- próby

  Future<List<SegmentAttempt>> attempts(String segmentId) async {
    final db = await _database.open();
    final rows = await db.query(
      'segment_attempts',
      where: 'segment_id = ?',
      whereArgs: [segmentId],
      orderBy: 'duration_seconds ASC',
    );
    return [for (final row in rows) _attemptFromRow(row)];
  }

  Future<void> saveAttempt(SegmentAttempt attempt) async {
    final db = await _database.open();
    await db.insert('segment_attempts', {
      'id': attempt.id,
      'segment_id': attempt.segmentId,
      'ride_id': attempt.rideId,
      'started_at': attempt.startedAt.millisecondsSinceEpoch,
      'duration_seconds': attempt.duration.inSeconds,
      'avg_speed_kmh': attempt.averageSpeedKmh,
      'avg_heart_rate': attempt.averageHeartRate,
      'avg_power': attempt.averagePower,
      'avg_cadence': attempt.averageCadence,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Najlepszy czas na każdym segmencie, jednym zapytaniem.
  ///
  /// Rekordy trzeba znać przed startem jazdy, żeby delta na ekranie pojawiła
  /// się od pierwszego metra — wczytywanie ich po kolei przy wjeździe byłoby
  /// za późno.
  Future<Map<String, Duration>> personalBests() async {
    final db = await _database.open();
    final rows = await db.rawQuery('''
      SELECT segment_id, MIN(duration_seconds) AS best
      FROM segment_attempts
      GROUP BY segment_id
    ''');
    return {
      for (final row in rows)
        '${row['segment_id']}': Duration(
          seconds: (row['best'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  // ------------------------------------------------------------- mapowanie

  Segment _segmentFromRow(Map<String, Object?> row) {
    final raw = jsonDecode('${row['points']}');
    final points = <GeoPoint>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! List || entry.length < 2) continue;
        points.add(
          GeoPoint(
            lat: (entry[0] as num).toDouble(),
            lon: (entry[1] as num).toDouble(),
            elevation: entry.length > 2 && entry[2] != null
                ? (entry[2] as num).toDouble()
                : null,
          ),
        );
      }
    }
    return Segment(
      id: '${row['id']}',
      name: '${row['name']}',
      points: points,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num?)?.toInt() ?? 0,
      ),
      sourceRouteId: row['source_route_id'] as String?,
    );
  }

  SegmentAttempt _attemptFromRow(Map<String, Object?> row) => SegmentAttempt(
    id: '${row['id']}',
    segmentId: '${row['segment_id']}',
    rideId: row['ride_id'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['started_at'] as num?)?.toInt() ?? 0,
    ),
    duration: Duration(
      seconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
    ),
    averageSpeedKmh: (row['avg_speed_kmh'] as num?)?.toDouble() ?? 0,
    averageHeartRate: (row['avg_heart_rate'] as num?)?.toInt(),
    averagePower: (row['avg_power'] as num?)?.toInt(),
    averageCadence: (row['avg_cadence'] as num?)?.toInt(),
  );
}
