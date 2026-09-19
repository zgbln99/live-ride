import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/services/auto_pause_detector.dart';

/// Scenariusze z prawdziwej jazdy, a nie z pojedynczych liczb.
///
/// Każdy przypadek to ciąg sekund: prędkość i pozycja tak, jak zobaczyłby je
/// telefon. Wszystkie kryteria akceptacji z przeglądu przedwydaniowego są tu
/// odtworzone dosłownie.

final DateTime _t0 = DateTime.utc(2026, 5, 1, 9);

/// Punkt oddalony o [meters] na północ od startu.
GeoPoint _north(double meters) =>
    GeoPoint(lat: 52.0 + meters / 111320.0, lon: 21.0);

/// Symuluje przejazd i zwraca akcje w kolejności, w jakiej padły.
///
/// [speeds] to prędkość GPS w kolejnych sekundach. Pozycja domyślnie
/// przesuwa się zgodnie z tą prędkością, czyli tak jak w rzeczywistości.
class _Ride {
  _Ride({AutoPauseDetector? detector, bool recording = true})
    : detector = detector ?? AutoPauseDetector(),
      _recording = recording;

  final AutoPauseDetector detector;
  bool _recording;
  double _travelled = 0;
  int _second = 0;

  final List<AutoPauseAction> actions = [];

  bool get recording => _recording;

  /// Jedna sekunda jazdy.
  ///
  /// [advanceMeters] pozwala rozjechać prędkość z pozycją — tak wygląda
  /// zgubiony doppler albo skok GPS.
  AutoPauseAction second(
    double? gpsSpeedKmh, {
    double? advanceMeters,
    double accuracy = 5,
    double? sensorSpeedKmh,
    bool sensorFresh = true,
    double? absolutePosition,
  }) {
    final step = advanceMeters ?? ((gpsSpeedKmh ?? 0) / 3.6);
    _travelled += step;
    final at = _t0.add(Duration(seconds: ++_second));
    final action = detector.update(
      AutoPauseSample(
        at: at,
        point: _north(absolutePosition ?? _travelled),
        gpsSpeedKmh: gpsSpeedKmh,
        accuracyMeters: accuracy,
        sensorSpeedKmh: sensorSpeedKmh,
        sensorAt: sensorSpeedKmh == null
            ? null
            : (sensorFresh ? at : at.subtract(const Duration(minutes: 1))),
      ),
      recording: _recording,
    );
    actions.add(action);
    if (action == AutoPauseAction.pause) _recording = false;
    if (action == AutoPauseAction.resume) _recording = true;
    return action;
  }

  /// Sekundy bez żadnej próbki — utrata sygnału.
  AutoPauseAction silence(int seconds) {
    _second += seconds;
    return detector.tick(_t0.add(Duration(seconds: _second)));
  }

  bool get paused => !_recording;
  bool get pausedAtLeastOnce => actions.contains(AutoPauseAction.pause);
  bool get resumedAtLeastOnce => actions.contains(AutoPauseAction.resume);
}

