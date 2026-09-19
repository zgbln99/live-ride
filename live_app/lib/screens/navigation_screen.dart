import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../models/ride_route.dart';
import '../services/heart_rate_service.dart';
import '../services/live_service.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.route,
    required this.api,
    required this.heartRate,
    required this.live,
  });

  final RideRoute route;
  final ApiClient api;
  final HeartRateService heartRate;
  final LiveSessionController live;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  ml.MapController? _map;
  NavigationPlan? _plan;
  String? _style;
  String? _error;
  StreamSubscription<Position>? _positionSub;
  Position? _position;
  Position? _lastPosition;
  bool _follow = true;
  bool _headingUp = true;
  double _rideDistance = 0;
  int _routeIndex = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final results = await Future.wait<dynamic>([
        widget.api.fetchMapStyle(),
        widget.api.buildNavigation(widget.route),
      ]);
      if (!mounted) return;
      setState(() {
        _style = results[0] as String;
        _plan = results[1] as NavigationPlan;
      });
      await _startLocation();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Włącz usługi lokalizacji.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw StateError('Live Ride nie ma dostępu do lokalizacji.');
    }

    final current = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
    );
    _onPosition(current);

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position position) {
    final previous = _lastPosition;
    if (previous != null) {
      final jump = distanceMeters(
        RidePoint(lat: previous.latitude, lon: previous.longitude),
        RidePoint(lat: position.latitude, lon: position.longitude),
      );
      if (jump < 250) _rideDistance += jump;
    }
    _lastPosition = position;
    _position = position;

    final plan = _plan;
    if (plan != null && plan.shape.isNotEmpty) {
      _routeIndex = _nearestShapeIndex(position, plan.shape, _routeIndex);
    }

    if (_follow) {
      final bearing = _headingUp && position.heading.isFinite && position.heading >= 0
          ? position.heading
          : 0.0;
      _map?.moveCamera(
        center: ml.Geographic(lat: position.latitude, lon: position.longitude),
        bearing: bearing,
      );
    }

    unawaited(
      widget.live.pushPosition(
        position,
        distanceMeters: _rideDistance,
      ),
    );

    if (mounted) setState(() {});
  }

  int _nearestShapeIndex(Position position, List<RidePoint> shape, int previousIndex) {
    if (shape.isEmpty) return 0;
    final from = math.max(0, previousIndex - 60);
    final to = math.min(shape.length - 1, previousIndex + 500);
    var best = previousIndex.clamp(0, shape.length - 1);
    var bestDistance = double.infinity;
    final p = RidePoint(lat: position.latitude, lon: position.longitude);
    for (var i = from; i <= to; i++) {
      final d = distanceMeters(p, shape[i]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    if (bestDistance > 400) {
      for (var i = 0; i < shape.length; i++) {
        final d = distanceMeters(p, shape[i]);
        if (d < bestDistance) {
          bestDistance = d;
          best = i;
        }
      }
    }
    return best;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nawigacja')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))),
      );
    }
    if (_style == null || _plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    const headerBodyHeight = 156.0;
    const dataBodyHeight = 132.0;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: safeTop + headerBodyHeight,
              bottom: safeBottom + dataBodyHeight,
              left: 0,
              right: 0,
              child: _mapArea(),
            ),
            Positioned(top: 0, left: 0, right: 0, child: _header()),
            Positioned(bottom: 0, left: 0, right: 0, child: _dataBar()),
          ],
        ),
      ),
    );
  }

  Widget _mapArea() {
    final plan = _plan!;
    final start = _position == null
        ? plan.shape.first
        : RidePoint(lat: _position!.latitude, lon: _position!.longitude);

    return Stack(
      fit: StackFit.expand,
      children: [
        ml.MapLibreMap(
          options: ml.MapOptions(
            initStyle: _style!,
            initCenter: ml.Geographic(lat: start.lat, lon: start.lon),
            initZoom: 16.0,
            gestures: const ml.MapGestures.all(),
            androidMode: ml.AndroidPlatformViewMode.hc,
          ),
          onMapCreated: (controller) => _map = controller,
          onStyleLoaded: _drawRoute,
          onEvent: (event) {
            if (event is ml.MapEventStartMoveCamera &&
                event.reason == ml.CameraChangeReason.apiGesture) {
              if (_follow && mounted) setState(() => _follow = false);
            }
          },
          layers: const [],
          children: [
            if (_position != null)
              ml.WidgetLayer(
                markers: [
                  ml.Marker(
                    point: ml.Geographic(
                      lat: _position!.latitude,
                      lon: _position!.longitude,
                    ),
                    size: const Size(58, 58),
                    child: IgnorePointer(
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1677FF),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Column(
            children: [
              _mapButton(Icons.close, () => Navigator.of(context).pop(), tooltip: 'Wyjdź'),
              const SizedBox(height: 10),
              _mapButton(Icons.sensors, _openLivePanel, tooltip: 'LIVE', active: widget.live.isActive),
              const SizedBox(height: 10),
              _mapButton(Icons.settings, _openNavSettings, tooltip: 'Ustawienia'),
            ],
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _mapButton(
            Icons.my_location,
            () {
              setState(() => _follow = true);
              final p = _position;
              if (p != null) {
                _map?.animateCamera(
                  center: ml.Geographic(lat: p.latitude, lon: p.longitude),
                  bearing: _headingUp ? p.heading : 0,
                  nativeDuration: const Duration(milliseconds: 250),
                );
              }
            },
            tooltip: 'Wyśrodkuj',
            active: _follow,
          ),
        ),
        if (widget.heartRate.latestBpm != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]),
              child: Row(children: [const Icon(Icons.favorite, color: Colors.red, size: 18), const SizedBox(width: 6), Text('${widget.heartRate.latestBpm}', style: const TextStyle(fontWeight: FontWeight.w900))]),
            ),
          ),
      ],
    );
  }

  Future<void> _drawRoute(ml.StyleController style) async {
    final shape = _plan!.shape.isNotEmpty ? _plan!.shape : widget.route.points;
    final geoJson = jsonEncode({
      'type': 'Feature',
      'properties': <String, Object?>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': [for (final p in shape) [p.lon, p.lat]],
      },
    });
    try {
      await style.addSource(ml.GeoJsonSource(id: 'live-route', data: geoJson));
      await style.addLayer(
        ml.LineStyleLayer(
          id: 'live-route-case',
          sourceId: 'live-route',
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {'line-color': '#ffffff', 'line-width': 11},
        ),
      );
      await style.addLayer(
        ml.LineStyleLayer(
          id: 'live-route-line',
          sourceId: 'live-route',
          layout: const {'line-cap': 'round', 'line-join': 'round'},
          paint: const {'line-color': '#00bfd8', 'line-width': 7},
        ),
      );
    } catch (_) {}
  }

  Widget _header() {
    final plan = _plan!;
    final index = _routeIndex.clamp(0, math.max(0, plan.shape.length - 1));
    NavManeuver? next;
    for (final m in plan.maneuvers) {
      if (m.beginShapeIndex >= index) {
        next = m;
        break;
      }
    }

    final nextIndex = next == null
        ? index
        : next.beginShapeIndex.clamp(index, math.max(index, plan.cumulativeMeters.length - 1));
    final toTurn = plan.cumulativeMeters.isEmpty
        ? 0.0
        : math.max(0, plan.cumulativeMeters[nextIndex] - plan.cumulativeMeters[index]);
    final remaining = plan.cumulativeMeters.isEmpty
        ? widget.route.totalDistanceMeters
        : math.max(0, plan.totalMeters - plan.cumulativeMeters[index]);

    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 156,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports_score, size: 24),
                    const SizedBox(width: 8),
                    Text(_distance(remaining), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    const Text('100 m', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    SizedBox(width: 94, child: Icon(_turnIcon(next?.type), size: 76, color: Colors.black)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              next == null ? 'TRASA' : _distance(toTurn),
                              style: const TextStyle(fontSize: 62, height: .9, fontWeight: FontWeight.w900, letterSpacing: -2),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            next?.instruction.isNotEmpty == true ? next!.instruction : 'Jedź po wyznaczonej trasie',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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

  Widget _dataBar() {
    final speed = ((_position?.speed ?? 0).isFinite ? (_position?.speed ?? 0) : 0) * 3.6;
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 132,
          child: Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE53935), width: 1.2))),
            child: Row(
              children: [
                Expanded(child: _metric('Prędkość', speed.toStringAsFixed(1), 'km/h')),
                Container(width: 1.2, color: const Color(0xFFE53935)),
                Expanded(child: _metric('Dystans', (_rideDistance / 1000).toStringAsFixed(2), 'km')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, String unit) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: const TextStyle(fontSize: 54, height: .85, fontWeight: FontWeight.w900, letterSpacing: -2)),
                const SizedBox(width: 5),
                Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(unit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ],
      );

  Widget _mapButton(IconData icon, VoidCallback onPressed, {required String tooltip, bool active = false}) => Material(
        color: active ? const Color(0xFF19D8FF) : Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(onPressed: onPressed, tooltip: tooltip, icon: Icon(icon, color: Colors.black), iconSize: 24),
      );

  Future<void> _openNavSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(contentPadding: EdgeInsets.zero, title: Text('Nawigacja', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mapa zgodnie z kierunkiem jazdy'),
                value: _headingUp,
                onChanged: (value) {
                  setState(() => _headingUp = value);
                  setSheetState(() {});
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.exit_to_app),
                title: const Text('Zakończ nawigację'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pop(this.context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLivePanel() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final session = widget.live.session;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('LIVE RIDE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  if (session == null) ...[
                    FilledButton.icon(
                      onPressed: () async {
                        await widget.live.create(title: widget.route.name);
                        setSheetState(() {});
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.sensors),
                      label: const Text('Uruchom LIVE'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final code = await showDialog<String>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Dołącz do LIVE'),
                            content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Kod')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
                              FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Dołącz')),
                            ],
                          ),
                        );
                        controller.dispose();
                        if (code != null && code.trim().isNotEmpty) {
                          await widget.live.join(code);
                          setSheetState(() {});
                          if (mounted) setState(() {});
                        }
                      },
                      icon: const Icon(Icons.group_add),
                      label: const Text('Dołącz kodem'),
                    ),
                  ] else ...[
                    Text('Kod: ${session.joinToken}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    SelectableText(widget.live.viewerUrl ?? ''),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => SharePlus.instance.share(ShareParams(text: widget.live.viewerUrl ?? '')),
                      icon: const Icon(Icons.share),
                      label: const Text('Udostępnij link'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await widget.live.stop();
                        setSheetState(() {});
                        if (mounted) setState(() {});
                      },
                      child: const Text('Zakończ LIVE'),
                    ),
                  ],
                  const Divider(height: 30),
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.heartRate.latestBpm == null ? 'WHOOP / HR: niepołączony' : 'HR: ${widget.heartRate.latestBpm} bpm')),
                      TextButton(
                        onPressed: () async {
                          await widget.heartRate.startScan();
                          if (!context.mounted) return;
                          await showModalBottomSheet<void>(
                            context: context,
                            builder: (_) => StreamBuilder<List<HeartRateDevice>>(
                              stream: widget.heartRate.devices,
                              builder: (context, snapshot) {
                                final devices = snapshot.data ?? const [];
                                return SafeArea(
                                  child: ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      const Text('Czujniki HR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 8),
                                      for (final device in devices.take(15))
                                        ListTile(
                                          leading: Icon(device.likelyHeartRate ? Icons.favorite : Icons.bluetooth),
                                          title: Text(device.name),
                                          subtitle: Text('${device.rssi} dBm'),
                                          onTap: () async {
                                            await widget.heartRate.connect(device.id);
                                            if (context.mounted) Navigator.pop(context);
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                          setSheetState(() {});
                        },
                        child: const Text('Połącz'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _turnIcon(int? type) => switch (type) {
        9 || 18 || 20 || 23 || 37 => Icons.turn_slight_right,
        10 => Icons.turn_right,
        11 => Icons.turn_sharp_right,
        12 => Icons.u_turn_right,
      13 => Icons.u_turn_left,
        14 => Icons.turn_sharp_left,
        15 => Icons.turn_left,
        16 || 19 || 21 || 24 || 38 => Icons.turn_slight_left,
        26 || 27 => Icons.roundabout_right,
        7 || 8 || 17 || 22 => Icons.straight,
        _ => Icons.navigation,
      };

  String _distance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return km >= 10 ? '${km.toStringAsFixed(1)} km' : '${km.toStringAsFixed(2)} km';
    }
    return '${meters.round()} m';
  }
}
