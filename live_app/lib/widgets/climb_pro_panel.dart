import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/climb_tracker.dart';
import 'climb_profile.dart';

/// Panel podjazdu pokazywany nad mapą, gdy zawodnik jest na podjeździe.
///
/// Pokazuje trzy rzeczy, których się wtedy naprawdę chce: ile zostało,
/// ile w pionie i jak stromo jest teraz. Reszta czeka na szczyt.
class ClimbProPanel extends StatelessWidget {
  const ClimbProPanel({
    super.key,
    required this.progress,
    required this.profile,
    this.metric = true,
  });

  final ClimbProgress progress;
  final List<({double distance, double elevation})> profile;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final climb = progress.climb;
    final remaining = progress.estimatedRemaining;

    return Container(
      decoration: const BoxDecoration(
        color: LR.surface,
        border: Border(bottom: BorderSide(color: LR.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: LR.alert,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  climb.category.shortLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(S.climbInProgress, style: LR.fieldLabel),
              const Spacer(),
              if (remaining != null)
                Text(
                  '≈ ${Fmt.durationCompact(remaining)}',
                  style: LR.body.copyWith(fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClimbProfileChart(
            samples: profile,
            climbs: [climb],
            highlight: climb,
            positionMeters: progress.alongMeters,
            fromMeters: climb.startDistanceMeters - 150,
            toMeters: climb.endDistanceMeters + 150,
            height: 74,
            showAxis: false,
            metric: metric,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: S.remainingClimb,
                  value: Fmt.distance(progress.remainingMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                ),
              ),
              Expanded(
                child: _Cell(
                  label: S.remainingAscent,
                  value: Fmt.elevation(
                    progress.remainingGainMeters,
                    metric: metric,
                  ),
                  unit: Fmt.elevationUnit(metric: metric),
                ),
              ),
              Expanded(
                child: _Cell(
                  label: S.gradientNow,
                  value: progress.currentGradientPercent == null
                      ? S.notAvailable
                      : Fmt.gradient(progress.currentGradientPercent!),
                  unit: '%',
                  alert: (progress.currentGradientPercent ?? 0) >= 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    this.unit = '',
    this.alert = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool alert;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: LR.fieldLabel),
      const SizedBox(height: 2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: LR
                    .fieldValue(24)
                    .copyWith(color: alert ? LR.alert : LR.ink),
              ),
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(unit, style: LR.fieldUnit),
          ],
        ],
      ),
    ],
  );
}

/// Podsumowanie pokazywane zaraz po szczycie.
class ClimbResultCard extends StatelessWidget {
  const ClimbResultCard({
    super.key,
    required this.result,
    required this.onDismiss,
    this.metric = true,
  });

  final ClimbResult result;
  final VoidCallback onDismiss;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final vam = result.vam;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: LR.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LR.go, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag, color: LR.go),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.climbDone, style: LR.fieldLabel),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.durationCompact(result.duration)} · '
                  '${Fmt.distance(result.climb.lengthMeters, metric: metric)} '
                  '${Fmt.distanceUnit(metric: metric)} · '
                  '${result.climb.averageGradientPercent.toStringAsFixed(1)} %',
                  style: LR.fieldValue(16),
                ),
                if (vam != null || result.averagePowerWatts != null)
                  Text(
                    [
                      if (vam != null) 'VAM ${vam.round()} m/h',
                      if (result.averagePowerWatts != null)
                        '${result.averagePowerWatts} W',
                      if (result.averageHeartRate != null)
                        '${result.averageHeartRate} bpm',
                    ].join(' · '),
                    style: LR.body.copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
