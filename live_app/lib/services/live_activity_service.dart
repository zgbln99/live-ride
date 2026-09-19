import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../i18n/strings.dart';
import '../models/navigation_plan.dart';
import '../models/ride_metrics.dart';

/// Drives the iOS Live Activity on the Lock Screen and Dynamic Island.
///
/// The native side owns the presentation; this side owns what is worth
/// showing and how often. ActivityKit budgets updates, and a Lock Screen that
/// redraws every 250 ms is both wasteful and unreadable, so values are pushed
/// on a fixed cadence and only when something a rider would notice changed.
class LiveActivityService {
  LiveActivityService({MethodChannel? channel, bool? platformSupported})
    : _channel = channel ?? const MethodChannel('live_ride/live_activity'),
      _platformSupported = platformSupported;

  /// Apple's guidance is sparse updates; once a second is plenty for a Lock
  /// Screen glance and keeps well inside the budget.
  static const Duration minimumInterval = Duration(milliseconds: 1000);

  final MethodChannel _channel;

  /// Overrides the host-platform check so the channel contract can be tested
  /// off-device. Null means "ask the platform", which is what ships.
  final bool? _platformSupported;

  bool _active = false;
  bool? _supported;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSignature;
  String? _lastError;

  bool get isActive => _active;
  String? get lastError => _lastError;

  /// Live Activities exist only on iOS 16.1 and later. The native side is the
  /// authority; this caches its answer.
  Future<bool> isSupported() async {
    if (!(_platformSupported ?? Platform.isIOS)) return false;
    final cached = _supported;
    if (cached != null) return cached;
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      _supported = result ?? false;
    } on PlatformException catch (e) {
      _lastError = e.message;
      _supported = false;
    } on MissingPluginException {
      // The widget extension is not installed in this build.
      _supported = false;
    }
    return _supported!;
  }

  Future<void> start({
    required String riderName,
    required String title,
    required bool navigating,
  }) async {
    if (!await isSupported() || _active) return;
    try {
      await _channel.invokeMethod<void>('start', {
        'riderName': riderName,
        'title': title,
        'navigating': navigating,
      });
      _active = true;
      _lastSignature = null;
      _lastError = null;
    } on PlatformException catch (e) {
      // A rider who has Live Activities switched off in Settings must not see
      // a ride fail because of it.
      _lastError = e.message;
      _active = false;
    } on MissingPluginException {
      _active = false;
    }
  }

  /// Pushes a new snapshot, throttled and de-duplicated.
  Future<void> update({
    required RideMetrics metrics,
    required bool paused,
    required bool live,
    required bool metric,
    NavigationProgress? progress,
    bool automaticPause = false,
  }) async {
    if (!_active) return;

    final payload = buildPayload(
      metrics: metrics,
      paused: paused,
      live: live,
      metric: metric,
      progress: progress,
      automaticPause: automaticPause,
    );
    final signature = payload.values.join('|');
    final now = DateTime.now();
    if (signature == _lastSignature) return;
    if (now.difference(_lastPush) < minimumInterval) return;

    _lastPush = now;
    _lastSignature = signature;
    try {
      await _channel.invokeMethod<void>('update', payload);
    } on PlatformException catch (e) {
      _lastError = e.message;
    } on MissingPluginException {
      _active = false;
    }
  }

  Future<void> end() async {
    if (!_active) return;
    _active = false;
    _lastSignature = null;
    try {
      await _channel.invokeMethod<void>('end');
    } on PlatformException catch (e) {
      _lastError = e.message;
    } on MissingPluginException {
      // Nothing to end.
    }
  }

  /// The exact map handed to Swift.
  ///
  /// Everything is pre-formatted here rather than in Swift: the widget then
  /// has no unit logic of its own to disagree with the ride screen, and a
  /// Lock Screen glance always matches the handlebar.
  @visibleForTesting
  Map<String, Object?> buildPayload({
    required RideMetrics metrics,
    required bool paused,
    required bool live,
    required bool metric,
    NavigationProgress? progress,
    bool automaticPause = false,
  }) {
    final maneuver = progress?.next;
    return {
      'speed': Fmt.speed(metrics.speedKmh, metric: metric),
      'speedUnit': Fmt.speedUnit(metric: metric),
      'distance': Fmt.distance(metrics.distanceMeters, metric: metric),
      'distanceUnit': Fmt.distanceUnit(metric: metric),
      'elapsed': Fmt.duration(metrics.elapsed),
      'heartRate': metrics.heartRate?.toString() ?? '--',
      'ascent': Fmt.elevation(metrics.elevationGainMeters, metric: metric),
      'ascentUnit': Fmt.elevationUnit(metric: metric),
      'paused': paused,
      // Gotowa etykieta, a nie flaga do zinterpretowania po stronie Swifta:
      // ekran blokady ma mówić dokładnie to samo co kierownica, a „PAUZA"
      // i „AUTO PAUZA" to dla zawodnika dwie różne sytuacje.
      'pauseLabel': !paused
          ? ''
          : (automaticPause ? S.autoPauseShort : S.manualPauseShort),
      'live': live,
      'maneuver': maneuver?.instruction ?? '',
      'maneuverDistance': maneuver == null
          ? ''
          : '${Fmt.turnDistance(progress!.distanceToManeuver, metric: metric)} '
                '${Fmt.turnDistanceUnit(progress.distanceToManeuver, metric: metric)}',
      // A stable symbol name so the widget does not have to map Valhalla
      // maneuver codes itself.
      'maneuverSymbol': _symbolFor(maneuver?.type),
      'offRoute': progress?.offRoute ?? false,
    };
  }

  /// Valhalla maneuver type to an SF Symbol the widget can render directly.
  String _symbolFor(int? type) => switch (type) {
    9 => 'arrow.turn.up.right',
    10 => 'arrow.turn.right.up',
    11 => 'arrow.turn.right.down',
    12 || 13 => 'arrow.uturn.left',
    14 => 'arrow.turn.left.down',
    15 => 'arrow.turn.left.up',
    16 => 'arrow.turn.up.left',
    26 || 27 => 'arrow.triangle.turn.up.right.circle',
    4 || 5 || 6 => 'flag.checkered',
    7 || 8 || 17 || 22 => 'arrow.up',
    _ => 'location.north.line',
  };
}