void main() {
  group('A — zwalnianie do 1,5 km/h nie jest postojem', () {
    test('ciąg 20/10/5/2/1.5/2/4 km/h nie pauzuje licznika', () {
      final ride = _Ride();
      for (final speed in [20.0, 10.0, 5.0, 2.0, 1.5, 2.0, 4.0]) {
        ride.second(speed);
      }
      expect(ride.pausedAtLeastOnce, isFalse);
      expect(ride.paused, isFalse);
    });

    test('nawet dłuższe pełzanie 1,2 km/h nie pauzuje', () {
      final ride = _Ride();
      for (var i = 0; i < 40; i++) {
        ride.second(1.2);
      }
      expect(ride.pausedAtLeastOnce, isFalse);
    });
  });

  group('B — faktyczny postój pauzuje', () {
    test('zwolnienie do zera bez przemieszczenia zatrzymuje licznik', () {
      final ride = _Ride();
      for (final speed in [15.0, 8.0, 2.0]) {
        ride.second(speed);
      }
      expect(ride.pausedAtLeastOnce, isFalse);

      for (var i = 0; i < 4; i++) {
        ride.second(0, advanceMeters: 0);
      }
      expect(ride.pausedAtLeastOnce, isTrue);
      expect(ride.paused, isTrue);
    });

    test('pauza nie pada wcześniej niż po progu czasu', () {
      final ride = _Ride(
        detector: AutoPauseDetector(pauseAfter: const Duration(seconds: 3)),
      );
      ride.second(12);
      ride.second(0, advanceMeters: 0);
      ride.second(0, advanceMeters: 0);
      // Dwie sekundy ciszy to za mało — auta ruszają z sygnalizacji wolniej.
      expect(ride.pausedAtLeastOnce, isFalse);
      ride.second(0, advanceMeters: 0);
      ride.second(0, advanceMeters: 0);
      expect(ride.pausedAtLeastOnce, isTrue);
    });

    test('jeden fix z zerem w środku jazdy nie pauzuje', () {
      final ride = _Ride();
      ride.second(24);
      // Tunel, wiadukt, kanion między blokami.
      ride.second(0, advanceMeters: 6.7);
      ride.second(24);
      ride.second(24);
      expect(ride.pausedAtLeastOnce, isFalse);
    });
  });

  group('C — ruszenie wznawia automatyczną pauzę', () {
    test('0/0/3/5/8 wznawia licznik', () {
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 5; i++) {
        ride.second(0, advanceMeters: 0);
      }
      expect(ride.paused, isTrue);

      ride.second(0, advanceMeters: 0);
      ride.second(0, advanceMeters: 0);
      expect(ride.resumedAtLeastOnce, isFalse);

      ride.second(3);
      ride.second(5);
      expect(ride.resumedAtLeastOnce, isTrue);
      expect(ride.paused, isFalse);
    });

    test('jedna próbka z ruchem to za mało, żeby wznowić', () {
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 5; i++) {
        ride.second(0, advanceMeters: 0);
      }
      ride.second(6);
      expect(ride.resumedAtLeastOnce, isFalse);
    });
  });

  group('E — skok GPS na postoju nie wznawia', () {
    test('piętnastometrowy przeskok i powrót zostawia pauzę', () {
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 5; i++) {
        ride.second(0, advanceMeters: 0);
      }
      expect(ride.paused, isTrue);
      final stoppedAt = ride._travelled;

      ride.second(0, absolutePosition: stoppedAt);
      // Odbiornik przeskakuje o 15 m i wraca.
      ride.second(0, absolutePosition: stoppedAt + 15);
      ride.second(0, absolutePosition: stoppedAt);
      ride.second(0, absolutePosition: stoppedAt);

      expect(ride.resumedAtLeastOnce, isFalse);
      expect(ride.paused, isTrue);
    });

    test('pozycja przesunięta na stałe o 15 m też nie wznawia', () {
      // Telefon nie jedzie — on stoi piętnaście metrów obok. Bez warunku na
      // ROSNĄCE oddalenie taki dryf wznawiałby licznik na każdym postoju.
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 5; i++) {
        ride.second(0, advanceMeters: 0);
      }
      final stoppedAt = ride._travelled;

      for (var i = 0; i < 8; i++) {
        ride.second(0, absolutePosition: stoppedAt + 15);
      }
      expect(ride.resumedAtLeastOnce, isFalse);
    });
  });

  group('F — bardzo wolny podjazd nigdy nie pauzuje', () {
    test('1,5–3 km/h z konsekwentnie rosnącym dystansem', () {
      final ride = _Ride();
      const speeds = [3.0, 2.4, 1.8, 1.5, 1.6, 2.0, 1.7, 1.5, 1.5, 1.9];
      for (var lap = 0; lap < 6; lap++) {
        for (final speed in speeds) {
          ride.second(speed);
        }
      }
      expect(ride.pausedAtLeastOnce, isFalse);
    });
  });

  group('G — utrata sygnału nie jest postojem', () {
    test('cisza w trakcie jazdy 25 km/h nie pauzuje', () {
      final ride = _Ride();
      for (var i = 0; i < 5; i++) {
        ride.second(25);
      }
      expect(ride.silence(30), AutoPauseAction.none);
      expect(ride.pausedAtLeastOnce, isFalse);

      // Po odzyskaniu sygnału jazda toczy się dalej.
      ride.second(25, advanceMeters: 200);
      expect(ride.pausedAtLeastOnce, isFalse);
    });

    test('przerwa w próbkach zeruje niedokończone okno postoju', () {
      final ride = _Ride();
      ride.second(10);
      ride.second(0, advanceMeters: 0);
      ride.second(0, advanceMeters: 0);
      // Sygnał znika na 20 s, więc okno nie jest ciągłe.
      ride.silence(20);
      ride.second(0, advanceMeters: 0);
      expect(ride.pausedAtLeastOnce, isFalse);
    });
  });

  group('H i I — czujnik na kole rozstrzyga', () {
    test('H: koło stoi, GPS dryfuje — pauza', () {
      final ride = _Ride();
      ride.second(12, sensorSpeedKmh: 12);
      // Rower stoi, ale pozycja skacze po kilkanaście metrów.
      for (var i = 0; i < 5; i++) {
        ride.second(
          9,
          advanceMeters: i.isEven ? 14 : -14,
          accuracy: 28,
          sensorSpeedKmh: 0,
        );
      }
      expect(ride.pausedAtLeastOnce, isTrue);
    });

    test('I: koło się kręci, GPS chwilowo zeruje — brak pauzy', () {
      final ride = _Ride();
      for (var i = 0; i < 8; i++) {
        ride.second(0, advanceMeters: 0, sensorSpeedKmh: 22);
      }
      expect(ride.pausedAtLeastOnce, isFalse);
    });

    test('nieświeży odczyt z czujnika nie jest dowodem', () {
      // Czujnik odpiął się kwadrans temu i „pamięta" 22 km/h. Taki odczyt nie
      // może blokować pauzy, bo rower stoi pod sklepem.
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 5; i++) {
        ride.second(
          0,
          advanceMeters: 0,
          sensorSpeedKmh: 22,
          sensorFresh: false,
        );
      }
      expect(ride.pausedAtLeastOnce, isTrue);
    });
  });

  group('słaba dokładność GPS', () {
    test('dryf przy dokładności 40 m nie udaje ruchu', () {
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 6; i++) {
        ride.second(0, advanceMeters: i.isEven ? 18 : -18, accuracy: 40);
      }
      expect(ride.pausedAtLeastOnce, isTrue);
    });

    test(
      'przy dobrej dokładności to samo przemieszczenie liczy się jako ruch',
      () {
        final ride = _Ride();
        ride.second(10);
        for (var i = 0; i < 6; i++) {
          // Odbiornik zgubił doppler, ale pozycja realnie ucieka.
          ride.second(null, advanceMeters: 18, accuracy: 4);
        }
        expect(ride.pausedAtLeastOnce, isFalse);
      },
    );
  });

  group('sam brak przemieszczenia to słabszy dowód', () {
    test('bez prędkości z GPS pauza czeka dłużej', () {
      final ride = _Ride();
      ride.second(null, advanceMeters: 6);
      for (var i = 0; i < 5; i++) {
        ride.second(null, advanceMeters: 0);
      }
      // Trzy sekundy bez przemieszczenia to przy 1,5 km/h półtora metra —
      // mniej niż szum. Za mało, żeby ogłosić postój.
      expect(ride.pausedAtLeastOnce, isFalse);

      for (var i = 0; i < 25; i++) {
        ride.second(null, advanceMeters: 0);
      }
      expect(ride.pausedAtLeastOnce, isTrue);
    });
  });

  group('histereza', () {
    test('próg wznowienia jest wyraźnie wyższy niż próg postoju', () {
      final detector = AutoPauseDetector();
      expect(detector.resumeKmh, greaterThan(detector.stationaryGpsKmh * 2));
    });

    test('pełzanie na granicy progu nie mruga licznikiem', () {
      final ride = _Ride();
      ride.second(10);
      for (var i = 0; i < 6; i++) {
        ride.second(0, advanceMeters: 0);
      }
      expect(ride.paused, isTrue);

      // Drgania wokół progu postoju: 0,5–1,2 km/h. Za mało na wznowienie.
      for (final speed in [0.5, 1.2, 0.8, 1.1, 0.4, 1.2]) {
        ride.second(speed);
      }
      expect(ride.resumedAtLeastOnce, isFalse);

      // Prawdziwe ruszenie wznawia od razu po dwóch próbkach.
      ride.second(6);
      ride.second(9);
      expect(ride.paused, isFalse);
    });
  });

  group('reset', () {
    test('czyści okna i kotwicę', () {
      final ride = _Ride();
      ride.second(10);
      ride.second(0, advanceMeters: 0);
      ride.second(0, advanceMeters: 0);
      ride.detector.reset();
      expect(ride.detector.standingFor(_t0), isNull);

      ride.second(0, advanceMeters: 0);
      ride.second(0, advanceMeters: 0);
      // Po resecie okno liczy się od nowa, więc dwie próbki to za mało.
      expect(ride.pausedAtLeastOnce, isFalse);
    });
  });

  group('źródło decyzji', () {
    test('czujnik ma pierwszeństwo przed GPS', () {
      final detector = AutoPauseDetector();
      detector.update(
        AutoPauseSample(
          at: _t0,
          point: _north(0),
          gpsSpeedKmh: 0,
          sensorSpeedKmh: 20,
          sensorAt: _t0,
        ),
        recording: true,
      );
      expect(detector.evidence, AutoPauseEvidence.wheelSensor);
    });

    test('bez czujnika decyduje prędkość GPS', () {
      final detector = AutoPauseDetector();
      detector.update(
        AutoPauseSample(at: _t0, point: _north(0), gpsSpeedKmh: 18),
        recording: true,
      );
      expect(detector.evidence, AutoPauseEvidence.gpsSpeed);
    });

    test('bez prędkości zostaje przemieszczenie', () {
      final detector = AutoPauseDetector();
      detector.update(
        AutoPauseSample(at: _t0, point: _north(0)),
        recording: true,
      );
      expect(detector.evidence, AutoPauseEvidence.displacement);
    });
  });
}
