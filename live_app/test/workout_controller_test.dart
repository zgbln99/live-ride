import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/training.dart';
import 'package:live_ride/services/workout_controller.dart';

Workout _intervals() => Workout(
  id: 'w1',
  name: '4 × 4 min',
  createdAt: DateTime(2026, 1, 1),
  steps: const [
    WorkoutStep(
      kind: WorkoutStepKind.warmUp,
      name: 'Rozgrzewka',
      duration: Duration(minutes: 10),
    ),
    WorkoutStep(
      kind: WorkoutStepKind.work,
      name: 'Interwał',
      duration: Duration(minutes: 4),
      target: WorkoutTarget.power,
      targetLow: 280,
      targetHigh: 320,
    ),
    WorkoutStep(
      kind: WorkoutStepKind.recovery,
      name: 'Odpoczynek',
      duration: Duration(minutes: 4),
    ),
  ],
);

void main() {
  group('krok treningu', () {
    const step = WorkoutStep(
      kind: WorkoutStepKind.work,
      duration: Duration(minutes: 4),
      target: WorkoutTarget.power,
      targetLow: 280,
      targetHigh: 320,
    );

    test('bez wartości nie ocenia', () {
      expect(step.isOnTarget(null), isTrue);
      expect(step.deviation(null), isNull);
    });

    test('rozpoznaje za nisko i za wysoko', () {
      expect(step.deviation(250), -1);
      expect(step.deviation(300), isNull);
      expect(step.deviation(340), 1);
    });

    test('krok bez celu nigdy nie jest poza normą', () {
      const free = WorkoutStep(kind: WorkoutStepKind.recovery);
      expect(free.hasTarget, isFalse);
      expect(free.deviation(0), isNull);
      expect(free.targetLabel, isEmpty);
    });

    test('etykieta celu ma jednostkę', () {
      expect(step.targetLabel, '280–320 W');
      expect(
        const WorkoutStep(
          kind: WorkoutStepKind.work,
          target: WorkoutTarget.heartRate,
          targetLow: 150,
        ).targetLabel,
        '150 bpm',
      );
    });
  });

  group('WorkoutController', () {
    late WorkoutController controller;

    setUp(() => controller = WorkoutController());

    test('bez treningu nic nie raportuje', () {
      expect(
        controller.update(elapsed: Duration.zero, distanceMeters: 0),
        isNull,
      );
      expect(controller.isRunning, isFalse);
    });

    test('pusty trening się nie uruchamia', () {
      controller.start(
        Workout(
          id: 'x',
          name: 'Pusty',
          steps: const [],
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      expect(controller.isRunning, isFalse);
    });

    test('zaczyna od pierwszego kroku', () {
      controller.start(_intervals());
      final progress = controller.update(
        elapsed: const Duration(seconds: 30),
        distanceMeters: 200,
      )!;
      expect(progress.stepIndex, 0);
      expect(progress.step.name, 'Rozgrzewka');
      expect(progress.remaining, const Duration(minutes: 9, seconds: 30));
      expect(progress.fraction, closeTo(0.05, 0.01));
      expect(progress.nextStep!.name, 'Interwał');
    });

    test('przechodzi dalej, gdy krok się kończy', () {
      controller.start(_intervals());
      controller.update(
        elapsed: const Duration(minutes: 9),
        distanceMeters: 4000,
      );
      controller.update(
        elapsed: const Duration(minutes: 10),
        distanceMeters: 4500,
      );
      final progress = controller.update(
        elapsed: const Duration(minutes: 10, seconds: 30),
        distanceMeters: 4700,
      )!;
      expect(progress.stepIndex, 1);
      expect(progress.step.name, 'Interwał');
      // Czas kroku liczy się od jego początku, nie od startu jazdy.
      expect(progress.stepElapsed, const Duration(seconds: 30));
    });

    test('bez miernika mocy nie ocenia interwału mocy', () {
      controller.start(_intervals());
      controller.skipStep();
      for (var i = 0; i < 20; i++) {
        controller.update(
          elapsed: Duration(seconds: i),
          distanceMeters: i * 8.0,
        );
      }
      expect(controller.progress!.deviation, isNull);
      expect(controller.takeDeviationAlert(), isNull);
    });

    test('odzywa się dopiero po kilku próbkach poza celem', () {
      controller.start(_intervals());
      controller.skipStep();
      for (var i = 0; i < WorkoutController.deviationSamples - 1; i++) {
        controller.update(
          elapsed: Duration(seconds: i),
          distanceMeters: 0,
          powerWatts: 200,
        );
      }
      expect(controller.takeDeviationAlert(), isNull);

      controller.update(
        elapsed: const Duration(seconds: 10),
        distanceMeters: 0,
        powerWatts: 200,
      );
      expect(controller.takeDeviationAlert(), -1);
      // Odczytanie kasuje alert, żeby nie powtarzał się co sekundę.
      expect(controller.takeDeviationAlert(), isNull);
    });

    test('powrót do celu zeruje licznik odchyleń', () {
      controller.start(_intervals());
      controller.skipStep();
      for (var i = 0; i < 4; i++) {
        controller.update(
          elapsed: Duration(seconds: i),
          distanceMeters: 0,
          powerWatts: 200,
        );
      }
      controller.update(
        elapsed: const Duration(seconds: 5),
        distanceMeters: 0,
        powerWatts: 300,
      );
      for (var i = 6; i < 9; i++) {
        controller.update(
          elapsed: Duration(seconds: i),
          distanceMeters: 0,
          powerWatts: 200,
        );
      }
      expect(controller.takeDeviationAlert(), isNull);
    });

    test('krok dystansowy kończy się na dystansie', () {
      controller.start(
        Workout(
          id: 'w2',
          name: 'Na dystans',
          createdAt: DateTime(2026, 1, 1),
          steps: const [
            WorkoutStep(kind: WorkoutStepKind.work, distanceMeters: 1000),
            WorkoutStep(kind: WorkoutStepKind.recovery, distanceMeters: 500),
          ],
        ),
      );
      final progress = controller.update(
        elapsed: const Duration(minutes: 1),
        distanceMeters: 400,
      )!;
      expect(progress.stepIndex, 0);
      expect(progress.remainingMeters, 600);

      final advanced = controller.update(
        elapsed: const Duration(minutes: 3),
        distanceMeters: 1100,
      )!;
      expect(advanced.stepIndex, 1);
      expect(advanced.stepDistanceMeters, 0);
    });

    test('ostatni krok kończy trening', () {
      controller.start(_intervals());
      controller.skipStep();
      controller.skipStep();
      expect(controller.progress?.stepIndex ?? 2, 2);
      controller.skipStep();
      expect(controller.isRunning, isFalse);
      expect(controller.progress, isNull);
    });

    test('da się cofnąć do poprzedniego kroku', () {
      controller.start(_intervals());
      controller.skipStep();
      controller.update(elapsed: const Duration(seconds: 5), distanceMeters: 0);
      expect(controller.progress!.stepIndex, 1);
      controller.previousStep();
      controller.update(
        elapsed: const Duration(seconds: 10),
        distanceMeters: 0,
      );
      expect(controller.progress!.stepIndex, 0);
    });
  });
}
