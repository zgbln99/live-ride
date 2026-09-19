import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/formatters.dart';
import '../core/idle_chrome_controller.dart';
import '../core/lr_theme.dart';
import '../models/navigation_plan.dart';
import '../models/ride_data_field.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import '../services/app_services.dart';
import '../services/location_service.dart';
import '../services/ride_recorder.dart';
import '../widgets/chrome_fade.dart';
import '../widgets/lr_common.dart';
import '../widgets/navigation_header.dart';
import '../widgets/ride_controls.dart';
import '../widgets/ride_data_grid.dart';
import '../widgets/ride_map.dart';
import '../widgets/weather_field.dart';
import 'data_field_editor.dart';
import 'live_sheet.dart';
import 'music_sheet.dart';
import 'ride_summary_screen.dart';

/// The Live Ride cycling computer.
///
/// One screen serves both modes on purpose: a free ride and a navigated route
/// are the same instrument, the navigated one simply grows a maneuver header.
/// That is what keeps the data fields, map behaviour and controls identical
/// whichever way a ride was started.
class RideComputerScreen extends StatefulWidget {
  const RideComputerScreen({super.key, this.route, this.plan});

  final RideRoute? route;
  final NavigationPlan? plan;

  @override
  State<RideComputerScreen> createState() => _RideComputerScreenState();
}

class _RideComputerScreenState extends State<RideComputerScreen> {
  final GlobalKey<RideMapState> _mapKey = GlobalKey<RideMapState>();

  late final AppServices _services = AppServices.of(context);

  /// Decides when the secondary controls retire. The instrument readings are
  /// never affected by it.
  late final IdleChromeController _chrome = IdleChromeController(
    canRetire: () =>
        _fatalError == null && _services.recorder.state == RideState.recording,
  );

  String? _style;
  String? _fatalError;
  bool _openSettingsOnError = false;
  bool _follow = true;
  bool _busy = false;
  bool _showMap = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  bool get _chromeVisible => _chrome.visible;

  void _wakeChrome() => _chrome.wake();

  /// Runs [action] with the controls pinned open, for anything that puts a
  /// sheet or a dialog on top of the ride computer.
  Future<T> _holdChrome<T>(Future<T> Function() action) async {
    _chrome.hold();
    try {
      return await action();
    } finally {
      _chrome.release();
    }
  }

