import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../models/ride_route.dart';
import '../../services/app_services.dart';
import '../../services/gpx_service.dart';
import '../../widgets/lr_common.dart';
import '../../widgets/track_preview.dart';
import '../ride_computer_screen.dart';
import '../route_builder_screen.dart';
import '../route_detail_screen.dart';

/// The route library: imported GPX files, ready to ride.
class RoutesTab extends StatefulWidget {
  const RoutesTab({super.key});

  @override
  State<RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends State<RoutesTab> {
  List<RouteSummary> _routes = const [];
  bool _loading = true;
  bool _importing = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final routes = await AppServices.of(context).routes.list(refresh: true);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loading = false;
    });
  }

  List<RouteSummary> get _visible {
    if (_query.trim().isEmpty) return _routes;
    final needle = _query.toLowerCase();
    return _routes
        .where((route) => route.name.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final metric = AppServices.of(context).profile.profile.metricUnits;

    return Column(
      children: [
        Container(
          color: LR.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 19),
                      hintText: 'Szukaj tras',
                      fillColor: LR.panel,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _openBuilder,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.add_road, size: 18),
                  label: const Text('PLANUJ'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _importing ? null : _import,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _importing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined, size: 18),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _visible.isEmpty
              ? LrEmptyState(
                  icon: Icons.route_outlined,
                  title: _routes.isEmpty ? 'No routes yet' : 'No matches',
                  message: _routes.isEmpty
                      ? 'Import a GPX file from Files, iCloud Drive or any '
                            'cloud provider and Live Ride will navigate it '
                            'turn by turn.'
                      : 'Nothing in your library matches "$_query".',
                  action: _routes.isEmpty
                      ? FilledButton.icon(
                          onPressed: _importing ? null : _import,
                          icon: const Icon(
                            Icons.file_upload_outlined,
                            size: 18,
                          ),
                          label: const Text('IMPORT GPX'),
                        )
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    itemCount: _visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _routeCard(_visible[index], metric),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _routeCard(RouteSummary route, bool metric) => LrPanel(
    padding: EdgeInsets.zero,
    onTap: () => _open(route),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                height: 64,
                child: TrackPreview(points: route.preview, strokeWidth: 2.4),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tag(route.shape.label),
                        _tag(route.source.label, accent: route.isImported),
                        _tag(
                          route.lastUsedAt == null
                              ? 'ADDED ${Fmt.date(route.createdAt)}'
                              : 'RIDDEN ${Fmt.date(route.lastUsedAt!)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: LrStat(
                  label: 'Dystans',
                  value: Fmt.distance(route.distanceMeters, metric: metric),
                  unit: Fmt.distanceUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
              Expanded(
                child: LrStat(
                  label: 'Podjazd',
                  value: Fmt.elevation(route.ascentMeters, metric: metric),
                  unit: Fmt.elevationUnit(metric: metric),
                  valueSize: 18,
                ),
              ),
              TextButton.icon(
                onPressed: () => _navigate(route),
                icon: const Icon(Icons.navigation, size: 17),
                label: const Text('JEDŹ'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Działania',
                icon: const Icon(Icons.more_vert, size: 20, color: LR.inkSoft),
                onSelected: (value) => _action(value, route),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'preview', child: Text('Podgląd')),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Edytuj w kreatorze'),
                  ),
                  PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                  PopupMenuItem(value: 'delete', child: Text('Usuń')),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _tag(String text, {bool accent = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: accent ? LR.accent.withValues(alpha: 0.16) : LR.panel,
      border: Border.all(color: accent ? LR.accentDeep : LR.line),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.7,
        color: accent ? LR.accentDeep : LR.inkSoft,
      ),
    ),
  );

  Future<void> _action(String action, RouteSummary route) async {
    switch (action) {
      case 'preview':
        await _open(route);
      case 'edit':
        await _openBuilder(existing: route);
      case 'rename':
        await _rename(route);
      case 'delete':
        await _delete(route);
    }
  }

  Future<void> _openBuilder({RouteSummary? existing}) async {
    final created = await Navigator.of(context).push<RouteSummary>(
      MaterialPageRoute<RouteSummary>(
        builder: (_) => RouteBuilderScreen(existing: existing),
      ),
    );
    await _load();
    if (created != null && mounted) {
      showLrMessage(context, 'Zapisano trasę \${created.name}');
    }
  }

  Future<void> _open(RouteSummary route) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(summary: route),
      ),
    );
    unawaited(_load());
  }

  Future<void> _navigate(RouteSummary summary) async {
    final services = AppServices.of(context);
    showLrMessage(context, 'Preparing ${summary.name}…');
    try {
      final route = await services.routes.load(summary);
      final plan = await services.api.buildNavigation(route);
      await services.routes.markUsed(summary);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RideComputerScreen(route: route, plan: plan),
        ),
      );
      unawaited(_load());
    } on GpxException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    }
  }

  Future<void> _rename(RouteSummary route) async {
    final controller = TextEditingController(text: route.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zmień nazwę trasy'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nazwa trasy'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await AppServices.of(context).routes.rename(route, name);
    unawaited(_load());
  }

  Future<void> _delete(RouteSummary route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this route?'),
        content: Text('"${route.name}" will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LR.alert),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppServices.of(context).routes.delete(route);
    unawaited(_load());
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final imported = await AppServices.of(context).routes.importFromPicker();
      if (!mounted) return;
      if (imported != null) {
        await _load();
        if (mounted) {
          showLrMessage(
            context,
            '${imported.name} imported · '
            '${Fmt.distance(imported.distanceMeters)} km · '
            '${imported.pointCount} points',
          );
        }
      }
    } on GpxException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) {
        showLrMessage(context, 'GPX import failed: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
