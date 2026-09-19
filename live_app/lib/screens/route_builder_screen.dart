import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/geo.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/ride_route.dart';
import '../services/app_services.dart';
import '../services/route_builder_controller.dart';
import '../widgets/elevation_profile.dart';
import '../widgets/lr_common.dart';
import '../widgets/route_builder_map.dart';
import 'route_preferences_sheet.dart';
import 'route_search_sheet.dart';
import 'waypoint_list_sheet.dart';

/// Kreator tras.
///
/// Mapa zajmuje tyle, ile się da; na dole jest to, co trzeba wiedzieć o
/// trasie w trakcie planowania, a sterowanie chowa się w arkuszach, żeby nie
/// zasłaniać mapy.
class RouteBuilderScreen extends StatefulWidget {
  const RouteBuilderScreen({super.key, this.existing});

  /// Trasa do edycji; null tworzy nową.
  final RouteSummary? existing;

  @override
  State<RouteBuilderScreen> createState() => _RouteBuilderScreenState();
}

class _RouteBuilderScreenState extends State<RouteBuilderScreen> {
  /// Klucz szkicu w bazie — kreator wraca tam, gdzie się skończyło.
  static const String draftId = 'route-builder';

  final GlobalKey<RouteBuilderMapState> _mapKey =
      GlobalKey<RouteBuilderMapState>();

  late final AppServices _services = AppServices.of(context);
  late final RouteBuilderController _controller = RouteBuilderController(
    solver: (waypoints, preferences) =>
        _services.routing.route(waypoints: waypoints, preferences: preferences),
    sketchSolver: (sketch, preferences) =>
        _services.routing.snapSketch(sketch: sketch, preferences: preferences),
    onDraftChanged: _scheduleDraftSave,
  );

  Timer? _draftTimer;
  String? _style;
  String? _error;
  int? _selectedWaypoint;
  bool _saving = false;
  bool _elevationRequested = false;
  GeoPoint? _initialCenter;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _controller
      ..removeListener(_onRouteChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    unawaited(_loadStyle());

    final existing = widget.existing;
    if (existing != null) {
      final route = await _services.routes.load(existing);
      if (!mounted) return;
      _controller.loadExisting(
        name: route.name,
        description: route.description,
        tags: route.tags,
        waypoints: route.waypoints,
        points: route.points,
        preferences: route.preferences,
        privacy: route.privacy,
      );
      setState(() => _initialCenter = route.center);
      return;
    }

    final draft = await _services.routes.loadDraft(draftId);
    if (!mounted) return;
    if (draft != null && (draft['waypoints'] as List?)?.isNotEmpty == true) {
      _controller.restoreDraft(draft);
      return;
    }

    // Nowa trasa zaczyna się tam, gdzie stoi rower.
    final position = await _services.location.lastKnown();
    if (mounted && position != null) {
      setState(() => _initialCenter = position);
    }
  }

  Future<void> _loadStyle() async {
    try {
      final style = await _services.api.fetchMapStyle();
      if (mounted) setState(() => _style = style);
    } catch (e, stack) {
      debugPrint('Live Ride: kreator trasy: $e\n$stack');
      if (mounted) setState(() => _error = S.somethingWentWrong);
    }
  }

  void _onRouteChanged() {
    // Wysokość dociągamy raz na gotową geometrię, a nie w trakcie
    // przeciągania punktu.
    if (_controller.hasRoute &&
        !_controller.isRouting &&
        !_elevationRequested) {
      _elevationRequested = true;
      unawaited(_attachElevation());
    }
    if (!_controller.hasRoute) _elevationRequested = false;
  }

  Future<void> _attachElevation() async {
    final points = _controller.points;
    if (points.length < 2) return;
    if (points.any((point) => point.elevation != null)) return;
    final withElevation = await _services.routing.withElevation(points);
    if (!mounted) return;
    _controller.attachElevation(withElevation);
  }

  void _scheduleDraftSave(RouteBuilderController controller) {
    if (widget.existing != null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_services.routes.saveDraft(draftId, controller.toDraft()));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LR.canvas,
    appBar: AppBar(
      title: Text(widget.existing == null ? S.newRoute : S.editRoute),
      actions: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            children: [
              IconButton(
                tooltip: S.undo,
                icon: const Icon(Icons.undo),
                onPressed: _controller.canUndo
                    ? () {
                        _controller.undo();
                        setState(() => _selectedWaypoint = null);
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Ponów',
                icon: const Icon(Icons.redo),
                onPressed: _controller.canRedo ? _controller.redo : null,
              ),
            ],
          ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        children: [
          _modeBar(),
          Expanded(child: _mapArea()),
          _summaryPanel(),
        ],
      ),
    ),
  );

