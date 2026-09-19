import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../data/segment_dao.dart';
import '../models/segment.dart';
import 'local_store.dart';
import 'segment_matcher.dart';

/// Segmenty zawodnika: lista, rekordy i wykrywanie w czasie jazdy.
class SegmentService extends ChangeNotifier {
  SegmentService(this._dao, {SegmentMatcher? matcher})
    : matcher = matcher ?? SegmentMatcher();

  final SegmentDao _dao;

  /// Dopasowywanie w czasie jazdy. Rejestrator karmi je pozycjami.
  final SegmentMatcher matcher;

  List<Segment> _segments = const [];
  Map<String, Duration> _bests = const {};
  bool _loaded = false;

  List<Segment> get segments => List.unmodifiable(_segments);
  Map<String, Duration> get personalBests => Map.unmodifiable(_bests);
  bool get isLoaded => _loaded;

  Duration? bestFor(String segmentId) => _bests[segmentId];

  Future<void> load() async {
    _segments = await _dao.listSegments();
    _bests = await _dao.personalBests();
    _loaded = true;
    matcher.load(_segments, bests: _bests);
    notifyListeners();
  }

  Future<List<SegmentAttempt>> attempts(String segmentId) =>
      _dao.attempts(segmentId);

  /// Tworzy segment z fragmentu trasy albo przejazdu.
  Future<Segment> create({
    required String name,
    required List<GeoPoint> points,
    String? sourceRouteId,
  }) async {
    final segment = Segment(
      id: newLocalId('segment'),
      name: name,
      points: List.unmodifiable(points),
      createdAt: DateTime.now(),
      sourceRouteId: sourceRouteId,
    );
    await _dao.saveSegment(segment);
    await load();
    return segment;
  }

  Future<void> rename(String id, String name) async {
    await _dao.rename(id, name);
    await load();
  }

  Future<void> delete(String id) async {
    await _dao.deleteSegment(id);
    await load();
  }

  /// Zapisuje wszystko, co matcher zebrał w trakcie przejazdu.
  Future<void> storeRuns(List<SegmentRun> runs, {String? rideId}) async {
    if (runs.isEmpty) return;
    for (final run in runs) {
      await _dao.saveAttempt(
        SegmentAttempt(
          id: newLocalId('attempt'),
          segmentId: run.segment.id,
          rideId: rideId,
          startedAt: run.startedAt,
          duration: run.duration,
          averageSpeedKmh: run.averageSpeedKmh,
        ),
      );
    }
    await load();
  }
}
