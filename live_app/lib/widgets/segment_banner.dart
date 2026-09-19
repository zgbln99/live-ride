import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/pace_partner.dart';
import '../services/segment_matcher.dart';

/// Pasek segmentu w czasie jazdy: ile zostało i jak idzie wobec rekordu.
class SegmentBanner extends StatelessWidget {
  const SegmentBanner({super.key, required this.progress, this.metric = true});

  final SegmentProgress progress;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final delta = progress.deltaSeconds;
    final ahead = delta != null && delta < 0;
    final color = delta == null
        ? LR.accentDeep
        : ahead
        ? LR.go
        : LR.alert;

    return Container(
      decoration: BoxDecoration(
        color: LR.surface,
        border: Border(bottom: BorderSide(color: color, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  progress.segment.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LR.fieldLabel.copyWith(color: color),
                ),
              ),
              Text(Fmt.duration(progress.elapsed), style: LR.fieldValue(17)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 5,
                    backgroundColor: LR.line,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${Fmt.distance(progress.remainingMeters, metric: metric)} '
                '${Fmt.distanceUnit(metric: metric)}',
                style: LR.body.copyWith(fontSize: 12),
              ),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Text(
              ahead
                  ? S.aheadOfRecord(_seconds(delta))
                  : S.behindRecord(_seconds(delta)),
              style: LR.fieldValue(14).copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }

  static String _seconds(double delta) =>
      delta.abs().toStringAsFixed(delta.abs() < 10 ? 1 : 0);
}

/// Pasek wirtualnego rywala.
class PaceBanner extends StatelessWidget {
  const PaceBanner({
    super.key,
    required this.comparison,
    required this.label,
    this.metric = true,
  });

  final PaceComparison comparison;
  final String label;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final delta = comparison.timeDelta;
    final ahead = comparison.isAhead;
    final color = ahead ? LR.go : LR.alert;

    return Container(
      decoration: BoxDecoration(
        color: LR.surface,
        border: Border(bottom: BorderSide(color: color, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Icon(
            ahead ? Icons.trending_up : Icons.trending_down,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: LR.fieldLabel),
                Text(
                  delta == null
                      ? '${Fmt.distance(comparison.distanceDelta.abs(), metric: metric)} '
                            '${Fmt.distanceUnit(metric: metric)}'
                      : Fmt.duration(Duration(seconds: delta.inSeconds.abs())),
                  style: LR.fieldValue(18).copyWith(color: color),
                ),
              ],
            ),
          ),
          Text(
            ahead ? S.aheadShort : S.behindShort,
            style: LR.fieldLabel.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