  Future<void> _boot() async {
    final services = AppServices.of(context);
    if (services.profile.profile.keepScreenAwake) {
      unawaited(WakelockPlus.enable());
    }

    unawaited(_loadStyle(services));

    if (!services.recorder.isActive) {
      try {
        await services.recorder.start(route: widget.route, plan: widget.plan);
      } on LocationUnavailable catch (e) {
        if (!mounted) return;
        setState(() {
          _fatalError = e.message;
          _openSettingsOnError = e.openSettings;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _fatalError = e.toString());
      }
    }
    if (mounted) _chrome.restart();
  }

  Future<void> _loadStyle(AppServices services) async {
    try {
      final style = await services.api.fetchMapStyle();
      if (mounted) setState(() => _style = style);
    } catch (_) {
      // Riding without map tiles is degraded but perfectly usable: every
      // number, the maneuver header and LIVE keep working.
      if (mounted) setState(() => _showMap = false);
    }
  }

  @override
  void dispose() {
    _chrome.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    return AnimatedBuilder(
      animation: Listenable.merge([
        services.recorder,
        services.profile,
        services.weather,
        services.live,
        services.spotify,
        _chrome,
      ]),
      builder: (context, _) {
        final recorder = services.recorder;
        final profile = services.profile.profile;
        final navigating = recorder.isNavigating;

        return PopScope(
          canPop: !recorder.isActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_confirmExit());
          },
          child: Scaffold(
            backgroundColor: LR.canvas,
            body: _fatalError != null
                ? _errorView()
                // Every touch anywhere on the instrument brings the controls
                // back. The listener only observes: it never swallows the
                // gesture, so a pan still pans the map on the same touch.
                : Listener(
                    onPointerDown: (_) => _wakeChrome(),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Column(
                        children: [
                          if (navigating)
                            NavigationHeader(
                              progress: recorder.progress,
                              metric: profile.metricUnits,
                              routeName: recorder.route?.name ?? 'Route',
                              etaSeconds: _etaSeconds(recorder),
                              live: services.live.isActive,
                              mapMatched: recorder.plan?.mapMatched ?? true,
                              chromeVisible: _chromeVisible,
                              onExit: _confirmExit,
                              onOverview: () => _mapKey.currentState?.fitRoute(
                                points: recorder.plan?.shape,
                              ),
                            )
                          else
                            _freeRideHeader(recorder),
                          Expanded(child: _mapArea(recorder)),
                          SizedBox(
                            height: _gridHeight(
                              profile.layout,
                              constraints.maxHeight,
                            ),
                            child: RideDataGrid(
                              fields: profile.activeFields,
                              layout: profile.layout,
                              compact: profile.layout.rows > 2,
                              // While the controls are retired a tap is a
                              // request for them back, not a request to
                              // reconfigure a field.
                              onFieldTap: _chromeVisible
                                  ? (_) => _openFieldPicker()
                                  : null,
                              data: RideFieldContext(
                                metrics: recorder.metrics,
                                metric: profile.metricUnits,
                                weather: services.weather.current,
                                remainingMeters:
                                    recorder.progress?.remainingMeters,
                                etaSeconds: _etaSeconds(recorder)?.round(),
                              ),
                            ),
                          ),
                          ChromeFade(
                            visible: _chromeVisible,
                            collapse: true,
                            child: RideControls(
                              state: recorder.state,
                              busy: _busy || recorder.state == RideState.saving,
                              liveActive: services.live.isActive,
                              onPause: () {
                                recorder.pause();
                                _wakeChrome();
                              },
                              onResume: () {
                                recorder.resume();
                                _wakeChrome();
                              },
                              onStop: _finish,
                              onLive: _openLiveSheet,
                            ),
                          ),
                          // Kept outside the collapse so the bottom row of data
                          // fields never ends up under the home indicator.
                          Container(
                            color: LR.surface,
                            height: MediaQuery.paddingOf(context).bottom,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  double? _etaSeconds(RideRecorder recorder) {
    final progress = recorder.progress;
    if (progress == null) return null;
    final planned = progress.remainingSeconds;
    final speed = recorder.metrics.speedKmh > 6
        ? recorder.metrics.speedKmh
        : recorder.metrics.averageSpeedKmh;
    if (speed > 4) {
      final fromSpeed = progress.remainingMeters / (speed / 3.6);
      // Trust the live pace once there is one; the routing estimate is only a
      // starting point.
      return planned == null ? fromSpeed : (fromSpeed * 0.7 + planned * 0.3);
    }
    return planned;
  }

  /// The height the data fields would like, before the screen has a say.
  double _preferredGridHeight(RideFieldLayout layout) => switch (layout) {
    RideFieldLayout.two => 190,
    RideFieldLayout.four => 194,
    RideFieldLayout.six => 252,
    RideFieldLayout.eight => 296,
  };

  /// The height the data fields actually get.
  ///
  /// On a short phone eight fields plus a maneuver header would squeeze the
  /// map down to nothing, so the instrument is capped at a share of the
  /// screen. Roomy phones are unaffected and get the full preferred height.
  double _gridHeight(RideFieldLayout layout, double availableHeight) {
    final preferred = _preferredGridHeight(layout);
    if (!availableHeight.isFinite || availableHeight <= 0) return preferred;
    return math.min(preferred, availableHeight * 0.42);
  }

  Widget _freeRideHeader(RideRecorder recorder) {
    final paused = recorder.state == RideState.paused;
    return Material(
      color: LR.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 52,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: LR.line)),
          ),
          child: Row(
            children: [
              ChromeFade(
                visible: _chromeVisible,
                child: IconButton(
                  onPressed: _confirmExit,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Exit ride',
                  visualDensity: VisualDensity.compact,
                  color: LR.ink,
                ),
              ),
              const SizedBox(width: 2),
              LrStatusChip(
                label: paused ? 'PAUSED' : 'RECORDING',
                color: paused ? LR.inkSoft : LR.alert,
                filled: !paused,
              ),
              const Spacer(),
              Text(
                Fmt.duration(recorder.metrics.elapsed),
                style: LR.fieldValue(21),
              ),
              const SizedBox(width: 4),
              Text('ELAPSED', style: LR.fieldLabel.copyWith(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapArea(RideRecorder recorder) {
    final services = _services;
    final profile = services.profile.profile;
    final style = _style;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (style != null && _showMap)
          RideMap(
            key: _mapKey,
            styleJson: style,
            position: recorder.position,
            headingDegrees: recorder.metrics.headingDegrees,
            follow: _follow,
            headingUp: profile.headingUp,
            onInteraction: _wakeChrome,
            onFollowChanged: (value) {
              if (_follow != value) setState(() => _follow = value);
            },
            routePoints: recorder.plan?.shape ?? const [],
            trackPoints: recorder.track,
            offRoute: recorder.progress?.offRoute ?? false,
          )
        else
          Container(
            color: LR.canvas,
            alignment: Alignment.center,
            child: _showMap
                ? const CircularProgressIndicator()
                : Text('Map unavailable offline', style: LR.body),
          ),
        Positioned(
          top: 10,
          left: 10,
          child: ChromeFade(
            visible: _chromeVisible,
            child: Column(
              children: [
                LrMapButton(
                  icon: Icons.tune,
                  tooltip: 'Ride settings',
                  onPressed: _openRideSettings,
                ),
                const SizedBox(height: 8),
                LrMapButton(
                  icon: Icons.sensors,
                  tooltip: 'LIVE',
                  active: services.live.isActive,
                  onPressed: _openLiveSheet,
                ),
                if (services.spotify.isConnected) ...[
                  const SizedBox(height: 8),
                  LrMapButton(
                    icon: Icons.graphic_eq,
                    tooltip: 'Music',
                    active: services.spotify.nowPlaying?.isPlaying ?? false,
                    onPressed: _openMusicSheet,
                  ),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (profile.weatherEnabled)
                ChromeFade(
                  visible: _chromeVisible,
                  collapse: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WeatherField(
                      weather: services.weather.current,
                      metric: profile.metricUnits,
                      onTap: () {
                        final position = recorder.position;
                        if (position != null) {
                          unawaited(
                            services.weather.refreshFor(position, force: true),
                          );
                        }
                      },
                    ),
                  ),
                ),
              // Recenter survives the quiet only when the map is not
              // following: it is then the way back, and its absence would
              // strand a rider who had panned away.
              ChromeFade(
                visible: _chromeVisible || !_follow,
                child: LrMapButton(
                  icon: Icons.my_location,
                  tooltip: 'Recenter',
                  active: _follow,
                  onPressed: () => _mapKey.currentState?.recenter(),
                ),
              ),
              ChromeFade(
                visible: _chromeVisible,
                collapse: true,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    LrMapButton(
                      icon: Icons.add,
                      tooltip: 'Zoom in',
                      onPressed: () => _mapKey.currentState?.zoomBy(1),
                    ),
                    const SizedBox(height: 8),
                    LrMapButton(
                      icon: Icons.remove,
                      tooltip: 'Zoom out',
                      onPressed: () => _mapKey.currentState?.zoomBy(-1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          // A degraded signal is not chrome. If the fix is poor or LIVE has
          // dropped, the strip stays up through the quiet.
          child: ChromeFade(
            visible: _chromeVisible || _signalDegraded(recorder),
            child: _signalStrip(recorder),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Center(child: ChromeHint(visible: _chrome.hintVisible)),
        ),
      ],
    );
  }

  /// True when the strip is carrying a warning rather than a reassurance.
  bool _signalDegraded(RideRecorder recorder) {
    final accuracy = recorder.metrics.gpsAccuracyMeters;
    return accuracy == null ||
        accuracy > 25 ||
        (_services.live.isActive && recorder.liveTelemetryFailed);
  }

  Widget _signalStrip(RideRecorder recorder) {
    final accuracy = recorder.metrics.gpsAccuracyMeters;
    final bpm = recorder.metrics.heartRate;
    final liveFailed = _services.live.isActive && recorder.liveTelemetryFailed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: LR.surface,
        border: Border.all(color: LR.lineStrong),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            accuracy == null
                ? Icons.gps_not_fixed
                : accuracy > 25
                ? Icons.gps_not_fixed
                : Icons.gps_fixed,
            size: 14,
            color: accuracy != null && accuracy <= 25 ? LR.go : LR.muted,
          ),
          const SizedBox(width: 5),
          Text(
            accuracy == null ? 'NO FIX' : '±${accuracy.round()} m',
            style: LR.fieldLabel.copyWith(fontSize: 10),
          ),
          if (bpm != null) ...[
            const SizedBox(width: 10),
            const Icon(Icons.favorite, size: 13, color: LR.alert),
            const SizedBox(width: 4),
            Text('$bpm', style: LR.fieldLabel.copyWith(fontSize: 10)),
          ],
          if (liveFailed) ...[
            const SizedBox(width: 10),
            const Icon(Icons.cloud_off, size: 13, color: LR.alert),
            const SizedBox(width: 4),
            Text(
              'LIVE OFFLINE',
              style: LR.fieldLabel.copyWith(fontSize: 10, color: LR.alert),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off, size: 42, color: LR.alert),
          const SizedBox(height: 18),
          Text(
            _fatalError!,
            textAlign: TextAlign.center,
            style: LR.body.copyWith(fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 24),
          if (_openSettingsOnError)
            OutlinedButton(
              onPressed: () => _services.location.openSettings(),
              child: const Text('OPEN SETTINGS'),
            ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () {
              setState(() {
                _fatalError = null;
                _openSettingsOnError = false;
              });
              unawaited(_boot());
            },
            child: const Text('TRY AGAIN'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back'),
          ),
        ],
      ),
    ),
  );

  Future<void> _openMusicSheet() async {
    await _holdChrome(() => showMusicSheet(context, _services));
    if (mounted) setState(() {});
  }

  Future<void> _openLiveSheet() async {
    await _holdChrome(() => showLiveSheet(context, _services));
    if (mounted) setState(() {});
  }

  Future<void> _openRideSettings() => _holdChrome(_showRideSettings);

  Future<void> _showRideSettings() async {
    final services = _services;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: services.profile,
        builder: (context, _) {
          final profile = services.profile.profile;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: LrSectionHeader(title: 'Ride settings'),
                ),
                SwitchListTile(
                  value: profile.headingUp,
                  onChanged: (value) => services.profile.update(
                    profile.copyWith(headingUp: value),
                  ),
                  title: const Text('Heading up'),
                  subtitle: const Text(
                    'Rotate the map with the direction of travel',
                  ),
                ),
                SwitchListTile(
                  value: profile.keepScreenAwake,
                  onChanged: (value) {
                    services.profile.update(
                      profile.copyWith(keepScreenAwake: value),
                    );
                    unawaited(
                      value ? WakelockPlus.enable() : WakelockPlus.disable(),
                    );
                  },
                  title: const Text('Keep the screen on'),
                ),
                SwitchListTile(
                  value: profile.weatherEnabled,
                  onChanged: (value) => services.profile.update(
                    profile.copyWith(weatherEnabled: value),
                  ),
                  title: const Text('Show weather'),
                ),
                ListTile(
                  leading: const Icon(Icons.grid_view),
                  title: const Text('Data fields'),
                  subtitle: Text(profile.layout.label),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openFieldPicker();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFieldPicker() async {
    await _holdChrome(() => showDataFieldEditor(context, _services));
    if (mounted) setState(() {});
  }

  Future<void> _confirmExit() => _holdChrome(_showExitOptions);

  Future<void> _showExitOptions() async {
    final recorder = _services.recorder;
    if (!recorder.isActive) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: LrSectionHeader(title: 'Ride in progress'),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Keep riding'),
              onTap: () => Navigator.pop(sheetContext, 'keep'),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('Finish and save'),
              onTap: () => Navigator.pop(sheetContext, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: LR.alert),
              title: const Text(
                'Discard this ride',
                style: TextStyle(color: LR.alert),
              ),
              onTap: () => Navigator.pop(sheetContext, 'discard'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (!mounted) return;
    switch (choice) {
      case 'save':
        await _finish();
      case 'discard':
        await recorder.discard();
        if (mounted) Navigator.of(context).pop();
      default:
        break;
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    _chrome.hold();
    setState(() => _busy = true);
    RecordedRide? ride;
    try {
      ride = await _services.recorder.stop();
    } finally {
      _chrome.release();
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    if (ride == null) {
      showLrMessage(context, 'Ride discarded — it was too short to save.');
      Navigator.of(context).pop();
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RideSummaryScreen(ride: ride!, justFinished: true),
      ),
    );
  }
}
