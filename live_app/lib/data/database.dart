import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Lokalna baza Live Ride.
///
/// Sezon jazdy to setki tysięcy punktów GPS — to jest powód, dla którego
/// przejazdy nie mogą mieszkać w plikach JSON. Schemat jest pisany ręcznie
/// (bez generatora), żeby migracje były czytelne i testowalne.
class LiveRideDatabase {
  LiveRideDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory,
      _path = path;

  static const String fileName = 'live_ride.db';

  /// Podbijaj przy każdej zmianie schematu i dopisuj krok w [_upgrade].
  static const int schemaVersion = 1;

  final DatabaseFactory? _factory;
  final String? _path;

  Database? _db;
  Completer<Database>? _opening;

  Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;
    final pending = _opening;
    if (pending != null) return pending.future;

    final completer = Completer<Database>();
    _opening = completer;
    try {
      final factory = _factory ?? databaseFactory;
      final path = _path ?? p.join(await factory.getDatabasesPath(), fileName);
      final database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => _create(db),
          onUpgrade: (db, from, to) => _upgrade(db, from, to),
        ),
      );
      _db = database;
      completer.complete(database);
      return database;
    } catch (error, stack) {
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _opening = null;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch();
    for (final statement in _schema) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    // Pierwsza wersja schematu; kolejne migracje dopisujemy tutaj krokami.
  }

  /// Pełny schemat wersji 1.
  static const List<String> _schema = [
    '''
    CREATE TABLE rides (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER NOT NULL,
      elapsed_seconds INTEGER NOT NULL DEFAULT 0,
      moving_seconds INTEGER NOT NULL DEFAULT 0,
      distance_meters REAL NOT NULL DEFAULT 0,
      ascent_meters REAL NOT NULL DEFAULT 0,
      descent_meters REAL NOT NULL DEFAULT 0,
      max_speed_kmh REAL NOT NULL DEFAULT 0,
      avg_heart_rate INTEGER,
      max_heart_rate INTEGER,
      avg_power INTEGER,
      max_power INTEGER,
      normalized_power INTEGER,
      intensity_factor REAL,
      tss REAL,
      avg_cadence INTEGER,
      calories INTEGER,
      route_id TEXT,
      route_name TEXT,
      rider_name TEXT,
      bike_id TEXT,
      sync_status TEXT NOT NULL DEFAULT 'local',
      health_exported INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_rides_started ON rides (started_at DESC)',
    'CREATE INDEX idx_rides_sync ON rides (sync_status)',
    '''
    CREATE TABLE ride_points (
      ride_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      lat REAL NOT NULL,
      lon REAL NOT NULL,
      elevation REAL,
      recorded_at INTEGER NOT NULL,
      speed_mps REAL NOT NULL DEFAULT 0,
      heart_rate INTEGER,
      cadence INTEGER,
      power INTEGER,
      distance_meters REAL NOT NULL DEFAULT 0,
      PRIMARY KEY (ride_id, seq),
      FOREIGN KEY (ride_id) REFERENCES rides (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE routes (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      tags TEXT NOT NULL DEFAULT '[]',
      distance_meters REAL NOT NULL DEFAULT 0,
      ascent_meters REAL NOT NULL DEFAULT 0,
      descent_meters REAL NOT NULL DEFAULT 0,
      point_count INTEGER NOT NULL DEFAULT 0,
      shape TEXT NOT NULL DEFAULT 'pointToPoint',
      source TEXT NOT NULL DEFAULT 'builder',
      privacy TEXT NOT NULL DEFAULT 'private',
      share_token TEXT,
      preferences TEXT NOT NULL DEFAULT '{}',
      preview TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_used_at INTEGER,
      sync_status TEXT NOT NULL DEFAULT 'local'
    )
    ''',
    'CREATE INDEX idx_routes_updated ON routes (updated_at DESC)',
    '''
    CREATE TABLE route_points (
      route_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      lat REAL NOT NULL,
      lon REAL NOT NULL,
      elevation REAL,
      PRIMARY KEY (route_id, seq),
      FOREIGN KEY (route_id) REFERENCES routes (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE route_waypoints (
      route_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      lat REAL NOT NULL,
      lon REAL NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      kind TEXT NOT NULL DEFAULT 'via',
      PRIMARY KEY (route_id, seq),
      FOREIGN KEY (route_id) REFERENCES routes (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE route_drafts (
      id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE segments (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      distance_meters REAL NOT NULL DEFAULT 0,
      ascent_meters REAL NOT NULL DEFAULT 0,
      avg_gradient REAL NOT NULL DEFAULT 0,
      points TEXT NOT NULL DEFAULT '[]',
      source_route_id TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE segment_attempts (
      id TEXT PRIMARY KEY,
      segment_id TEXT NOT NULL,
      ride_id TEXT,
      started_at INTEGER NOT NULL,
      duration_seconds INTEGER NOT NULL,
      avg_speed_kmh REAL NOT NULL DEFAULT 0,
      avg_heart_rate INTEGER,
      avg_power INTEGER,
      avg_cadence INTEGER,
      FOREIGN KEY (segment_id) REFERENCES segments (id) ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX idx_attempts_segment ON segment_attempts (segment_id, duration_seconds)',
    '''
    CREATE TABLE bikes (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'road',
      weight_kg REAL,
      wheel_circumference_mm INTEGER,
      photo_path TEXT,
      odometer_meters REAL NOT NULL DEFAULT 0,
      is_default INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE bike_components (
      id TEXT PRIMARY KEY,
      bike_id TEXT NOT NULL,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      installed_at INTEGER NOT NULL,
      odometer_at_install_meters REAL NOT NULL DEFAULT 0,
      limit_meters REAL,
      limit_days INTEGER,
      FOREIGN KEY (bike_id) REFERENCES bikes (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE sensors (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      bike_id TEXT,
      auto_connect INTEGER NOT NULL DEFAULT 1,
      last_seen_at INTEGER
    )
    ''',
    '''
    CREATE TABLE workouts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE workout_steps (
      workout_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      kind TEXT NOT NULL,
      duration_seconds INTEGER,
      distance_meters REAL,
      target_kind TEXT NOT NULL DEFAULT 'none',
      target_low REAL,
      target_high REAL,
      repeat_count INTEGER,
      PRIMARY KEY (workout_id, seq),
      FOREIGN KEY (workout_id) REFERENCES workouts (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      target TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
    ''',
    'CREATE INDEX idx_queue_kind ON sync_queue (kind, created_at)',
  ];
}

/// Status synchronizacji lokalnego rekordu.
enum SyncStatus {
  local,
  pending,
  synced,
  conflict;

  static SyncStatus parse(String? value) => SyncStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => SyncStatus.local,
  );
}
