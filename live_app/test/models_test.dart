import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/formatters.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/ride_data_field.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/models/ride_route.dart';
import 'package:live_ride/models/rider_profile.dart';
import 'package:live_ride/models/weather.dart';

void main() {
  group('RiderProfile identity', () {
    test('prefers the display name', () {
      const profile = RiderProfile(displayName: 'Marek P', username: 'marek');
      expect(profile.effectiveName, 'Marek P');
    });

    test('falls back to the username', () {
      const profile = RiderProfile(username: 'marek');
      expect(profile.effectiveName, 'marek');
    });

    test('only says Rider when there is no identity at all', () {
      expect(const RiderProfile().effectiveName, 'Rider');
      expect(const RiderProfile().hasIdentity, isFalse);
    });

    test('survives a round trip through JSON', () {
      const profile = RiderProfile(
        displayName: 'Ada',
        username: 'ada',
        metricUnits: false,
        layout: RideFieldLayout.six,
        fields: [
          RideDataField.speed,
          RideDataField.avgSpeed,
          RideDataField.heartRate,
          RideDataField.distance,
          RideDataField.elevationGain,
          RideDataField.elapsed,
        ],
      );
      final restored = RiderProfile.fromJson(profile.toJson());
      expect(restored.displayName, 'Ada');
      expect(restored.metricUnits, isFalse);
      expect(restored.layout, RideFieldLayout.six);
      expect(restored.fields.length, 6);
    });

    test('pads the field list to match the layout', () {
      const profile = RiderProfile(
        layout: RideFieldLayout.eight,
        fields: [RideDataField.speed],
      );
      expect(profile.activeFields.length, 8);
      expect(profile.activeFields.first, RideDataField.speed);
    });

    test('trims the field list when the layout shrinks', () {
      const profile = RiderProfile(
        layout: RideFieldLayout.two,
        fields: [
          RideDataField.speed,
          RideDataField.distance,
          RideDataField.elapsed,
          RideDataField.heartRate,
        ],
      );
      expect(profile.activeFields, [
        RideDataField.speed,
        RideDataField.distance,
      ]);
    });
  });

  group('RideDataField', () {
    const metrics = RideMetrics(
      speedKmh: 28.4,
      distanceMeters: 15400,
      elapsed: Duration(minutes: 41),
      movingTime: Duration(minutes: 38),
      elevationGainMeters: 240,
      heartRate: 148,
      gpsAccuracyMeters: 42,
    );

    test('formats values with their units', () {
      const context = RideFieldContext(metrics: metrics, metric: true);
      expect(RideDataField.speed.read(context).value, '28.4');
      expect(RideDataField.speed.read(context).unit, 'km/h');
      expect(RideDataField.distance.read(context).value, '15.4');
      expect(RideDataField.heartRate.read(context).value, '148');
      expect(RideDataField.elapsed.read(context).value, '41:00');
    });

    test('flags a poor GPS fix', () {
      const context = RideFieldContext(metrics: metrics, metric: true);
      expect(RideDataField.gpsAccuracy.read(context).alert, isTrue);
    });

    test('shows placeholders when weather is missing', () {
      const context = RideFieldContext(metrics: metrics, metric: true);
      expect(RideDataField.temperature.read(context).value, '--');
      expect(RideDataField.wind.read(context).value, '--');
      expect(RideDataField.rainChance.read(context).value, '--');
    });

    test('converts to imperial units', () {
      const context = RideFieldContext(metrics: metrics, metric: false);
      expect(RideDataField.distance.read(context).unit, 'mi');
      expect(
        double.parse(RideDataField.distance.read(context).value),
        closeTo(9.57, 0.05),
      );
    });
  });

  group('RideRoute', () {
    test('detects a loop', () {
      final points = <GeoPoint>[
        const GeoPoint(lat: 52.0, lon: 13.0),
        const GeoPoint(lat: 52.01, lon: 13.0),
        const GeoPoint(lat: 52.01, lon: 13.01),
        const GeoPoint(lat: 52.0, lon: 13.01),
        const GeoPoint(lat: 52.0, lon: 13.0),
      ];
      expect(
        RideRoute(id: 'a', name: 'Loop', points: points).shape,
        RouteShape.loop,
      );
    });

    test('summarises for the library index', () {
      final points = [
        for (var i = 0; i < 500; i++)
          GeoPoint(lat: 52 + i / 10000, lon: 13, elevation: 100 + i / 5),
      ];
      final summary = RideRoute(
        id: 'a',
        name: 'Climb',
        points: points,
      ).toSummary();
      expect(summary.pointCount, 500);
      expect(summary.preview.length, lessThan(130));
      expect(summary.ascentMeters, greaterThan(50));
      expect(summary.name, 'Climb');
    });
  });

  group('RecordedRide', () {
    RecordedRide build() => RecordedRide(
      id: 'ride',
      name: 'Test',
      startedAt: DateTime.utc(2026, 4, 2, 8),
      endedAt: DateTime.utc(2026, 4, 2, 9),
      elapsedSeconds: 3600,
      movingSeconds: 3000,
      distanceMeters: 25000,
      elevationGainMeters: 300,
      points: [
        for (var i = 0; i < 60; i++)
          RecordedRidePoint(
            lat: 52 + i / 10000,
            lon: 13,
            recordedAt: DateTime.utc(2026, 4, 2, 8).add(Duration(seconds: i)),
            altitude: 100 + i.toDouble(),
            distanceMeters: i * 400,
          ),
      ],
    );

    test('averages speed over moving time', () {
      expect(build().averageSpeedKmh, closeTo(30, 0.1));
    });

    test('round-trips through JSON', () {
      final restored = RecordedRide.fromJson(build().toJson());
      expect(restored.points.length, 60);
      expect(restored.elapsedSeconds, 3600);
      expect(restored.distanceMeters, 25000);
    });

    test(
      'falls back to moving time for rides saved before elapsed existed',
      () {
        final json = build().toJson()..remove('elapsed_seconds');
        expect(RecordedRide.fromJson(json).elapsedSeconds, 3000);
      },
    );

    test('builds a smoothed elevation profile', () {
      final profile = build().elevationProfile();
      expect(profile.length, greaterThan(5));
      expect(profile.first.distance, 0);
      expect(profile.last.elevation, greaterThan(profile.first.elevation));
    });
  });

  group('WeatherSnapshot', () {
    test('round-trips through JSON', () {
      final snapshot = WeatherSnapshot(
        temperatureCelsius: 18.2,
        apparentTemperatureCelsius: 17.1,
        windSpeedKmh: 14,
        windDirectionDegrees: 270,
        condition: WeatherCondition.partlyCloudy,
        isDay: true,
        observedAt: DateTime.utc(2026, 4, 2, 8),
        precipitationProbability: 20,
      );
      final restored = WeatherSnapshot.fromJson(snapshot.toJson());
      expect(restored.condition, WeatherCondition.partlyCloudy);
      expect(restored.precipitationProbability, 20);
      expect(restored.windDirectionDegrees, 270);
    });
  });

  group('Fmt', () {
    test('scales distance precision', () {
      expect(Fmt.distance(1234), '1.23');
      expect(Fmt.distance(45678), '45.7');
      expect(Fmt.distance(145678), '146');
    });

    test('switches turn distance units at a kilometre', () {
      expect(Fmt.turnDistanceUnit(450), 'm');
      expect(Fmt.turnDistanceUnit(1400), 'km');
      expect(Fmt.turnDistance(1400), '1.4');
    });

    test('formats durations with and without hours', () {
      expect(Fmt.duration(const Duration(minutes: 7, seconds: 5)), '07:05');
      expect(
        Fmt.duration(const Duration(hours: 2, minutes: 7, seconds: 5)),
        '2:07:05',
      );
    });

    test('names compass sectors', () {
      expect(Fmt.compass(0), 'N');
      expect(Fmt.compass(90), 'E');
      expect(Fmt.compass(225), 'SW');
      expect(Fmt.compass(359), 'N');
    });

    test('derives initials from a rider name', () {
      expect(Fmt.initials('Marek Piatak'), 'MP');
      expect(Fmt.initials('marek'), 'MA');
      expect(Fmt.initials(''), 'LR');
    });
  });
}
