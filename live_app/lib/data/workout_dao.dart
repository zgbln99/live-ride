import 'package:sqflite/sqflite.dart';

import '../models/training.dart';
import 'database.dart';

/// Treningi z krokami w bazie.
class WorkoutDao {
  WorkoutDao(this._database);

  final LiveRideDatabase _database;

  Future<List<Workout>> list() async {
    final db = await _database.open();
    final rows = await db.query('workouts', orderBy: 'created_at DESC');
    final workouts = <Workout>[];
    for (final row in rows) {
      final id = '${row['id']}';
      workouts.add(
        Workout(
          id: id,
          name: '${row['name']}',
          description: row['description'] as String? ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (row['created_at'] as num?)?.toInt() ?? 0,
          ),
          steps: await _steps(db, id),
        ),
      );
    }
    return workouts;
  }

  Future<List<WorkoutStep>> _steps(
    DatabaseExecutor db,
    String workoutId,
  ) async {
    final rows = await db.query(
      'workout_steps',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'seq ASC',
    );
    return [
      for (final row in rows)
        WorkoutStep(
          kind: WorkoutStepKind.parse(row['kind'] as String?),
          name: row['name'] as String? ?? '',
          duration: row['duration_seconds'] == null
              ? null
              : Duration(seconds: (row['duration_seconds'] as num).toInt()),
          distanceMeters: (row['distance_meters'] as num?)?.toDouble(),
          target: WorkoutTarget.parse(row['target_kind'] as String?),
          targetLow: (row['target_low'] as num?)?.toDouble(),
          targetHigh: (row['target_high'] as num?)?.toDouble(),
        ),
    ];
  }

  /// Zapisuje trening razem z krokami.
  ///
  /// Kroki są przepisywane w całości, a nie łatane: numer kroku niesie
  /// kolejność, a częściowa aktualizacja potrafiłaby zostawić dziurę
  /// w środku treningu.
  Future<void> save(Workout workout) async {
    final db = await _database.open();
    await db.transaction((txn) async {
      await txn.insert('workouts', {
        'id': workout.id,
        'name': workout.name,
        'description': workout.description,
        'created_at': workout.createdAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'workout_steps',
        where: 'workout_id = ?',
        whereArgs: [workout.id],
      );

      final batch = txn.batch();
      for (var i = 0; i < workout.steps.length; i++) {
        final step = workout.steps[i];
        batch.insert('workout_steps', {
          'workout_id': workout.id,
          'seq': i,
          'kind': step.kind.name,
          'name': step.name,
          'duration_seconds': step.duration?.inSeconds,
          'distance_meters': step.distanceMeters,
          'target_kind': step.target.name,
          'target_low': step.targetLow,
          'target_high': step.targetHigh,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> delete(String id) async {
    final db = await _database.open();
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }
}
