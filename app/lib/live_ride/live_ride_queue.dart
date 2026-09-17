import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wanderer/live_ride/live_ride_api.dart';
import 'package:wanderer/live_ride/live_ride_models.dart';

/// Tiny disk-backed queue for telemetry that survives app restarts and mobile
/// data gaps. One JSON object per line makes partial recovery straightforward
/// and avoids adding another generated ObjectBox entity to the first patch.
///
/// All file mutation is serialized. Without this lock an enqueue that lands
/// while flush() is awaiting the network could be overwritten by flush()'s
/// later rewrite of an older file snapshot, losing a GPS point.
class LiveRideTelemetryQueue {
  LiveRideTelemetryQueue({required this.api, required this.sessionId});

  final LiveRideApi api;
  final String sessionId;
  File? _file;
  bool _flushing = false;
  Future<void> _lockTail = Future<void>.value();

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final previous = _lockTail;
    final release = Completer<void>();
    _lockTail = release.future;
    try {
      // A prior operation failing must not poison the mutex forever.
      try {
        await previous;
      } catch (_) {}
      return await action();
    } finally {
      if (!release.isCompleted) release.complete();
    }
  }

  Future<File> _queueFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    final liveDir = Directory('${dir.path}/live_ride');
    await liveDir.create(recursive: true);
    _file = File('${liveDir.path}/$sessionId.ndjson');
    return _file!;
  }

  Future<void> enqueue(LiveRideTelemetryPoint point) => _withLock(() async {
    final file = await _queueFile();
    await file.writeAsString(
      '${jsonEncode(point.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  });

  Future<int> pendingCount() => _withLock(() async {
    final file = await _queueFile();
    if (!await file.exists()) return 0;
    final lines = await file.readAsLines();
    return lines.where((line) => line.trim().isNotEmpty).length;
  });

  /// Sends oldest samples first in server-sized batches. If connectivity dies
  /// mid-flush, only successfully acknowledged lines are removed.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _withLock(() async {
        final file = await _queueFile();
        if (!await file.exists()) return;

        while (true) {
          final lines = (await file.readAsLines())
              .where((line) => line.trim().isNotEmpty)
              .toList();
          if (lines.isEmpty) {
            await file.writeAsString('');
            return;
          }

          final take = lines.length > 100 ? 100 : lines.length;
          final batchLines = lines.take(take).toList();
          final points = batchLines
              .map(
                (line) => LiveRideTelemetryPoint.fromJson(
                  jsonDecode(line) as Map<String, dynamic>,
                ),
              )
              .toList();

          try {
            await api.sendTelemetry(sessionId, points);
          } catch (_) {
            // The queue is authoritative. A future GPS tick/online transition
            // will retry; no data is lost and navigation itself is untouched.
            return;
          }

          final remaining = lines.skip(take).join('\n');
          await file.writeAsString(
            remaining.isEmpty ? '' : '$remaining\n',
            flush: true,
          );
        }
      });
    } finally {
      _flushing = false;
    }
  }

  Future<void> clear() => _withLock(() async {
    final file = await _queueFile();
    if (await file.exists()) await file.delete();
  });
}
