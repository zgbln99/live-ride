import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/geo.dart';
import '../models/ride_route.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';
import 'database.dart';

/// Dostęp do tras w bazie.
class RouteDao {
  RouteDao(this._database);

  final LiveRideDatabase _database;

  static const int _insertChunk = 800;

  Future<void> save(RideRoute route) async {
    final db = await _database.open();
    final summary = route.toSummary();
    await db.transaction((txn) async {
      await txn.insert('routes', {
        'id': route.id,
        'name': route.name,
        'description': route.description,
        'tags': jsonEncode(route.tags),
        'distance_meters': summary.distanceMeters,
        'ascent_meters': summary.ascentMeters,
        'descent_meters': summary.descentMeters,
        'point_count': route.points.length,
        'shape': summary.shape.name,
        'source': route.source.name,
        'privacy': route.privacy.name,
        'share_token': route.shareToken,
        'preferences': jsonEncode(route.preferences.toJson()),
        'preview': jsonEncode([
          for (final point in summary.preview) [point.lat, point.lon],
        ]),
        'created_at': route.createdAt.millisecondsSinceEpoch,
        'updated_at': route.updatedAt.millisecondsSinceEpoch,
        'last_used_at': route.lastUsedAt?.millisecondsSinceEpoch,
        'sync_status': route.syncStatus.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'route_points',
        where: 'route_id = ?',
        whereArgs: [route.id],
      );
      for (var start = 0; start < route.points.length; start += _insertChunk) {
        final batch = txn.batch();
        final end = (start + _insertChunk).clamp(0, route.points.length);
        for (var i = start; i < end; i++) {
          final point = route.points[i];
          batch.insert('route_points', {
            'route_id': route.id,
            'seq': i,
            'lat': point.lat,
            'lon': point.lon,
            'elevation': point.elevation,
          });
        }
        await batch.commit(noResult: true);
      }

      await txn.delete(
        'route_waypoints',
        where: 'route_id = ?',
        whereArgs: [route.id],
      );
      final waypointBatch = txn.batch();
      for (var i = 0; i < route.waypoints.length; i++) {
        final waypoint = route.waypoints[i];
        waypointBatch.insert('route_waypoints', {
          'route_id': route.id,
          'seq': i,
          'lat': waypoint.lat,
          'lon': waypoint.lon,
          'name': waypoint.name,
          'kind': waypoint.kind.name,
        });
      }
      await waypointBatch.commit(noResult: true);
    });
  }

  Future<List<RouteSummary>> listSummaries({String? query}) async {
    final db = await _database.open();
    final rows = await db.query(
      'routes',
      where: query == null || query.trim().isEmpty
          ? null
          : 'LOWER(name) LIKE ? OR LOWER(description) LIKE ?',
      whereArgs: query == null || query.trim().isEmpty
          ? null
          : ['%${query.toLowerCase()}%', '%${query.toLowerCase()}%'],
      orderBy: 'COALESCE(last_used_at, updated_at) DESC',
    );
    return rows.map(_summaryFromRow).toList(growable: false);
  }

  Future<RouteSummary?> findSummary(String id) async {
    final db = await _database.open();
    final rows = await db.query(
      'routes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _summaryFromRow(rows.first);
  }

  Future<RideRoute?> load(String id) async {
    final db = await _database.open();
    final rows = await db.query(
      'routes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;

    final pointRows = await db.query(
      'route_points',
      where: 'route_id = ?',
      whereArgs: [id],
      orderBy: 'seq ASC',
    );
    final waypointRows = await db.query(
      'route_waypoints',
      where: 'route_id = ?',
      whereArgs: [id],
      orderBy: 'seq ASC',
    );

    return RideRoute(
      id: id,
      name: row['name']! as String,
      description: row['description'] as String? ?? '',
      tags: _decodeTags(row['tags'] as String?),
      points: [
        for (final point in pointRows)
          GeoPoint(
            lat: (point['lat']! as num).toDouble(),
            lon: (point['lon']! as num).toDouble(),
            elevation: (point['elevation'] as num?)?.toDouble(),
          ),
      ],
      waypoints: [
        for (final waypoint in waypointRows)
          RouteWaypoint(
            point: GeoPoint(
              lat: (waypoint['lat']! as num).toDouble(),
              lon: (waypoint['lon']! as num).toDouble(),
            ),
            name: waypoint['name'] as String? ?? '',
            kind: WaypointKind.parse(waypoint['kind'] as String?),
          ),
      ],
      preferences: _decodePreferences(row['preferences'] as String?),
      privacy: RoutePrivacy.parse(row['privacy'] as String?),
      source: RouteSource.parse(row['source'] as String?),
      shareToken: row['share_token'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at']! as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at']! as num).toInt(),
      ),
      lastUsedAt: row['last_used_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (row['last_used_at']! as num).toInt(),
            ),
      syncStatus: SyncStatus.parse(row['sync_status'] as String?),
    );
  }

  Future<void> rename(String id, String name) async {
    final db = await _database.open();
    await db.update(
      'routes',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markUsed(String id) async {
    final db = await _database.open();
    await db.update(
      'routes',
      {'last_used_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Trasy czekające na wysłanie na serwer.
  Future<List<RouteSummary>> pendingSync() async {
    final db = await _database.open();
    final rows = await db.query(
      'routes',
      where: 'sync_status IN (?, ?)',
      whereArgs: [SyncStatus.local.name, SyncStatus.pending.name],
      orderBy: 'updated_at ASC',
    );
    return [for (final row in rows) _summaryFromRow(row)];
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await _database.open();
    await db.update(
      'routes',
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setSharing({
    required String id,
    required RoutePrivacy privacy,
    String? shareToken,
  }) async {
    final db = await _database.open();
    await db.update(
      'routes',
      {
        'privacy': privacy.name,
        'share_token': shareToken,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database.open();
    await db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _database.open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM routes');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  // --------------------------------------------------------------- szkice

  Future<void> saveDraft(String id, Map<String, dynamic> payload) async {
    final db = await _database.open();
    await db.insert('route_drafts', {
      'id': id,
      'payload': jsonEncode(payload),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> loadDraft(String id) async {
    final db = await _database.open();
    final rows = await db.query(
      'route_drafts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['payload']! as String);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteDraft(String id) async {
    final db = await _database.open();
    await db.delete('route_drafts', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------- mapowanie

  RouteSummary _summaryFromRow(Map<String, Object?> row) => RouteSummary(
    id: row['id']! as String,
    name: row['name']! as String,
    description: row['description'] as String? ?? '',
    tags: _decodeTags(row['tags'] as String?),
    distanceMeters: (row['distance_meters'] as num?)?.toDouble() ?? 0,
    ascentMeters: (row['ascent_meters'] as num?)?.toDouble() ?? 0,
    descentMeters: (row['descent_meters'] as num?)?.toDouble() ?? 0,
    pointCount: (row['point_count'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at']! as num).toInt(),
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['updated_at']! as num).toInt(),
    ),
    lastUsedAt: row['last_used_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (row['last_used_at']! as num).toInt(),
          ),
    preview: _decodePreview(row['preview'] as String?),
    source: RouteSource.parse(row['source'] as String?),
    privacy: RoutePrivacy.parse(row['privacy'] as String?),
    shareToken: row['share_token'] as String?,
    shape: RouteShape.parse(row['shape'] as String?),
    preferences: _decodePreferences(row['preferences'] as String?),
    syncStatus: SyncStatus.parse(row['sync_status'] as String?),
  );

  List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.whereType<String>().toList(growable: false)
          : const [];
    } catch (_) {
      return const [];
    }
  }

  List<GeoPoint> _decodePreview(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is List && entry.length >= 2)
            GeoPoint(
              lat: (entry[0] as num).toDouble(),
              lon: (entry[1] as num).toDouble(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  RoutePreferences _decodePreferences(String? raw) {
    if (raw == null || raw.isEmpty) return const RoutePreferences();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? RoutePreferences.fromJson(Map<String, dynamic>.from(decoded))
          : const RoutePreferences();
    } catch (_) {
      return const RoutePreferences();
    }
  }
}
