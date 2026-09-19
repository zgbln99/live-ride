import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/services/gpx_service.dart';

const _track = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Alpine loop</name></metadata>
  <trk>
    <name>Track name</name>
    <trkseg>
      <trkpt lat="47.0" lon="11.0"><ele>1000</ele><time>2026-01-01T09:00:00Z</time></trkpt>
      <trkpt lat="47.001" lon="11.001"><ele>1010</ele></trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="47.002" lon="11.002"><ele>1020</ele></trkpt>
    </trkseg>
  </trk>
</gpx>
''';

void main() {
  final gpx = GpxService();

  group('parse', () {
    test('reads track points across multiple segments', () {
      final parsed = gpx.parse(_track, fallbackName: 'file.gpx');
      expect(parsed.points.length, 3);
      expect(parsed.segmentCount, 2);
      expect(parsed.trackCount, 1);
      expect(parsed.source, 'trk');
    });

    test('prefers the metadata name over the track name', () {
      expect(gpx.parse(_track, fallbackName: 'file.gpx').name, 'Alpine loop');
    });

    test('falls back to the file name when no name is present', () {
      const xml = '''
<gpx><trk><trkseg>
<trkpt lat="1" lon="1"/><trkpt lat="1.001" lon="1"/>
</trkseg></trk></gpx>''';
      expect(gpx.parse(xml, fallbackName: 'Sunday.gpx').name, 'Sunday');
    });

    test('falls back to route points when there is no track', () {
      const xml = '''
<gpx><rte><name>Planned</name>
<rtept lat="47" lon="11"/><rtept lat="47.01" lon="11.01"/>
</rte></gpx>''';
      final parsed = gpx.parse(xml, fallbackName: 'x.gpx');
      expect(parsed.source, 'rte');
      expect(parsed.points.length, 2);
      expect(parsed.name, 'Planned');
    });

    test('falls back to waypoints when there is nothing else', () {
      const xml = '''
<gpx><wpt lat="47" lon="11"/><wpt lat="47.01" lon="11.01"/></gpx>''';
      final parsed = gpx.parse(xml, fallbackName: 'x.gpx');
      expect(parsed.source, 'wpt');
      expect(parsed.points.length, 2);
    });

    test('survives namespaced elements and unknown extensions', () {
      const xml = '''
<?xml version="1.0"?>
<gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1">
  <gpx:trk><gpx:trkseg>
    <gpx:trkpt lat="47.0" lon="11.0">
      <gpx:ele>500</gpx:ele>
      <gpx:extensions><foo:bar xmlns:foo="urn:x">42</foo:bar></gpx:extensions>
    </gpx:trkpt>
    <gpx:trkpt lat="47.001" lon="11.0"><gpx:ele>505</gpx:ele></gpx:trkpt>
  </gpx:trkseg></gpx:trk>
</gpx:gpx>''';
      final parsed = gpx.parse(xml, fallbackName: 'x.gpx');
      expect(parsed.points.length, 2);
      expect(parsed.points.first.elevation, 500);
    });

    test('keeps a point whose optional fields are malformed', () {
      const xml = '''
<gpx><trk><trkseg>
  <trkpt lat="47.0" lon="11.0"><ele>N/A</ele><time>not-a-time</time></trkpt>
  <trkpt lat="47.001" lon="11.0"><ele></ele><time></time></trkpt>
</trkseg></trk></gpx>''';
      final parsed = gpx.parse(xml, fallbackName: 'x.gpx');
      expect(parsed.points.length, 2);
      expect(parsed.points.first.elevation, isNull);
      expect(parsed.points.first.time, isNull);
    });

    test('skips coordinates that are not numbers or out of range', () {
      const xml = '''
<gpx><trk><trkseg>
  <trkpt lat="abc" lon="11.0"/>
  <trkpt lat="200" lon="11.0"/>
  <trkpt lat="47.0" lon="11.0"/>
  <trkpt lat="47.001" lon="11.0"/>
</trkseg></trk></gpx>''';
      final parsed = gpx.parse(xml, fallbackName: 'x.gpx');
      expect(parsed.points.length, 2);
      expect(parsed.skippedPoints, 2);
    });

    test('handles a leading byte order mark and stray preamble', () {
      final xml = '﻿\n  $_track';
      expect(gpx.parse(xml, fallbackName: 'x.gpx').points.length, 3);
    });

    test('explains an empty document instead of failing generically', () {
      expect(
        () => gpx.parse('', fallbackName: 'x.gpx'),
        throwsA(
          isA<GpxException>().having(
            (e) => e.message,
            'message',
            contains('no readable text'),
          ),
        ),
      );
    });

    test('explains a GPX with a single usable point', () {
      const xml =
          '<gpx><trk><trkseg><trkpt lat="47" lon="11"/></trkseg></trk></gpx>';
      expect(
        () => gpx.parse(xml, fallbackName: 'x.gpx'),
        throwsA(
          isA<GpxException>().having(
            (e) => e.message,
            'message',
            contains('only 1 valid coordinate'),
          ),
        ),
      );
    });

    test('recovers points from a truncated file', () {
      const xml = '''
