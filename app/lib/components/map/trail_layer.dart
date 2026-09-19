export 'trail_layer_legacy.dart' hide TrailLayer, kTrailRouteColor;

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:wanderer/components/map/trail_layer_legacy.dart' as legacy;
import 'package:wanderer/models/trail.dart';

/// Live Ride navigation color: high-contrast cyan inspired by dedicated bike
/// computers, clearly separated from the red ridden breadcrumb.
const Color kTrailRouteColor = Color(0xff00b8d9);

/// Presentation override for the upstream native MapLibre route layer.
/// Everything except the default route color is delegated unchanged.
class TrailLayer extends legacy.TrailLayer {
  const TrailLayer({
    super.sourceId = 'trail',
    super.casingLayerId = 'trail-casing',
    super.routeLayerId = 'trail-route',
    super.arrowsLayerId = 'trail-arrows',
    super.showArrows = true,
  });

  @override
  Future<void> add(
    ml.StyleController style,
    Trail trail, {
    Color routeColor = kTrailRouteColor,
  }) {
    return super.add(style, trail, routeColor: routeColor);
  }
}
