import 'package:flutter/foundation.dart';

import '../data/workout_dao.dart';
import '../models/training.dart';
import 'local_store.dart';

/// Biblioteka treningów zawodnika.
class WorkoutService extends ChangeNotifier {
  WorkoutService(this._dao);

  final WorkoutDao _dao;

  List<Workout> _workouts = const [];
  bool _loaded = false;

  List<Workout> get workouts => List.unmodifiable(_workouts);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _workouts = await _dao.list();
    _loaded = true;
    notifyListeners();
  }

  Future<Workout> save(Workout workout) async {
    await _dao.save(workout);
    await load();
    return workout;
  }

  Future<void> delete(String id) async {
    await _dao.delete(id);
    await load();
  }

  /// Zakłada gotowe treningi na pustej bibliotece.
  ///
  /// Cele są w procentach FTP, a nie w watach, bo wat oznacza coś innego dla
  /// każdego zawodnika. Bez FTP w profilu krok po prostu nie ocenia.
  Future<void> seedDefaults({int? ftpWatts}) async {
    if (_workouts.isNotEmpty) return;
    for (final workout in defaults(ftpWatts: ftpWatts)) {
      await _dao.save(workout);
    }
    await load();
  }

  @visibleForTesting
  static List<Workout> defaults({int? ftpWatts}) {
    double? at(double fraction) =>
        ftpWatts == null ? null : ftpWatts * fraction;

    final now = DateTime.now();
    return [
      Workout(
        id: newLocalId('workout'),
        name: '4 × 4 min VO2 max',
        description: 'Klasyka na moc tlenową.',
        createdAt: now,
        steps: [
          const WorkoutStep(
            kind: WorkoutStepKind.warmUp,
            name: 'Rozgrzewka',
            duration: Duration(minutes: 15),
          ),
          for (var i = 0; i < 4; i++) ...[
            WorkoutStep(
              kind: WorkoutStepKind.work,
              name: 'Interwał ${i + 1}',
              duration: const Duration(minutes: 4),
              target: WorkoutTarget.power,
              targetLow: at(1.06),
              targetHigh: at(1.20),
            ),
            const WorkoutStep(
              kind: WorkoutStepKind.recovery,
              name: 'Odpoczynek',
              duration: Duration(minutes: 4),
            ),
          ],
          const WorkoutStep(
            kind: WorkoutStepKind.coolDown,
            name: 'Schłodzenie',
            duration: Duration(minutes: 10),
          ),
        ],
      ),
      Workout(
        id: newLocalId('workout'),
        name: '2 × 20 min próg',
        description: 'Podstawa wytrzymałości progowej.',
        createdAt: now,
        steps: [
          const WorkoutStep(
            kind: WorkoutStepKind.warmUp,
            name: 'Rozgrzewka',
            duration: Duration(minutes: 15),
          ),
          for (var i = 0; i < 2; i++) ...[
            WorkoutStep(
              kind: WorkoutStepKind.work,
              name: 'Próg ${i + 1}',
              duration: const Duration(minutes: 20),
              target: WorkoutTarget.power,
              targetLow: at(0.92),
              targetHigh: at(1.02),
            ),
            const WorkoutStep(
              kind: WorkoutStepKind.recovery,
              name: 'Odpoczynek',
              duration: Duration(minutes: 8),
            ),
          ],
          const WorkoutStep(
            kind: WorkoutStepKind.coolDown,
            name: 'Schłodzenie',
            duration: Duration(minutes: 10),
          ),
        ],
      ),
      Workout(
        id: newLocalId('workout'),
        name: 'Kadencja 3 × 8 min',
        description: 'Wysoka kadencja bez wysokiej mocy.',
        createdAt: now,
        steps: [
          const WorkoutStep(
            kind: WorkoutStepKind.warmUp,
            name: 'Rozgrzewka',
            duration: Duration(minutes: 10),
          ),
          for (var i = 0; i < 3; i++) ...[
            const WorkoutStep(
              kind: WorkoutStepKind.work,
              name: 'Wysoka kadencja',
              duration: Duration(minutes: 8),
              target: WorkoutTarget.cadence,
              targetLow: 95,
              targetHigh: 110,
            ),
            const WorkoutStep(
              kind: WorkoutStepKind.recovery,
              name: 'Swobodnie',
              duration: Duration(minutes: 4),
            ),
          ],
          const WorkoutStep(
            kind: WorkoutStepKind.coolDown,
            name: 'Schłodzenie',
            duration: Duration(minutes: 8),
          ),
        ],
      ),
    ];
  }
}