  Widget _modeBar() => Container(
    color: LR.surface,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: [
        for (final mode in BuilderMode.values) ...[
          Expanded(
            child: _ModeButton(
              label: mode.label,
              icon: mode == BuilderMode.waypoints
                  ? Icons.place_outlined
                  : Icons.gesture,
              selected: _controller.mode == mode,
              onTap: () => _controller.setMode(mode),
            ),
          ),
          const SizedBox(width: 8),
        ],
        LrMapButton(
          icon: Icons.search,
          tooltip: S.searchPlace,
          onPressed: _openSearch,
          size: 40,
        ),
        const SizedBox(width: 8),
        LrMapButton(
          icon: Icons.my_location,
          tooltip: S.myPosition,
          onPressed: _useCurrentPosition,
          size: 40,
        ),
      ],
    ),
  );

  Widget _mapArea() {
    if (_error != null) {
      return LrEmptyState(
        icon: Icons.map_outlined,
        title: 'Mapa niedostępna',
        message: _error!,
      );
    }
    if (_style == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        RouteBuilderMap(
          key: _mapKey,
          styleJson: _style!,
          controller: _controller,
          initialCenter: _initialCenter,
          selectedIndex: _selectedWaypoint,
          onTapMap: (point) {
            _controller.addWaypoint(point);
            setState(() => _selectedWaypoint = null);
          },
          onMoveWaypoint: _controller.moveWaypoint,
          onSelectWaypoint: (index) =>
              setState(() => _selectedWaypoint = index),
          onSketch: (sketch) => unawaited(_controller.applySketch(sketch)),
        ),
        if (_controller.mode == BuilderMode.draw)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: _hint(
              'Przeciągnij palcem po mapie. Szkic zostanie dopasowany do dróg.',
            ),
          )
        else if (_controller.waypoints.isEmpty)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: _hint('Dotknij mapy, aby postawić start trasy.'),
          ),
        if (_controller.isStraightLine)
          Positioned(
            top: 56,
            left: 10,
            right: 10,
            child: _hint(
              'Router nie odpowiedział — punkty są na razie połączone '
              'linią prostą.',
              alert: true,
            ),
          ),
        if (_controller.error != null)
          Positioned(
            top: 56,
            left: 10,
            right: 10,
            child: _hint(_controller.error!, alert: true),
          ),
        Positioned(
          right: 10,
          bottom: 10,
          child: Column(
            children: [
              if (_selectedWaypoint != null) ...[
                LrMapButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Usuń punkt',
                  onPressed: () {
                    _controller.removeWaypoint(_selectedWaypoint!);
                    setState(() => _selectedWaypoint = null);
                  },
                ),
                const SizedBox(height: 8),
              ],
              LrMapButton(
                icon: Icons.zoom_out_map,
                tooltip: S.fitView,
                onPressed: () => _mapKey.currentState?.fitRoute(),
              ),
              const SizedBox(height: 8),
              LrMapButton(
                icon: Icons.add,
                tooltip: 'Przybliż',
                onPressed: () => _mapKey.currentState?.zoomBy(1),
              ),
              const SizedBox(height: 8),
              LrMapButton(
                icon: Icons.remove,
                tooltip: S.zoomOut,
                onPressed: () => _mapKey.currentState?.zoomBy(-1),
              ),
            ],
          ),
        ),
        if (_controller.isRouting)
          const Positioned(left: 10, bottom: 10, child: _RoutingBadge()),
      ],
    );
  }

  Widget _hint(String text, {bool alert = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: alert ? LR.alert : LR.surface,
      border: Border.all(color: alert ? LR.alert : LR.lineStrong),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: alert ? Colors.white : LR.inkSoft,
      ),
    ),
  );

  Widget _summaryPanel() {
    final analysis = _controller.analysis;
    final metric = _services.profile.profile.metricUnits;
    final hasRoute = _controller.hasRoute;

    return Container(
      decoration: const BoxDecoration(
        color: LR.surface,
        border: Border(top: BorderSide(color: LR.alert, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LrStat(
                      label: S.distance,
                      value: hasRoute
                          ? Fmt.distance(
                              _controller.distanceMeters,
                              metric: metric,
                            )
                          : '--',
                      unit: Fmt.distanceUnit(metric: metric),
                      valueSize: 24,
                    ),
                  ),
                  Expanded(
                    child: LrStat(
                      label: S.ascent,
                      value: analysis.hasElevationData
                          ? Fmt.elevation(analysis.ascentMeters, metric: metric)
                          : '--',
                      unit: Fmt.elevationUnit(metric: metric),
                      valueSize: 24,
                    ),
                  ),
                  Expanded(
                    child: LrStat(
                      label: S.descent,
                      value: analysis.hasElevationData
                          ? Fmt.elevation(
                              analysis.descentMeters,
                              metric: metric,
                            )
                          : '--',
                      unit: Fmt.elevationUnit(metric: metric),
                      valueSize: 24,
                    ),
                  ),
                  Expanded(
                    child: LrStat(
                      label: 'Czas',
                      value: hasRoute
                          ? Fmt.durationCompact(_controller.estimatedDuration)
                          : '--',
                      valueSize: 24,
                    ),
                  ),
                ],
              ),
            ),
            if (analysis.profile.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: SizedBox(
                  height: 62,
                  child: ElevationProfile(
                    samples: analysis.profile,
                    metric: metric,
                    height: 44,
                  ),
                ),
              ),
            if (analysis.climbs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.terrain, size: 15, color: LR.inkSoft),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${analysis.climbs.length} '
                        '${analysis.climbs.length == 1 ? 'podjazd' : 'podjazdy'}'
                        ' · najdłuższy '
                        '${Fmt.distance(analysis.biggestClimb!.lengthMeters, metric: metric)} '
                        '${Fmt.distanceUnit(metric: metric)} '
                        '@ ${analysis.biggestClimb!.averageGradientPercent.toStringAsFixed(1)} %',
                        style: LR.body.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  _action(Icons.list, S.waypointsShort, _openWaypoints),
                  _action(Icons.tune, S.profileShort, _openPreferences),
                  _action(
                    Icons.swap_horiz,
                    'Odwróć',
                    hasRoute ? _controller.reverse : null,
                  ),
                  _action(
                    Icons.loop,
                    'Pętla',
                    hasRoute ? _controller.closeLoop : null,
                  ),
                  _action(
                    Icons.delete_outline,
                    'Wyczyść',
                    _controller.isEmpty ? null : _confirmClear,
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: hasRoute && !_saving ? _save : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(S.saveUpper),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
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

  Widget _action(IconData icon, String label, VoidCallback? onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: onTap == null ? LR.muted : LR.ink),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: onTap == null ? LR.muted : LR.inkSoft,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ------------------------------------------------------------- działania

  Future<void> _openSearch() async {
    final place = await showRouteSearchSheet(
      context,
      _services.geocoding,
      near: _controller.points.isEmpty
          ? _initialCenter
          : _controller.points.first,
    );
    if (place == null || !mounted) return;
    _controller.addWaypoint(place.point, name: place.name);
    _mapKey.currentState?.centerOn(place.point);
  }

  Future<void> _useCurrentPosition() async {
    final position = await _services.location.lastKnown();
    if (position == null) {
      if (mounted) {
        showLrMessage(context, S.noGpsPosition, error: true);
      }
      return;
    }
    _controller.addWaypoint(position, name: S.myPosition);
    _mapKey.currentState?.centerOn(position);
  }

  Future<void> _openWaypoints() async {
    await showWaypointListSheet(context, _controller);
    if (mounted) setState(() {});
  }

  Future<void> _openPreferences() async {
    final preferences = await showRoutePreferencesSheet(
      context,
      _controller.preferences,
    );
    if (preferences != null) _controller.setPreferences(preferences);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wyczyścić trasę?'),
        content: const Text('Wszystkie punkty zostaną usunięte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LR.alert),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Wyczyść'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _controller.clear();
      setState(() => _selectedWaypoint = null);
    }
  }

  Future<void> _save() async {
    final name = await _askName();
    if (name == null || !mounted) return;

    setState(() => _saving = true);
    try {
      // Wysokość musi być w zapisanej trasie, żeby briefing i podjazdy
      // działały też bez sieci.
      final points = _controller.points.any((p) => p.elevation != null)
          ? _controller.points
          : await _services.routing.withElevation(_controller.points);

      final summary = await _services.routes.saveRoute(
        id: widget.existing?.id,
        name: name,
        description: _controller.description,
        tags: _controller.tags,
        points: points,
        waypoints: _controller.waypoints,
        preferences: _controller.preferences,
        source: widget.existing == null
            ? RouteSource.builder
            : widget.existing!.source,
      );
      if (widget.existing == null) {
        await _services.routes.deleteDraft(draftId);
      }
      if (!mounted) return;
      Navigator.of(context).pop(summary);
    } catch (e) {
      if (mounted) {
        showLrMessage(context, 'Nie udało się zapisać: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askName() async {
    final nameField = TextEditingController(
      text: _controller.name.isEmpty ? '' : _controller.name,
    );
    final descriptionField = TextEditingController(
      text: _controller.description,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zapisz trasę'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameField,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: S.routeName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionField,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Opis (opcjonalnie)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, nameField.text),
            child: Text(S.save),
          ),
        ],
      ),
    );
    _controller.description = descriptionField.text;
    nameField.dispose();
    descriptionField.dispose();
    if (result == null) return null;
    final trimmed = result.trim();
    return trimmed.isEmpty ? S.unnamedRoute : trimmed;
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(5),
    child: Container(
      height: 40,
      decoration: BoxDecoration(
        color: selected ? LR.accent.withValues(alpha: 0.16) : LR.surface,
        border: Border.all(color: selected ? LR.accentDeep : LR.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: selected ? LR.accentDeep : LR.inkSoft),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? LR.accentDeep : LR.inkSoft,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoutingBadge extends StatelessWidget {
  const _RoutingBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: LR.surface,
      border: Border.all(color: LR.lineStrong),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 9),
        Text('Liczę trasę…', style: LR.fieldLabel.copyWith(fontSize: 10)),
      ],
    ),
  );
}
