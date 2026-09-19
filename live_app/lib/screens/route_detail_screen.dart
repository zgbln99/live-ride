import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/geo.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/ride_route.dart';
import '../models/route/route_analysis.dart';
import '../models/route/route_briefing.dart';
import '../models/route/route_weather.dart';
import '../services/app_services.dart';
import '../widgets/climb_profile.dart';
import '../widgets/lr_common.dart';
import '../widgets/ride_map.dart';
import '../widgets/route_weather_strip.dart';
import '../widgets/track_preview.dart';
import 'ride_computer_screen.dart';

/// Briefing trasy: mapa, liczby, profil, podjazdy i pogoda — wszystko, co
/// zawodnik chce wiedzieć, zanim naciśnie NAWIGUJ.
///
/// Nic tu nie jest wymyślone: jeśli trasa nie ma wysokości, nie ma sekcji
/// podjazdów; jeśli prognoza nie doszła, nie ma sekcji pogody.
class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({super.key, required this.summary});

  final RouteSummary summary;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late RouteSummary _summary = widget.summary;
  RideRoute? _route;
  RouteBriefing? _briefing;
  RouteForecast? _forecast;
  String? _style;
  String? _error;
  bool _starting = false;
  bool _loadingForecast = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = AppServices.of(context);
    try {
      final route = await services.routes.load(_summary);
      if (!mounted) return;
      setState(() {
        _route = route;
        _briefing = _buildBriefing(route, null);
      });
      unawaitedForecast(route);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    try {
      final style = await services.api.fetchMapStyle();
      if (mounted) setState(() => _style = style);
    } catch (_) {
      // Szkic trasy poniżej wystarcza, gdy styl mapy nie dojdzie.
    }
  }

  RouteBriefing _buildBriefing(RideRoute route, RouteForecast? forecast) {
    final profile = AppServices.of(context).profile.profile;
    return RouteBriefing.build(
      analysis: route.analysis,
      preferences: route.preferences,
      forecast: forecast,
      riderWeightKg: profile.weightKg,
      metric: profile.metricUnits,
    );
  }

  /// Prognoza leci w tle — briefing pokazuje się natychmiast, a pogoda
  /// dokleja się, gdy dojdzie.
  void unawaitedForecast(RideRoute route) {
    if (route.points.length < 2) return;
    setState(() => _loadingForecast = true);
    AppServices.of(context).routeWeather
        .forecast(
          points: route.points,
          estimatedDuration: route.estimatedDuration(),
        )
        .then((forecast) {
          if (!mounted) return;
          setState(() {
            _loadingForecast = false;
            _forecast = forecast.isEmpty ? null : forecast;
            _briefing = _buildBriefing(route, _forecast);
          });
        })
        .catchError((_) {
          if (mounted) setState(() => _loadingForecast = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final metric = services.profile.profile.metricUnits;
    final route = _route;
    final briefing = _briefing;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(S.route)),
        body: LrEmptyState(
          icon: Icons.error_outline,
          title: S.routeUnavailable,
          message: _error!,
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            title: Text(S.briefingTitle),
            actions: [
              IconButton(
                tooltip: S.rename,
                icon: const Icon(Icons.edit_outlined),
                onPressed: _rename,
              ),
              IconButton(
                tooltip: S.exportGpx,
                icon: const Icon(Icons.ios_share),
                onPressed: _share,
              ),
              IconButton(
                tooltip: S.downloadOfflineMap,
                icon: Icon(
                  services.offlineMaps.hasRegionFor(_summary.id)
                      ? Icons.offline_pin
                      : Icons.download_for_offline_outlined,
                ),
                onPressed: services.offlineMaps.isSupported
                    ? _downloadOffline
                    : null,
              ),
              IconButton(
                tooltip: S.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _style != null && route != null
                  ? RideMap(
                      styleJson: _style!,
                      position: null,
                      follow: false,
                      headingUp: false,
                      fitRouteOnLoad: true,
                      onFollowChanged: (_) {},
                      routePoints: route.points,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
                      child: TrackPreview(
                        points: route?.points ?? _summary.preview,
                        strokeWidth: 3,
                        background: LR.surface,
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                    '${_summary.shape.label} · ${_summary.source.label} · '
                    '${Fmt.date(_summary.createdAt)}',
                    style: LR.body.copyWith(fontSize: 12.5),
                  ),
                  if (briefing != null && briefing.headline.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in briefing.headline)
                          LrStatusChip(label: item, color: LR.accentDeep),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _StatsRow(summary: _summary, route: route, metric: metric),
                ],
              ),
            ),
          ),
          if (briefing != null && briefing.lines.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: LrPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in briefing.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: _BriefingRow(line: line),
                        ),
                      if (_loadingForecast)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                S.loadingForecast,
                                style: LR.body.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (route != null && route.analysis.hasElevationData) ...[
            SliverToBoxAdapter(
              child: LrSectionHeader(title: S.elevationProfile),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClimbProfileChart(
                  samples: route.analysis.profile,
                  climbs: route.analysis.climbs,
                  metric: metric,
                ),
              ),
            ),
          ],
          if (route != null && route.analysis.climbs.isNotEmpty) ...[
            SliverToBoxAdapter(child: LrSectionHeader(title: S.climbs)),
            SliverList.separated(
              itemCount: route.analysis.climbs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ClimbTile(
                  climb: route.analysis.climbs[index],
                  index: index + 1,
                  metric: metric,
                  onCreateSegment: () =>
                      _createSegment(route, route.analysis.climbs[index]),
                ),
              ),
            ),
          ],
          if (_forecast != null) ...[
            SliverToBoxAdapter(
              child: LrSectionHeader(title: S.weatherAlongRoute),
            ),
            SliverToBoxAdapter(
              child: RouteWeatherStrip(forecast: _forecast!, metric: metric),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              child: FilledButton.icon(
                onPressed: route == null || _starting ? null : _navigate,
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
                label: Text(_starting ? S.preparing : S.navigate),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wycina podjazd z trasy i zapisuje go jako segment.
  ///
  /// Segment bierze dokładnie te punkty trasy, które składają się na
  /// podjazd — nie przybliżenie po prostej — żeby dopasowanie w czasie
  /// jazdy szło po tej samej geometrii, na której liczono nachylenie.
  Future<void> _createSegment(RideRoute route, Climb climb) async {
    final cumulative = route.cumulativeMeters;
    final points = <GeoPoint>[];
    for (var i = 0; i < route.points.length; i++) {
      final along = cumulative[i];
      if (along < climb.startDistanceMeters) continue;
      if (along > climb.endDistanceMeters) break;
      points.add(route.points[i]);
    }
    if (points.length < 3) return;

    final services = AppServices.of(context);
    final segment = await services.segments.create(
      name: '${route.name} — ${climb.category.label}',
      points: points,
      sourceRouteId: route.id,
    );
    if (!mounted) return;
    showLrMessage(context, S.segmentCreated(segment.name));
  }

  /// Pobiera mapę wokół trasy, żeby nawigacja działała bez zasięgu.
  Future<void> _downloadOffline() async {
    final route = _route;
    if (route == null) return;
    final services = AppServices.of(context);
    if (services.offlineMaps.hasRegionFor(route.id)) {
      final region = services.offlineMaps.regionFor(route.id);
      if (region != null) await services.offlineMaps.deleteRegion(region.id);
      return;
    }
    await services.offlineMaps.downloadForRoute(
      routeId: route.id,
      routeName: route.name,
      points: route.points,
    );
    if (!mounted) return;
    showLrMessage(context, S.offlineMapReady);
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
        title: Text(S.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.route),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(S.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await AppServices.of(context).routes.rename(_summary, name);
    if (mounted) {
      setState(() => _summary = _summary.copyWith(name: name.trim()));
    }
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
        title: Text(S.deleteRouteTitle),
        content: Text(S.deleteRouteMessage(_summary.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LR.alert),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppServices.of(context).routes.delete(_summary);
    if (mounted) Navigator.of(context).pop(true);
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.summary,
    required this.route,
    required this.metric,
  });

  final RouteSummary summary;
  final RideRoute? route;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final duration = route?.estimatedDuration();
    return Row(
      children: [
        Expanded(
          child: LrStat(
            label: S.distance,
            value: Fmt.distance(summary.distanceMeters, metric: metric),
            unit: Fmt.distanceUnit(metric: metric),
            valueSize: 26,
          ),
        ),
        Expanded(
          child: LrStat(
            label: S.ascent,
            value: Fmt.elevation(summary.ascentMeters, metric: metric),
            unit: Fmt.elevationUnit(metric: metric),
            valueSize: 26,
          ),
        ),
        Expanded(
          child: LrStat(
            label: S.estimatedTime,
            value: duration == null || duration == Duration.zero
                ? S.notAvailable
                : Fmt.durationCompact(duration),
            valueSize: 26,
          ),
        ),
      ],
    );
  }
}

class _BriefingRow extends StatelessWidget {
  const _BriefingRow({required this.line});

  final BriefingLine line;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (line.tone) {
      BriefingTone.good => (Icons.check_circle_outline, LR.go),
      BriefingTone.warning => (Icons.warning_amber_rounded, LR.alert),
      BriefingTone.neutral => (Icons.circle, LR.lineStrong),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: line.tone == BriefingTone.neutral ? 8 : 16,
            color: color,
          ),
        ),
        SizedBox(width: line.tone == BriefingTone.neutral ? 14 : 8),
        Expanded(
          child: Text(
            line.text,
            style: LR.body.copyWith(
              fontSize: 13.5,
              height: 1.35,
              color: line.tone == BriefingTone.warning ? LR.ink : LR.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClimbTile extends StatelessWidget {
  const _ClimbTile({
    required this.climb,
    required this.index,
    required this.metric,
    this.onCreateSegment,
  });

  final Climb climb;
  final int index;
  final bool metric;
  final VoidCallback? onCreateSegment;

  @override
  Widget build(BuildContext context) {
    return LrPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _categoryColor(climb.category).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              climb.category.shortLabel,
              style: LR
                  .fieldValue(15)
                  .copyWith(color: _categoryColor(climb.category)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$index. ${Fmt.distance(climb.lengthMeters, metric: metric)} '
                  '${Fmt.distanceUnit(metric: metric)} · '
                  '${climb.averageGradientPercent.toStringAsFixed(1)} %',
                  style: LR.fieldValue(16),
                ),
                const SizedBox(height: 2),
                Text(
                  'od ${Fmt.distance(climb.startDistanceMeters, metric: metric)} '
                  '${Fmt.distanceUnit(metric: metric)} · '
                  '+${Fmt.elevation(climb.gainMeters, metric: metric)} '
                  '${Fmt.elevationUnit(metric: metric)} · maks. '
                  '${climb.maxGradientPercent.toStringAsFixed(0)} %',
                  style: LR.body.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          if (onCreateSegment != null)
            IconButton(
              tooltip: S.newSegment,
              icon: const Icon(Icons.timer_outlined, size: 20),
              onPressed: onCreateSegment,
            ),
        ],
      ),
    );
  }

  static Color _categoryColor(ClimbCategory category) => switch (category) {
    ClimbCategory.hc => LR.alert,
    ClimbCategory.one => LR.alert,
    ClimbCategory.two => const Color(0xFFE07A1F),
    ClimbCategory.three => LR.accentDeep,
    ClimbCategory.four => LR.accentDeep,
    ClimbCategory.uncategorised => LR.muted,
  };
}
