import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/ride_metrics_accumulator.dart';
import 'package:live_ride/models/ride_data_field.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/models/sensor_device.dart';
import 'package:live_ride/models/ride_pages.dart';
import 'package:live_ride/models/rider_profile.dart';
import 'package:live_ride/models/training.dart';

void main() {
  _speedSourceTests();
  group('RideDataPage', () {
    const page = RideDataPage(
      name: 'Jazda',
      layout: RideFieldLayout.four,
      fields: [RideDataField.speed, RideDataField.distance],
    );

    test('dopełnia brakujące pola do rozmiaru układu', () {
      expect(page.activeFields, hasLength(4));
      expect(page.activeFields.take(2), [
        RideDataField.speed,
        RideDataField.distance,
      ]);
      expect(page.activeFields.toSet(), hasLength(4));
    });

    test('przycina nadmiarowe pola', () {
      const wide = RideDataPage(
        name: 'Za dużo',
        layout: RideFieldLayout.two,
        fields: [
          RideDataField.speed,
          RideDataField.distance,
          RideDataField.elapsed,
        ],
      );
      expect(wide.activeFields, [RideDataField.speed, RideDataField.distance]);
    });

    test('podmienia jedno pole i zostawia resztę', () {
      final next = page.withFieldAt(1, RideDataField.power);
      expect(next.activeFields[0], RideDataField.speed);
      expect(next.activeFields[1], RideDataField.power);
      expect(next.layout, page.layout);
    });

    test('ignoruje podmianę poza zakresem', () {
      expect(
        page.withFieldAt(9, RideDataField.power).activeFields,
        page.activeFields,
      );
      expect(
        page.withFieldAt(-1, RideDataField.power).activeFields,
        page.activeFields,
      );
    });

    test('przechodzi przez JSON bez strat', () {
      final restored = RideDataPage.fromJson(page.toJson());
      expect(restored.name, page.name);
      expect(restored.layout, page.layout);
      expect(restored.fields, page.fields);
    });

    test('nieznane pole z zapisu jest pomijane, nie wywala wczytywania', () {
      final restored = RideDataPage.fromJson({
        'name': 'Stara',
        'layout': 'four',
        'fields': ['speed', 'pole_ktorego_nie_ma', 'distance'],
      });
      expect(restored.fields, [RideDataField.speed, RideDataField.distance]);
    });
  });

  group('zestawy stron', () {
    test('każdy zestaw ma co najmniej jedną stronę z polami', () {
      for (final preset in RidePagePreset.values) {
        expect(preset.pages, isNotEmpty, reason: preset.name);
        for (final page in preset.pages) {
          expect(page.activeFields, hasLength(page.layout.fieldCount));
          expect(page.name, isNotEmpty);
        }
      }
    });

    test('zestaw treningowy stawia na moc, wycieczkowy nie', () {
      final training = RidePagePreset.training.pages
          .expand((page) => page.activeFields)
          .toSet();
      expect(training.any((field) => field.needsPowerMeter), isTrue);

      final basic = RidePagePreset.basic.pages
          .expand((page) => page.activeFields)
          .toSet();
      expect(basic.any((field) => field.needsPowerMeter), isFalse);
    });
  });

  group('RiderProfile a strony', () {
    test('stary profil bez stron dostaje jedną z dawnego układu', () {
      const profile = RiderProfile(
        layout: RideFieldLayout.six,
        fields: [
          RideDataField.speed,
          RideDataField.cadence,
          RideDataField.power,
        ],
      );
      final pages = profile.ridePages;
      expect(pages, hasLength(1));
      expect(pages.single.layout, RideFieldLayout.six);
      expect(pages.single.activeFields.take(3), [
        RideDataField.speed,
        RideDataField.cadence,
        RideDataField.power,
      ]);
    });

    test('strony przechodzą przez JSON', () {
      final profile = const RiderProfile().copyWith(
        pages: RidePagePreset.training.pages,
        weightKg: 72.5,
        ftpWatts: 240,
      );
      final restored = RiderProfile.fromJson(profile.toJson());
      expect(restored.pages, hasLength(3));
      expect(restored.pages.first.name, 'Moc');
      expect(restored.weightKg, 72.5);
      expect(restored.ftpWatts, 240);
    });
  });

  group('pola danych bez sensorów', () {
    const bare = RideFieldContext(metrics: RideMetrics(), metric: true);

    test('moc i kadencja pokazują --, a nie zero', () {
      for (final field in RideDataField.values.where(
        (field) => field.needsPowerMeter || field.needsCadenceSensor,
      )) {
        expect(field.read(bare).value, '--', reason: field.name);
      }
    });

    test('strefy nie pojawiają się bez profilu treningowego', () {
      expect(RideDataField.powerZone.read(bare).value, '--');
      expect(RideDataField.heartRateZone.read(bare).value, '--');
      expect(RideDataField.heartRatePercent.read(bare).value, '--');
      expect(RideDataField.powerPerKg.read(bare).value, '--');
    });

    test('strefy pojawiają się, gdy profil i dane są', () {
      const context = RideFieldContext(
        metrics: RideMetrics(heartRate: 160, power: PowerMetrics(current: 250)),
        metric: true,
        training: TrainingProfile(
          maxHeartRate: 190,
          functionalThresholdPower: 250,
          weightKg: 70,
        ),
        riderWeightKg: 70,
      );
      expect(context.metrics.heartRate, 160);
      expect(RideDataField.heartRateZone.read(context).value, 'Z4');
      expect(RideDataField.powerZone.read(context).value, 'Z4');
      expect(RideDataField.heartRatePercent.read(context).value, '84');
      expect(RideDataField.powerPerKg.read(context).value, '3.6');
    });

    test('VAM potrzebuje i czasu w ruchu, i przewyższenia', () {
      expect(RideDataField.vam.read(bare).value, '--');
      const climbing = RideFieldContext(
        metrics: RideMetrics(
          movingTime: Duration(minutes: 30),
          elevationGainMeters: 500,
        ),
        metric: true,
      );
      expect(RideDataField.vam.read(climbing).value, '1000');
    });
  });

  group('akumulator: moc i kadencja', () {
    test('bez sensora nie ma ani mocy, ani kadencji', () {
      final accumulator = RideMetricsAccumulator();
      final metrics = accumulator.build(
        elapsed: const Duration(minutes: 5),
        pointCount: 10,
        hasFix: true,
      );
      expect(metrics.power, isNull);
      expect(metrics.cadenceRpm, isNull);
      expect(metrics.workKj, isNull);
    });

    test('liczy pracę z mocy i czasu między próbkami', () {
      final accumulator = RideMetricsAccumulator();
      final start = DateTime(2026, 5, 1, 12);
      for (var i = 0; i <= 10; i++) {
        accumulator.addPower(200, at: start.add(Duration(seconds: i)));
      }
      // 200 W przez 10 sekund to 2000 J.
      final metrics = accumulator.build(
        elapsed: const Duration(seconds: 10),
        pointCount: 0,
        hasFix: true,
      );
      expect(metrics.workKj, closeTo(2.0, 0.001));
      expect(metrics.power!.average, 200);
      expect(metrics.power!.maximum, 200);
    });

    test('przerwa w danych nie dolicza pracy z powietrza', () {
      final accumulator = RideMetricsAccumulator();
      final start = DateTime(2026, 5, 1, 12);
      accumulator.addPower(200, at: start);
      accumulator.addPower(200, at: start.add(const Duration(minutes: 5)));
      final metrics = accumulator.build(
        elapsed: const Duration(minutes: 5),
        pointCount: 0,
        hasFix: true,
      );
      expect(metrics.workKj, isNull);
    });

    test('średnia kadencja liczy też zera z wybiegu', () {
      final accumulator = RideMetricsAccumulator();
      accumulator.addCadence(90);
      accumulator.addCadence(0);
      final metrics = accumulator.build(
        elapsed: const Duration(seconds: 2),
        pointCount: 0,
        hasFix: true,
      );
      expect(metrics.averageCadenceRpm, 45);
      expect(metrics.maxCadenceRpm, 90);
      expect(metrics.cadenceRpm, 0);
    });

    test('odrzuca kadencję spoza zakresu', () {
      final accumulator = RideMetricsAccumulator();
      accumulator.addCadence(400);
      accumulator.addCadence(-5);
      final metrics = accumulator.build(
        elapsed: const Duration(seconds: 1),
        pointCount: 0,
        hasFix: true,
      );
      expect(metrics.cadenceRpm, isNull);
    });

    test('reset czyści moc i kadencję razem z resztą', () {
      final accumulator = RideMetricsAccumulator();
      accumulator.addPower(300);
      accumulator.addCadence(95);
      accumulator.reset();
      final metrics = accumulator.build(
        elapsed: Duration.zero,
        pointCount: 0,
        hasFix: false,
      );
      expect(metrics.power, isNull);
      expect(metrics.cadenceRpm, isNull);
      expect(metrics.workKj, isNull);
    });
  });
}

