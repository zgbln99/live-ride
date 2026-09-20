import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/i18n/strings.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/core/lr_theme.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/widgets/chrome_fade.dart';
import 'package:live_ride/widgets/navigation_header.dart';

Widget host(Widget child) => MaterialApp(
  theme: LR.theme(),
  home: Scaffold(body: child),
);

void main() {
  group('ChromeFade', () {
    testWidgets('is fully opaque while visible', (tester) async {
      await tester.pumpWidget(
        host(const ChromeFade(visible: true, child: Text('button'))),
      );
      await tester.pumpAndSettle();

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 1);
    });

    testWidgets('fades away when it retires', (tester) async {
      await tester.pumpWidget(
        host(const ChromeFade(visible: false, child: Text('button'))),
      );
      await tester.pumpAndSettle();

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0);
    });

    testWidgets('stops taking taps the instant it starts fading', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Center(
            child: ChromeFade(
              visible: false,
              child: ElevatedButton(
                onPressed: () => taps++,
                child: const Text('FINISH'),
              ),
            ),
          ),
        ),
      );
      // Before the fade has even finished, the button must be inert: a tap
      // must never land on a half-transparent FINISH.
      await tester.pump(const Duration(milliseconds: 20));

      // The outermost IgnorePointer is the one ChromeFade owns; a Material
      // button brings its own further down the tree.
      final ignore = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(ChromeFade),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);

      await tester.tap(find.text('FINISH'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('still takes taps while visible', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Center(
            child: ChromeFade(
              visible: true,
              child: ElevatedButton(
                onPressed: () => taps++,
                child: const Text('FINISH'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('FINISH'));
      expect(taps, 1);
    });

    testWidgets('gives its space back when it collapses', (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              const ChromeFade(
                visible: false,
                collapse: true,
                child: SizedBox(height: 80, width: 200),
              ),
              Container(key: const Key('below'), height: 20, color: LR.accent),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The collapsed bar occupies nothing, so what sits below it moves up.
      expect(tester.getTopLeft(find.byKey(const Key('below'))).dy, 0);
    });

    testWidgets('keeps its space while visible', (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              const ChromeFade(
                visible: true,
                collapse: true,
                child: SizedBox(height: 80, width: 200),
              ),
              Container(key: const Key('below'), height: 20, color: LR.accent),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const Key('below'))).dy, 80);
    });

    testWidgets('returns faster than it retires', (tester) async {
      expect(
        ChromeFade.durationFor(visible: true),
        lessThan(ChromeFade.durationFor(visible: false)),
      );
    });
  });

  group('ChromeHint', () {
    testWidgets('says how to bring the controls back', (tester) async {
      await tester.pumpWidget(host(const ChromeHint(visible: true)));
      await tester.pumpAndSettle();
      expect(find.text(S.tapToShowControls), findsOneWidget);
    });
  });

  group('navigation header while the ride is quiet', () {
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
          'street_names': ['Seestrasse'],
        },
      ],
      'summary': {'time': 600},
    });

    Widget header({required bool chromeVisible, VoidCallback? onExit}) => host(
      NavigationHeader(
        progress: plan().progressAt(const GeoPoint(lat: 52.0, lon: 13.002)),
        metric: true,
        routeName: 'Lake loop',
        etaSeconds: 600,
        chromeVisible: chromeVisible,
        onExit: onExit ?? () {},
        onOverview: () {},
      ),
    );

    testWidgets('keeps the maneuver, the distance left and the ETA', (
      tester,
    ) async {
      await tester.pumpWidget(header(chromeVisible: false));
      await tester.pumpAndSettle();

      // Nagłówek nawigacji mówi po polsku także wtedy, gdy router nie.
    expect(find.text('Skręć w lewo w Seestrasse'), findsOneWidget);
      expect(find.byIcon(Icons.turn_left), findsOneWidget);
      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('ETA'), findsOneWidget);
    });

    testWidgets('the exit button stops responding', (tester) async {
      var exits = 0;
      await tester.pumpWidget(
        header(chromeVisible: false, onExit: () => exits++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(exits, 0);
    });

    testWidgets('the exit button works again once controls return', (
      tester,
    ) async {
      var exits = 0;
      await tester.pumpWidget(
        header(chromeVisible: true, onExit: () => exits++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(exits, 1);
    });
  });
}
