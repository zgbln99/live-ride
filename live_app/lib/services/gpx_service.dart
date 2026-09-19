import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:gpx/gpx.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ride_route.dart';

class GpxService {
  Future<RideRoute?> importRoute() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: false,
    );
    final file = result?.files.single;
    if (file == null) return null;

    final name = file.name.trim();
    if (!name.toLowerCase().endsWith('.gpx')) {
      throw const FormatException('Wybierz plik z rozszerzeniem .gpx.');
    }

    final bytes = await _readPickedFile(file);
    if (bytes.isEmpty) {
      throw const FileSystemException('Wybrany plik GPX jest pusty.');
    }

    String xml;
    try {
      xml = utf8.decode(bytes);
    } on FormatException {
      xml = utf8.decode(bytes, allowMalformed: true);
    }

    final route = parseXml(xml, fallbackName: name);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/routes');
    await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe',
    );
    await destination.writeAsBytes(bytes, flush: true);

    return RideRoute(
      name: route.name,
      points: route.points,
      rawGpx: route.rawGpx,
      sourcePath: destination.path,
    );
  }

  Future<List<int>> _readPickedFile(PlatformFile file) async {
    final inMemory = file.bytes;
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final path = file.path;
    if (path != null && path.isNotEmpty) {
      final selected = File(path);
      if (await selected.exists()) {
        return selected.readAsBytes();
      }
    }

    throw const FileSystemException(
      'iOS nie udostępnił danych wybranego pliku. Pobierz plik z iCloud do Plików i spróbuj ponownie.',
    );
  }

  RideRoute parseXml(String xml, {required String fallbackName, String? sourcePath}) {
    final normalized = xml.startsWith('\ufeff') ? xml.substring(1) : xml;
    final gpx = GpxReader().fromString(normalized);
    final points = <RidePoint>[];

    for (final track in gpx.trks) {
      for (final segment in track.trksegs) {
        for (final point in segment.trkpts) {
          final lat = point.lat;
          final lon = point.lon;
          if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
            continue;
          }
          points.add(
            RidePoint(
              lat: lat,
              lon: lon,
              elevation: point.ele,
              time: point.time,
            ),
          );
        }
      }
    }

    if (points.length < 2) {
      for (final route in gpx.rtes) {
        for (final point in route.rtepts) {
          final lat = point.lat;
          final lon = point.lon;
          if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
            continue;
          }
          points.add(
            RidePoint(
              lat: lat,
              lon: lon,
              elevation: point.ele,
              time: point.time,
            ),
          );
        }
      }
    }

    if (points.length < 2) {
      throw FormatException(
        'GPX został odczytany, ale zawiera tylko ${points.length} poprawnych punktów.',
      );
    }

    final metadataName = gpx.metadata?.name?.trim();
    final trackName = gpx.trks.isNotEmpty ? gpx.trks.first.name?.trim() : null;
    final routeName = gpx.rtes.isNotEmpty ? gpx.rtes.first.name?.trim() : null;
    final name = [metadataName, trackName, routeName]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .firstOrNull ??
        fallbackName.replaceFirst(RegExp(r'\.gpx$', caseSensitive: false), '');

    return RideRoute(
      name: name,
      points: points,
      rawGpx: normalized,
      sourcePath: sourcePath,
    );
  }

  Future<List<RideRoute>> loadSaved() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/routes');
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.gpx'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));

    final routes = <RideRoute>[];
    for (final file in files) {
      try {
        final xml = await file.readAsString();
        routes.add(
          parseXml(
            xml,
            fallbackName: file.uri.pathSegments.last,
            sourcePath: file.path,
          ),
        );
      } catch (_) {}
    }
    return routes;
  }

  Future<void> delete(RideRoute route) async {
    final path = route.sourcePath;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
