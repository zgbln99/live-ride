import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// Klucz–wartość dla ustawień, które nie zasługują na własną tabelę.
class SettingsDao {
  SettingsDao(this._database);

  final LiveRideDatabase _database;

  Future<String?> readString(String key) async {
    final db = await _database.open();
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeString(String key, String value) async {
    final db = await _database.open();
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> readJson(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Map<String, dynamic> value) =>
      writeString(key, jsonEncode(value));

  Future<void> remove(String key) async {
    final db = await _database.open();
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}

/// Kolejka rzeczy do wysłania, gdy wróci internet.
class SyncQueueDao {
  SyncQueueDao(this._database);

  final LiveRideDatabase _database;

  /// Ile wpisów maksymalnie trzymamy — telemetria z długiej jazdy bez
  /// zasięgu nie może rozsadzić bazy.
  static const int maxEntries = 5000;

  Future<void> enqueue({
    required String kind,
    required String target,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _database.open();
    await db.insert('sync_queue', {
      'kind': kind,
      'target': target,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_queue');
    final count = (rows.first['c'] as num?)?.toInt() ?? 0;
    if (count > maxEntries) {
      // Najstarsza telemetria jest najmniej warta: widz i tak chce wiedzieć,
      // gdzie zawodnik jest teraz.
      await db.rawDelete(
        'DELETE FROM sync_queue WHERE id IN ('
        'SELECT id FROM sync_queue ORDER BY created_at ASC LIMIT ?)',
        [count - maxEntries],
      );
    }
  }

  Future<List<QueuedItem>> take({String? kind, int limit = 50}) async {
    final db = await _database.open();
    final rows = await db.query(
      'sync_queue',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows
        .map((row) {
          Map<String, dynamic> payload;
          try {
            final decoded = jsonDecode(row['payload']! as String);
            payload = decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{};
          } catch (_) {
            payload = <String, dynamic>{};
          }
          return QueuedItem(
            id: (row['id']! as num).toInt(),
            kind: row['kind']! as String,
            target: row['target']! as String,
            payload: payload,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (row['created_at']! as num).toInt(),
            ),
            attempts: (row['attempts'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);
  }

  Future<void> remove(int id) async {
    final db = await _database.open();
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(int id, String error) async {
    final db = await _database.open();
    await db.rawUpdate(
      'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? '
      'WHERE id = ?',
      [error, id],
    );
  }

  Future<int> pendingCount({String? kind}) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_queue'
      '${kind == null ? '' : ' WHERE kind = ?'}',
      kind == null ? null : [kind],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> clear({String? kind}) async {
    final db = await _database.open();
    await db.delete(
      'sync_queue',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind],
    );
  }
}

/// Wpis w kolejce synchronizacji.
class QueuedItem {
  const QueuedItem({
    required this.id,
    required this.kind,
    required this.target,
    required this.payload,
    required this.createdAt,
    required this.attempts,
  });

  final int id;
  final String kind;
  final String target;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
}
