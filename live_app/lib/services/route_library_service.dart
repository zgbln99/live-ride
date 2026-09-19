import 'dart:convert';

import '../core/geo.dart';
import '../models/ride_route.dart';
import 'gpx_service.dart';
import 'local_store.dart';

/// The Live Ride route library: imported GPX files plus a small index that
/// keeps the Routes tab instant even with large files stored.
class RouteLibraryService {
  RouteLibraryService(this._gpx);

  static const String _indexFile = 'index.json';

  final GpxService _gpx;
  final LocalStore _store = LocalStore('routes');

  List<RouteSummary>? _cache;

  Future<List<RouteSummary>> list({bool refresh = false}) async {
    if (!refresh && _cache != null) return List.unmodifiable(_cache!);
    final json = await _store.readJson(_indexFile);
    final entries = (json?['routes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) {
          try {
            return RouteSummary.fromJson(Map<String, dynamic>.from(item));
          } catch (_) {
            return null;
          }
        })
        .whereType<RouteSummary>()
        .toList();
    entries.sort((a, b) {
      final left = a.lastUsedAt ?? a.createdAt;
      final right = b.lastUsedAt ?? b.createdAt;
      return right.compareTo(left);
    });
    _cache = entries;
    return List.unmodifiable(entries);
  }

  Future<void> _persist(List<RouteSummary> routes) async {
    _cache = routes;
    await _store.writeJson(_indexFile, {
      'version': 1,
      'routes': [for (final route in routes) route.toJson()],
    });
  }

  /// Imports the file the rider picks. Returns null when they cancel.
  Future<RouteSummary?> importFromPicker() async {
    final picked = await _gpx.pickAndParse();
    if (picked == null) return null;
    return _importParsed(picked.parsed, picked.bytes, picked.fileName);
  }

  Future<RouteSummary> _importParsed(
    ParsedGpx parsed,
    List<int> bytes,
    String originalName,
  ) async {
    final id = newLocalId('route');
    final fileName = '$id.gpx';
    await _store.writeBytes(fileName, bytes);

    final route = RideRoute(
      id: id,
      name: parsed.name.isEmpty ? originalName : parsed.name,
      points: parsed.points,
      fileName: fileName,
    );
    final summary = route.toSummary();
    final routes = [summary, ...await list()];
    await _persist(routes);
    return summary;
  }

  /// Saves a route built inside the app (for example a recorded ride reused as
  /// a route) without going through the file picker.
  Future<RouteSummary> saveRoute({
    required String name,
    required List<GeoPoint> points,
    bool imported = false,
  }) async {
    final id = newLocalId('route');
    final fileName = '$id.gpx';
    final route = RideRoute(
      id: id,
      name: name,
      points: points,
      fileName: fileName,
      imported: imported,
    );
    await _store.writeString(fileName, _encodeRoute(route));
    final routes = [route.toSummary(), ...await list()];
    await _persist(routes);
    return route.toSummary();
  }

  /// Loads the full geometry for a library entry.
  Future<RideRoute> load(RouteSummary summary) async {
    final handle = await _store.file(summary.fileName);
    if (!await handle.exists()) {
      throw GpxException(
        'The GPX file for "${summary.name}" is missing from local storage. '
        'Import it again.',
        detail: summary.fileName,
      );
    }
    final bytes = await handle.readAsBytes();
    final parsed = _gpx.parse(
      _gpx.decodeXml(bytes),
      fallbackName: summary.name,
    );
    return RideRoute(
      id: summary.id,
      name: summary.name,
      points: parsed.points,
      fileName: summary.fileName,
      imported: summary.imported,
      createdAt: summary.createdAt,
    );
  }

  Future<String> rawGpx(RouteSummary summary) async {
    final handle = await _store.file(summary.fileName);
    return handle.readAsString();
  }

  Future<String> filePath(RouteSummary summary) async =>
      (await _store.file(summary.fileName)).path;

  Future<void> rename(RouteSummary summary, String name) async {
    final routes = [
      for (final route in await list())
        route.id == summary.id ? route.copyWith(name: name.trim()) : route,
    ];
    await _persist(routes);
  }

  Future<void> markUsed(RouteSummary summary) async {
    final routes = [
      for (final route in await list())
        route.id == summary.id
            ? route.copyWith(lastUsedAt: DateTime.now())
            : route,
    ];
    routes.sort((a, b) {
      final left = a.lastUsedAt ?? a.createdAt;
      final right = b.lastUsedAt ?? b.createdAt;
      return right.compareTo(left);
    });
    await _persist(routes);
  }

  Future<void> delete(RouteSummary summary) async {
    await _store.deleteFile(summary.fileName);
    final routes = [
      for (final route in await list())
        if (route.id != summary.id) route,
    ];
    await _persist(routes);
  }

  String _encodeRoute(RideRoute route) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Live Ride" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(route.name)}</name>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(route.name)}</name>')
      ..writeln('    <trkseg>');
    for (final point in route.points) {
      buffer.write(
        '      <trkpt lat="${point.lat.toStringAsFixed(7)}" '
        'lon="${point.lon.toStringAsFixed(7)}">',
      );
      if (point.elevation != null) {
        buffer.write('<ele>${point.elevation!.toStringAsFixed(1)}</ele>');
      }
      buffer.writeln('</trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  String _escape(String value) => const HtmlEscape().convert(value);
}
