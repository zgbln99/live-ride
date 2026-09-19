import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/geo.dart';
import '../data/route_dao.dart';
import '../i18n/strings.dart';
import '../models/ride_route.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';
import 'gpx_service.dart';
import 'local_store.dart';

/// Biblioteka tras.
///
/// Geometria leży w SQLite, a pliki GPX generujemy na żądanie — dzięki temu
/// trasa zbudowana w kreatorze i trasa zaimportowana zachowują się tak samo.
class RouteLibraryService {
  RouteLibraryService(this._gpx, this._dao);

  final GpxService _gpx;
  final RouteDao _dao;
  final LocalStore _store = LocalStore('routes');

  List<RouteSummary>? _cache;

  Future<List<RouteSummary>> list({bool refresh = false, String? query}) async {
    if (query != null && query.trim().isNotEmpty) {
      return _dao.listSummaries(query: query);
    }
    if (!refresh && _cache != null) return List.unmodifiable(_cache!);
    final routes = await _dao.listSummaries();
    _cache = routes;
    return List.unmodifiable(routes);
  }

  Future<RideRoute> load(RouteSummary summary) async {
    final route = await _dao.load(summary.id);
    if (route == null) {
      throw GpxException(S.gpxMissing(summary.name));
    }
    return route;
  }

  Future<RideRoute?> loadById(String id) => _dao.load(id);

  Future<RouteSummary?> findSummary(String id) => _dao.findSummary(id);

  Future<void> save(RideRoute route) async {
    await _dao.save(route);
    _cache = null;
  }

  /// Importuje plik wybrany przez użytkownika. Null, gdy anulował.
  Future<RouteSummary?> importFromPicker() async {
    final picked = await _gpx.pickAndParse();
    if (picked == null) return null;

    final route = RideRoute(
      id: newRouteId(),
      name: picked.parsed.name.isEmpty ? picked.fileName : picked.parsed.name,
      points: picked.parsed.points,
      source: RouteSource.imported,
      waypoints: _endpointsOf(picked.parsed.points),
    );
    await save(route);
    return route.toSummary();
  }

  /// Zapisuje trasę zbudowaną w aplikacji.
  Future<RouteSummary> saveRoute({
    required String name,
    required List<GeoPoint> points,
    String description = '',
    List<String> tags = const [],
    List<RouteWaypoint> waypoints = const [],
    RoutePreferences preferences = const RoutePreferences(),
    RouteSource source = RouteSource.builder,
    String? id,
  }) async {
    final route = RideRoute(
      id: id ?? newRouteId(),
      name: name,
      description: description,
      tags: tags,
      points: points,
      waypoints: waypoints.isEmpty ? _endpointsOf(points) : waypoints,
      preferences: preferences,
      source: source,
    );
    await save(route);
    return route.toSummary();
  }

  Future<void> rename(RouteSummary summary, String name) async {
    await _dao.rename(summary.id, name.trim());
    _cache = null;
  }

  Future<void> markUsed(RouteSummary summary) async {
    await _dao.markUsed(summary.id);
    _cache = null;
  }

  Future<void> setSharing({
    required String id,
    required RoutePrivacy privacy,
    String? shareToken,
  }) async {
    await _dao.setSharing(id: id, privacy: privacy, shareToken: shareToken);
    _cache = null;
  }

  Future<void> delete(RouteSummary summary) async {
    await _dao.delete(summary.id);
    _cache = null;
  }

  /// Plik GPX trasy, generowany na żądanie.
  Future<File> exportGpx(RouteSummary summary) async {
    final route = await load(summary);
    final directory = await _store.directory();
    final safe = summary.name
        .replaceAll(RegExp(r'[^A-Za-z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
    final file = File('${directory.path}/${safe.isEmpty ? 'trasa' : safe}.gpx');
    await file.writeAsString(encodeRoute(route), flush: true);
    return file;
  }

  /// GPX trasy jako tekst.
  String encodeRoute(RideRoute route) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Live Ride" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(route.name)}</name>');
    if (route.description.isNotEmpty) {
      buffer.writeln('    <desc>${_escape(route.description)}</desc>');
    }
    buffer.writeln('  </metadata>');

    for (final waypoint in route.waypoints) {
      buffer
        ..writeln(
          '  <wpt lat="${waypoint.lat.toStringAsFixed(7)}" '
          'lon="${waypoint.lon.toStringAsFixed(7)}">',
        )
        ..writeln(
          '    <name>${_escape(waypoint.name.isEmpty ? waypoint.kind.label : waypoint.name)}</name>',
        )
        ..writeln('  </wpt>');
    }

    buffer
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(route.name)}</name>')
      ..writeln('    <type>cycling</type>')
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

  /// Start i meta jako waypointy, gdy trasa przyszła bez nich.
  List<RouteWaypoint> _endpointsOf(List<GeoPoint> points) {
    if (points.length < 2) return const [];
    return [
      RouteWaypoint(point: points.first, kind: WaypointKind.start),
      RouteWaypoint(point: points.last, kind: WaypointKind.finish),
    ];
  }

  String _escape(String value) => const HtmlEscape().convert(value);

  // ------------------------------------------------------------- szkice

  Future<void> saveDraft(String id, Map<String, dynamic> payload) =>
      _dao.saveDraft(id, payload);

  Future<Map<String, dynamic>?> loadDraft(String id) => _dao.loadDraft(id);

  Future<void> deleteDraft(String id) => _dao.deleteDraft(id);

  // ------------------------------------------------------------- migracja

  /// Przenosi trasy ze starego magazynu plikowego do bazy.
  Future<int> migrateLegacyFiles() async {
    final directory = await _store.directory();
    final index = File('${directory.path}/index.json');
    if (!await index.exists()) return 0;

    List<dynamic> entries;
    try {
      final decoded = jsonDecode(await index.readAsString());
      entries = decoded is Map
          ? (decoded['routes'] as List? ?? const [])
          : const [];
    } catch (_) {
      return 0;
    }

    var migrated = 0;
    for (final entry in entries.whereType<Map>()) {
      final id = entry['id'] as String?;
      final fileName = entry['file_name'] as String?;
      if (id == null || fileName == null) continue;
      if (await _dao.findSummary(id) != null) continue;

      final file = File('${directory.path}/$fileName');
      if (!await file.exists()) continue;
      try {
        final parsed = _gpx.parse(
          _gpx.decodeXml(await file.readAsBytes()),
          fallbackName: entry['name'] as String? ?? 'Trasa',
        );
        final createdAt =
            DateTime.tryParse(entry['created_at'] as String? ?? '') ??
            DateTime.now();
        await _dao.save(
          RideRoute(
            id: id,
            name: entry['name'] as String? ?? parsed.name,
            points: parsed.points,
            waypoints: _endpointsOf(parsed.points),
            source: (entry['imported'] as bool? ?? true)
                ? RouteSource.imported
                : RouteSource.builder,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastUsedAt: DateTime.tryParse(
              entry['last_used_at'] as String? ?? '',
            ),
          ),
        );
        migrated++;
      } catch (_) {
        // Nieczytelny plik pomijamy, reszta biblioteki ma się przenieść.
      }
    }

    if (migrated > 0) {
      try {
        await index.rename('${directory.path}/index.json.kopia');
      } catch (_) {}
      _cache = null;
    }
    return migrated;
  }
}

/// Nowy identyfikator trasy.
String newRouteId() {
  final now = DateTime.now();
  final salt = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
  return 'route-${now.millisecondsSinceEpoch.toRadixString(36)}$salt';
}
