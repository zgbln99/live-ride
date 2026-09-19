import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../core/geo.dart';
import '../core/lr_theme.dart';

/// The map used by both navigation and free rides.
///
/// Two rules drive the whole widget:
///
///  * the rider marker is a real map marker bound to its geographic position,
///    so it never drifts from where the GPS says the rider is; and
///  * the camera follows the rider only while follow mode is on — one manual
///    pan turns it off, the recenter button turns it back on.
class RideMap extends StatefulWidget {
  const RideMap({
    super.key,
    required this.styleJson,
    required this.position,
    required this.follow,
    required this.headingUp,
    required this.onFollowChanged,
    this.routePoints = const <GeoPoint>[],
    this.trackPoints = const <GeoPoint>[],
    this.headingDegrees,
    this.offRoute = false,
    this.initialZoom = 15.5,
    this.fitRouteOnLoad = false,
  });

  final String styleJson;
  final GeoPoint? position;
  final bool follow;
  final bool headingUp;
  final ValueChanged<bool> onFollowChanged;
  final List<GeoPoint> routePoints;
  final List<GeoPoint> trackPoints;
  final double? headingDegrees;
  final bool offRoute;
  final double initialZoom;

  /// Frames the whole route once the style is ready. Used by route preview.
  final bool fitRouteOnLoad;

  @override
  State<RideMap> createState() => RideMapState();
}

class RideMapState extends State<RideMap> {
  static const String _routeSource = 'lr-route';
  static const String _trackSource = 'lr-track';

  ml.MapController? _controller;
  ml.StyleController? _style;
  bool _routeLayerAdded = false;
  bool _trackLayerAdded = false;
  DateTime _trackUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _trackPointsDrawn = 0;
  double _lastBearing = 0;

