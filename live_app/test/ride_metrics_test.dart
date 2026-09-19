import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/ride_metrics_accumulator.dart';

RideSample sample({
  required double lat,
  required double lon,
  required int second,
  double? accuracy = 5,
  double? speed,
  double? altitude,
}) => RideSample(
  lat: lat,
  lon: lon,
  timestamp: DateTime(2026, 1, 1).add(Duration(seconds: second)),
  accuracyMeters: accuracy,
  speedMps: speed,
  altitude: altitude,
);

void main() {
  group('distance', () {
    test('accumulates steady riding', () {
      final accumulator = RideMetricsAccumulator();
      // Roughly 7 m per second eastwards at 52°N: about 25 km/h.
      for (var i = 0; i <= 60; i++) {
        accumulator.add(
          sample(lat: 52, lon: 13 + i * 0.0001, second: i, speed: 6.8),
        );
      }
      expect(accumulator.distanceMeters, closeTo(410, 40));
      expect(accumulator.movingTime.inSeconds, closeTo(60, 2));
      expect(accumulator.speedKmh, closeTo(24.5, 1));
    });

    test('does not accumulate drift while stationary', () {
      final accumulator = RideMetricsAccumulator();
      // A parked bike wandering by a couple of metres with a 10 m fix.
      const wobble = [0.0, 0.00002, -0.00001, 0.000015, -0.00002, 0.0];
      for (var i = 0; i < wobble.length; i++) {
        accumulator.add(
          sample(
            lat: 52 + wobble[i],
            lon: 13 + wobble[i],
            second: i * 2,
            accuracy: 10,
            speed: 0.2,
          ),
        );
      }
      expect(accumulator.distanceMeters, 0);
      expect(accumulator.movingTime, Duration.zero);
    });

    test('rejects a single implausible jump', () {
      final accumulator = RideMetricsAccumulator()
        ..add(sample(lat: 52, lon: 13, second: 0, speed: 5))
        ..add(sample(lat: 52, lon: 13.0001, second: 1, speed: 5));
      final before = accumulator.distanceMeters;

      // 1 km in one second is not a bicycle.
      final verdict = accumulator.add(
        sample(lat: 52, lon: 13.02, second: 2, speed: 5),
      );

      expect(verdict, SampleVerdict.rejected);
      expect(accumulator.distanceMeters, before);
    });

    test('resynchronises after repeated jumps without crediting distance', () {
      final accumulator = RideMetricsAccumulator()
        ..add(sample(lat: 52, lon: 13, second: 0, speed: 5));
      final before = accumulator.distanceMeters;
      SampleVerdict? verdict;
      for (var i = 1; i <= 3; i++) {
        verdict = accumulator.add(
          sample(lat: 52.5, lon: 13.5, second: i, speed: 5),
        );
      }
      expect(verdict, SampleVerdict.stationary);
      expect(accumulator.distanceMeters, before);
    });

    test('ignores fixes with unusable accuracy', () {
      final accumulator = RideMetricsAccumulator()
        ..add(sample(lat: 52, lon: 13, second: 0, speed: 5));
      final verdict = accumulator.add(
        sample(lat: 52, lon: 13.0005, second: 5, accuracy: 300, speed: 5),
      );
      expect(verdict, SampleVerdict.rejected);
      expect(accumulator.distanceMeters, 0);
    });

    test('drops out-of-order samples', () {
      final accumulator = RideMetricsAccumulator()
        ..add(sample(lat: 52, lon: 13, second: 10, speed: 5));
      final verdict = accumulator.add(
        sample(lat: 52, lon: 13.0002, second: 5, speed: 5),
      );
      expect(verdict, SampleVerdict.rejected);
    });
  });

  group('moving time', () {
    test('only counts time above the movement threshold', () {
      final accumulator = RideMetricsAccumulator();
      for (var i = 0; i <= 10; i++) {
        accumulator.add(
          sample(lat: 52, lon: 13 + i * 0.0001, second: i, speed: 6.8),
        );
      }
      final riding = accumulator.movingTime;
      // Now stop at a red light for a minute.
      for (var i = 11; i <= 70; i++) {
        accumulator.add(sample(lat: 52, lon: 13.001, second: i, speed: 0.1));
      }
      expect(accumulator.movingTime, riding);
    });
  });

  group('max speed', () {
    test('ignores implausible speed readings', () {
      final accumulator = RideMetricsAccumulator()
        ..add(sample(lat: 52, lon: 13, second: 0, speed: 8))
        ..add(sample(lat: 52, lon: 13.0002, second: 2, speed: 8))
        ..add(sample(lat: 52, lon: 13.0004, second: 4, speed: 250));
      expect(accumulator.maxSpeedKmh, lessThan(40));
    });
  });

  group('heart rate', () {
    test('tracks average and maximum', () {
      final accumulator = RideMetricsAccumulator()
        ..addHeartRate(120)
        ..addHeartRate(140)
        ..addHeartRate(160)
        ..addHeartRate(900);
      expect(accumulator.heartRate, 160);
      expect(accumulator.averageHeartRate, 140);
      expect(accumulator.maxHeartRate, 160);
    });
  });

  group('gradient', () {
    test('reports a climb once enough road has passed', () {
      final accumulator = RideMetricsAccumulator();
      // ~7 m per sample east, gaining 0.5 m each time: about 7 %.
      for (var i = 0; i <= 60; i++) {
        accumulator.add(
          sample(
            lat: 52,
            lon: 13 + i * 0.0001,
            second: i,
            speed: 6.8,
            altitude: 100 + i * 0.5,
          ),
        );
      }
      expect(accumulator.gradientPercent, greaterThan(2));
      expect(accumulator.gradientPercent, lessThan(12));
    });
  });

  group('metrics snapshot', () {
    test('derives average speed from moving time', () {
      final accumulator = RideMetricsAccumulator();
      for (var i = 0; i <= 60; i++) {
        accumulator.add(
          sample(lat: 52, lon: 13 + i * 0.0001, second: i, speed: 6.8),
        );
      }
      final metrics = accumulator.build(
        elapsed: const Duration(minutes: 2),
        pointCount: 61,
        hasFix: true,
      );
      expect(metrics.averageSpeedKmh, closeTo(24.5, 2));
      // Overall speed includes the stopped minute, so it must be lower.
      expect(metrics.overallSpeedKmh, lessThan(metrics.averageSpeedKmh));
    });
  });
}
