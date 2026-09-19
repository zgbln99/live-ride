import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/segment.dart';
import 'package:live_ride/services/segment_matcher.dart';

const double _lat = 52.0;
final double _degLon = 1 / (111320 * math.cos(_lat * math.pi / 180));
const double _degLat = 1 / 110540;

/// Punkt [meters] metrów na wschód od startu, [offset] metrów na północ.
GeoPoint _east(double meters, {double offset = 0, double? elevation}) =>
    GeoPoint(
      lat: _lat + offset * _degLat,
      lon: 21.0 + meters * _degLon,
      elevation: elevation,
    );

Segment _segment({double length = 1000}) => Segment(
  id: 'seg-1',
  name: 'Podjazd testowy',
  createdAt: DateTime(2026, 1, 1),
  points: [
    for (var meters = 0.0; meters <= length; meters += 50)
      _east(meters, elevation: 100 + meters * 0.05),
  ],
);

final DateTime _t0 = DateTime(2026, 5, 1, 12);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

void main() {
  group('segment', () {
    test('liczy dystans, przewyższenie i nachylenie', () {
      final segment = _segment();
      expect(segment.distanceMeters, closeTo(1000, 15));
      // Przewyższenie liczy ta sama analiza co dla tras, z wygładzeniem
      // i histerezą — na kilometrze zjada to kilka metrów i tak ma być:
      // lepiej trochę zaniżyć niż doliczyć szum wysokościomierza.
      expect(segment.ascentMeters, closeTo(50, 5));
      expect(segment.averageGradientPercent, closeTo(5, 0.6));
    });
  });

  group('SegmentMatcher', () {
    late SegmentMatcher matcher;

    setUp(() {
      matcher = SegmentMatcher()..load([_segment()]);
    });

    test('daleko od segmentu nic się nie dzieje', () {
      matcher.update(_east(0, offset: 500), now: _at(0));
      expect(matcher.update(_east(50, offset: 500), now: _at(5)), isNull);
      expect(matcher.activeSegment, isNull);
    });

    test('wjazd we właściwym kierunku uruchamia próbę', () {
      matcher.update(_east(-30), now: _at(0));
      final progress = matcher.update(_east(5), now: _at(3));
      expect(progress, isNotNull);
      expect(matcher.activeSegment!.id, 'seg-1');
      expect(progress!.fraction, lessThan(0.1));
    });

    test('przejazd w przeciwnym kierunku nie liczy się jako próba', () {
      // Jedzie na zachód przez punkt startowy.
      matcher.update(_east(30), now: _at(0));
      final progress = matcher.update(_east(5), now: _at(3));
      expect(progress, isNull);
      expect(matcher.activeSegment, isNull);
    });

    test('przejazd do końca zapisuje próbę i rekord', () {
      matcher.update(_east(-30), now: _at(0));
      matcher.update(_east(5), now: _at(2));
      for (var meters = 100; meters <= 1000; meters += 100) {
        matcher.update(_east(meters.toDouble()), now: _at(2 + meters ~/ 10));
      }
      expect(matcher.activeSegment, isNull);
      expect(matcher.finished, hasLength(1));

      final run = matcher.finished.single;
      expect(run.completed, isTrue);
      expect(run.duration.inSeconds, greaterThan(5));
      expect(run.averageSpeedKmh, greaterThan(5));
    });

    test('zjazd z segmentu przerywa próbę bez wyniku', () {
      matcher.update(_east(-30), now: _at(0));
      matcher.update(_east(5), now: _at(2));
      matcher.update(_east(300), now: _at(30));
      expect(matcher.activeSegment, isNotNull);

      // Skręt w bok, 200 m od linii segmentu.
      matcher.update(_east(320, offset: 200), now: _at(40));
      expect(matcher.activeSegment, isNull);
      expect(matcher.finished, isEmpty);
    });

    test('drugi przejazd porównuje się z rekordem', () {
      // Pierwszy przejazd: 100 sekund.
      matcher.update(_east(-30), now: _at(0));
      matcher.update(_east(5), now: _at(1));
      for (var meters = 100; meters <= 1000; meters += 100) {
        matcher.update(_east(meters.toDouble()), now: _at(1 + meters ~/ 10));
      }
      expect(matcher.finished, hasLength(1));

      // Drugi przejazd, szybszy.
      matcher.update(_east(-30), now: _at(500));
      matcher.update(_east(5), now: _at(501));
      final half = matcher.update(_east(500), now: _at(521));
      expect(half!.personalBest, isNotNull);
      // W połowie po 20 s przy rekordzie ~100 s: 20 - 50 = -30 s przewagi.
      expect(half.deltaSeconds, lessThan(0));
      expect(half.projectedTime!.inSeconds, lessThan(100));
    });

    test('delta milczy na pierwszych metrach', () {
      final progress = SegmentProgress(
        segment: _segment(),
        alongMeters: 5,
        elapsed: const Duration(seconds: 1),
        personalBest: const Duration(seconds: 100),
      );
      expect(progress.deltaSeconds, isNull);
      expect(progress.projectedTime, isNull);
    });

    test('bez rekordu nie ma z czym porównywać', () {
      final progress = SegmentProgress(
        segment: _segment(),
        alongMeters: 500,
        elapsed: const Duration(seconds: 50),
      );
      expect(progress.deltaSeconds, isNull);
      expect(progress.remainingMeters, closeTo(500, 15));
      expect(progress.projectedTime!.inSeconds, closeTo(100, 5));
    });

    test('reset czyści aktywną próbę i historię', () {
      matcher.update(_east(-30), now: _at(0));
      matcher.update(_east(5), now: _at(2));
      expect(matcher.activeSegment, isNotNull);
      matcher.reset();
      expect(matcher.activeSegment, isNull);
      expect(matcher.finished, isEmpty);
    });
  });
}
