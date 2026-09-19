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

/// Garmin Edge-inspired presentation layered over the proven Live Ride
/// navigation engine. The map remains native/interactive while the visible HUD
/// follows a flat cycling-computer layout instead of card-based mobile UI.
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
          _GarminHeader(
            maneuvers: widget.response.maneuvers,
            currentIndex: currentIndex,
            unit: unit,
          ),
        _GarminDataBar(stats: stats, unit: unit),
      ],
    );
  }
}

class _GarminHeader extends StatelessWidget {
  const _GarminHeader({
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
    final nextMeters = maneuver.length * 1000;
    final remainingMeters = maneuvers
        .skip(safeIndex)
        .fold<double>(0, (sum, item) => sum + item.length * 1000);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Material(
          color: Colors.white,
          elevation: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              height: 154,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0x22000000), width: 1),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sports_score, color: Colors.black, size: 23),
                      const SizedBox(width: 6),
                      Text(
                        formatDistance(remainingMeters, unit: unit),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '100 m',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 112,
                        height: 92,
                        child: Center(
                          child: Icon(
                            _maneuverIcon(maneuver.type),
                            color: Colors.black,
                            size: 82,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                formatDistance(nextMeters, unit: unit),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 62,
                                  height: .88,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -2.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              maneuver.instruction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
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

class _GarminDataBar extends StatelessWidget {
  const _GarminDataBar({required this.stats, required this.unit});

  final NavigationStats stats;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Material(
          color: Colors.white,
          elevation: 0,
          child: SafeArea(
            top: false,
            child: Container(
              height: 132,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE53935), width: 1.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _GarminMetric(
                      label: 'Speed',
                      value: _speedNumber(stats.currentSpeedKmh, unit),
                      suffix: unit == 'metric' ? 'km/h' : 'mph',
                    ),
                  ),
                  Container(width: 1.2, color: const Color(0xFFE53935)),
                  Expanded(
                    child: _GarminMetric(
                      label: 'Distance',
                      value: _distanceNumber(stats.distanceMeters, unit),
                      suffix: unit == 'metric' ? 'km' : 'mi',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _speedNumber(double kmh, String unit) {
    final value = unit == 'metric' ? kmh : kmh * 0.621371;
    return value.toStringAsFixed(1);
  }

  static String _distanceNumber(double meters, String unit) {
    final value = unit == 'metric' ? meters / 1000 : meters * 0.000621371;
    return value.toStringAsFixed(2);
  }
}

class _GarminMetric extends StatelessWidget {
  const _GarminMetric({
    required this.label,
    required this.value,
    required this.suffix,
  });

  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 53,
                    height: .8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.2,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    suffix,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
