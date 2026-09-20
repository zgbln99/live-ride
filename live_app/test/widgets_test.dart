import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/core/lr_theme.dart';
import 'package:live_ride/models/navigation_plan.dart';
import 'package:live_ride/models/ride_data_field.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/widgets/lr_common.dart';
import 'package:live_ride/widgets/navigation_header.dart';
import 'package:live_ride/widgets/ride_data_grid.dart';
import 'package:live_ride/widgets/track_preview.dart';
import 'package:live_ride/widgets/weather_field.dart';

Widget host(Widget child) => MaterialApp(
  theme: LR.theme(),
  home: Scaffold(body: child),
);

void main() {
  const metrics = RideMetrics(
    speedKmh: 31.2,
    distanceMeters: 18450,
    elapsed: Duration(minutes: 52),
    movingTime: Duration(minutes: 48),
    elevationGainMeters: 412,
    heartRate: 151,
  );

  testWidgets('data grid renders every configured field', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          height: 240,
          child: RideDataGrid(
            fields: const [
              RideDataField.speed,
              RideDataField.heartRate,
              RideDataField.distance,
              RideDataField.elapsed,
            ],
            layout: RideFieldLayout.four,
            data: const RideFieldContext(metrics: metrics, metric: true),
          ),
        ),
      ),
    );

    expect(find.text(RideDataField.speed.label), findsOneWidget);
    expect(find.text('31.2'), findsOneWidget);
    expect(find.text(RideDataField.heartRate.label), findsOneWidget);
    expect(find.text('151'), findsOneWidget);
    expect(find.text('18.4'), findsOneWidget);
    expect(find.text('52:00'), findsOneWidget);
  });

  testWidgets('data grid honours a two-field layout', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          height: 200,
          child: RideDataGrid(
            fields: const [RideDataField.speed, RideDataField.distance],
            layout: RideFieldLayout.two,
            data: const RideFieldContext(metrics: metrics, metric: true),
          ),
        ),
      ),
    );

    expect(find.text(RideDataField.speed.label), findsOneWidget);
    expect(find.text(RideDataField.distance.label), findsOneWidget);
    expect(find.text(RideDataField.heartRate.label), findsNothing);
  });

  testWidgets('navigation header shows the upcoming maneuver', (tester) async {
    final plan = NavigationPlan.fromJson({
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
      'summary': {'time': 300},
    });

    await tester.pumpWidget(
      host(
        NavigationHeader(
          progress: plan.progressAt(const GeoPoint(lat: 52.0, lon: 13.002)),
          metric: true,
          routeName: 'Lake loop',
        ),
      ),
    );

    // Nagłówek nawigacji mówi po polsku także wtedy, gdy router nie.
    expect(find.text('Skręć w lewo w Seestrasse'), findsOneWidget);
    expect(find.text('Seestrasse'), findsOneWidget);
    expect(find.text('Lake loop'), findsOneWidget);
    expect(find.byIcon(Icons.turn_left), findsOneWidget);
  });

  testWidgets('navigation header warns when off route', (tester) async {
    final plan = NavigationPlan.fromJson({
      'shape': [
        [52.0, 13.0],
        [52.0, 13.01],
      ],
      'maneuvers': <Map<String, Object?>>[],
    });

    await tester.pumpWidget(
      host(
        NavigationHeader(
          progress: plan.progressAt(const GeoPoint(lat: 52.01, lon: 13.005)),
          metric: true,
          routeName: 'Lake loop',
        ),
      ),
    );

    expect(find.textContaining('OFF ROUTE'), findsOneWidget);
  });

  testWidgets('weather field degrades to placeholders', (tester) async {
    await tester.pumpWidget(
      host(const WeatherField(weather: null, metric: true)),
    );
    expect(find.text('--'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('track preview paints without a map', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 120,
          height: 80,
          child: TrackPreview(
            points: [
              for (var i = 0; i < 40; i++)
                GeoPoint(lat: 52 + i / 5000, lon: 13 + (i % 7) / 5000),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('status chip renders its label', (tester) async {
    await tester.pumpWidget(
      host(const LrStatusChip(label: 'RECORDING', color: LR.alert)),
    );
    expect(find.text('RECORDING'), findsOneWidget);
  });
}
