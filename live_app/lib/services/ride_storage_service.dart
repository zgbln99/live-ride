import 'dart:convert';
import 'dart:io';

import '../data/database.dart';
import '../data/ride_dao.dart';
import '../models/ride_record.dart';
import 'gpx_service.dart';
import 'local_store.dart';

/// Historia przejazdów.
///
/// Dane leżą w SQLite; ta klasa dokłada do tego cache nagłówków dla UI,
/// eksport do GPX i jednorazową migrację ze starych plików JSON.
class RideStorageService {
  RideStorageService(this._gpx, this._dao);

  final GpxService _gpx;
  final RideDao _dao;
  final LocalStore _store = LocalStore('rides');

  List<RecordedRide>? _cache;

  /// Zapytania statystyczne idą wprost do bazy, bo SQLite policzy je szybciej
  /// niż jakakolwiek pętla po wczytanych przejazdach.
  RideDao get dao => _dao;

  /// Nagłówki przejazdów, bez punktów.
  Future<List<RecordedRide>> list({bool refresh = false}) async {
    if (!refresh && _cache != null) return List.unmodifiable(_cache!);
    final rides = await _dao.listSummaries();
    _cache = rides;
    return List.unmodifiable(rides);
  }

  /// Pełny przejazd razem ze śladem.
  Future<RecordedRide?> load(String id) => _dao.findById(id);

  /// Rzadki ślad do miniatury na karcie.
  Future<List<RecordedRidePoint>> preview(String id) =>
      _dao.loadPreview(id, maxPoints: 120);

  Future<void> save(RecordedRide ride) async {
    await _dao.save(ride);
    _cache = null;
  }

  Future<void> delete(String id) async {
    await _dao.delete(id);
    _cache = null;
  }

  Future<RecordedRide> rename(RecordedRide ride, String name) async {
    await _dao.rename(ride.id, name.trim());
    _cache = null;
    return ride.copyWith(name: name.trim());
  }

  Future<RideTotals> totals({DateTime? from, DateTime? to}) =>
      _dao.totals(from: from, to: to);

  Future<void> markSynced(String id) =>
      _dao.updateSyncStatus(id, SyncStatus.synced);

  Future<void> markHealthExported(String id) => _dao.markHealthExported(id);

  Future<List<RecordedRide>> pendingSync() => _dao.pendingSync();

  /// Zapisuje przejazd jako GPX i zwraca plik gotowy do udostępnienia.
  Future<File> exportGpx(RecordedRide ride) async {
    final full = ride.points.isEmpty ? await load(ride.id) ?? ride : ride;
    final safeName = _fileName(ride.name);
    final directory = await _store.directory();
    final export = File('${directory.path}/$safeName.gpx');
    await export.writeAsString(_gpx.encodeRide(full), flush: true);
    return export;
  }

  /// Zapisuje przejazd jako TCX — format, który rozumie Garmin Connect
  /// i większość serwisów treningowych.
  Future<File> exportTcx(RecordedRide ride) async {
    final full = ride.points.isEmpty ? await load(ride.id) ?? ride : ride;
    final directory = await _store.directory();
    final export = File('${directory.path}/${_fileName(ride.name)}.tcx');
    await export.writeAsString(_gpx.encodeTcx(full), flush: true);
    return export;
  }

  String _fileName(String name) {
    final safe = name
        .replaceAll(RegExp(r'[^A-Za-z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
    return safe.isEmpty ? 'live-ride' : safe;
  }

  /// Przenosi przejazdy ze starego magazynu plikowego do bazy.
  ///
  /// Uruchamiane raz; stare pliki zostają na dysku jako kopia, bo utrata
  /// sezonu jazdy przy aktualizacji aplikacji jest nie do naprawienia.
  Future<int> migrateLegacyFiles() async {
    final directory = await _store.directory();
    if (!await directory.exists()) return 0;

    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.isEmpty) return 0;

    var migrated = 0;
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final ride = RecordedRide.fromJson(Map<String, dynamic>.from(decoded));
        if (await _dao.findById(ride.id, withPoints: false) != null) continue;
        await _dao.save(ride);
        migrated++;
      } catch (_) {
        // Uszkodzony plik nie może zatrzymać migracji reszty sezonu.
      }
    }

    if (migrated > 0) {
      final backup = Directory('${directory.path}/kopia-json');
      await backup.create(recursive: true);
      for (final file in files) {
        try {
          await file.rename('${backup.path}/${file.uri.pathSegments.last}');
        } catch (_) {}
      }
      _cache = null;
    }
    return migrated;
  }
}
