import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../models/ride_route.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import '../widgets/ride_map.dart';
import '../widgets/track_preview.dart';
import 'ride_computer_screen.dart';

/// Route preview: see it on the map, check the numbers, then ride it.
class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({super.key, required this.summary});

  final RouteSummary summary;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late RouteSummary _summary = widget.summary;
  RideRoute? _route;
  String? _style;
  String? _error;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = AppServices.of(context);
    try {
      final route = await services.routes.load(_summary);
      if (mounted) setState(() => _route = route);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    try {
      final style = await services.api.fetchMapStyle();
      if (mounted) setState(() => _style = style);
    } catch (_) {
      // The sketch preview below covers an offline map.
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final metric = services.profile.profile.metricUnits;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ROUTE'),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
          IconButton(
            tooltip: 'Share GPX',
            icon: const Icon(Icons.ios_share),
            onPressed: _share,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _error != null
                ? LrEmptyState(
                    icon: Icons.error_outline,
                    title: 'Route unavailable',
                    message: _error!,
                  )
                : _style != null && _route != null
                ? RideMap(
                    styleJson: _style!,
                    position: null,
                    follow: false,
                    headingUp: false,
                    fitRouteOnLoad: true,
                    onFollowChanged: (_) {},
                    routePoints: _route!.points,
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: TrackPreview(
                      points: _route?.points ?? _summary.preview,
                      strokeWidth: 3,
                      background: LR.surface,
                    ),
                  ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: LR.surface,
              border: Border(top: BorderSide(color: LR.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _summary.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LR.title,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_summary.shape.label} · '
                      '${_summary.source.label} · '
                      '${Fmt.date(_summary.createdAt)}',
                      style: LR.body.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: LrStat(
                            label: 'Distance',
                            value: Fmt.distance(
                              _summary.distanceMeters,
                              metric: metric,
                            ),
                            unit: Fmt.distanceUnit(metric: metric),
                            valueSize: 26,
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'Ascent',
                            value: Fmt.elevation(
                              _summary.ascentMeters,
                              metric: metric,
                            ),
                            unit: Fmt.elevationUnit(metric: metric),
                            valueSize: 26,
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'Points',
                            value: '${_summary.pointCount}',
                            valueSize: 26,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _route == null || _starting ? null : _navigate,
                      icon: _starting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.navigation, size: 18),
                      label: Text(_starting ? 'PREPARING…' : 'NAVIGATE'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigate() async {
    final route = _route;
    if (route == null) return;
    setState(() => _starting = true);
    final services = AppServices.of(context);
    final plan = await services.api.buildNavigation(route);
    await services.routes.markUsed(_summary);
    if (!mounted) return;
    setState(() => _starting = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideComputerScreen(route: route, plan: plan),
      ),
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _summary.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename route'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Route name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await AppServices.of(context).routes.rename(_summary, name);
    if (mounted)
      setState(() => _summary = _summary.copyWith(name: name.trim()));
  }

  Future<void> _share() async {
    final file = await AppServices.of(context).routes.exportGpx(_summary);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: _summary.name),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this route?'),
        content: Text('"${_summary.name}" will be removed from this device.'),
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
    await AppServices.of(context).routes.delete(_summary);
    if (mounted) Navigator.of(context).pop(true);
  }
}
