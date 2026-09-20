import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/ride_metrics.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/models/training.dart';
import 'package:live_ride/models/route/route_analysis.dart';
import 'package:live_ride/models/weather.dart';
import 'package:live_ride/services/ride_intelligence.dart';

/// Ride Intelligence sprawdzany tam, gdzie łatwo skłamać.
///
/// Każda przepowiednia ma próg, poniżej którego wolno powiedzieć wyłącznie
/// „kalibruję". Test pilnuje właśnie tych progów, bo to one odróżniają
/// przyrząd od generatora zdań.

RideMetrics _metrics({
  required double distance,
  required Duration moving,
  double accuracy = 5,
}) => RideMetrics(
  distanceMeters: distance,
  movingTime: moving,
  elapsed: moving,
  gpsAccuracyMeters: accuracy,
);

RiderHistoryProfile _profile({double avgKmh = 25}) => RiderHistoryProfile(
  rideCount: 12,
  movingAverageKmh: avgKmh,
  typicalDistanceMeters: 50000,
  typicalAscentPerKm: 8,
);

RecordedRide _ride({
  List<RecordedRidePoint> points = const [],
  double distance = 50800,
  int movingSeconds = 7380,
  double maxSpeed = 53.2,
  double ascent = 470,
}) => RecordedRide(
  id: 'r1',
  name: 'Dzisiaj',
  startedAt: DateTime.utc(2026, 5, 1, 10),
  endedAt: DateTime.utc(2026, 5, 1, 12, 20),
  elapsedSeconds: 8400,
  movingSeconds: movingSeconds,
  distanceMeters: distance,
  elevationGainMeters: ascent,
  maxSpeedKmh: maxSpeed,
  points: points,
);

