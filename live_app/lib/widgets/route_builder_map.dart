import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../core/geo.dart';
import '../core/lr_theme.dart';
import '../models/route/route_waypoint.dart';
import '../services/route_builder_controller.dart';

/// Mapa kreatora tras.
///
/// Trzy sposoby pracy na jednej mapie: dotknięcie dokłada punkt,
/// przeciągnięcie markera go przesuwa, a w trybie rysowania palec zostawia
/// szkic, który potem przykleja się do dróg.
class RouteBuilderMap extends StatefulWidget {
  const RouteBuilderMap({
    super.key,
    required this.styleJson,
    required this.controller,
    required this.onTapMap,
    required this.onMoveWaypoint,
    required this.onSketch,
    required this.onSelectWaypoint,
    this.selectedIndex,
    this.initialCenter,
  });

  final String styleJson;
  final RouteBuilderController controller;
  final void Function(GeoPoint point) onTapMap;
  final void Function(int index, GeoPoint point) onMoveWaypoint;
  final void Function(List<GeoPoint> sketch) onSketch;
  final void Function(int? index) onSelectWaypoint;
  final int? selectedIndex;
  final GeoPoint? initialCenter;

  @override
  State<RouteBuilderMap> createState() => RouteBuilderMapState();
}

class RouteBuilderMapState extends State<RouteBuilderMap> {
  static const String _routeSource = 'builder-route';
  static const String _sketchSource = 'builder-sketch';

  final GlobalKey _mapKey = GlobalKey();

  ml.MapController? _map;
  ml.StyleController? _style;
  bool _routeLayerAdded = false;
  bool _sketchLayerAdded = false;

