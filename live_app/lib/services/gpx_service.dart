import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:xml/xml_events.dart';

import '../core/geo.dart';
import '../models/ride_record.dart';

/// Raised when a GPX file cannot be turned into a usable route. The message is
/// written to be shown to a rider verbatim — never "import failed".
class GpxException implements Exception {
  GpxException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// The geometry and metadata recovered from a GPX document.
class ParsedGpx {
  ParsedGpx({
    required this.name,
    required this.points,
    required this.trackCount,
    required this.segmentCount,
    required this.skippedPoints,
    required this.source,
  });

  final String name;
  final List<GeoPoint> points;
  final int trackCount;
  final int segmentCount;
  final int skippedPoints;

  /// Which GPX element the geometry came from: `trk`, `rte` or `wpt`.
  final String source;
}

/// A picked file resolved to bytes, whichever way the platform handed it over.
class _PickedBytes {
  const _PickedBytes(this.name, this.bytes, this.path);

  final String name;
  final List<int> bytes;
  final String? path;
}

class GpxService {
  /// Opens the system file picker and parses the selection.
  ///
  /// Returns null when the rider cancels. Everything else throws a
  /// [GpxException] carrying a message that says what actually went wrong.
  Future<({ParsedGpx parsed, List<int> bytes, String fileName})?>
  pickAndParse() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        // iOS does not reliably map a "gpx" extension filter onto a UTI, so
        // any file is accepted here and the extension is checked below.
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
    } catch (e) {
      throw GpxException(
        'The file picker could not be opened.',
        detail: e.toString(),
      );
    }

    final file = result?.files.singleOrNull;
    if (file == null) return null;

    final name = file.name.trim();
    if (!name.toLowerCase().endsWith('.gpx')) {
      throw GpxException(
        'That is not a GPX file.',
        detail: name.isEmpty ? 'no file name' : name,
      );
    }

    final picked = await _resolveBytes(file);
    if (picked.bytes.isEmpty) {
      throw GpxException(
        'The selected GPX file is empty (0 bytes).',
        detail: picked.path,
      );
    }

