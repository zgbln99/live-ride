import 'dart:convert';
import 'dart:io';

import '../models/ride_record.dart';
import 'gpx_service.dart';
import 'local_store.dart';

/// Local ride history. One JSON file per ride keeps writes cheap and means a
/// single corrupt ride can never take the whole history down with it.
class RideStorageService {
  RideStorageService(this._gpx);

  final GpxService _gpx;
  final LocalStore _store = LocalStore('rides');

  List<RecordedRide>? _cache;

  Future<List<RecordedRide>> list({bool refresh = false}) async {
    if (!refresh && _cache != null) return List.unmodifiable(_cache!);
    final dir = await _store.directory();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final rides = <RecordedRide>[];
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          rides.add(RecordedRide.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Skip unreadable files instead of failing the whole history.
      }
    }
    rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _cache = rides;
    return List.unmodifiable(rides);
  }

  Future<void> save(RecordedRide ride) async {
    await _store.writeJson('${ride.id}.json', ride.toJson());
    final rides = [
      for (final existing in await list())
        if (existing.id != ride.id) existing,
      ride,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _cache = rides;
  }

  Future<void> delete(String id) async {
    await _store.deleteFile('$id.json');
    _cache = [
      for (final ride in await list())
        if (ride.id != id) ride,
    ];
  }

  Future<RecordedRide> rename(RecordedRide ride, String name) async {
    final renamed = ride.copyWith(name: name.trim());
    await save(renamed);
    return renamed;
  }

  /// Writes the ride out as GPX and returns the file, ready to be shared.
  Future<File> exportGpx(RecordedRide ride) async {
    final safeName = ride.name
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
    final directory = await _store.directory();
    final export = File(
      '${directory.path}/${safeName.isEmpty ? 'live-ride' : safeName}.gpx',
    );
    await export.writeAsString(_gpx.encodeRide(ride), flush: true);
    return export;
  }
}
