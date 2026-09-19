import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/services/live_activity_service.dart';

/// The Dart and Swift sides of the Live Activity are compiled separately and
/// can only disagree at runtime, on a device, where the symptom is a Lock
/// Screen field that silently shows a default. These tests read the Swift
/// sources and hold both ends to the same contract.
void main() {
  final attributes = File('ios_native/Shared/RideActivityAttributes.swift');
  final bridge = File('ios_native/Runner/LiveRideActivityBridge.swift');
  final widget = File('ios_native/LiveRideWidgets/RideLiveActivity.swift');
  final bundle = File('ios_native/LiveRideWidgets/LiveRideWidgetBundle.swift');
  final plist = File('ios_native/LiveRideWidgets/Info.plist');

  test('the native sources are present', () {
    for (final file in [attributes, bridge, widget, bundle, plist]) {
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
    }
  });

  test('Swift reads every key Dart sends', () {
    final swift = attributes.readAsStringSync();
    final consumed = RegExp(
      r'payload\["(\w+)"\]',
    ).allMatches(swift).map((match) => match.group(1)!).toSet();

    final sent = LiveActivityService()
        .buildPayload(
          metrics: const RideMetrics(),
          paused: false,
          live: false,
          metric: true,
        )
        .keys
        .toSet();

    expect(
      sent.difference(consumed),
      isEmpty,
      reason: 'Dart sends keys the widget never reads',
    );
    expect(
      consumed.difference(sent),
      isEmpty,
      reason: 'Swift reads keys Dart never sends',
    );
  });

  test('the bridge answers exactly the methods Dart calls', () {
    final swift = bridge.readAsStringSync();
    for (final method in ['isSupported', 'start', 'update', 'end']) {
      expect(
        swift.contains('case "$method"'),
        isTrue,
        reason: 'the bridge does not handle $method',
      );
    }
  });

  test('the channel name matches on both sides', () {
    expect(
      bridge.readAsStringSync().contains('"live_ride/live_activity"'),
      isTrue,
    );
  });

  test('start arguments line up with what Swift reads', () {
    final swift = bridge.readAsStringSync();
    for (final key in ['riderName', 'title', 'navigating']) {
      expect(swift.contains('arguments["$key"]'), isTrue, reason: key);
    }
  });

  test('every maneuver maps to a plausible SF Symbol name', () {
    final service = LiveActivityService();
    // A symbol Apple does not ship renders as a blank box on the Lock Screen,
    // and Valhalla maneuver codes are the only thing feeding this.
    const valhallaTypes = [
      0,
      1,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      22,
      26,
      27,
    ];
    for (final type in valhallaTypes) {
      final plan = NavigationPlan.fromJson({
        'shape': [
          [52.0, 13.0],
          [52.0, 13.005],
          [52.0, 13.01],
        ],
        'maneuvers': [
          {'instruction': 'Start', 'begin_shape_index': 0, 'type': 1},
          {'instruction': 'Turn', 'begin_shape_index': 2, 'type': type},
        ],
      });
      final payload = service.buildPayload(
        metrics: const RideMetrics(),
        paused: false,
        live: false,
        metric: true,
        progress: plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.002)),
      );
      final symbol = payload['maneuverSymbol']! as String;
      expect(
        symbol,
        matches(RegExp(r'^[a-z][a-z0-9.]*[a-z0-9]$')),
        reason: 'maneuver $type produced "$symbol"',
      );
      expect(payload['maneuver'], 'Turn', reason: 'maneuver $type');
    }
  });

  test('the widget declares itself a WidgetKit extension', () {
    final xml = plist.readAsStringSync();
    expect(xml.contains('com.apple.widgetkit-extension'), isTrue);
    expect(bundle.readAsStringSync().contains('@main'), isTrue);
    expect(bundle.readAsStringSync().contains('RideLiveActivity()'), isTrue);
  });

  test('app and widget agree on the minimum iOS version', () {
    // A mismatch here compiles and then fails to start an activity at runtime.
    const required = '16.2';
    expect(attributes.readAsStringSync(), contains('iOS $required'));
    expect(bridge.readAsStringSync(), contains('iOS $required'));
    expect(widget.readAsStringSync(), contains('iOS $required'));
    expect(
      File('ios_native/scripts/add_live_activity_target.rb').readAsStringSync(),
      contains("DEPLOYMENT_TARGET = '$required'"),
    );
  });

  test('the widget renders every field the state carries', () {
    final swift = widget.readAsStringSync();
    for (final field in [
      'speed',
      'distance',
      'elapsed',
      'heartRate',
      'ascent',
      'paused',
      'live',
      'maneuverSymbol',
      'offRoute',
    ]) {
      expect(
        swift.contains('state.$field') ||
            swift.contains('context.state.$field'),
        isTrue,
        reason: '$field is never shown on the Lock Screen',
      );
    }
  });
}
