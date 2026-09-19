import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../models/ride_record.dart';
import '../../models/ride_route.dart';
import '../../services/app_services.dart';
import '../../widgets/lr_common.dart';
import '../../widgets/track_preview.dart';
import '../../widgets/weather_field.dart';
import '../ride_computer_screen.dart';
import '../ride_summary_screen.dart';
import '../route_detail_screen.dart';

/// The home screen: start a ride in one tap, or pick up where you left off.
class RideTab extends StatefulWidget {
  const RideTab({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  State<RideTab> createState() => _RideTabState();
}

class _RideTabState extends State<RideTab> {
  List<RouteSummary> _routes = const [];
  List<RecordedRide> _rides = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = AppServices.of(context);
    final routes = await services.routes.list(refresh: true);
    final rides = await services.rides.list(refresh: true);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _rides = rides;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final metric = services.profile.profile.metricUnits;

    return AnimatedBuilder(
      animation: Listenable.merge([
        services.recorder,
        services.weather,
        services.profile,
      ]),
      builder: (context, _) {
        final active = services.recorder.isActive;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _startPanel(active),
              const SizedBox(height: 22),
              if (services.profile.profile.weatherEnabled) ...[
                const LrSectionHeader(title: 'Conditions'),
                LrPanel(
                  padding: const EdgeInsets.all(16),
                  child: WeatherCard(
                    weather: services.weather.current,
                    metric: metric,
                    error: services.weather.lastError,
                  ),
                ),
                const SizedBox(height: 22),
              ],
              _statsBlock(metric),
              const SizedBox(height: 22),
              LrSectionHeader(
                title: 'Routes',
                trailing: TextButton(
                  onPressed: () => widget.onOpenTab(1),
                  child: const Text('ALL'),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_routes.isEmpty)
                LrPanel(
                  onTap: () => widget.onOpenTab(1),
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.file_upload_outlined, color: LR.inkSoft),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Import a GPX file to navigate a planned route.',
                          style: LR.body,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: LR.muted),
                    ],
                  ),
                )
              else
                for (final route in _routes.take(3)) ...[
                  _routeRow(route, metric),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 18),
              LrSectionHeader(
                title: 'Last ride',
                trailing: TextButton(
                  onPressed: () => widget.onOpenTab(2),
                  child: const Text('HISTORY'),
                ),
              ),
              if (_rides.isEmpty)
                LrPanel(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Your finished rides will appear here with full stats and '
                    'a GPX export.',
                    style: LR.body,
                  ),
                )
              else
                _lastRide(_rides.first, metric),
            ],
          ),
        );
      },
    );
  }

  Widget _startPanel(bool active) => Container(
    decoration: BoxDecoration(
      color: LR.night,
      borderRadius: BorderRadius.circular(6),
    ),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              active ? 'RIDE IN PROGRESS' : 'READY TO RIDE',
              style: const TextStyle(
                color: LR.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            const Spacer(),
            if (active)
              Text(
                Fmt.duration(AppServices.of(context).recorder.metrics.elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontFeatures: LR.numeric,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          active
              ? 'Your ride computer is still running.'
              : 'Free ride — no route needed.',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'GPS track, speed, distance, ascent, heart rate and LIVE tracking.',
          style: TextStyle(color: Color(0xFF9BAEBD), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LR.accent,
              foregroundColor: LR.ink,
            ),
            onPressed: _startRide,
            icon: Icon(
              active ? Icons.open_in_full : Icons.play_arrow,
              size: 22,
            ),
            label: Text(
              active ? 'BACK TO RIDE' : 'START RIDE',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _statsBlock(bool metric) {
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 30));
    final recent = _rides.where((ride) => ride.startedAt.isAfter(since));
    final distance = recent.fold<double>(
      0,
      (sum, ride) => sum + ride.distanceMeters,
    );
    final ascent = recent.fold<double>(
      0,
      (sum, ride) => sum + ride.elevationGainMeters,
    );
    final moving = recent.fold<int>(0, (sum, ride) => sum + ride.movingSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LrSectionHeader(title: 'Last 30 days'),
        LrPanel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
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
                  value: Fmt.durationCompact(Duration(seconds: moving)),
                  valueSize: 24,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: 'Rides',
                  value: '${recent.length}',
                  valueSize: 24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeRow(RouteSummary route, bool metric) => LrPanel(
    padding: const EdgeInsets.all(12),
    onTap: () => _openRoute(route),
    child: Row(
      children: [
        SizedBox(
          width: 56,
          height: 44,
          child: TrackPreview(points: route.preview),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${Fmt.distance(route.distanceMeters, metric: metric)} '
                '${Fmt.distanceUnit(metric: metric)} · '
                '${Fmt.elevation(route.ascentMeters, metric: metric)} '
                '${Fmt.elevationUnit(metric: metric)}',
                style: LR.body.copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: LR.muted),
      ],
    ),
  );

  Widget _lastRide(RecordedRide ride, bool metric) => LrPanel(
    padding: const EdgeInsets.all(16),
    accentEdge: true,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideSummaryScreen(ride: ride)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ride.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          Fmt.dateTime(ride.startedAt),
          style: LR.body.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: LrStat(
                label: 'Distance',
                value: Fmt.distance(ride.distanceMeters, metric: metric),
                unit: Fmt.distanceUnit(metric: metric),
              ),
            ),
            Expanded(
              child: LrStat(
                label: 'Moving',
                value: Fmt.duration(ride.movingTime),
              ),
            ),
            Expanded(
              child: LrStat(
                label: 'Avg',
                value: Fmt.speed(ride.averageSpeedKmh, metric: metric),
                unit: Fmt.speedUnit(metric: metric),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _openRoute(RouteSummary route) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(summary: route),
      ),
    );
    unawaited(_load());
  }

  Future<void> _startRide() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RideComputerScreen()));
    unawaited(_load());
  }
}
