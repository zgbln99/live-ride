import 'package:flutter/foundation.dart';

import '../models/training.dart';

/// Stan bieżącego kroku treningu.
class WorkoutProgress {
  const WorkoutProgress({
    required this.workout,
    required this.stepIndex,
    required this.step,
    required this.stepElapsed,
    required this.stepDistanceMeters,
    this.currentValue,
    this.deviation,
  });

  final Workout workout;
  final int stepIndex;
  final WorkoutStep step;
  final Duration stepElapsed;
  final double stepDistanceMeters;

  /// Wartość, którą krok mierzy (moc, tętno, kadencja albo prędkość).
  final num? currentValue;

  /// -1 za nisko, 1 za wysoko, null w normie albo bez celu.
  final int? deviation;

  bool get isLastStep => stepIndex >= workout.steps.length - 1;
  bool get isOnTarget => deviation == null;

  WorkoutStep? get nextStep => isLastStep ? null : workout.steps[stepIndex + 1];

  /// Ile zostało do końca kroku. Null, gdy krok nie ma limitu.
  Duration? get remaining {
    final duration = step.duration;
    if (duration == null) return null;
    final left = duration - stepElapsed;
    return left.isNegative ? Duration.zero : left;
  }

  double? get remainingMeters {
    final target = step.distanceMeters;
    if (target == null) return null;
    final left = target - stepDistanceMeters;
    return left < 0 ? 0 : left;
  }

  /// Postęp kroku w zakresie 0–1, po tym limicie, który krok ma.
  double get fraction {
    final duration = step.duration;
    if (duration != null && duration.inMilliseconds > 0) {
      return (stepElapsed.inMilliseconds / duration.inMilliseconds).clamp(
        0.0,
        1.0,
      );
    }
    final distance = step.distanceMeters;
    if (distance != null && distance > 0) {
      return (stepDistanceMeters / distance).clamp(0.0, 1.0);
    }
    return 0;
  }
}

/// Prowadzi zawodnika przez trening z krokami.
///
/// Kontroler nie zgaduje: krok bez limitu czasu i dystansu trwa, dopóki
/// zawodnik sam nie przejdzie dalej, a krok z celem, którego nie da się
/// zmierzyć (moc bez miernika), nie krzyczy, że jest źle — po prostu nie
/// ocenia.
class WorkoutController extends ChangeNotifier {
  Workout? _workout;
  int _stepIndex = 0;
  Duration _stepStartedAtElapsed = Duration.zero;
  double _stepStartedAtDistance = 0;
  WorkoutProgress? _progress;
  int? _lastDeviation;

  /// Ile razy z rzędu wartość musi być poza celem, zanim się odezwiemy.
  ///
  /// Jedna próbka to wyjście zza zakrętu, a nie odpuszczenie tempa.
  static const int deviationSamples = 5;
  int _deviationStreak = 0;

  Workout? get workout => _workout;
  WorkoutProgress? get progress => _progress;
  bool get isRunning => _workout != null;

  /// Ostatnie przekroczenie celu, o którym warto powiedzieć. Zerowane po
  /// odczytaniu, żeby powiadomienie nie powtarzało się w kółko.
  int? takeDeviationAlert() {
    final value = _lastDeviation;
    _lastDeviation = null;
    return value;
  }

  void start(
    Workout workout, {
    Duration elapsed = Duration.zero,
    double distanceMeters = 0,
  }) {
    if (workout.steps.isEmpty) return;
    _workout = workout;
    _stepIndex = 0;
    _stepStartedAtElapsed = elapsed;
    _stepStartedAtDistance = distanceMeters;
    _deviationStreak = 0;
    _lastDeviation = null;
    notifyListeners();
  }

  void stop() {
    _workout = null;
    _progress = null;
    _stepIndex = 0;
    _deviationStreak = 0;
    _lastDeviation = null;
    notifyListeners();
  }

  /// Ręczne przejście dalej — zawsze dostępne, bo plan treningu nie zna
  /// świateł ani korków.
  void skipStep({Duration elapsed = Duration.zero, double distanceMeters = 0}) {
    final workout = _workout;
    if (workout == null) return;
    if (_stepIndex >= workout.steps.length - 1) {
      stop();
      return;
    }
    _advance(elapsed, distanceMeters);
  }

  void previousStep({
    Duration elapsed = Duration.zero,
    double distanceMeters = 0,
  }) {
    if (_workout == null || _stepIndex == 0) return;
    _stepIndex--;
    _stepStartedAtElapsed = elapsed;
    _stepStartedAtDistance = distanceMeters;
    _deviationStreak = 0;
    notifyListeners();
  }

  /// Karmione raz na sekundę przez rejestrator.
  WorkoutProgress? update({
    required Duration elapsed,
    required double distanceMeters,
    int? powerWatts,
    int? heartRate,
    double? cadenceRpm,
    double? speedKmh,
  }) {
    final workout = _workout;
    if (workout == null) return null;
    if (_stepIndex >= workout.steps.length) {
      stop();
      return null;
    }

    final step = workout.steps[_stepIndex];
    final stepElapsed = elapsed - _stepStartedAtElapsed;
    final stepDistance = distanceMeters - _stepStartedAtDistance;

    final value = switch (step.target) {
      WorkoutTarget.power => powerWatts,
      WorkoutTarget.heartRate => heartRate,
      WorkoutTarget.cadence => cadenceRpm,
      WorkoutTarget.speed => speedKmh,
      WorkoutTarget.none => null,
    };

    final deviation = step.deviation(value);
    if (deviation == null) {
      _deviationStreak = 0;
    } else {
      _deviationStreak++;
      if (_deviationStreak == deviationSamples) _lastDeviation = deviation;
    }

    _progress = WorkoutProgress(
      workout: workout,
      stepIndex: _stepIndex,
      step: step,
      stepElapsed: stepElapsed.isNegative ? Duration.zero : stepElapsed,
      stepDistanceMeters: stepDistance < 0 ? 0 : stepDistance,
      currentValue: value,
      deviation: deviation,
    );

    final duration = step.duration;
    final distanceTarget = step.distanceMeters;
    final timeDone = duration != null && stepElapsed >= duration;
    final distanceDone =
        distanceTarget != null && stepDistance >= distanceTarget;
    if (timeDone || distanceDone) {
      if (_stepIndex >= workout.steps.length - 1) {
        stop();
        return null;
      }
      _advance(elapsed, distanceMeters);
      // Po przejściu dalej stan musi już opisywać nowy krok. Zostawienie
      // poprzedniego pokazywałoby zawodnikowi krok, którego nie robi.
      _progress = WorkoutProgress(
        workout: workout,
        stepIndex: _stepIndex,
        step: workout.steps[_stepIndex],
        stepElapsed: Duration.zero,
        stepDistanceMeters: 0,
      );
      notifyListeners();
      return _progress;
    }

    notifyListeners();
    return _progress;
  }

  void _advance(Duration elapsed, double distanceMeters) {
    _stepIndex++;
    _stepStartedAtElapsed = elapsed;
    _stepStartedAtDistance = distanceMeters;
    _deviationStreak = 0;
    notifyListeners();
  }
}
