import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_waypoint.dart';
import 'package:live_ride/services/route_builder_controller.dart';
import 'package:live_ride/services/routing_service.dart';

/// Udaje router: łączy waypointy prostymi odcinkami z gęstą geometrią,
/// żeby dało się sprawdzić samą logikę edycji bez sieci.
Future<RoutedPath> fakeSolver(
  List<RouteWaypoint> waypoints,
  RoutePreferences preferences,
  CancelToken cancelToken,
) async {
  final points = <GeoPoint>[];
  for (var i = 0; i < waypoints.length - 1; i++) {
    final from = waypoints[i].point;
    final to = waypoints[i + 1].point;
    for (var step = 0; step < 20; step++) {
      final t = step / 20;
      points.add(
        GeoPoint(
          lat: from.lat + (to.lat - from.lat) * t,
          lon: from.lon + (to.lon - from.lon) * t,
          elevation: 100 + step.toDouble(),
        ),
      );
    }
  }
  if (waypoints.isNotEmpty) points.add(waypoints.last.point);
  return RoutedPath(
    points: points,
    maneuvers: const [],
    distanceMeters: totalDistanceMeters(points),
    duration: Duration(seconds: (totalDistanceMeters(points) / 6).round()),
  );
}

Future<RoutedPath> fakeSketchSolver(
  List<GeoPoint> sketch,
  RoutePreferences preferences,
) async => RoutedPath(
  points: sketch,
  maneuvers: const [],
  distanceMeters: totalDistanceMeters(sketch),
  duration: Duration.zero,
);

RouteBuilderController buildController({
  void Function(RouteBuilderController)? onDraftChanged,
}) => RouteBuilderController(
  solver: fakeSolver,
  sketchSolver: fakeSketchSolver,
  onDraftChanged: onDraftChanged,
  recomputeDelay: Duration.zero,
);

