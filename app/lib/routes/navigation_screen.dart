export 'navigation_screen_legacy.dart' hide NavigationScreen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:gpx/gpx.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:wanderer/entities/active_navigation_entity.dart';
import 'package:wanderer/models/navigate_response.dart';
import 'package:wanderer/provider/local_settings_provider.dart';
import 'package:wanderer/provider/navigation_provider.dart';
import 'package:wanderer/provider/navigation_stats_provider.dart';
import 'package:wanderer/util/format.dart';
import 'package:wanderer/util/geo/polyline.dart';
import 'package:wanderer/routes/navigation_screen_legacy.dart' as legacy;

/// Live Ride's cycling-computer presentation layer.
///
/// The mature navigation engine stays in navigation_screen_legacy.dart and is
/// rendered unchanged underneath this HUD. That preserves the single Tracelet
/// GPS stream, route advancement, background recording, Live Ride sharing,
/// WHOOP controls, persistence and MapLibre behavior while allowing the visual
/// surface to evolve independently into a glanceable bike-computer UI.
class NavigationScreen extends ConsumerStatefulWidget {
  final String id;
  final NavigateResponse response;
  final ActiveNavigationEntity? resumeSession;
  final bool isRecording;
  final ml.Geographic? initialCenter;
  final geo.Position? initialPosition;
  final String? recordingCosting;

  const NavigationScreen({
    super.key,
    required this.id,
    required this.response,
    this.resumeSession,
    this.isRecording = false,
    this.initialCenter,
    this.initialPosition,
    this.recordingCosting,
  });

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  late final int? _resumeManeuverIndex;
  late final List<Wpt>? _resumeBreadcrumb;
  late final NavigationStatsSeed? _resumeStats;

  @override
  void initState() {
    super.initState();
    final resume = widget.resumeSession;
    _resumeManeuverIndex = resume?.currentManeuverIndex;

    final positions = resume?.breadcrumbPolyline != null
        ? PolylineUtil.decode(resume!.breadcrumbPolyline!)
        : null;
    final elevations = resume?.elevations;
    final timestamps = resume?.timestampsUtc;
    _resumeBreadcrumb = positions
        ?.asMap()
        .entries
        .map(
          (entry) => Wpt(
            lat: entry.value.lat,
            lon: entry.value.lon,
            ele: elevations != null && entry.key < elevations.length
                ? elevations[entry.key]
                : null,
            time: timestamps != null && entry.key < timestamps.length
                ? DateTime.fromMillisecondsSinceEpoch(timestamps[entry.key])
                : null,
          ),
        )
        .toList();

    _resumeStats = resume == null
        ? null
        : NavigationStatsSeed(
            distanceMeters: resume.distanceMeters,
            elevationGainMeters: resume.elevationGainMeters,
            elevationLossMeters: resume.elevationLossMeters,
            elapsed: Duration(seconds: resume.currentElapsedSeconds),
            pausedAccum: Duration(seconds: resume.pausedAccumSeconds),
            isPaused: resume.isPaused,
          );
  }

  @override
  Widget build(BuildContext context) {
    final navProvider = navigationProvider(
      widget.response,
      resumeManeuverIndex: _resumeManeuverIndex,
      resumeBreadcrumb: _resumeBreadcrumb,
    );
    final statsProvider = navigationStatsProvider(
      widget.response,
      resume: _resumeStats,
    );

    final currentIndex = ref.watch(
      navProvider.select((state) => state.currentManeuverIndex),
    );
    final stats = ref.watch(statsProvider);
    final unit = ref.watch(unitProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        legacy.NavigationScreen(
          id: widget.id,
          response: widget.response,
          resumeSession: widget.resumeSession,
          isRecording: widget.isRecording,
          initialCenter: widget.initialCenter,
          initialPosition: widget.initialPosition,
          recordingCosting: widget.recordingCosting,
        ),
        if (!widget.isRecording)
          _GarminTurnHeader(
            maneuvers: widget.response.maneuvers,
            currentIndex: currentIndex,
            unit: unit,
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 82,
          child: IgnorePointer(
            child: _RideDashboard(stats: stats, unit: unit),
          ),
        ),
      ],
    );
  }
}

class _GarminTurnHeader extends StatelessWidget {
  const _GarminTurnHeader({
    required this.maneuvers,
    required this.currentIndex,
    required this.unit,
  });

  final List<NavigateManeuver> maneuvers;
  final int currentIndex;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (maneuvers.isEmpty) return const SizedBox.shrink();
    final safeIndex = currentIndex.clamp(0, maneuvers.length - 1);
    final maneuver = maneuvers[safeIndex];
    final remainingMeters = maneuvers
        .skip(safeIndex)
        .fold<double>(0, (sum, item) => sum + item.length * 1000);
    final nextMeters = maneuver.length * 1000;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.white.withValues(alpha: 0.97),
          elevation: 3,
          child: Container(
            constraints: const BoxConstraints(minHeight: 150),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x22000000))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports_score, size: 24, color: Colors.black),
                    const SizedBox(width: 7),
                    Text(
                      formatDistance(remainingMeters, unit: unit),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'LIVE RIDE',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Icon(
                        _maneuverIcon(maneuver.type),
                        size: 68,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatDistance(nextMeters, unit: unit),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 58,
                                height: 0.95,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            maneuver.instruction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _maneuverIcon(int type) => switch (type) {
    4 || 5 || 6 => Icons.flag,
    7 || 8 || 17 || 22 => Icons.straight,
    9 || 18 || 20 || 23 || 37 => Icons.turn_slight_right,
    10 => Icons.turn_right,
    11 => Icons.turn_sharp_right,
    12 => Icons.u_turn_right,
    13 => Icons.u_turn_left,
    14 => Icons.turn_sharp_left,
    15 => Icons.turn_left,
    16 || 19 || 21 || 24 || 38 => Icons.turn_slight_left,
    26 || 27 => Icons.roundabout_right,
    _ => Icons.navigation,
  };
}

class _RideDashboard extends StatelessWidget {
  const _RideDashboard({required this.stats, required this.unit});

  final NavigationStats stats;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.98),
      elevation: 5,
      child: Container(
        height: 142,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0x33000000)),
            bottom: BorderSide(color: Color(0x22000000)),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _MetricCell(
                      label: 'Speed',
                      value: formatSpeed(stats.currentSpeedKmh, unit: unit),
                    ),
                  ),
                  Container(width: 1, color: const Color(0x33000000)),
                  Expanded(
                    child: _MetricCell(
                      label: 'Distance',
                      value: formatDistance(stats.distanceMeters, unit: unit),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: const Color(0x22000000)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: Colors.black54),
                  const SizedBox(width: 5),
                  Text(
                    formatElapsed(stats.elapsed),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.trending_up, size: 16, color: Colors.black54),
                  const SizedBox(width: 5),
                  Text(
                    formatElevation(stats.elevationGainMeters, unit: unit),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 40,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
