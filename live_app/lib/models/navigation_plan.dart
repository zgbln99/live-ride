import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/geo.dart';
import 'ride_route.dart';

/// A single turn instruction, normalised from the Valhalla maneuver list.
class NavManeuver {
  const NavManeuver({
    required this.instruction,
    required this.beginShapeIndex,
    required this.endShapeIndex,
    required this.type,
    required this.lengthKm,
    required this.seconds,
    this.streetNames = const <String>[],
    this.verbalPost,
    this.roundaboutExit,
  });

  final String instruction;
  final int beginShapeIndex;
  final int endShapeIndex;
  final int type;
  final double lengthKm;
  final double seconds;
  final List<String> streetNames;
  final String? verbalPost;
  final int? roundaboutExit;

  String get streetName => streetNames.isEmpty ? '' : streetNames.first;

  bool get isDestination => type == 4 || type == 5 || type == 6;

  /// Valhalla maneuver type to a cycling-computer arrow.
  IconData get icon => switch (type) {
    1 || 2 || 3 => Icons.trip_origin,
    4 || 5 || 6 => Icons.sports_score,
    9 => Icons.turn_slight_right,
    10 => Icons.turn_right,
    11 => Icons.turn_sharp_right,
    12 => Icons.u_turn_right,
    13 => Icons.u_turn_left,
    14 => Icons.turn_sharp_left,
    15 => Icons.turn_left,
    16 => Icons.turn_slight_left,
    18 || 20 || 23 || 37 => Icons.ramp_right,
    19 || 21 || 24 || 38 => Icons.ramp_left,
    26 || 27 => Icons.roundabout_right,
    25 => Icons.merge,
    7 || 8 || 17 || 22 => Icons.straight,
    _ => Icons.navigation,
  };

  factory NavManeuver.fromJson(Map<String, dynamic> json) {
    final begin = (json['begin_shape_index'] as num? ?? 0).toInt();
    return NavManeuver(
      instruction: (json['instruction'] as String? ?? '').trim(),
      beginShapeIndex: begin,
      endShapeIndex: (json['end_shape_index'] as num? ?? begin).toInt(),
      type: (json['type'] as num? ?? 0).toInt(),
      lengthKm: (json['length'] as num? ?? 0).toDouble(),
      seconds: (json['time'] as num? ?? 0).toDouble(),
      streetNames: (json['street_names'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      verbalPost: json['verbal_post_instruction'] as String?,
      roundaboutExit: (json['roundabout_exit_count'] as num?)?.toInt(),
    );
  }
}

/// Where the rider is on the route right now.
class NavigationProgress {
  const NavigationProgress({
    required this.alongMeters,
    required this.remainingMeters,
    required this.offRouteMeters,
    required this.snapped,
    required this.shapeIndex,
    this.current,
    this.next,
    this.distanceToManeuver = 0,
    this.remainingSeconds,
  });

  final double alongMeters;
  final double remainingMeters;
  final double offRouteMeters;
  final GeoPoint snapped;
  final int shapeIndex;
  final NavManeuver? current;
  final NavManeuver? next;
  final double distanceToManeuver;
  final double? remainingSeconds;

  /// 80 m is wide enough for GPS error under trees and narrow enough to catch
  /// a genuinely missed turn.
  bool get offRoute => offRouteMeters > 80;

  double get fraction {
    final total = alongMeters + remainingMeters;
    if (total <= 0) return 0;
    return (alongMeters / total).clamp(0.0, 1.0);
  }

  static const NavigationProgress unknown = NavigationProgress(
    alongMeters: 0,
    remainingMeters: 0,
    offRouteMeters: 0,
    snapped: GeoPoint(lat: 0, lon: 0),
    shapeIndex: 0,
  );
}

/// A navigable route: map-matched geometry plus turn instructions.
class NavigationPlan {
  NavigationPlan({
    required this.shape,
    required this.maneuvers,
    this.totalSeconds = 0,
    this.mapMatched = true,
  }) : cumulativeMeters = cumulativeDistances(shape);

  final List<GeoPoint> shape;
  final List<NavManeuver> maneuvers;
  final List<double> cumulativeMeters;
  final double totalSeconds;

  /// False when the server could not map-match and the raw GPX geometry is
  /// being navigated instead. The UI says so rather than pretending.
  final bool mapMatched;

  bool get hasTurnByTurn => maneuvers.length > 1;

  double get totalMeters =>
      cumulativeMeters.isEmpty ? 0 : cumulativeMeters.last;

  factory NavigationPlan.fromJson(Map<String, dynamic> json) {
    final shape = <GeoPoint>[];
    for (final entry in (json['shape'] as List<dynamic>? ?? const [])) {
      if (entry is List && entry.length >= 2) {
        final lat = (entry[0] as num).toDouble();
        final lon = (entry[1] as num).toDouble();
        final point = GeoPoint(lat: lat, lon: lon);
        if (point.isValid) shape.add(point);
      }
    }
    final maneuvers = (json['maneuvers'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => NavManeuver.fromJson(Map<String, dynamic>.from(m)))
        .where((m) => m.beginShapeIndex < shape.length)
        .toList(growable: false);
    final summary = json['summary'];
    return NavigationPlan(
      shape: shape,
      maneuvers: maneuvers,
      totalSeconds: summary is Map
          ? ((summary['time'] as num?) ?? 0).toDouble()
          : 0,
    );
  }

  /// Used when the routing service is unreachable: the rider still gets the
  /// line, the map and every ride metric, just without turn callouts.
  factory NavigationPlan.fromRoute(RideRoute route) => NavigationPlan(
    shape: route.points,
    maneuvers: const <NavManeuver>[],
    mapMatched: false,
  );

  NavigationProgress progressAt(GeoPoint position, {int fromIndex = 0}) {
    final projection = projectOnPolyline(
      position,
      shape,
      cumulativeMeters,
      fromIndex: fromIndex,
    );
    if (projection == null) return NavigationProgress.unknown;

    final along = projection.alongMeters;
    final remaining = math.max(0.0, totalMeters - along);

    NavManeuver? current;
    NavManeuver? next;
    for (final maneuver in maneuvers) {
      final maneuverAlong = cumulativeMeters.isEmpty
          ? 0.0
          : cumulativeMeters[maneuver.beginShapeIndex.clamp(
              0,
              cumulativeMeters.length - 1,
            )];
      // 12 m of slack keeps the next turn on screen until the rider has
      // actually passed through the junction.
      if (maneuverAlong <= along + 12) {
        current = maneuver;
      } else {
        next = maneuver;
        break;
      }
    }
    next ??= maneuvers.isNotEmpty && maneuvers.last.isDestination
        ? maneuvers.last
        : null;

    var distanceToManeuver = remaining;
    if (next != null && cumulativeMeters.isNotEmpty) {
      final index = next.beginShapeIndex.clamp(0, cumulativeMeters.length - 1);
      distanceToManeuver = math.max(0.0, cumulativeMeters[index] - along);
    }

    double? remainingSeconds;
    if (totalSeconds > 0 && totalMeters > 0) {
      remainingSeconds = totalSeconds * (remaining / totalMeters);
    }

    return NavigationProgress(
      alongMeters: along,
      remainingMeters: remaining,
      offRouteMeters: projection.offRouteMeters,
      snapped: projection.snapped,
      shapeIndex: projection.segmentIndex,
      current: current,
      next: next,
      distanceToManeuver: distanceToManeuver,
      remainingSeconds: remainingSeconds,
    );
  }
}