void main() {
  group('ETA', () {
    test('po dwóch minutach jazdy jeszcze się kalibruje', () {
      // „ETA 14:31" po trzech minutach jest liczbą wyssaną z palca.
      final estimate = RideIntelligence.eta(
        RideContext(
          metrics: _metrics(distance: 900, moving: const Duration(minutes: 2)),
          profile: _profile(),
          remainingMeters: 30000,
        ),
      );
      expect(estimate.confidence, InsightConfidence.calibrating);
      expect(estimate.at, isNull);
      expect(estimate.isUsable, isFalse);
    });

    test('po pół godzinie podaje godzinę z przedziałem', () {
      final now = DateTime.utc(2026, 5, 1, 12);
      final estimate = RideIntelligence.eta(
        RideContext(
          metrics: _metrics(
            distance: 14000,
            moving: const Duration(minutes: 35),
          ),
          profile: _profile(),
          remainingMeters: 20000,
          now: now,
        ),
      );
      expect(estimate.confidence, InsightConfidence.solid);
      expect(estimate.at, isNotNull);
      expect(estimate.spread, isNotNull);
      // 20 km przy 24 km/h to około pięćdziesiąt minut.
      final minutes = estimate.at!.difference(now).inMinutes;
      expect(minutes, inInclusiveRange(40, 60));
    });

    test('przewyższenie przed nami wydłuża ETA i poszerza przedział', () {
      final now = DateTime.utc(2026, 5, 1, 12);
      RideContext context({double ascent = 0}) => RideContext(
        metrics: _metrics(
          distance: 14000,
          moving: const Duration(minutes: 35),
        ),
        profile: _profile(),
        remainingMeters: 20000,
        routeAscentAheadMeters: ascent,
        now: now,
      );

      final flat = RideIntelligence.eta(context());
      final hilly = RideIntelligence.eta(context(ascent: 600));
      expect(hilly.at!.isAfter(flat.at!), isTrue);
      expect(hilly.spread!, greaterThan(flat.spread!));
    });

    test('bez trasy nie ma ETA, bo nie ma mety', () {
      final estimate = RideIntelligence.eta(
        RideContext(
          metrics: _metrics(
            distance: 20000,
            moving: const Duration(minutes: 50),
          ),
          profile: _profile(),
        ),
      );
      expect(estimate.isUsable, isFalse);
    });
  });

  group('insighty w trakcie', () {
    test('bez danych nie ma żadnego insightu', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(distance: 500, moving: const Duration(minutes: 2)),
          profile: RiderHistoryProfile.empty,
        ),
      );
      expect(insights, isEmpty);
    });

    test('bez historii nie mówimy „szybciej niż zwykle"', () {
      // Nie ma „zwykle", dopóki nie ma z czym porównać.
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 12000,
            moving: const Duration(minutes: 30),
          ),
          profile: RiderHistoryProfile.empty,
        ),
      );
      expect(insights.where((i) => i.kind == InsightKind.pace), isEmpty);
    });

    test('szybsza jazda niż zwykle jest podana w minutach, nie w km/h', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 12000,
            moving: const Duration(minutes: 24),
          ),
          profile: _profile(avgKmh: 25),
        ),
      );
      final pace = insights.firstWhere((i) => i.kind == InsightKind.pace);
      // 30 km/h wobec zwykłych 25.
      expect(pace.body, contains('szybciej'));
      expect(pace.body, contains('min'));
    });

    test('podjazd przed nami dostaje długość i nachylenie', () {
      final climb = Climb(
        index: 2,
        startDistanceMeters: 12000,
        endDistanceMeters: 14400,
        startElevation: 100,
        summitElevation: 252,
        maxGradientPercent: 9.1,
        points: const [],
      );
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 10000,
            moving: const Duration(minutes: 25),
          ),
          profile: _profile(),
          upcomingClimb: climb,
          metersToUpcomingClimb: 1800,
        ),
      );
      final ahead = insights.firstWhere((i) => i.kind == InsightKind.climb);
      expect(ahead.body, contains('1,8 km'));
      expect(ahead.body, contains('2,4 km'));
      expect(ahead.body, contains('+152 m'));
    });

    test('na podjeździe liczy się to, ile zostało', () {
      final climb = Climb(
        index: 2,
        startDistanceMeters: 12000,
        endDistanceMeters: 14400,
        startElevation: 100,
        summitElevation: 252,
        maxGradientPercent: 9.1,
        points: const [],
      );
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 13300,
            moving: const Duration(minutes: 35),
          ),
          profile: _profile(),
          activeClimb: climb,
          climbRemainingMeters: 1100,
        ),
      );
      final active = insights.firstWhere((i) => i.kind == InsightKind.climb);
      expect(active.body, contains('1,1 km'));
      expect(active.body, contains('pozostało'));
      expect(active.priority, InsightPriority.notable);
    });

    test('słaby GPS jest powiedziany wprost', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 8000,
            moving: const Duration(minutes: 20),
          ),
          profile: _profile(),
          gpsAccuracyMeters: 38,
        ),
      );
      final gps = insights.firstWhere((i) => i.kind == InsightKind.gps);
      expect(gps.body, contains('±38 m'));
    });

    test('przy słabym GPS nie ogłaszamy zjechania z trasy', () {
      // Trzydzieści metrów błędu pomiaru wygląda tak samo jak trzydzieści
      // metrów objazdu. Fałszywy alarm w lesie jest gorszy niż milczenie.
      expect(
        RideIntelligence.offRouteConfident(
          offRouteMeters: 120,
          gpsAccuracyMeters: 38,
        ),
        isFalse,
      );
      // Przy dobrym GPS ten sam dystans to już prawdziwy objazd.
      expect(
        RideIntelligence.offRouteConfident(
          offRouteMeters: 120,
          gpsAccuracyMeters: 4,
        ),
        isTrue,
      );
    });

    test('bez miernika mocy nie ma kart mocy', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 12000,
            moving: const Duration(minutes: 30),
          ),
          profile: _profile(),
        ),
      );
      expect(insights.map((i) => i.title), isNot(contains('MOC')));
    });

    test('deszcz i zachód słońca wchodzą tylko, gdy dotyczą tej jazdy', () {
      final now = DateTime.utc(2026, 5, 1, 18);
      final weather = WeatherSnapshot(
        temperatureCelsius: 15,
        apparentTemperatureCelsius: 14,
        windSpeedKmh: 24,
        windDirectionDegrees: 270,
        condition: WeatherCondition.cloudy,
        isDay: true,
        observedAt: now,
        precipitationProbability: 70,
        sunset: DateTime.utc(2026, 5, 1, 19, 6),
      );
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 30000,
            moving: const Duration(minutes: 75),
          ),
          profile: _profile(),
          remainingMeters: 40000,
          weather: weather,
          now: now,
        ),
      );
      expect(insights.map((i) => i.title), contains('POGODA'));
      expect(insights.map((i) => i.title), contains('ŚWIATŁO'));
      expect(insights.map((i) => i.title), contains('WIATR'));
    });

    test('niska bateria jest pilna, wysoka milczy', () {
      List<RideInsight> at(int percent) => RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 20000,
            moving: const Duration(minutes: 50),
          ),
          profile: _profile(),
          batteryPercent: percent,
        ),
      );
      expect(at(64).where((i) => i.kind == InsightKind.battery), isEmpty);
      final low = at(9).firstWhere((i) => i.kind == InsightKind.battery);
      expect(low.priority, InsightPriority.urgent);
      // Pilne idą na górę listy, bo panel pokazuje pierwsze dwa.
      expect(at(9).first.kind, InsightKind.battery);
    });

    test('plan porównuje tempo, a nie sam dystans', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 26000,
            moving: const Duration(minutes: 60),
          ),
          profile: _profile(),
          plannedDistanceMeters: 50000,
          plannedDuration: const Duration(hours: 2),
        ),
      );
      final plan = insights.firstWhere((i) => i.kind == InsightKind.plan);
      expect(plan.body, contains('przed planem'));
    });
  });

  group('profil z historii', () {
    test('krótkie dojazdy nie psują średniej', () {
      final profile = RiderHistoryProfile.fromRides([
        _ride(distance: 50000, movingSeconds: 7200),
        _ride(distance: 1500, movingSeconds: 300),
        _ride(distance: 40000, movingSeconds: 6000),
      ]);
      expect(profile.rideCount, 2);
      // Średnia ważona dystansem: 90 km w 3 godz. 40 min.
      expect(profile.movingAverageKmh, closeTo(24.5, 0.2));
    });

    test('dwa przejazdy to za mało, żeby cokolwiek twierdzić', () {
      final profile = RiderHistoryProfile.fromRides([
        _ride(distance: 50000, movingSeconds: 7200),
        _ride(distance: 40000, movingSeconds: 6000),
      ]);
      expect(profile.isUsable, isFalse);
    });

    test('brak historii nie jest zerem, tylko brakiem', () {
      expect(RiderHistoryProfile.fromRides(const []).isUsable, isFalse);
    });
  });

  group('podsumowanie po jeździe', () {
    test('highlighty biorą się z liczb, nie z przymiotników', () {
      final highlights = RideIntelligence.highlights(
        _ride(
          points: [
            for (var i = 0; i < 40; i++)
              RecordedRidePoint(
                lat: 52 + i * 0.001,
                lon: 13,
                recordedAt: DateTime.utc(2026, 5, 1, 10).add(
                  Duration(minutes: i < 20 ? i * 4 : 80 + (i - 20) * 2),
                ),
                altitude: 100 + (i < 20 ? i * 6 : (40 - i) * 6),
                distanceMeters: i * 1270,
              ),
          ],
        ),
        profile: _profile(avgKmh: 23),
      );

      expect(highlights.any((h) => h.contains('najwyższy punkt')), isTrue);
      expect(highlights.any((h) => h.contains('maks.')), isTrue);
      expect(highlights.any((h) => h.contains('druga połowa szybsza')), isTrue);
      expect(highlights.any((h) => h.contains('km/h względem')), isTrue);
    });

    test('bez punktów nie zmyślamy podziału na połówki', () {
      final highlights = RideIntelligence.highlights(_ride());
      expect(highlights.any((h) => h.contains('połowa')), isFalse);
    });
  });

  _zonesFuelAndCheckpoints();
  _shareable();
}