  @override
  void didUpdateWidget(RideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.routePoints, widget.routePoints)) {
      unawaited(_pushRoute());
    }
    _maybePushTrack();
    if (widget.follow) _followRider(animate: !oldWidget.follow);
  }

  GeoPoint get _initialCenter =>
      widget.position ??
      (widget.routePoints.isNotEmpty
          ? widget.routePoints.first
          : const GeoPoint(lat: 52.52, lon: 13.405));

  @override
  Widget build(BuildContext context) => ml.MapLibreMap(
    options: ml.MapOptions(
      initStyle: widget.styleJson,
      initCenter: ml.Geographic(
        lat: _initialCenter.lat,
        lon: _initialCenter.lon,
      ),
      initZoom: widget.initialZoom,
      gestures: const ml.MapGestures.all(),
      androidMode: ml.AndroidPlatformViewMode.hc,
    ),
    onMapCreated: (controller) => _controller = controller,
    onStyleLoaded: _onStyleLoaded,
    onEvent: _onEvent,
    children: [
      if (widget.position != null)
        ml.WidgetLayer(
          markers: [
            ml.Marker(
              point: ml.Geographic(
                lat: widget.position!.lat,
                lon: widget.position!.lon,
              ),
              size: const Size(56, 56),
              child: Builder(
                builder: (context) {
                  // The widget layer draws in screen space, so the marker is
                  // rotated by the rider heading relative to the current map
                  // bearing. In heading-up mode the two cancel out and the
                  // arrow points straight up — never rotated twice.
                  final cameraBearing =
                      ml.MapCamera.maybeOf(context)?.bearing ?? 0;
                  final heading = widget.headingDegrees;
                  return IgnorePointer(
                    child: _RiderMarker(
                      rotationDegrees: heading == null
                          ? null
                          : heading - cameraBearing,
                      offRoute: widget.offRoute,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
    ],
  );

  void _onEvent(ml.MapEvent event) {
    if (event is ml.MapEventStartMoveCamera &&
        event.reason == ml.CameraChangeReason.apiGesture &&
        widget.follow) {
      // A rider who reaches for the map wants to look around, so follow mode
      // releases immediately rather than fighting them for the camera.
      widget.onFollowChanged(false);
    }
  }

  Future<void> _onStyleLoaded(ml.StyleController style) async {
    _style = style;
    // A style reload drops every runtime layer, so they are re-added below.
    _routeLayerAdded = false;
    _trackLayerAdded = false;
    await _pushRoute();
    await _pushTrack(force: true);
    if (widget.fitRouteOnLoad) {
      fitRoute();
    } else if (widget.follow) {
      _followRider(animate: false);
    }
  }

  Future<void> _pushRoute() async {
    final style = _style;
    if (style == null) return;
    final data = _lineGeoJson(widget.routePoints);
    try {
      if (_routeLayerAdded) {
        await style.updateGeoJsonSource(id: _routeSource, data: data);
        return;
      }
      await style.addSource(ml.GeoJsonSource(id: _routeSource, data: data));
      await style.addLayer(
        ml.LineStyleLayer(
          id: '$_routeSource-case',
          sourceId: _routeSource,
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {
            'line-color': '#FFFFFF',
            'line-width': 11.0,
            'line-opacity': 0.95,
          },
        ),
      );
      await style.addLayer(
        ml.LineStyleLayer(
          id: '$_routeSource-line',
          sourceId: _routeSource,
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {'line-color': '#00BFD8', 'line-width': 6.5},
        ),
      );
      _routeLayerAdded = true;
    } catch (_) {
      // A style that rejects the layer must not take the ride computer down.
    }
  }

  void _maybePushTrack() {
    final now = DateTime.now();
    final grew = widget.trackPoints.length - _trackPointsDrawn;
    if (grew <= 0) return;
    if (grew < 8 && now.difference(_trackUpdatedAt).inSeconds < 4) return;
    unawaited(_pushTrack());
  }

  Future<void> _pushTrack({bool force = false}) async {
    final style = _style;
    if (style == null) return;
    if (!force && widget.trackPoints.length < 2) return;
    _trackUpdatedAt = DateTime.now();
    _trackPointsDrawn = widget.trackPoints.length;
    final data = _lineGeoJson(widget.trackPoints);
    try {
      if (_trackLayerAdded) {
        await style.updateGeoJsonSource(id: _trackSource, data: data);
        return;
      }
      await style.addSource(ml.GeoJsonSource(id: _trackSource, data: data));
      await style.addLayer(
        ml.LineStyleLayer(
          id: '$_trackSource-line',
          sourceId: _trackSource,
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {
            'line-color': '#0B1116',
            'line-width': 4.0,
            'line-opacity': 0.85,
          },
        ),
      );
      _trackLayerAdded = true;
    } catch (_) {}
  }

  String _lineGeoJson(List<GeoPoint> points) => jsonEncode({
    'type': 'Feature',
    'properties': <String, Object?>{},
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final point in points) [point.lon, point.lat],
      ],
    },
  });

  void _followRider({bool animate = false}) {
    final controller = _controller;
    final position = widget.position;
    if (controller == null || position == null) return;

    var bearing = 0.0;
    if (widget.headingUp) {
      final heading = widget.headingDegrees;
      // Heading is noisy when nearly stationary, so the last good bearing is
      // held rather than letting the map spin on the spot.
      bearing = heading == null || !heading.isFinite ? _lastBearing : heading;
      _lastBearing = bearing;
    }

    final center = ml.Geographic(lat: position.lat, lon: position.lon);
    if (animate) {
      unawaited(
        controller.animateCamera(
          center: center,
          bearing: bearing,
          nativeDuration: const Duration(milliseconds: 350),
        ),
      );
    } else {
      unawaited(controller.moveCamera(center: center, bearing: bearing));
    }
  }

  /// Centres the map on the rider again and re-enables follow mode.
  void recenter() {
    widget.onFollowChanged(true);
    _followRider(animate: true);
  }

  /// Frames the whole route, used by the route preview screen.
  void fitRoute({List<GeoPoint>? points}) {
    final controller = _controller;
    final bounds = GeoBounds.of(points ?? widget.routePoints);
    if (controller == null || bounds == null) return;
    unawaited(
      controller.fitBounds(
        bounds: ml.LngLatBounds(
          longitudeWest: bounds.minLon,
          latitudeSouth: bounds.minLat,
          longitudeEast: bounds.maxLon,
          latitudeNorth: bounds.maxLat,
        ),
        padding: const EdgeInsets.all(48),
        nativeDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void zoomBy(double delta) {
    final controller = _controller;
    if (controller == null) return;
    final camera = controller.camera ?? controller.getCamera();
    unawaited(
      controller.animateCamera(
        zoom: (camera.zoom + delta).clamp(2.0, 20.0),
        nativeDuration: const Duration(milliseconds: 180),
      ),
    );
  }
}

/// The rider puck: a cyan arrow when the heading is known, a dot when it is
/// not, and red-ringed when off route.
class _RiderMarker extends StatelessWidget {
  const _RiderMarker({required this.rotationDegrees, required this.offRoute});

  final double? rotationDegrees;
  final bool offRoute;

  @override
  Widget build(BuildContext context) {
    final ring = offRoute ? LR.alert : Colors.white;
    final core = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: LR.accentDeep,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3.5),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, spreadRadius: 1),
        ],
      ),
      child: rotationDegrees == null
          ? null
          : const Icon(Icons.navigation, color: Colors.white, size: 22),
    );

    if (rotationDegrees == null) return Center(child: core);
    return Center(
      child: Transform.rotate(
        angle: rotationDegrees! * math.pi / 180,
        child: core,
      ),
    );
  }
}