  /// Punkty szkicu zbierane w trakcie rysowania.
  final List<GeoPoint> _sketch = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    unawaited(_pushRoute());
    if (mounted) setState(() {});
  }

  /// Zamienia punkt na ekranie na współrzędne geograficzne.
  GeoPoint? _toGeo(Offset local) {
    final map = _map;
    if (map == null) return null;
    final geographic = map.toLngLat(local);
    final point = GeoPoint(lat: geographic.lat, lon: geographic.lon);
    return point.isValid ? point : null;
  }

  Offset? _toLocal(Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final drawing = widget.controller.mode == BuilderMode.draw;
    final center =
        widget.initialCenter ??
        (widget.controller.points.isNotEmpty
            ? widget.controller.points.first
            : const GeoPoint(lat: 52.2297, lon: 21.0122));

    return Stack(
      key: _mapKey,
      fit: StackFit.expand,
      children: [
        ml.MapLibreMap(
          options: ml.MapOptions(
            initStyle: widget.styleJson,
            initCenter: ml.Geographic(lat: center.lat, lon: center.lon),
            initZoom: 12,
            // W trybie rysowania mapa nie może uciekać spod palca.
            gestures: drawing
                ? const ml.MapGestures.none()
                : const ml.MapGestures.all(),
            androidMode: ml.AndroidPlatformViewMode.hc,
          ),
          onMapCreated: (controller) => _map = controller,
          onStyleLoaded: _onStyleLoaded,
          onEvent: _onEvent,
          children: [if (!drawing) _waypointLayer()],
        ),
        if (drawing)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                _sketch.clear();
                _addSketchPoint(details.globalPosition);
              },
              onPanUpdate: (details) => _addSketchPoint(details.globalPosition),
              onPanEnd: (_) {
                if (_sketch.length >= 2) {
                  widget.onSketch(List.of(_sketch));
                }
                _sketch.clear();
                unawaited(_pushSketch(const []));
              },
            ),
          ),
      ],
    );
  }

  ml.WidgetLayer _waypointLayer() {
    final waypoints = widget.controller.waypoints;
    return ml.WidgetLayer(
      allowInteraction: true,
      markers: [
        for (var i = 0; i < waypoints.length; i++)
          ml.Marker(
            point: ml.Geographic(lat: waypoints[i].lat, lon: waypoints[i].lon),
            size: const Size(44, 44),
            child: _WaypointMarker(
              waypoint: waypoints[i],
              index: i,
              total: waypoints.length,
              selected: widget.selectedIndex == i,
              onTap: () =>
                  widget.onSelectWaypoint(widget.selectedIndex == i ? null : i),
              onDrag: (globalPosition) {
                final local = _toLocal(globalPosition);
                if (local == null) return;
                final point = _toGeo(local);
                if (point != null) widget.onMoveWaypoint(i, point);
              },
            ),
          ),
      ],
    );
  }

  void _addSketchPoint(Offset globalPosition) {
    final local = _toLocal(globalPosition);
    if (local == null) return;
    final point = _toGeo(local);
    if (point == null) return;

    // Punkty bliżej niż 8 m to drżenie palca, nie kształt trasy.
    if (_sketch.isNotEmpty && haversineMeters(_sketch.last, point) < 8) return;
    _sketch.add(point);
    unawaited(_pushSketch(_sketch));
  }

  void _onEvent(ml.MapEvent event) {
    if (event is ml.MapEventClick &&
        widget.controller.mode == BuilderMode.waypoints) {
      final point = GeoPoint(lat: event.point.lat, lon: event.point.lon);
      if (point.isValid) widget.onTapMap(point);
    }
  }

  Future<void> _onStyleLoaded(ml.StyleController style) async {
    _style = style;
    _routeLayerAdded = false;
    _sketchLayerAdded = false;
    await _pushRoute();
    fitRoute();
  }

  Future<void> _pushRoute() async {
    final style = _style;
    if (style == null) return;
    final data = _lineGeoJson(widget.controller.points);
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
          paint: const {'line-color': '#FFFFFF', 'line-width': 10.0},
        ),
      );
      await style.addLayer(
        ml.LineStyleLayer(
          id: '$_routeSource-line',
          sourceId: _routeSource,
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {'line-color': '#00BFD8', 'line-width': 6.0},
        ),
      );
      _routeLayerAdded = true;
    } catch (_) {
      // Styl bez obsługi warstwy nie może położyć kreatora.
    }
  }

  Future<void> _pushSketch(List<GeoPoint> sketch) async {
    final style = _style;
    if (style == null) return;
    // Szkic rysuje się dziesiątki razy na sekundę; aktualizujemy tylko
    // źródło, nigdy nie dodając warstwy ponownie.
    final data = _lineGeoJson(sketch);
    try {
      if (_sketchLayerAdded) {
        await style.updateGeoJsonSource(id: _sketchSource, data: data);
        return;
      }
      await style.addSource(ml.GeoJsonSource(id: _sketchSource, data: data));
      await style.addLayer(
        ml.LineStyleLayer(
          id: '$_sketchSource-line',
          sourceId: _sketchSource,
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {
            'line-color': '#E02B20',
            'line-width': 4.0,
            'line-dasharray': [2.0, 1.5],
          },
        ),
      );
      _sketchLayerAdded = true;
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

  /// Kadruje całą trasę.
  void fitRoute() {
    final controller = _map;
    final bounds = GeoBounds.of(widget.controller.points);
    if (controller == null || bounds == null) return;
    unawaited(
      controller.fitBounds(
        bounds: ml.LngLatBounds(
          longitudeWest: bounds.minLon,
          latitudeSouth: bounds.minLat,
          longitudeEast: bounds.maxLon,
          latitudeNorth: bounds.maxLat,
        ),
        padding: const EdgeInsets.all(56),
        nativeDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  void centerOn(GeoPoint point, {double zoom = 14}) {
    unawaited(
      _map?.animateCamera(
        center: ml.Geographic(lat: point.lat, lon: point.lon),
        zoom: zoom,
        nativeDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void zoomBy(double delta) {
    final controller = _map;
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

/// Znacznik punktu trasy: start, meta albo numer punktu pośredniego.
class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.waypoint,
    required this.index,
    required this.total,
    required this.selected,
    required this.onTap,
    required this.onDrag,
  });

  final RouteWaypoint waypoint;
  final int index;
  final int total;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onDrag;

  @override
  Widget build(BuildContext context) {
    final isEnd =
        waypoint.kind == WaypointKind.start ||
        waypoint.kind == WaypointKind.finish;
    final color = switch (waypoint.kind) {
      WaypointKind.start => LR.go,
      WaypointKind.finish => LR.alert,
      WaypointKind.via => LR.ink,
    };

    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDrag(details.globalPosition),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: selected ? 34 : 28,
          height: selected ? 34 : 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? LR.accent : Colors.white,
              width: selected ? 3.5 : 2.5,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x44000000), blurRadius: 5),
            ],
          ),
          child: Text(
            isEnd
                ? (waypoint.kind == WaypointKind.start ? 'S' : 'M')
                : '$index',
            style: TextStyle(
              color: Colors.white,
              fontSize: selected ? 13 : 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