/// Druga część: strefy, moc, rozjazd, paliwo i punkty kontrolne.
///
/// Te reguły są najłatwiejsze do nadużycia — strefa zgadnięta bez tętna
/// maksymalnego, „IF 0,87" po dwóch minutach, przypomnienie o piciu co
/// pół minuty. Każdy test pilnuje dokładnie tego progu.
void _zonesFuelAndCheckpoints() {
  group('paliwo', () {
    RideContext fuelContext(Duration moving, {double? temperature}) =>
        RideContext(
          metrics: _metrics(distance: moving.inMinutes * 400, moving: moving),
          profile: _profile(),
          weather: temperature == null
              ? null
              : WeatherSnapshot(
                  temperatureCelsius: temperature,
                  apparentTemperatureCelsius: temperature,
                  windSpeedKmh: 5,
                  windDirectionDegrees: 180,
                  condition: WeatherCondition.clear,
                  isDay: true,
                  observedAt: DateTime.utc(2026, 5, 1, 12),
                ),
        );

    test('na pierwszym kwadransie milczy', () {
      final insights = RideIntelligence.during(
        fuelContext(const Duration(minutes: 12)),
      );
      expect(insights.where((i) => i.kind == InsightKind.fuel), isEmpty);
    });

    test('po dwudziestu minutach przypomina o piciu', () {
      final insights = RideIntelligence.during(
        fuelContext(const Duration(minutes: 20)),
      );
      final fuel = insights.firstWhere((i) => i.kind == InsightKind.fuel);
      expect(fuel.title, 'PICIE');
    });

    test('nie wisi na panelu przez cały kubełek', () {
      // Osiem minut po progu przypomnienie już zniknęło — inaczej byłoby
      // stałym elementem interfejsu, a nie przypomnieniem.
      final insights = RideIntelligence.during(
        fuelContext(const Duration(minutes: 28)),
      );
      expect(insights.where((i) => i.kind == InsightKind.fuel), isEmpty);
    });

    test('po czterdziestu pięciu minutach woła o jedzenie, nie o picie', () {
      final insights = RideIntelligence.during(
        fuelContext(const Duration(minutes: 45)),
      );
      final fuel = insights.firstWhere((i) => i.kind == InsightKind.fuel);
      expect(fuel.title, 'JEDZENIE');
    });

    test('w upale mówi wprost, żeby pić częściej', () {
      final insights = RideIntelligence.during(
        fuelContext(const Duration(minutes: 20), temperature: 31),
      );
      final fuel = insights.firstWhere((i) => i.kind == InsightKind.fuel);
      expect(fuel.body, contains('Gorąco'));
      expect(fuel.priority, InsightPriority.notable);
    });
  });

  group('strefy tętna', () {
    test('bez tętna maksymalnego nie zgaduje strefy', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: RideMetrics(
            distanceMeters: 20000,
            movingTime: const Duration(minutes: 50),
            elapsed: const Duration(minutes: 50),
            heartRate: 152,
          ),
          profile: _profile(),
          training: const TrainingProfile(),
        ),
      );
      expect(insights.where((i) => i.kind == InsightKind.zone), isEmpty);
    });

    test('z tętnem maksymalnym podaje numer i nazwę strefy', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: RideMetrics(
            distanceMeters: 20000,
            movingTime: const Duration(minutes: 50),
            elapsed: const Duration(minutes: 50),
            heartRate: 152,
          ),
          profile: _profile(),
          training: const TrainingProfile(maxHeartRate: 190),
        ),
      );
      final zone = insights.firstWhere((i) => i.kind == InsightKind.zone);
      expect(zone.title, 'STREFA 3');
      expect(zone.body, contains('152 bpm'));
    });
  });

  group('moc', () {
    RideContext powerContext({
      required Duration moving,
      int? normalized,
      int? ftp,
    }) => RideContext(
      metrics: RideMetrics(
        distanceMeters: 20000,
        movingTime: moving,
        elapsed: moving,
        power: PowerMetrics(current: 240, normalized: normalized),
      ),
      profile: _profile(),
      training: TrainingProfile(functionalThresholdPower: ftp),
    );

    test('bez FTP nie liczy intensywności', () {
      final insights = RideIntelligence.during(
        powerContext(moving: const Duration(minutes: 50), normalized: 240),
      );
      expect(insights.where((i) => i.kind == InsightKind.power), isEmpty);
    });

    test('po dziesięciu minutach jeszcze nic nie mówi', () {
      final insights = RideIntelligence.during(
        powerContext(
          moving: const Duration(minutes: 10),
          normalized: 240,
          ftp: 250,
        ),
      );
      expect(insights.where((i) => i.kind == InsightKind.power), isEmpty);
    });

    test('podaje moc znormalizowaną i IF', () {
      final insights = RideIntelligence.during(
        powerContext(
          moving: const Duration(minutes: 50),
          normalized: 225,
          ftp: 250,
        ),
      );
      final power = insights.firstWhere((i) => i.kind == InsightKind.power);
      expect(power.body, contains('225 W'));
      expect(power.body, contains('0.90'));
      expect(power.body, contains('mocne tempo'));
    });
  });

  group('rozjazd tętna i tempa', () {
    test('tracker milczy, dopóki obie połowy nie mają próbek', () {
      final tracker = DecouplingTracker(minimumSamplesPerHalf: 5);
      for (var i = 0; i < 6; i++) {
        tracker.add(
          movingTime: Duration(minutes: i),
          speedKmh: 28,
          heartRate: 140,
        );
      }
      expect(tracker.percent, isNull);
    });

    test('pomija próbki bez tętna i na postoju', () {
      final tracker = DecouplingTracker(minimumSamplesPerHalf: 2);
      tracker.add(movingTime: Duration.zero, speedKmh: 28, heartRate: null);
      tracker.add(movingTime: Duration.zero, speedKmh: 0, heartRate: 140);
      tracker.add(movingTime: Duration.zero, speedKmh: 28, heartRate: 40);
      expect(tracker.sampleCount, 0);
    });

    test('równa jazda daje rozjazd bliski zeru', () {
      final tracker = DecouplingTracker(minimumSamplesPerHalf: 10);
      for (var i = 0; i < 40; i++) {
        tracker.add(
          movingTime: Duration(minutes: i),
          speedKmh: 28,
          heartRate: 145,
        );
      }
      expect(tracker.percent!.abs(), lessThan(0.5));
    });

    test('to samo tętno przy wolniejszej jeździe to dodatni rozjazd', () {
      final tracker = DecouplingTracker(minimumSamplesPerHalf: 10);
      for (var i = 0; i < 20; i++) {
        tracker.add(
          movingTime: Duration(minutes: i),
          speedKmh: 30,
          heartRate: 145,
        );
      }
      for (var i = 20; i < 40; i++) {
        tracker.add(
          movingTime: Duration(minutes: i),
          speedKmh: 27,
          heartRate: 145,
        );
      }
      expect(tracker.percent, closeTo(10, 0.5));
    });

    test('mówi o obserwacji, nie o zdrowiu', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 40000,
            moving: const Duration(minutes: 90),
          ),
          profile: _profile(),
          decouplingPercent: 12,
        ),
      );
      final effort = insights.firstWhere((i) => i.kind == InsightKind.effort);
      expect(effort.body, contains('12%'));
      for (final word in ['chor', 'lekarz', 'objaw', 'zdrowi']) {
        expect(effort.body.toLowerCase(), isNot(contains(word)));
      }
    });

    test('na krótkiej jeździe nie ma czego porównywać', () {
      final insights = RideIntelligence.during(
        RideContext(
          metrics: _metrics(
            distance: 10000,
            moving: const Duration(minutes: 25),
          ),
          profile: _profile(),
          decouplingPercent: 12,
        ),
      );
      expect(insights.where((i) => i.kind == InsightKind.effort), isEmpty);
    });
  });

  group('ETA do podjazdu i checkpointów', () {
    RideContext longRide({
      double? metersToClimb,
      List<RideCheckpoint> checkpoints = const [],
    }) => RideContext(
      metrics: _metrics(distance: 30000, moving: const Duration(minutes: 60)),
      profile: _profile(),
      metersToUpcomingClimb: metersToClimb,
      checkpoints: checkpoints,
      now: DateTime.utc(2026, 5, 1, 12),
    );

    test('bez podjazdu przed sobą kalibruje, a nie zmyśla', () {
      expect(
        RideIntelligence.etaToClimb(longRide()).confidence,
        InsightConfidence.calibrating,
      );
    });

    test('pięć kilometrów do podjazdu przy 30 km/h to dziesięć minut', () {
      final estimate = RideIntelligence.etaToClimb(
        longRide(metersToClimb: 5000),
      );
      expect(estimate.isUsable, isTrue);
      expect(
        estimate.at!.difference(DateTime.utc(2026, 5, 1, 12)).inMinutes,
        closeTo(10, 1),
      );
    });

    test('wybiera najbliższy punkt przed sobą, nie ten za plecami', () {
      final insights = RideIntelligence.during(
        longRide(
          checkpoints: const [
            RideCheckpoint(name: 'Sklep', distanceMeters: 12000),
            RideCheckpoint(name: 'Przełęcz', distanceMeters: 42000),
            RideCheckpoint(name: 'Dworzec', distanceMeters: 65000),
          ],
        ),
      );
      final next = insights.firstWhere((i) => i.kind == InsightKind.eta);
      expect(next.title, 'PRZEŁĘCZ');
      expect(next.body, contains('12,0 km'));
    });

    test('po minięciu ostatniego punktu nic nie pokazuje', () {
      final insights = RideIntelligence.during(
        longRide(
          checkpoints: const [
            RideCheckpoint(name: 'Sklep', distanceMeters: 12000),
          ],
        ),
      );
      expect(insights.where((i) => i.kind == InsightKind.eta), isEmpty);
    });
  });
}

