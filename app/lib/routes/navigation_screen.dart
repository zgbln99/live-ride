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
import 'package:wanderer/util/format.dart';
import 'package:wanderer/util/geo/polyline.dart';
import 'package:wanderer/routes/navigation_screen_legacy.dart' as legacy;

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
  }

  @override
  Widget build(BuildContext context) {
    final navProvider = navigationProvider(
      widget.response,
      resumeManeuverIndex: _resumeManeuverIndex,
      resumeBreadcrumb: _resumeBreadcrumb,
    );
    final currentIndex = ref.watch(
      navProvider.select((state) => state.currentManeuverIndex),
    );
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
          _LiveRideTurnBar(
            maneuvers: widget.response.maneuvers,
            currentIndex: currentIndex,
            unit: unit,
          ),
      ],
    );
  }
}

class _LiveRideTurnBar extends StatelessWidget {
  const _LiveRideTurnBar({
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
      child: SafeArea(
        bottom: false,
        child: Material(
          color: const Color(0xF5111111),
          elevation: 6,
          child: SizedBox(
            height: 104,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Center(
                      child: Icon(
                        _maneuverIcon(maneuver.type),
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                formatDistance(nextMeters, unit: unit),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  height: 0.95,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.4,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(bottom: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                formatDistance(remainingMeters, unit: unit),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          maneuver.instruction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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

  static IconData _maneuverIcon(int type) => switch (type) {
    4 || 5 || 6 => Icons.flag_rounded,
    7 || 8 || 17 || 22 => Icons.straight_rounded,
    9 || 18 || 20 || 23 || 37 => Icons.turn_slight_right_rounded,
    10 => Icons.turn_right_rounded,
    11 => Icons.turn_sharp_right_rounded,
    12 => Icons.u_turn_right_rounded,
    13 => Icons.u_turn_left_rounded,
    14 => Icons.turn_sharp_left_rounded,
    15 => Icons.turn_left_rounded,
    16 || 19 || 21 || 24 || 38 => Icons.turn_slight_left_rounded,
    26 || 27 => Icons.roundabout_right_rounded,
    _ => Icons.navigation_rounded,
  };
}