    final xml = decodeXml(picked.bytes);
    final parsed = parse(xml, fallbackName: name);
    return (parsed: parsed, bytes: picked.bytes, fileName: name);
  }

  /// Reads the picked file whichever way the platform exposed it.
  ///
  /// iOS hands over in-memory bytes for iCloud documents but only a path for
  /// local ones; Android can do either. A file still materialising from iCloud
  /// gives neither, which is reported as such instead of as a parse failure.
  Future<_PickedBytes> _resolveBytes(PlatformFile file) async {
    final inMemory = file.bytes;
    if (inMemory != null && inMemory.isNotEmpty) {
      return _PickedBytes(file.name, inMemory, file.path);
    }

    final path = file.path;
    if (path != null && path.isNotEmpty) {
      final handle = File(path);
      try {
        if (await handle.exists()) {
          final bytes = await handle.readAsBytes();
          if (bytes.isNotEmpty) {
            return _PickedBytes(file.name, bytes, path);
          }
        }
      } on FileSystemException catch (e) {
        throw GpxException(
          'The GPX file could not be read from storage.',
          detail: e.osError?.message ?? e.message,
        );
      }
    }

    final stream = file.readStream;
    if (stream != null) {
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
      }
      if (bytes.isNotEmpty) {
        return _PickedBytes(file.name, bytes, path);
      }
    }

    throw GpxException(
      'iOS did not provide the contents of that file. If it lives in iCloud '
      'Drive, open Files, download it so the cloud icon disappears, then '
      'import it again.',
      detail: path,
    );
  }

  /// Decodes bytes to text, coping with BOMs, UTF-16 and broken encodings.
  String decodeXml(List<int> bytes) {
    var data = bytes;
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
    }
    if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
      return _decodeUtf16(data.sublist(2), littleEndian: true);
    }
    if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
      return _decodeUtf16(data.sublist(2), littleEndian: false);
    }
    try {
      return utf8.decode(data);
    } on FormatException {
      // Exports from older devices are often latin-1: decoding leniently keeps
      // accented track names readable instead of failing the whole import.
      return utf8.decode(data, allowMalformed: true);
    }
  }

  String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  /// Parses GPX text.
  ///
  /// Uses the streaming event parser rather than building a document tree: it
  /// tolerates unknown namespaces, unexpected extension blocks and truncated
  /// files, and it keeps memory flat for very large tracks.
  ParsedGpx parse(String xml, {required String fallbackName}) {
    final text = _stripPreamble(xml);
    if (text.isEmpty) {
      throw GpxException('The GPX file contains no readable text.');
    }

    final trackPoints = <GeoPoint>[];
    final routePoints = <GeoPoint>[];
    final waypoints = <GeoPoint>[];

    final stack = <String>[];
    var trackCount = 0;
    var segmentCount = 0;
    var skipped = 0;

    String? metadataName;
    String? trackName;
    String? routeName;

    double? pendingLat;
    double? pendingLon;
    double? pendingEle;
    DateTime? pendingTime;
    String? pendingKind;
    final buffer = StringBuffer();
    var capturing = false;

    void commitPoint() {
      final lat = pendingLat;
      final lon = pendingLon;
      final kind = pendingKind;
      pendingLat = null;
      pendingLon = null;
      pendingKind = null;
      final ele = pendingEle;
      final time = pendingTime;
      pendingEle = null;
      pendingTime = null;
      if (kind == null) return;
      if (lat == null || lon == null) {
        skipped++;
        return;
      }
      final point = GeoPoint(lat: lat, lon: lon, elevation: ele, time: time);
      if (!point.isValid) {
        skipped++;
        return;
      }
      switch (kind) {
        case 'trkpt':
          trackPoints.add(point);
        case 'rtept':
          routePoints.add(point);
        default:
          waypoints.add(point);
      }
    }

    void handleEvents(Iterable<XmlEvent> events) {
      for (final event in events) {
        if (event is XmlStartElementEvent) {
          final local = _localName(event.name);
          switch (local) {
            case 'trk':
              trackCount++;
            case 'trkseg':
              segmentCount++;
            case 'trkpt':
            case 'rtept':
            case 'wpt':
              pendingKind = local;
              pendingLat = _readCoordinate(event, 'lat');
              pendingLon = _readCoordinate(event, 'lon');
              pendingEle = null;
              pendingTime = null;
            case 'ele':
            case 'time':
            case 'name':
              buffer.clear();
              capturing = true;
          }
          if (!event.isSelfClosing) {
            stack.add(local);
          } else if (local == 'trkpt' || local == 'rtept' || local == 'wpt') {
            commitPoint();
          }
          continue;
        }

        if (event is XmlTextEvent) {
          if (capturing) buffer.write(event.value);
          continue;
        }
        if (event is XmlCDATAEvent) {
          if (capturing) buffer.write(event.value);
          continue;
        }

        if (event is XmlEndElementEvent) {
          final local = _localName(event.name);
          final value = buffer.toString().trim();
          capturing = false;
          switch (local) {
            case 'ele':
              // A malformed elevation is dropped; it must never kill an import.
              final parsedEle = double.tryParse(value);
              if (parsedEle != null &&
                  parsedEle.isFinite &&
                  parsedEle > -500 &&
                  parsedEle < 9000) {
                pendingEle = parsedEle;
              }
            case 'time':
              pendingTime = DateTime.tryParse(value);
            case 'name':
              final parent = stack.length >= 2 ? stack[stack.length - 2] : '';
              if (value.isNotEmpty) {
                switch (parent) {
                  case 'metadata':
                    metadataName ??= value;
                  case 'trk':
                    trackName ??= value;
                  case 'rte':
                    routeName ??= value;
                }
              }
            case 'trkpt':
            case 'rtept':
            case 'wpt':
              commitPoint();
          }
          if (stack.isNotEmpty) {
            // Tolerate mismatched closing tags rather than aborting.
            final index = stack.lastIndexOf(local);
            if (index >= 0) {
              stack.removeRange(index, stack.length);
            } else {
              stack.removeLast();
            }
          }
        }
      }
    }

    try {
      handleEvents(parseEvents(text));
    } on Exception catch (e) {
      final recovered =
          trackPoints.length + routePoints.length + waypoints.length;
      if (recovered < 2) {
        throw GpxException(
          'The GPX file is not valid XML and could not be read.',
          detail: e.toString().split('\n').first,
        );
      }
      // Truncated download: keep what was recovered instead of losing the ride.
    }

    var points = trackPoints;
    var source = 'trk';
    if (points.length < 2 && routePoints.length > points.length) {
      points = routePoints;
      source = 'rte';
    }
    if (points.length < 2 && waypoints.length > points.length) {
      points = waypoints;
      source = 'wpt';
    }

    if (points.length < 2) {
      throw GpxException(
        'This GPX file has no usable route: only ${points.length} valid '
        'coordinate${points.length == 1 ? '' : 's'} were found'
        '${skipped > 0 ? ' and $skipped were unreadable' : ''}.',
      );
    }

    final name = [
      metadataName,
      trackName,
      routeName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).firstOrNull;

    return ParsedGpx(
      name:
          name?.trim() ??
          fallbackName.replaceFirst(
            RegExp(r'\.gpx$', caseSensitive: false),
            '',
          ),
      points: points,
      trackCount: trackCount,
      segmentCount: segmentCount,
      skippedPoints: skipped,
      source: source,
    );
  }

  /// Drops anything before the XML declaration or the root element. Some
  /// exporters and mail gateways prepend whitespace or stray characters.
  String _stripPreamble(String xml) {
    var text = xml;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    final start = text.indexOf('<');
    if (start > 0) text = text.substring(start);
    return text.trim();
  }

  String _localName(String name) {
    final colon = name.indexOf(':');
    return colon == -1 ? name : name.substring(colon + 1);
  }

  double? _readCoordinate(XmlStartElementEvent event, String attribute) {
    for (final candidate in event.attributes) {
      if (_localName(candidate.name) != attribute) continue;
      final value = double.tryParse(candidate.value.trim());
      if (value != null && value.isFinite) return value;
      return null;
    }
    return null;
  }

  /// Serialises a recorded ride as a GPX 1.1 track, including heart rate in
  /// the Garmin TrackPointExtension namespace so other tools can read it.
  String encodeRide(RecordedRide ride) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Live Ride" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(ride.name)}</name>')
      ..writeln('    <time>${ride.startedAt.toUtc().toIso8601String()}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(ride.name)}</name>')
      ..writeln('    <type>cycling</type>')
      ..writeln('    <trkseg>');

    for (final point in ride.points) {
      buffer.writeln(
        '      <trkpt lat="${point.lat.toStringAsFixed(7)}" '
        'lon="${point.lon.toStringAsFixed(7)}">',
      );
      if (point.altitude != null && point.altitude!.isFinite) {
        buffer.writeln(
          '        <ele>${point.altitude!.toStringAsFixed(1)}</ele>',
        );
      }
      buffer.writeln(
        '        <time>${point.recordedAt.toUtc().toIso8601String()}</time>',
      );
      if (point.heartRate != null && point.heartRate! > 0) {
        buffer
          ..writeln('        <extensions>')
          ..writeln('          <gpxtpx:TrackPointExtension>')
          ..writeln('            <gpxtpx:hr>${point.heartRate}</gpxtpx:hr>')
          ..writeln('          </gpxtpx:TrackPointExtension>')
          ..writeln('        </extensions>');
      }
      buffer.writeln('      </trkpt>');
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

extension _IterableHelpers<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? get singleOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    final value = iterator.current;
    return iterator.moveNext() ? null : value;
  }
}