/// Co wolno wysłać obserwującym.
///
/// Zdania o ciele zostają na telefonie — nie dlatego, że serwer je odetnie
/// (odetnie), tylko dlatego, że nie mają powodu go opuszczać.
void _shareable() {
  group('insighty dla widzów', () {
    RideInsight insight(InsightKind kind) =>
        RideInsight(kind: kind, title: kind.name, body: 'cokolwiek');

    test('strefa, wysiłek i paliwo nie opuszczają telefonu', () {
      final out = RideIntelligence.shareable([
        insight(InsightKind.zone),
        insight(InsightKind.effort),
        insight(InsightKind.fuel),
        insight(InsightKind.climb),
      ], limit: 10);
      expect(out.map((i) => i['kind']), ['climb']);
    });

    test('lista prywatnych rodzajów jest jawna i pełna', () {
      expect(RideIntelligence.privateKinds, {
        InsightKind.zone,
        InsightKind.effort,
        InsightKind.fuel,
      });
    });

    test('limit obcina po odrzuceniu prywatnych, a nie przed', () {
      // Trzy prywatne na początku nie mogą zjeść limitu i zostawić widza
      // z pustym panelem mimo pięciu bezpiecznych insightów.
      final out = RideIntelligence.shareable([
        insight(InsightKind.zone),
        insight(InsightKind.effort),
        insight(InsightKind.fuel),
        insight(InsightKind.climb),
        insight(InsightKind.weather),
        insight(InsightKind.pace),
      ], limit: 3);
      expect(out.map((i) => i['kind']), ['climb', 'weather', 'pace']);
    });

    test('zdanie idzie gotowe, razem z tytułem i priorytetem', () {
      final out = RideIntelligence.shareable([
        const RideInsight(
          kind: InsightKind.climb,
          title: 'PODJAZD',
          body: 'Za 3,2 km podjazd.',
          priority: InsightPriority.notable,
        ),
      ]);
      expect(out.single, {
        'kind': 'climb',
        'title': 'PODJAZD',
        'body': 'Za 3,2 km podjazd.',
        'priority': 'notable',
      });
    });
  });
}
