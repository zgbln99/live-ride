import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/segment.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import '../widgets/track_preview.dart';

/// Lista segmentów z rekordami i próbami.
class SegmentsScreen extends StatelessWidget {
  const SegmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).segments;
    final metric = AppServices.of(context).profile.profile.metricUnits;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(S.segments)),
        body: service.segments.isEmpty
            ? LrEmptyState(
                icon: Icons.timer_outlined,
                title: S.noSegments,
                message: S.noSegmentsMessage,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: service.segments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final segment = service.segments[index];
                  return _SegmentCard(
                    segment: segment,
                    best: service.bestFor(segment.id),
                    metric: metric,
                  );
                },
              ),
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({
    required this.segment,
    required this.best,
    required this.metric,
  });

  final Segment segment;
  final Duration? best;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).segments;
    return LrPanel(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SegmentDetailScreen(segment: segment),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 48,
              child: TrackPreview(points: segment.points, strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LR.fieldValue(16),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${Fmt.distance(segment.distanceMeters, metric: metric)} '
                    '${Fmt.distanceUnit(metric: metric)} · '
                    '${segment.averageGradientPercent.toStringAsFixed(1)} % · '
                    '+${Fmt.elevation(segment.ascentMeters, metric: metric)} '
                    '${Fmt.elevationUnit(metric: metric)}',
                    style: LR.body.copyWith(fontSize: 12),
                  ),
                  if (best != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 13,
                          color: LR.accentDeep,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${S.personalBest}: ${Fmt.duration(best!)}',
                          style: LR.fieldLabel.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') await service.delete(segment.id);
                if (value == 'rename' && context.mounted) {
                  await _rename(context, segment);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(S.rename)),
                PopupMenuItem(value: 'delete', child: Text(S.delete)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, Segment segment) async {
    final service = AppServices.of(context).segments;
    final controller = TextEditingController(text: segment.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.segmentName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(S.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await service.rename(segment.id, name.trim());
  }
}

/// Szczegóły segmentu: profil i lista prób.
class SegmentDetailScreen extends StatefulWidget {
  const SegmentDetailScreen({super.key, required this.segment});

  final Segment segment;

  @override
  State<SegmentDetailScreen> createState() => _SegmentDetailScreenState();
}

class _SegmentDetailScreenState extends State<SegmentDetailScreen> {
  List<SegmentAttempt> _attempts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final attempts = await AppServices.of(
      context,
    ).segments.attempts(widget.segment.id);
    if (!mounted) return;
    setState(() {
      _attempts = attempts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final metric = AppServices.of(context).profile.profile.metricUnits;
    final segment = widget.segment;

    return Scaffold(
      appBar: AppBar(title: Text(segment.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SizedBox(
            height: 140,
            child: TrackPreview(points: segment.points, strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LrStat(
                  label: S.distance,
                  value: Fmt.distance(segment.distanceMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 22,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.ascent,
                  value: Fmt.elevation(segment.ascentMeters, metric: metric),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 22,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: S.averageGradient,
                  value: segment.averageGradientPercent.toStringAsFixed(1),
                  unit: '%',
                  valueSize: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LrSectionHeader(
            title: S.attempts,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_attempts.isEmpty)
            Text(S.noAttempts, style: LR.body)
          else
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _attempts.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: i == 0
                          ? const Icon(
                              Icons.emoji_events,
                              color: LR.accentDeep,
                              size: 20,
                            )
                          : Text(
                              '${i + 1}',
                              style: LR.body.copyWith(fontSize: 13),
                            ),
                      title: Text(
                        Fmt.duration(_attempts[i].duration),
                        style: LR.fieldValue(16),
                      ),
                      subtitle: Text(
                        '${Fmt.date(_attempts[i].startedAt)} · '
                        '${Fmt.speed(_attempts[i].averageSpeedKmh, metric: metric)} '
                        '${Fmt.speedUnit(metric: metric)}',
                        style: LR.body.copyWith(fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
