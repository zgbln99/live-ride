import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../models/ride_record.dart';
import '../../services/app_services.dart';
import '../../widgets/lr_common.dart';
import '../../widgets/track_preview.dart';
import '../ride_summary_screen.dart';

/// Ride history with lifetime totals on top.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<RecordedRide> _rides = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final rides = await AppServices.of(context).rides.list(refresh: true);
    if (!mounted) return;
    setState(() {
      _rides = rides;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final metric = AppServices.of(context).profile.profile.metricUnits;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rides.isEmpty) {
      return const LrEmptyState(
        icon: Icons.history,
        title: 'No rides yet',
        message:
            'Press START RIDE on the Ride tab. When you finish, the ride is '
            'saved here with its track, stats and a GPX export.',
      );
    }

    final distance = _rides.fold<double>(
      0,
      (sum, ride) => sum + ride.distanceMeters,
    );
    final ascent = _rides.fold<double>(
      0,
      (sum, ride) => sum + ride.elevationGainMeters,
    );
    final moving = _rides.fold<int>(0, (sum, ride) => sum + ride.movingSeconds);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: _rides.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LrSectionHeader(title: 'All time'),
                  LrPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: LrStat(
                            label: 'Rides',
                            value: '${_rides.length}',
                            valueSize: 24,
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'Distance',
                            value: Fmt.distance(distance, metric: metric),
                            unit: Fmt.distanceUnit(metric: metric),
                            valueSize: 24,
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'Ascent',
                            value: Fmt.elevation(ascent, metric: metric),
                            unit: Fmt.elevationUnit(metric: metric),
                            valueSize: 24,
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'Time',
                            value: Fmt.durationCompact(
                              Duration(seconds: moving),
                            ),
                            valueSize: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return _rideCard(_rides[index - 1], metric);
        },
      ),
    );
  }

  Widget _rideCard(RecordedRide ride, bool metric) => LrPanel(
    padding: EdgeInsets.zero,
    onTap: () => _open(ride),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 58,
                child: TrackPreview(points: ride.preview, strokeWidth: 2.2),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${Fmt.date(ride.startedAt)} · ${Fmt.clock(ride.startedAt)}',
                      style: LR.body.copyWith(fontSize: 12.5),
                    ),
                    if (ride.averageHeartRate != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.favorite, size: 12, color: LR.alert),
                          const SizedBox(width: 5),
                          Text(
                            '${ride.averageHeartRate} bpm avg'
                            '${ride.maxHeartRate == null ? '' : ' · ${ride.maxHeartRate} max'}',
                            style: LR.fieldLabel.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: LrStat(
                  label: 'Distance',
                  value: Fmt.distance(ride.distanceMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: 'Moving',
                  value: Fmt.duration(ride.movingTime),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: 'Avg',
                  value: Fmt.speed(ride.averageSpeedKmh, metric: metric),
                  unit: Fmt.speedUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: 'Ascent',
                  value: Fmt.elevation(
                    ride.elevationGainMeters,
                    metric: metric,
                  ),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _open(RecordedRide ride) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideSummaryScreen(ride: ride)),
    );
    unawaited(_load());
  }
}