const warsaw = GeoPoint(lat: 52.2297, lon: 21.0122);
const radom = GeoPoint(lat: 51.4027, lon: 21.1471);
const lublin = GeoPoint(lat: 51.2465, lon: 22.5684);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  _polylineRoundTrip();
  group('dodawanie punktów', () {
    test('pierwszy punkt jest startem, drugi metą', () async {
      final controller = buildController()..addWaypoint(warsaw);
      expect(controller.waypoints.single.kind, WaypointKind.start);

      controller.addWaypoint(radom);
      expect(controller.waypoints.first.kind, WaypointKind.start);
      expect(controller.waypoints.last.kind, WaypointKind.finish);
      controller.dispose();
    });

    test('trzeci punkt robi z drugiego punkt pośredni', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..addWaypoint(lublin);

      expect(controller.waypoints.map((w) => w.kind).toList(), [
        WaypointKind.start,
        WaypointKind.via,
        WaypointKind.finish,
      ]);
      controller.dispose();
    });

    test('dwa punkty dają trasę', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom);
      await settle();

      expect(controller.hasRoute, isTrue);
      expect(controller.points.length, greaterThan(10));
      expect(controller.distanceMeters, greaterThan(50000));
      controller.dispose();
    });

    test('jeden punkt to jeszcze nie trasa', () async {
      final controller = buildController()..addWaypoint(warsaw);
      await settle();
      expect(controller.hasRoute, isFalse);
      controller.dispose();
    });

    test('punkt da się wstawić w środek', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(lublin)
        ..insertWaypoint(1, radom);

      expect(controller.waypoints.length, 3);
      expect(controller.waypoints[1].point.lat, radom.lat);
      expect(controller.waypoints[1].kind, WaypointKind.via);
      controller.dispose();
    });
  });

  group('edycja punktów', () {
    test('przesunięcie punktu przelicza trasę', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom);
      await settle();
      final before = controller.distanceMeters;

      controller.moveWaypoint(1, lublin);
      await settle();
      expect(controller.distanceMeters, isNot(closeTo(before, 1)));
      controller.dispose();
    });

    test('usunięcie punktu skraca listę', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..addWaypoint(lublin)
        ..removeWaypoint(1);

      expect(controller.waypoints.length, 2);
      expect(controller.waypoints.last.kind, WaypointKind.finish);
      controller.dispose();
    });

    test('zmiana kolejności zachowuje role punktów', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..addWaypoint(lublin)
        ..reorderWaypoint(2, 0);

      expect(controller.waypoints.first.point.lat, lublin.lat);
      expect(controller.waypoints.first.kind, WaypointKind.start);
      expect(controller.waypoints.last.kind, WaypointKind.finish);
      controller.dispose();
    });

    test('odwrócenie zamienia start z metą', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..reverse();

      expect(controller.waypoints.first.point.lat, radom.lat);
      expect(controller.waypoints.first.kind, WaypointKind.start);
      controller.dispose();
    });

    test('pętla dokłada powrót do startu', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..closeLoop();

      expect(controller.waypoints.length, 3);
      expect(controller.waypoints.last.point.lat, warsaw.lat);
      controller.dispose();
    });

    test('pętla nie dubluje punktu, gdy trasa już jest zamknięta', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..addWaypoint(warsaw);
      final before = controller.waypoints.length;

      controller.closeLoop();
      expect(controller.waypoints.length, before);
      controller.dispose();
    });

    test('tam i z powrotem odbija trasę', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..addWaypoint(lublin)
        ..outAndBack();

      expect(controller.waypoints.length, 5);
      expect(controller.waypoints.last.point.lat, warsaw.lat);
      controller.dispose();
    });

    test('wyczyszczenie kasuje wszystko', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom);
      await settle();

      controller.clear();
      await settle();
      expect(controller.isEmpty, isTrue);
      expect(controller.hasRoute, isFalse);
      controller.dispose();
    });
  });

  group('cofanie i ponawianie', () {
    test('cofa dodanie punktu', () async {
      final controller = buildController()..addWaypoint(warsaw);
      expect(controller.canUndo, isTrue);

      controller
        ..addWaypoint(radom)
        ..undo();
      expect(controller.waypoints.length, 1);
      controller.dispose();
    });

    test('ponawia cofniętą zmianę', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..undo();
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.waypoints.length, 2);
      controller.dispose();
    });

    test('nowa zmiana kasuje gałąź ponawiania', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..undo()
        ..addWaypoint(lublin);

      expect(controller.canRedo, isFalse);
      controller.dispose();
    });

    test('cofa też zmianę preferencji', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom);
      await settle();

      controller.setPreferences(
        const RoutePreferences(profile: BikeProfile.mountain),
      );
      expect(controller.preferences.profile, BikeProfile.mountain);

      controller.undo();
      expect(controller.preferences.profile, BikeProfile.road);
      controller.dispose();
    });

    test('cofanie pustej historii nic nie psuje', () {
      final controller = buildController()
        ..undo()
        ..redo();
      expect(controller.isEmpty, isTrue);
      controller.dispose();
    });

    test('historia ma ograniczoną długość', () {
      final controller = buildController();
      for (var i = 0; i < RouteBuilderController.historyLimit + 20; i++) {
        controller.addWaypoint(GeoPoint(lat: 52 + i / 1000, lon: 21));
      }
      var undos = 0;
      while (controller.canUndo && undos < 500) {
        controller.undo();
        undos++;
      }
      expect(undos, lessThanOrEqualTo(RouteBuilderController.historyLimit));
      controller.dispose();
    });
  });

  group('rysowanie', () {
    test('szkic zamienia się w trasę z punktami kontrolnymi', () async {
      final sketch = [
        for (var i = 0; i < 300; i++)
          GeoPoint(lat: 52.0 + i / 20000, lon: 21.0 + i / 30000),
      ];
      final controller = buildController();
      await controller.applySketch(sketch);

      expect(controller.hasRoute, isTrue);
      expect(controller.waypoints.length, greaterThanOrEqualTo(2));
      expect(controller.waypoints.length, lessThanOrEqualTo(12));
      expect(controller.waypoints.first.kind, WaypointKind.start);
      expect(controller.waypoints.last.kind, WaypointKind.finish);
      controller.dispose();
    });

    test('za krótki szkic jest ignorowany', () async {
      final controller = buildController();
      await controller.applySketch([warsaw]);
      expect(controller.hasRoute, isFalse);
      controller.dispose();
    });
  });

  group('szkic zapisany na później', () {
    test('powiadamia o każdej zmianie', () async {
      var changes = 0;
      final controller = buildController(onDraftChanged: (_) => changes++)
        ..addWaypoint(warsaw)
        ..addWaypoint(radom);
      expect(changes, greaterThanOrEqualTo(2));
      controller.dispose();
    });

    test('zapisuje i odtwarza stan', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom)
        ..name = 'Wypad na Radom'
        ..description = 'Płasko i szybko'
        ..tags = ['szosa'];
      controller.setPreferences(
        const RoutePreferences(profile: BikeProfile.gravel),
      );
      final draft = controller.toDraft();
      controller.dispose();

      final restored = buildController()..restoreDraft(draft);
      await settle();

      expect(restored.name, 'Wypad na Radom');
      expect(restored.description, 'Płasko i szybko');
      expect(restored.tags, ['szosa']);
      expect(restored.preferences.profile, BikeProfile.gravel);
      expect(restored.waypoints.length, 2);
      expect(restored.hasRoute, isTrue);
      restored.dispose();
    });
  });

  group('analiza w kreatorze', () {
    test('liczy się po każdym przeliczeniu trasy', () async {
      final controller = buildController()
        ..addWaypoint(warsaw)
        ..addWaypoint(radom);
      await settle();

      expect(controller.analysis.hasElevationData, isTrue);
      expect(controller.analysis.distanceMeters, greaterThan(0));
      expect(controller.estimatedDuration, greaterThan(Duration.zero));
      controller.dispose();
    });
  });

  group('błędy trasowania', () {
    test('pokazuje komunikat, gdy router odmawia', () async {
      final controller = RouteBuilderController(
        solver: (_, _, _) async =>
            throw const RoutingException('Za daleko od drogi.'),
        sketchSolver: fakeSketchSolver,
        recomputeDelay: Duration.zero,
      )..addWaypoint(warsaw);
      controller.addWaypoint(radom);
      await settle();

      expect(controller.error, 'Za daleko od drogi.');
      controller.dispose();
    });
  });
}