<gpx><trk><trkseg>
  <trkpt lat="47.0" lon="11.0"><ele>500</ele></trkpt>
  <trkpt lat="47.001" lon="11.0"><ele>505</ele></trkpt>
  <trkpt lat="47.002" lon="11.0"><ele>51''';
      final parsed = gpx.parse(xml, fallbackName: 'x.gpx');
      expect(parsed.points.length, greaterThanOrEqualTo(2));
    });

    test('parses a large file without help', () {
      final buffer = StringBuffer('<gpx><trk><trkseg>');
      for (var i = 0; i < 60000; i++) {
        buffer.write(
          '<trkpt lat="${47 + i / 1000000}" lon="11.0"><ele>500</ele></trkpt>',
        );
      }
      buffer.write('</trkseg></trk></gpx>');
      final parsed = gpx.parse(buffer.toString(), fallbackName: 'big.gpx');
      expect(parsed.points.length, 60000);
    });
  });

  group('decodeXml', () {
    test('strips a UTF-8 byte order mark', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('<gpx/>')];
      expect(gpx.decodeXml(bytes), '<gpx/>');
    });

    test('decodes UTF-16 little endian', () {
      final bytes = <int>[0xFF, 0xFE];
      for (final unit in '<gpx/>'.codeUnits) {
        bytes.addAll([unit & 0xFF, unit >> 8]);
      }
      expect(gpx.decodeXml(bytes), '<gpx/>');
    });

    test('does not throw on invalid UTF-8', () {
      expect(
        gpx.decodeXml([0xC3, 0x28, 0x3C, 0x67, 0x70, 0x78, 0x2F, 0x3E]),
        contains('<gpx/>'),
      );
    });
  });

  group('encodeRide', () {
    test('round-trips a recorded ride through GPX', () {
      final ride = RecordedRide(
        id: 'ride-1',
        name: 'Evening ride',
        startedAt: DateTime.utc(2026, 5, 1, 17),
        endedAt: DateTime.utc(2026, 5, 1, 18),
        elapsedSeconds: 3600,
        movingSeconds: 3400,
        distanceMeters: 24000,
        elevationGainMeters: 320,
        points: [
          RecordedRidePoint(
            lat: 47.0,
            lon: 11.0,
            recordedAt: DateTime.utc(2026, 5, 1, 17),
            altitude: 500,
            heartRate: 142,
          ),
          RecordedRidePoint(
            lat: 47.001,
            lon: 11.001,
            recordedAt: DateTime.utc(2026, 5, 1, 17, 0, 10),
            altitude: 505,
            heartRate: 145,
          ),
        ],
      );

      final xml = gpx.encodeRide(ride);
      expect(xml, contains('<gpxtpx:hr>142</gpxtpx:hr>'));

      final parsed = gpx.parse(xml, fallbackName: 'out.gpx');
      expect(parsed.name, 'Evening ride');
      expect(parsed.points.length, 2);
      expect(parsed.points.first.elevation, 500);
      expect(parsed.points.first.time, isNotNull);
    });

    test('escapes names that would break the document', () {
      final ride = RecordedRide(
        id: 'ride-2',
        name: 'Tom & Jerry <fast>',
        startedAt: DateTime.utc(2026, 5, 1),
        endedAt: DateTime.utc(2026, 5, 1, 1),
        elapsedSeconds: 60,
        movingSeconds: 60,
        distanceMeters: 100,
        elevationGainMeters: 0,
        points: [
          RecordedRidePoint(
            lat: 47,
            lon: 11,
            recordedAt: DateTime.utc(2026, 5, 1),
          ),
          RecordedRidePoint(
            lat: 47.001,
            lon: 11,
            recordedAt: DateTime.utc(2026, 5, 1, 0, 0, 5),
          ),
        ],
      );
      final parsed = gpx.parse(gpx.encodeRide(ride), fallbackName: 'x.gpx');
      expect(parsed.name, 'Tom & Jerry <fast>');
    });
  });

  group('shared GPX corpus', () {
    // The repository-level corpus is the cross-language contract for GPX
    // handling. Live Ride does not reuse the old metrics pipeline, but its
    // importer must still read every file in it.
    final corpus = Directory('../fixtures/gpx-corpus');

    test('every fixture imports', () {
      if (!corpus.existsSync()) {
        markTestSkipped('GPX corpus not present');
        return;
      }
      final directories = corpus
          .listSync()
          .whereType<Directory>()
          .where((dir) => File('${dir.path}/input.gpx').existsSync())
          .toList();
      expect(directories, isNotEmpty);

      for (final directory in directories) {
        final file = File('${directory.path}/input.gpx');
        final parsed = gpx.parse(
          gpx.decodeXml(file.readAsBytesSync()),
          fallbackName: 'input.gpx',
        );
        expect(
          parsed.points.length,
          greaterThanOrEqualTo(2),
          reason: '${directory.path} produced too few points',
        );
      }
    });
  });
}
