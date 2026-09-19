import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Small JSON-file persistence helper.
///
/// Live Ride stores little enough that a database would be overhead: the
/// profile is one document, the route library is an index plus GPX files and
/// each ride is its own file. Writes go to a temporary file first so a crash
/// mid-write cannot leave a half-written index behind.
class LocalStore {
  LocalStore(this.folder);

  /// Folder name below the application documents directory.
  final String folder;

  Directory? _directory;

  Future<Directory> directory() async {
    final cached = _directory;
    if (cached != null) return cached;
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/$folder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directory = dir;
    return dir;
  }

  Future<File> file(String name) async =>
      File('${(await directory()).path}/$name');

  Future<Map<String, dynamic>?> readJson(String name) async {
    final handle = await file(name);
    if (!await handle.exists()) return null;
    try {
      final decoded = jsonDecode(await handle.readAsString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A corrupt document behaves like a missing one; callers fall back to
      // defaults rather than crashing on launch.
    }
    return null;
  }

  Future<void> writeJson(String name, Map<String, dynamic> value) async {
    final handle = await file(name);
    final temporary = File('${handle.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(handle.path);
  }

  Future<void> writeString(String name, String value) async {
    final handle = await file(name);
    final temporary = File('${handle.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(handle.path);
  }

  Future<void> writeBytes(String name, List<int> bytes) async {
    final handle = await file(name);
    final temporary = File('${handle.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(handle.path);
  }

  Future<void> deleteFile(String name) async {
    final handle = await file(name);
    if (await handle.exists()) await handle.delete();
  }
}

/// Collision-free identifier for locally stored documents.
String newLocalId(String prefix) {
  final now = DateTime.now();
  final stamp = now.millisecondsSinceEpoch.toRadixString(36);
  final salt = now.microsecond.toRadixString(36).padLeft(4, '0');
  return '$prefix-$stamp$salt';
}
