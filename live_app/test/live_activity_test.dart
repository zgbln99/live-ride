import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/services/live_activity_service.dart';

const _metrics = RideMetrics(
  speedKmh: 31.4,
  distanceMeters: 18450,
  elapsed: Duration(minutes: 47, seconds: 12),
  movingTime: Duration(minutes: 45),
  elevationGainMeters: 415,
  heartRate: 152,
);

NavigationPlan plan() => NavigationPlan.fromJson({
  'shape': [
    [52.0, 13.0],
    [52.0, 13.005],
    [52.0, 13.01],
  ],
  'maneuvers': [
    {'instruction': 'Head east', 'begin_shape_index': 0, 'type': 1},
    {
      'instruction': 'Turn left onto Seestrasse',
      'begin_shape_index': 2,
      'type': 15,
    },
  ],
  'summary': {'time': 600},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('payload', () {
    final service = LiveActivityService();

    test('sends preformatted values so the widget needs no unit logic', () {
      final payload = service.buildPayload(
        metrics: _metrics,
        paused: false,
        live: true,
        metric: true,
      );

      expect(payload['speed'], '31.4');
      expect(payload['speedUnit'], 'km/h');
      expect(payload['distance'], '18.4');
      expect(payload['distanceUnit'], 'km');
      expect(payload['elapsed'], '47:12');
      expect(payload['heartRate'], '152');
      expect(payload['ascent'], '415');
      expect(payload['live'], isTrue);
      expect(payload['paused'], isFalse);
    });

    test('honours imperial units', () {
      final payload = service.buildPayload(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: false,
      );
      expect(payload['speedUnit'], 'mph');
      expect(payload['distanceUnit'], 'mi');
      expect(payload['ascentUnit'], 'ft');
    });

    test('carries the next maneuver and an SF Symbol for it', () {
      final payload = service.buildPayload(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
        progress: plan().progressAt(const GeoPoint(lat: 52.0, lon: 13.002)),
      );

      expect(payload['maneuver'], 'Turn left onto Seestrasse');
      expect(payload['maneuverSymbol'], 'arrow.turn.left.up');
      expect(payload['maneuverDistance'], isNot(isEmpty));
      expect(payload['offRoute'], isFalse);
    });

    test('flags being off route', () {
      final payload = service.buildPayload(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
        progress: plan().progressAt(const GeoPoint(lat: 52.01, lon: 13.005)),
      );
      expect(payload['offRoute'], isTrue);
    });

    test('leaves the maneuver empty on a free ride', () {
      final payload = service.buildPayload(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
      );
      expect(payload['maneuver'], '');
      expect(payload['maneuverDistance'], '');
    });
  });

  group('channel behaviour', () {
    late List<MethodCall> calls;
    late LiveActivityService service;

    setUp(() {
      calls = [];
      const channel = MethodChannel('live_ride/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'isSupported') return true;
            return null;
          });
      // The platform check is overridden so the channel contract itself can
      // be exercised off-device.
      service = LiveActivityService(channel: channel, platformSupported: true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('live_ride/live_activity'),
            null,
          );
    });

    test('reports support from the native side', () async {
      expect(await service.isSupported(), isTrue);
      expect(calls.single.method, 'isSupported');
    });

    test('does nothing before a ride has started it', () async {
      await service.update(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
      );
      expect(calls, isEmpty);
      expect(service.isActive, isFalse);
    });

    test('throttles and de-duplicates updates', () async {
      await service.start(
        riderName: 'Ada',
        title: 'Evening ride',
        navigating: false,
      );
      expect(service.isActive, isTrue);
      calls.clear();

      await service.update(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
      );
      expect(calls.length, 1, reason: 'first snapshot is sent');

      // Same values and inside the interval: nothing more is sent.
      await service.update(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
      );
      await service.update(
        metrics: const RideMetrics(speedKmh: 31.5),
        paused: false,
        live: false,
        metric: true,
      );
      expect(calls.length, 1);
    });

    test('ends the activity and stops updating afterwards', () async {
      await service.start(riderName: 'Ada', title: 'Ride', navigating: false);
      await service.end();
      calls.clear();

      await service.update(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
      );
      expect(calls, isEmpty);
      expect(service.isActive, isFalse);
    });

    test('survives a platform that has no widget extension', () async {
      const missing = MethodChannel('live_ride/live_activity_missing');
      final orphan = LiveActivityService(
        channel: missing,
        platformSupported: true,
      );
      await orphan.start(riderName: 'Ada', title: 'Ride', navigating: false);
      expect(orphan.isActive, isFalse);
      // Must not throw.
      await orphan.update(
        metrics: _metrics,
        paused: false,
        live: false,
        metric: true,
      );
      await orphan.end();
    });
  });
}
