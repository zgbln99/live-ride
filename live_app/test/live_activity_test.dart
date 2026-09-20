import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/core/route_preview.dart';
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
      // Tak wygląda odpowiedź Valhalli, gdy nie oddała polskiego tekstu:
      // angielskie zdanie plus nazwa ulicy w osobnym polu.
      'instruction': 'Turn left onto Seestrasse',
      'begin_shape_index': 2,
      'type': 15,
      'street_names': ['Seestrasse'],
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

      // Ekran blokady dostaje POLSKĄ instrukcję, tę samą co ekran jazdy.
      // Nazwa ulicy zostaje w oryginale — rowerzysta szuka jej na tabliczce.
      expect(payload['maneuver'], 'Skręć w lewo w Seestrasse');
      expect(payload['maneuverStreet'], 'Seestrasse');
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

  group('Dynamic Island nie skacze', () {
    String compact(double kmh, {bool metric = true}) =>
        LiveActivityService().buildPayload(
              metrics: RideMetrics(speedKmh: kmh),
              paused: false,
              live: false,
              metric: metric,
            )['speedCompact']!
            as String;

    test('prędkość na wyspie nie ma części dziesiętnej', () {
      // „9.8", „31.4" i „0.0" to za każdym razem inna liczba znaków, a wyspa
      // ma kilkadziesiąt punktów szerokości — każda taka zmiana przesuwała
      // cały układ i wyglądała jak usterka.
      for (final speed in [0.0, 9.4, 9.8, 31.4, 99.6]) {
        expect(compact(speed), isNot(contains('.')));
        expect(compact(speed), isNot(contains(',')));
      }
    });

    test('szerokość pola zmienia się tylko przy przekroczeniu dziesiątki', () {
      expect(compact(0).length, 1);
      expect(compact(9.4).length, 1);
      expect(compact(31.4).length, 2);
      expect(compact(99.6).length, 3);
    });

    test('nierealna prędkość nie rozsadza pola', () {
      // Zepsuty odczyt nie ma prawa rozciągnąć wyspy na pół ekranu.
      expect(compact(99999).length, lessThanOrEqualTo(3));
      expect(compact(double.infinity), '0');
      expect(compact(double.nan), '0');
      expect(compact(-5), '0');
    });

    test('w milach też bez części dziesiętnej', () {
      expect(compact(32.2, metric: false), '20');
    });
  });

  group('priorytet aktualizacji', () {
    /// Kanał, który zapamiętuje każde wywołanie.
    ({LiveActivityService service, List<MethodCall> calls}) wired() {
      final calls = <MethodCall>[];
      const channel = MethodChannel('live_ride/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'isSupported') return true;
            return null;
          });
      return (
        service: LiveActivityService(platformSupported: true),
        calls: calls,
      );
    }

    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('live_ride/live_activity'),
            null,
          );
    });

    test('zmiana stanu nie czeka na okno, zmiana liczb czeka', () async {
      final wiring = wired();
      final service = wiring.service;
      await service.start(riderName: 'Marek', title: 'Test', navigating: false);

      Future<void> push({
        required bool paused,
        required double speed,
      }) => service.update(
        metrics: RideMetrics(speedKmh: speed),
        paused: paused,
        live: false,
        metric: true,
      );

      await push(paused: false, speed: 20);
      final afterFirst = wiring.calls.length;

      // Sama prędkość: zdławione, bo minęło mniej niż sekunda.
      await push(paused: false, speed: 21);
      expect(wiring.calls.length, afterFirst);

      // Postój: przechodzi natychmiast, bo to zmiana stanu.
      await push(paused: true, speed: 0);
      expect(wiring.calls.length, afterFirst + 1);
      final last = wiring.calls.last.arguments as Map;
      expect(last['priority'], isTrue);
      expect(last['pauseLabel'], isNotEmpty);
    });

    test('geometria trasy idzie osobnym wywołaniem i tylko raz', () async {
      final wiring = wired();
      final service = wiring.service;
      await service.start(riderName: 'Marek', title: 'Test', navigating: true);

      final preview = RoutePreview.fromRoute([
        for (var i = 0; i < 30; i++)
          GeoPoint(lat: 52.0 + i * 0.001, lon: 21.0 + i * 0.001),
      ]);

      await service.setRoute(preview);
      await service.setRoute(preview);

      final routeCalls =
          wiring.calls.where((call) => call.method == 'route').toList();
      expect(routeCalls.length, 1, reason: 'ten sam kształt drugi raz nie leci');
      final payload = routeCalls.single.arguments as Map;
      expect(payload['routeShape'], isNotEmpty);
      expect(payload['routeAspect'], isA<double>());

      // A metryki nie niosą geometrii ze sobą.
      await service.update(
        metrics: const RideMetrics(speedKmh: 20),
        paused: false,
        live: false,
        metric: true,
      );
      final update =
          wiring.calls.lastWhere((call) => call.method == 'update').arguments
              as Map;
      expect(update.containsKey('routeShape'), isFalse);
    });

    test('nowy kształt po przeliczeniu trasy jednak leci', () async {
      final wiring = wired();
      final service = wiring.service;
      await service.start(riderName: 'Marek', title: 'Test', navigating: true);

      await service.setRoute(
        RoutePreview.fromRoute([
          for (var i = 0; i < 20; i++)
            GeoPoint(lat: 52.0 + i * 0.001, lon: 21.0),
        ]),
      );
      await service.setRoute(
        RoutePreview.fromRoute([
          for (var i = 0; i < 20; i++)
            GeoPoint(lat: 52.0, lon: 21.0 + i * 0.001),
        ]),
      );

      expect(wiring.calls.where((c) => c.method == 'route').length, 2);
    });
  });
}
