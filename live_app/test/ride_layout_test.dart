import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/core/lr_theme.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/models/ride_data_field.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/models/rider_profile.dart';
import 'package:live_ride/services/ride_recorder.dart';
import 'package:live_ride/widgets/navigation_header.dart';
import 'package:live_ride/widgets/ride_controls.dart';
import 'package:live_ride/widgets/ride_data_grid.dart';

/// The ride computer chrome, without the map. The map is the only part that
/// needs a platform view, so everything else can be laid out for real and
/// checked for overflow at the sizes riders actually hold.
Widget rideScaffold({
  required RideFieldLayout layout,
  required bool navigating,
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
              progress: plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.002)),
              metric: true,
              routeName: 'A long route name that should still fit on one line',
              etaSeconds: 1800,
              live: true,
              onExit: () {},
              onOverview: () {},
            ),
          const Expanded(child: ColoredBox(color: LR.canvas)),
          SizedBox(
            height: switch (layout) {
              RideFieldLayout.two => 190,
              RideFieldLayout.four => 194,
              RideFieldLayout.six => 252,
              RideFieldLayout.eight => 296,
            },
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
          RideControls(
            state: RideState.recording,
            onPause: () {},
            onResume: () {},
            onStop: () {},
            onLive: () {},
            liveActive: true,
          ),
        ],
      ),
    ),
  );
}

void main() {
  // A small phone, a standard phone and a large phone.
  const sizes = [Size(320, 568), Size(375, 667), Size(430, 932)];

  for (final size in sizes) {
    for (final layout in RideFieldLayout.values) {
      for (final navigating in [false, true]) {
        testWidgets(
          'ride computer fits ${size.width.toInt()}x${size.height.toInt()} '
          'with ${layout.fieldCount} fields'
          '${navigating ? ' while navigating' : ''}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              rideScaffold(layout: layout, navigating: navigating),
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