void _polylineRoundTrip() {
  group('polilinia', () {
    test('koduje i dekoduje ten sam ślad', () {
      const points = [
        GeoPoint(lat: 52.229676, lon: 21.012229),
        GeoPoint(lat: 52.230100, lon: 21.013500),
        GeoPoint(lat: 52.231000, lon: 21.015000),
      ];
      final encoded = encodeValhallaPolyline(points);
      expect(encoded, isNotEmpty);

      final decoded = decodeValhallaPolyline(encoded);
      expect(decoded, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(decoded[i].lat, closeTo(points[i].lat, 0.000002));
        expect(decoded[i].lon, closeTo(points[i].lon, 0.000002));
      }
    });

    test('pusta lista daje pusty ciąg i pustą listę', () {
      expect(encodeValhallaPolyline(const []), isEmpty);
      expect(decodeValhallaPolyline(''), isEmpty);
    });

    test('kodowanie skraca ślad wielokrotnie', () {
      final points = [
        for (var i = 0; i < 500; i++)
          GeoPoint(lat: 52.0 + i * 0.0001, lon: 21.0 + i * 0.0001),
      ];
      final encoded = encodeValhallaPolyline(points);
      // Sam JSON z parami liczb to ponad 20 znaków na punkt.
      expect(encoded.length, lessThan(points.length * 12));
      expect(decodeValhallaPolyline(encoded), hasLength(points.length));
    });
  });

  group('przeliczanie w trakcie edycji', () {
    test('nowa zmiana anuluje poprzednią serię prób', () async {
      // Jedno „policz trasę" to w środku nawet kilkanaście żądań do routera.
      // Przeciąganie punktu unieważnia je co kilkaset milisekund, więc bez
      // anulowania nieaktualne serie biją się o łącze z tą aktualną.
      final tokens = <CancelToken>[];
      final controller = RouteBuilderController(
        solver: (waypoints, preferences, cancelToken) async {
          tokens.add(cancelToken);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return fakeSolver(waypoints, preferences, cancelToken);
        },
        sketchSolver: fakeSketchSolver,
        recomputeDelay: Duration.zero,
      );

      controller.addWaypoint(warsaw);
      controller.addWaypoint(radom);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      controller.addWaypoint(lublin);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(tokens.length, greaterThanOrEqualTo(2));
      expect(
        tokens.first.isCancelled,
        isTrue,
        reason: 'pierwsza seria miała zostać przerwana',
      );
      expect(tokens.last.isCancelled, isFalse);

      controller.dispose();
    });

    test('zamknięcie kreatora przerywa trwające liczenie', () async {
      CancelToken? token;
      final controller = RouteBuilderController(
        solver: (waypoints, preferences, cancelToken) async {
          token = cancelToken;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return fakeSolver(waypoints, preferences, cancelToken);
        },
        sketchSolver: fakeSketchSolver,
        recomputeDelay: Duration.zero,
      );
      controller.addWaypoint(warsaw);
      controller.addWaypoint(radom);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      controller.dispose();
      expect(token?.isCancelled, isTrue);
    });

    test('stara trasa zostaje na ekranie, dopóki nie ma nowej', () async {
      // Czyszczenie geometrii na czas liczenia daje mrugnięcie pustą mapą
      // przy każdym przesunięciu punktu.
      // Router, który odpowiada z opóźnieniem — inaczej liczenie kończy się
      // w tym samym mikrotasku i nie da się zajrzeć w jego środek.
      final controller = RouteBuilderController(
        solver: (waypoints, preferences, cancelToken) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return fakeSolver(waypoints, preferences, cancelToken);
        },
        sketchSolver: fakeSketchSolver,
        recomputeDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.addWaypoint(warsaw);
      controller.addWaypoint(radom);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final before = controller.path.points;
      expect(before.length, greaterThan(1));

      controller.addWaypoint(lublin);
      // Liczenie rusza po odczekaniu, więc dajemy pętli zdarzeń tyknąć.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // W trakcie liczenia trasa nadal jest, a kreator uczciwie mówi, że
      // pracuje. Czyszczenie geometrii dawałoby mrugnięcie pustą mapą przy
      // każdym przesunięciu punktu.
      expect(controller.isRouting, isTrue);
      expect(controller.path.points, same(before));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.isRouting, isFalse);
      expect(controller.path.points, isNot(same(before)));
    });
  });
}
