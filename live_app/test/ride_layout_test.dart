import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/core/lr_theme.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/models/ride_data_field.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/models/rider_profile.dart';
import 'package:live_ride/services/ride_recorder.dart';
import 'package:live_ride/widgets/chrome_fade.dart';
import 'package:live_ride/widgets/navigation_header.dart';
import 'package:live_ride/widgets/ride_controls.dart';
import 'package:live_ride/widgets/ride_data_grid.dart';

/// The ride computer chrome, without the map. The map is the only part that
/// needs a platform view, so everything else can be laid out for real and
/// checked for overflow at the sizes riders actually hold.
Widget rideScaffold({
  required RideFieldLayout layout,
  required bool navigating,
  bool chromeVisible = true,
  double bottomInset = 0,
  double availableHeight = double.infinity,
}) {
  const metrics = RideMetrics(
    speedKmh: 34.7,
    maxSpeedKmh: 61.2,
    distanceMeters: 48230,
    elapsed: Duration(hours: 2, minutes: 4, seconds: 9),
    movingTime: Duration(hours: 1, minutes: 58),
    elevationGainMeters: 1240,
    gradientPercent: 7.4,
    heartRate: 163,
    averageHeartRate: 148,
    gpsAccuracyMeters: 6,
  );

  final plan = NavigationPlan.fromJson({
    'shape': [
      [52.0, 13.0],
      [52.0, 13.005],
      [52.0, 13.01],
    ],
    'maneuvers': [
      {'instruction': 'Head east', 'begin_shape_index': 0, 'type': 1},
      {
        'instruction': 'Turn left onto a street with a very long German name',
        'begin_shape_index': 2,
        'type': 15,
        'street_names': ['Kurfürstendammstrassenallee'],
      },
    ],
    'summary': {'time': 900},
  });

  final profile = RiderProfile(layout: layout).activeFields;

  return MaterialApp(
    theme: LR.theme(),
    home: Scaffold(
      body: Column(
        children: [
          if (navigating)
            NavigationHeader(
              chromeVisible: chromeVisible,
              progress: plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.002)),
              metric: true,
              routeName: 'A long route name that should still fit on one line',
              etaSeconds: 1800,
              live: true,
              onExit: () {},
              onOverview: () {},
            ),
          const Expanded(
            child: ColoredBox(key: Key('map'), color: LR.canvas),
          ),
          SizedBox(
            // Mirrors the screen's rule: the instrument is capped at a share
            // of the screen so the map is never squeezed out.
            height: math.min(switch (layout) {
              RideFieldLayout.two => 190.0,
              RideFieldLayout.four => 194.0,
              RideFieldLayout.six => 252.0,
              RideFieldLayout.eight => 296.0,
            }, availableHeight * 0.42),
            child: RideDataGrid(
              fields: profile,
              layout: layout,
              compact: layout.rows > 2,
              data: const RideFieldContext(
                metrics: metrics,
                metric: true,
                remainingMeters: 12400,
                etaSeconds: 1800,
              ),
            ),
          ),
          ChromeFade(
            visible: chromeVisible,
            collapse: true,
            child: RideControls(
              key: const Key('controls'),
              state: RideState.recording,
              onPause: () {},
              onResume: () {},
              onStop: () {},
              onLive: () {},
              liveActive: true,
            ),
          ),
          // The permanent inset that keeps a data field clear of the home
          // indicator once the control bar has retired.
          Container(
            key: const Key('inset'),
            height: bottomInset,
            color: LR.surface,
          ),
        ],
      ),
    ),
  );
}

void main() {
  // A small phone with no home indicator, a standard phone, and a large phone
  // with one.
  const sizes = <({Size size, double inset})>[
    (size: Size(320, 568), inset: 0),
    (size: Size(375, 667), inset: 0),
    (size: Size(430, 932), inset: 34),
  ];

  for (final device in sizes) {
    final size = device.size;
    for (final layout in RideFieldLayout.values) {
      for (final navigating in [false, true]) {
        for (final chromeVisible in [true, false]) {
          testWidgets(
            'ride computer fits ${size.width.toInt()}x${size.height.toInt()} '
            'with ${layout.fieldCount} fields'
            '${navigating ? ' while navigating' : ''}'
            '${chromeVisible ? '' : ' once quiet'}',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);

              await tester.pumpWidget(
                rideScaffold(
                  layout: layout,
                  navigating: navigating,
                  chromeVisible: chromeVisible,
                  bottomInset: device.inset,
                  availableHeight: size.height,
                ),
              );
              await tester.pumpAndSettle();

              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  testWidgets('the control bar gives the map its space back when quiet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      rideScaffold(
        layout: RideFieldLayout.four,
        navigating: true,
        availableHeight: 667,
      ),
    );
    await tester.pumpAndSettle();
    final loudHeight = tester.getSize(find.byKey(const Key('controls'))).height;
    final loudMap = tester.getSize(find.byKey(const Key('map'))).height;
    expect(loudHeight, greaterThan(0));

    await tester.pumpWidget(
      rideScaffold(
        layout: RideFieldLayout.four,
        navigating: true,
        chromeVisible: false,
        availableHeight: 667,
      ),
    );
    await tester.pumpAndSettle();

    // The bar is laid out but occupies nothing, and the map has taken the
    // space instead.
    final quietMap = tester.getSize(find.byKey(const Key('map'))).height;
    expect(quietMap, greaterThan(loudMap));
    expect(quietMap - loudMap, closeTo(loudHeight, 1));
  });

  testWidgets('the bottom inset survives the quiet', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      rideScaffold(
        layout: RideFieldLayout.four,
        navigating: false,
        chromeVisible: false,
        bottomInset: 34,
        availableHeight: 667,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('inset'))).height, 34);
    expect(
      tester.getBottomLeft(find.byKey(const Key('inset'))).dy,
      closeTo(667, 1),
    );
  });
}