/// Wybór źródła prędkości: czujnik koła czy GPS.
void _speedSourceTests() {
  group('źródło prędkości', () {
    final start = DateTime(2026, 5, 1, 12);

    RideMetricsAccumulator withGps(double kmh) {
      final accumulator = RideMetricsAccumulator();
      // Dwie próbki oddalone o sekundę dają akumulatorowi prędkość z GPS.
      final metersPerSecond = kmh / 3.6;
      accumulator.add(
        RideSample(lat: 52.0, lon: 21.0, timestamp: start, accuracyMeters: 5),
      );
      accumulator.add(
        RideSample(
          lat: 52.0,
          lon: 21.0 + metersPerSecond / 68500,
          timestamp: start.add(const Duration(seconds: 1)),
          speedMps: metersPerSecond,
          accuracyMeters: 5,
        ),
      );
      return accumulator;
    }

    test('bez czujnika liczy się GPS', () {
      final accumulator = withGps(30);
      expect(accumulator.speedKmh, greaterThan(20));
    });

    test('automatycznie woli czujnik koła', () {
      final accumulator = withGps(30)
        ..speedSource = MetricSource.auto
        ..setSensorSpeed(34, at: DateTime.now());
      expect(accumulator.speedKmh, 34);
    });

    test('wymuszony GPS ignoruje czujnik', () {
      final accumulator = withGps(30)
        ..speedSource = MetricSource.gps
        ..setSensorSpeed(34, at: DateTime.now());
      expect(accumulator.speedKmh, isNot(34));
    });

    test('wymuszony czujnik spada na GPS, gdy czujnik milczy', () {
      final accumulator = withGps(30)
        ..speedSource = MetricSource.sensor
        ..setSensorSpeed(null);
      expect(accumulator.speedKmh, greaterThan(20));
    });

    test('przeterminowany odczyt czujnika nie udaje aktualnego', () {
      final accumulator = withGps(30)
        ..speedSource = MetricSource.auto
        ..setSensorSpeed(
          34,
          at: DateTime.now().subtract(const Duration(seconds: 10)),
        );
      expect(accumulator.speedKmh, isNot(34));
    });

    test('absurdalna prędkość z czujnika jest odrzucana', () {
      final accumulator = withGps(30)
        ..speedSource = MetricSource.sensor
        ..setSensorSpeed(400, at: DateTime.now());
      expect(accumulator.speedKmh, lessThan(100));
    });
  });
}
