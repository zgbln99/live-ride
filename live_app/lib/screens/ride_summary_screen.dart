import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/ride_record.dart';
import '../services/app_services.dart';
import '../services/ride_intelligence.dart';
import '../widgets/elevation_profile.dart';
import '../widgets/lr_common.dart';
import 'integrations_screen.dart';
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

  /// Profil z pozostałych przejazdów — bez niego „szybciej niż zwykle”
  /// nie miałoby do czego się odnieść.
  RiderHistoryProfile _history = RiderHistoryProfile.empty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    final rides = await AppServices.of(context).rides.list();
    if (!mounted) return;
    // Bieżący przejazd nie może być własnym punktem odniesienia.
    setState(() {
      _history = RiderHistoryProfile.fromRides(
        rides.where((ride) => ride.id != _ride.id).toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final metric = services.profile.profile.metricUnits;
    final profile = _ride.elevationProfile();

    return Scaffold(
      appBar: AppBar(
        title: Text(S.rideSummary),
        actions: [
          IconButton(
            tooltip: S.rename,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _busy ? null : _rename,
          ),
          IconButton(
            tooltip: S.exportAndSync,
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => IntegrationsScreen(ride: _ride),
              ),
            ),
          ),
          IconButton(
            tooltip: S.exportGpx,
            icon: const Icon(Icons.ios_share),
            onPressed: _busy ? null : _export,
          ),
          IconButton(
            tooltip: S.delete,
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
          _highlights(),
          LrSectionHeader(title: S.ride),
          LrPanel(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 28,
              runSpacing: 22,
              children: [
                LrStat(
                  label: S.distance,
                  value: Fmt.distance(_ride.distanceMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 30,
                ),
                LrStat(
                  label: S.movingTime,
                  value: Fmt.duration(_ride.movingTime),
                  valueSize: 30,
                ),
                LrStat(
                  label: S.elapsed,
                  value: Fmt.duration(_ride.elapsed),
                  valueSize: 30,
                ),
                // Wiersz pauzy pokazuje się tylko przejazdom, które go znają.
                // Przejazd sprzed rozdzielenia pauz pokazałby tu zero, co
                // znaczyłoby „nigdzie się nie zatrzymałem" — a tego nie wiemy.
                if (_ride.hasPauseBreakdown)
                  LrStat(
                    label: S.pausedTime,
                    value: Fmt.duration(_ride.pausedTime),
                    valueSize: 30,
                  ),
                LrStat(
                  label: S.avgSpeed,
                  value: Fmt.speed(_ride.averageSpeedKmh, metric: metric),
                  unit: Fmt.speedUnit(metric: metric),
                  valueSize: 30,
                ),
                LrStat(
                  label: S.maxSpeed,
                  value: Fmt.speed(_ride.maxSpeedKmh, metric: metric),
                  unit: Fmt.speedUnit(metric: metric),
                  valueSize: 30,
                ),
                LrStat(
                  label: S.ascent,
                  value: Fmt.elevation(
                    _ride.elevationGainMeters,
                    metric: metric,
                  ),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 30,
                ),
                if (_ride.elevationLossMeters > 0)
                  LrStat(
                    label: S.descent,
                    value: Fmt.elevation(
                      _ride.elevationLossMeters,
                      metric: metric,
                    ),
                    unit: Fmt.elevationUnit(metric: metric),
                    valueSize: 30,
                  ),
                if (_ride.averageHeartRate != null)
                  LrStat(
                    label: S.avgHeartRate,
                    value: '${_ride.averageHeartRate}',
                    unit: 'bpm',
                    valueSize: 30,
                  ),
                if (_ride.maxHeartRate != null)
                  LrStat(
                    label: S.maxHeartRateShort,
                    value: '${_ride.maxHeartRate}',
                    unit: 'bpm',
                    valueSize: 30,
                  ),
                LrStat(
                  label: S.gpsPoints,
                  value: '${_ride.points.length}',
                  valueSize: 30,
                ),
              ],
            ),
          ),
          if (profile.length >= 3) ...[
            const SizedBox(height: 22),
            LrSectionHeader(title: S.elevation),
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
              child: Text(S.done),
            ),
        ],
      ),
    );
  }

  /// To, co naprawdę się wydarzyło — policzone, nie napisane.
  ///
  /// Panel znika w całości, gdy nie ma czego pokazać. Pusta sekcja
  /// „Warte odnotowania” byłaby gorsza niż jej brak.
  Widget _highlights() {
    final lines = RideIntelligence.highlights(_ride, profile: _history);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LrSectionHeader(title: S.worthNoting),
        LrPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: LR.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          line,
                          style: LR.body.copyWith(fontSize: 13.5, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _ride.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.renameRide),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.rideName),
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
        title: Text(S.deleteRideTitle),
        content: Text(S.deleteRideMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LR.alert),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppServices.of(context).rides.delete(_ride.id);
    if (mounted) Navigator.of(context).pop(true);
  }
}
