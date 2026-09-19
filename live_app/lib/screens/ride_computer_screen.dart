import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/formatters.dart';
import '../core/idle_chrome_controller.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/navigation_plan.dart';
import '../models/ride_data_field.dart';
import '../models/ride_pages.dart';
import '../models/ride_record.dart';
import '../models/ride_route.dart';
import '../services/app_services.dart';
import '../services/location_service.dart';
import '../services/ride_recorder.dart';
import '../widgets/chrome_fade.dart';
import '../widgets/climb_pro_panel.dart';
import '../widgets/lr_common.dart';
import '../widgets/navigation_header.dart';
import '../widgets/ride_controls.dart';
import '../widgets/ride_alert_overlay.dart';
import '../widgets/ride_page_view.dart';
import '../widgets/screen_lock_overlay.dart';
import '../widgets/sos_overlay.dart';
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

  /// Dotknięcie przywraca sterowanie — ale nie w trybie wyścigu.
  ///
  /// W wyścigu ekran ma pokazywać tylko liczby, a przypadkowe muśnięcie
  /// kierownicy nie może tego psuć. Świadome przytrzymanie
  /// ([_wakeChromeDeliberately]) działa zawsze, więc z trybu zawsze da się
  /// wyjść — wyjście bez wyjścia byłoby pułapką.
  void _wakeChrome() {
    if (_services.race.isRaceMode) return;
    _chrome.wake();
  }

  void _wakeChromeDeliberately() => _chrome.wake();

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
        services.alerts,
        services.race,
        services.safety,
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
                : Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onLongPress: _wakeChromeDeliberately,
                        child: Listener(
                          onPointerDown: (_) => _wakeChrome(),
                          child: LayoutBuilder(
                            builder: (context, constraints) => Column(
                              children: [
                                if (navigating)
                                  NavigationHeader(
                                    progress: recorder.progress,
                                    metric: profile.metricUnits,
                                    routeName: recorder.route?.name ?? S.route,
                                    etaSeconds: _etaSeconds(recorder),
                                    live: services.live.isActive,
                                    mapMatched:
                                        recorder.plan?.mapMatched ?? true,
                                    chromeVisible: _chromeVisible,
                                    onExit: _confirmExit,
                                    onOverview: () =>
                                        _mapKey.currentState?.fitRoute(
                                          points: recorder.plan?.shape,
                                        ),
                                  )
                                else
                                  _freeRideHeader(recorder),
                                // ClimbPro wchodzi tylko wtedy, gdy zawodnik jest
                                // na wykrytym podjeździe; poza nim nie zabiera
                                // mapie ani piksela.
                                if (recorder.climbProgress != null)
                                  ClimbProPanel(
                                    progress: recorder.climbProgress!,
                                    profile:
                                        recorder.route?.analysis.profile ??
                                        const [],
                                    metric: profile.metricUnits,
                                  ),
                                // Powiadomienie wjeżdża nad mapę, nigdy nad pola
                                // danych ani nad pauzę.
                                RideAlertOverlay(
                                  alert: services.alerts.current,
                                  onDismiss: services.alerts.dismiss,
                                ),
                                Expanded(child: _mapArea(recorder)),
                                RidePageView(
                                  key: _pagesKey,
                                  pages: profile.ridePages,
                                  height: _gridHeight(
                                    profile
                                        .ridePages[_pageIndex.clamp(
                                          0,
                                          profile.ridePages.length - 1,
                                        )]
                                        .layout,
                                    constraints.maxHeight,
                                  ),
                                  showIndicator: _chromeVisible,
                                  onPageChanged: (index) =>
                                      setState(() => _pageIndex = index),
                                  // While the controls are retired a tap is a
                                  // request for them back, not a request to
                                  // reconfigure a field.
                                  onFieldTap: _chromeVisible
                                      ? (_, _) => _openFieldPicker()
                                      : null,
                                  // Przytrzymanie zmienia to jedno pole w miejscu,
                                  // bez wchodzenia w ustawienia.
                                  onFieldLongPress: _chromeVisible
                                      ? _replaceField
                                      : null,
                                  data: RideFieldContext(
                                    metrics: recorder.metrics,
                                    metric: profile.metricUnits,
                                    weather: services.weather.current,
                                    remainingMeters:
                                        recorder.progress?.remainingMeters,
                                    etaSeconds: _etaSeconds(recorder)?.round(),
                                    training: services.profile.trainingProfile,
                                    riderWeightKg: profile.weightKg,
                                  ),
                                ),
                                ChromeFade(
                                  visible: _chromeVisible,
                                  collapse: true,
                                  child: RideControls(
                                    state: recorder.state,
                                    busy:
                                        _busy ||
                                        recorder.state == RideState.saving,
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
                      ScreenLockOverlay(
                        locked: services.race.isScreenLocked,
                        onUnlock: services.race.unlockScreen,
                      ),
                      // Alarm jest ponad wszystkim, także ponad blokadą
                      // ekranu: nie ma stanu, w którym zawodnik nie może go
                      // anulować.
                      SosOverlay(safety: services.safety, onSend: _sendSos),
                    ],
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
  double _preferredGridHeight(RideFieldLayout layout) => layout.preferredHeight;

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
                  tooltip: S.exitRide,
                  visualDensity: VisualDensity.compact,
                  color: LR.ink,
                ),
              ),
              const SizedBox(width: 2),
              LrStatusChip(
                label: paused ? S.paused : S.recording,
                color: paused ? LR.inkSoft : LR.alert,
                filled: !paused,
              ),
              const Spacer(),
              Text(
                Fmt.duration(recorder.metrics.elapsed),
                style: LR.fieldValue(21),
              ),
              const SizedBox(width: 4),
              Text(S.elapsed, style: LR.fieldLabel.copyWith(fontSize: 9)),
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
                : Text(S.mapUnavailableOffline, style: LR.body),
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
                  tooltip: S.rideSettings,
                  onPressed: _openRideSettings,
                ),
                const SizedBox(height: 8),
                LrMapButton(
                  icon: Icons.sensors,
                  tooltip: S.live,
                  active: services.live.isActive,
                  onPressed: _openLiveSheet,
                ),
                if (services.spotify.isConnected) ...[
                  const SizedBox(height: 8),
                  LrMapButton(
                    icon: Icons.graphic_eq,
                    tooltip: S.music,
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
                  tooltip: S.recenter,
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
                      tooltip: S.zoomIn,
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
            accuracy == null ? S.noFix : '±${accuracy.round()} m',
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
              S.liveOffline,
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
              child: Text(S.openSettingsButton),
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
            child: Text(S.tryAgain),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(S.back),
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
        animation: Listenable.merge([
          services.profile,
          services.race,
          services.safety,
        ]),
        builder: (context, _) {
          final profile = services.profile.profile;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: LrSectionHeader(title: S.rideSettings),
                ),
                SwitchListTile(
                  value: profile.headingUp,
                  onChanged: (value) => services.profile.update(
                    profile.copyWith(headingUp: value),
                  ),
                  title: Text(S.headingUp),
                  subtitle: Text(S.headingUpSubtitle),
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
                  title: Text(S.keepScreenOn),
                ),
                SwitchListTile(
                  value: profile.weatherEnabled,
                  onChanged: (value) => services.profile.update(
                    profile.copyWith(weatherEnabled: value),
                  ),
                  title: Text(S.showWeather),
                ),
                ListTile(
                  leading: const Icon(Icons.grid_view),
                  title: Text(S.dataFields),
                  subtitle: Text(
                    profile.ridePages.map((page) => page.name).join(' · '),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openFieldPicker();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.flag_outlined),
                  value: services.race.isRaceMode,
                  onChanged: (value) {
                    unawaited(services.race.setRaceMode(value));
                  },
                  title: Text(S.raceMode),
                  subtitle: Text(
                    services.race.lastError ?? S.raceModeHint,
                    style: services.race.lastError == null
                        ? null
                        : const TextStyle(color: LR.alert),
                  ),
                ),
                if (services.race.isRaceMode)
                  SwitchListTile(
                    value: services.race.boostBrightness,
                    onChanged: (value) {
                      unawaited(services.race.setBoostBrightness(value));
                    },
                    title: Text(S.boostBrightness),
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.report_problem_outlined,
                    color: LR.alert,
                  ),
                  title: Text(
                    S.sos,
                    style: const TextStyle(
                      color: LR.alert,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    services.safety.settings.crashContacts.isEmpty
                        ? S.crashDetectionNeedsContact
                        : S.sosCountdown(
                            services.safety.settings.countdownSeconds,
                          ),
                  ),
                  onTap: services.safety.settings.crashContacts.isEmpty
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          services.safety.triggerManual();
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(S.lockScreen),
                  subtitle: Text(S.holdToUnlock.toLowerCase()),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    services.race.lockScreen();
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

  final GlobalKey<RidePageViewState> _pagesKey = GlobalKey();
  int _pageIndex = 0;

  /// Podmienia jedno pole na przytrzymanej pozycji.
  Future<void> _replaceField(int pageIndex, int fieldIndex) async {
    final field = await _holdChrome(
      () => showFieldPicker(context, _services.profile.profile),
    );
    if (field == null || !mounted) return;
    final profileService = _services.profile;
    final profile = profileService.profile;
    final pages = List<RideDataPage>.of(profile.ridePages);
    if (pageIndex < 0 || pageIndex >= pages.length) return;
    pages[pageIndex] = pages[pageIndex].withFieldAt(fieldIndex, field);
    await profileService.update(profile.copyWith(pages: pages));
    if (mounted) setState(() {});
  }

  /// Wysyła alarm i pokazuje, co dalej, gdy system odmówi.
  Future<void> _sendSos() async {
    final sent = await _services.safety.sendAlert();
    if (!mounted) return;
    if (!sent) {
      showLrMessage(context, S.sosSendFailed, error: true);
      return;
    }
    _services.safety.cancelAlarm();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: LrSectionHeader(title: S.rideInProgress),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(S.keepRiding),
              onTap: () => Navigator.pop(sheetContext, 'keep'),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: Text(S.finishAndSave),
              onTap: () => Navigator.pop(sheetContext, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: LR.alert),
              title: Text(
                S.discardRide,
                style: const TextStyle(color: LR.alert),
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
