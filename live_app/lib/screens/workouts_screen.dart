import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/training.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Biblioteka treningów.
class WorkoutsScreen extends StatelessWidget {
  const WorkoutsScreen({super.key, this.onStart});

  /// Podane, gdy ekran otwiera się z jazdy — wtedy wybór kroku uruchamia
  /// trening zamiast tylko go pokazywać.
  final void Function(Workout workout)? onStart;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final profile = services.profile.profile;

    return AnimatedBuilder(
      animation: services.workouts,
      builder: (context, _) {
        final workouts = services.workouts.workouts;
        return Scaffold(
          appBar: AppBar(title: Text(S.workouts)),
          body: workouts.isEmpty
              ? LrEmptyState(
                  icon: Icons.fitness_center,
                  title: S.noWorkouts,
                  message: S.noWorkoutsMessage,
                  action: FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(S.addDefaultWorkouts),
                    onPressed: () => services.workouts.seedDefaults(
                      ftpWatts: profile.ftpWatts,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    if (profile.ftpWatts == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LrPanel(
                          child: Text(
                            S.workoutNeedsFtp,
                            style: LR.body.copyWith(fontSize: 12.5),
                          ),
                        ),
                      ),
                    for (final workout in workouts) ...[
                      _WorkoutCard(workout: workout, onStart: onStart),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout, required this.onStart});

  final Workout workout;
  final void Function(Workout workout)? onStart;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return LrPanel(
      padding: EdgeInsets.zero,
      onTap: onStart == null
          ? null
          : () {
              onStart!(workout);
              Navigator.of(context).pop();
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(workout.name, style: LR.fieldValue(16)),
            subtitle: Text(
              workout.description.isEmpty
                  ? workout.summary
                  : '${workout.summary} · ${workout.description}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  services.workouts.delete(workout.id);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'delete', child: Text(S.delete)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.steps, style: LR.fieldLabel),
                const SizedBox(height: 6),
                // Pasek kroków: szerokość proporcjonalna do czasu, kolor
                // mówi o rodzaju. Jeden rzut oka wystarcza, żeby zobaczyć
                // kształt treningu.
                SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      for (final step in workout.steps)
                        Expanded(
                          flex: (step.duration?.inSeconds ?? 60).clamp(
                            30,
                            3600,
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(right: 1),
                            color: switch (step.kind) {
                              WorkoutStepKind.work => LR.alert,
                              WorkoutStepKind.recovery => LR.go,
                              WorkoutStepKind.rest => LR.muted,
                              _ => LR.accentDeep,
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${Fmt.durationCompact(workout.totalDuration)} · '
                  '${workout.steps.length} ${S.steps.toLowerCase()}',
                  style: LR.body.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
