import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../models/ride_record.dart';
import '../services/app_services.dart';
import '../widgets/elevation_profile.dart';
import '../widgets/lr_common.dart';
import '../widgets/track_preview.dart';

/// The ride report: what happened, where, and how it felt.
class RideSummaryScreen extends StatefulWidget {
  const RideSummaryScreen({
    super.key,
    required this.ride,
    this.justFinished = false,
  });

  final RecordedRide ride;

  /// True when the rider has just pressed Finish, which changes the primary
  /// action from "back" to "done".
  final bool justFinished;

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  late RecordedRide _ride = widget.ride;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final metric = services.profile.profile.metricUnits;
    final profile = _ride.elevationProfile();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RIDE SUMMARY'),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _busy ? null : _rename,
          ),
          IconButton(
            tooltip: 'Export GPX',
            icon: const Icon(Icons.ios_share),
            onPressed: _busy ? null : _export,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(_ride.name, style: LR.title.copyWith(fontSize: 26)),
          const SizedBox(height: 5),
          Text(
            [
              Fmt.dateTime(_ride.startedAt),
              if (_ride.riderName != null) _ride.riderName!,
              if (_ride.routeName != null) 'on ${_ride.routeName}',
            ].join(' · '),
            style: LR.body,
          ),
          const SizedBox(height: 18),
          if (_ride.hasTrack)
            LrPanel(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                height: 200,
                child: TrackPreview(
                  points: _ride.track,
                  strokeWidth: 3,
                  background: LR.surface,
                ),
              ),
            ),
          const SizedBox(height: 18),
          const LrSectionHeader(title: 'Ride'),
          LrPanel(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 28,
              runSpacing: 22,
              children: [
                LrStat(
                  label: 'Distance',
                  value: Fmt.distance(_ride.distanceMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 30,
                ),
                LrStat(
                  label: 'Moving',
                  value: Fmt.duration(_ride.movingTime),
                  valueSize: 30,
                ),
                LrStat(
                  label: 'Elapsed',
                  value: Fmt.duration(_ride.elapsed),
                  valueSize: 30,
                ),
                LrStat(
                  label: 'Avg speed',
                  value: Fmt.speed(_ride.averageSpeedKmh, metric: metric),
                  unit: Fmt.speedUnit(metric: metric),
                  valueSize: 30,
                ),
                LrStat(
                  label: 'Max speed',
                  value: Fmt.speed(_ride.maxSpeedKmh, metric: metric),
                  unit: Fmt.speedUnit(metric: metric),
                  valueSize: 30,
                ),
                LrStat(
                  label: 'Ascent',
                  value: Fmt.elevation(
                    _ride.elevationGainMeters,
                    metric: metric,
                  ),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 30,
                ),
                if (_ride.elevationLossMeters > 0)
                  LrStat(
                    label: 'Descent',
                    value: Fmt.elevation(
                      _ride.elevationLossMeters,
                      metric: metric,
                    ),
                    unit: Fmt.elevationUnit(metric: metric),
                    valueSize: 30,
                  ),
                if (_ride.averageHeartRate != null)
                  LrStat(
                    label: 'Avg HR',
                    value: '${_ride.averageHeartRate}',
                    unit: 'bpm',
                    valueSize: 30,
                  ),
                if (_ride.maxHeartRate != null)
                  LrStat(
                    label: 'Max HR',
                    value: '${_ride.maxHeartRate}',
                    unit: 'bpm',
                    valueSize: 30,
                  ),
                LrStat(
                  label: 'GPS points',
                  value: '${_ride.points.length}',
                  valueSize: 30,
                ),
              ],
            ),
          ),
          if (profile.length >= 3) ...[
            const SizedBox(height: 22),
            const LrSectionHeader(title: 'Elevation'),
            LrPanel(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
              child: ElevationProfile(samples: profile, metric: metric),
            ),
          ],
          const SizedBox(height: 26),
          if (widget.justFinished)
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('DONE'),
            ),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _ride.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename ride'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Ride name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;

    final renamed = await AppServices.of(context).rides.rename(_ride, name);
    if (mounted) setState(() => _ride = renamed);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final file = await AppServices.of(context).rides.exportGpx(_ride);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: _ride.name,
          text: '${_ride.name} · Live Ride',
        ),
      );
    } catch (e) {
      if (mounted) showLrMessage(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this ride?'),
        content: const Text(
          'The recorded track will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LR.alert),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppServices.of(context).rides.delete(_ride.id);
    if (mounted) Navigator.of(context).pop(true);
  }
}
