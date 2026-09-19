import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ride_record.dart';

class RideStorageService {
  Future<Directory> _ridesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/recorded_rides');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> save(RecordedRide ride) async {
    final dir = await _ridesDirectory();
    final file = File('${dir.path}/${ride.id}.json');
    await file.writeAsString(jsonEncode(ride.toJson()), flush: true);
  }

  Future<List<RecordedRide>> loadAll() async {
    final dir = await _ridesDirectory();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final rides = <RecordedRide>[];
    for (final file in files) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        rides.add(
          RecordedRide.fromJson(
            Map<String, dynamic>.from(decoded as Map),
          ),
        );
      } catch (_) {}
    }
    rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rides;
  }

  Future<void> delete(String id) async {
    final dir = await _ridesDirectory();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) await file.delete();
  }
}
