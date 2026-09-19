import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/training.dart';
import '../services/workout_controller.dart';

/// Pasek treningu w czasie jazdy: co teraz, ile jeszcze i czy w celu.
class WorkoutBanner extends StatelessWidget {
  const WorkoutBanner({
    super.key,
    required this.progress,
    required this.onSkip,
    this.metric = true,
  });

  final WorkoutProgress progress;
  final VoidCallback onSkip;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final step = progress.step;
    final color = switch (progress.deviation) {
      null => _kindColor(step.kind),
      -1 => const Color(0xFFE07A1F),
      _ => LR.alert,
    };

    return Container(
      decoration: BoxDecoration(
        color: LR.surface,
        border: Border(bottom: BorderSide(color: color, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  step.kind.label.toUpperCase(),
                  style: LR.fieldLabel.copyWith(color: color, fontSize: 9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.name.isEmpty ? progress.workout.name : step.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LR.fieldValue(15),
                ),
              ),
              if (progress.remaining != null)
                Text(
                  Fmt.duration(progress.remaining!),
                  style: LR.fieldValue(18),
                )
              else if (progress.remainingMeters != null)
                Text(
                  '${Fmt.distance(progress.remainingMeters!, metric: metric)} '
                  '${Fmt.distanceUnit(metric: metric)}',
                  style: LR.fieldValue(18),
                ),
              IconButton(
                tooltip: S.skipStep,
                icon: const Icon(Icons.skip_next, size: 20),
                onPressed: onSkip,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 5,
              backgroundColor: LR.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (step.hasTarget) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Text(
                  '${S.target}: ${step.targetLabel}',
                  style: LR.body.copyWith(fontSize: 12),
                ),
                const Spacer(),
                Text(
                  progress.currentValue == null
                      ? S.noSensorForTarget
                      : switch (progress.deviation) {
                          null => S.onTarget,
                          -1 => S.pushHarder,
                          _ => S.easeOff,
                        },
                  style: LR
                      .fieldValue(13)
                      .copyWith(
                        color: progress.currentValue == null ? LR.muted : color,
                      ),
                ),
              ],
            ),
          ],
          if (progress.nextStep != null) ...[
            const SizedBox(height: 3),
            Text(
              '${S.nextStep}: ${progress.nextStep!.name}'
              '${progress.nextStep!.duration == null ? '' : ' · ${Fmt.durationCompact(progress.nextStep!.duration!)}'}',
              style: LR.body.copyWith(fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  static Color _kindColor(WorkoutStepKind kind) => switch (kind) {
    WorkoutStepKind.warmUp => LR.accentDeep,
    WorkoutStepKind.work => LR.alert,
    WorkoutStepKind.recovery => LR.go,
    WorkoutStepKind.coolDown => LR.accentDeep,
    WorkoutStepKind.rest => LR.muted,
  };
}
