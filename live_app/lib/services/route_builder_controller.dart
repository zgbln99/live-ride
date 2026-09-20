import 'dart:async';

import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../models/route/route_analysis.dart';
import '../models/route/route_preferences.dart';
import '../models/route/route_waypoint.dart';
import 'routing_service.dart';

/// Liczy trasę między waypointami.
/// Liczy trasę przez punkty.
///
/// [CancelToken] jest częścią kontraktu, bo przeciąganie punktu po mapie
/// unieważnia poprzednie zapytanie co kilkaset milisekund, a jedno zapytanie
/// to w środku cała seria prób u routera. Bez anulowania nieaktualna seria
/// biegnie do końca i zajmuje łącze, którego potrzebuje ta aktualna.
typedef RouteSolver =
    Future<RoutedPath> Function(
      List<RouteWaypoint>,
      RoutePreferences,
      CancelToken,
    );

/// Przykleja narysowany szkic do dróg.
typedef SketchSolver =
    Future<RoutedPath> Function(List<GeoPoint>, RoutePreferences);

/// Tryb pracy kreatora.
enum BuilderMode {
  waypoints('Punkty'),
  draw('Rysowanie');

  const BuilderMode(this.label);

  final String label;
}

/// Zdjęcie stanu kreatora do cofania i ponawiania.
@immutable
class _Snapshot {
  const _Snapshot(this.waypoints, this.preferences, this.drawnSketch);

  final List<RouteWaypoint> waypoints;
  final RoutePreferences preferences;
  final List<GeoPoint> drawnSketch;
}

/// Logika kreatora tras.
///
/// Trzyma punkty użytkownika, liczy z nich trasę i pilnuje historii zmian.
/// Nie wie nic o widgetach, więc każdą operację edycyjną da się sprawdzić
/// w teście bez mapy i bez sieci.
class RouteBuilderController extends ChangeNotifier {
  RouteBuilderController({
    required RouteSolver solver,
    required SketchSolver sketchSolver,
    this.onDraftChanged,
    this.recomputeDelay = const Duration(milliseconds: 350),
  }) : _solver = solver,
       _sketchSolver = sketchSolver;

  /// Ile kroków historii pamiętamy.
  static const int historyLimit = 50;

  final RouteSolver _solver;
  final SketchSolver _sketchSolver;

  /// Wywoływane po każdej zmianie, do autosave szkicu.
  final void Function(RouteBuilderController controller)? onDraftChanged;

  /// Odstęp między zmianą a przeliczeniem trasy: przeciąganie punktu nie
  /// może wysyłać żądania na każdą klatkę.
  final Duration recomputeDelay;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  List<RouteWaypoint> _waypoints = [];
  List<GeoPoint> _drawnSketch = [];
  RoutePreferences _preferences = const RoutePreferences();
  RoutedPath _path = RoutedPath.empty;
  RouteAnalysis _analysis = RouteAnalysis.empty;
  BuilderMode _mode = BuilderMode.waypoints;

  String name = '';
  String description = '';
  List<String> tags = [];
  RoutePrivacy privacy = RoutePrivacy.private;

  Timer? _recomputeTimer;

  /// Trwająca seria prób trasowania, do anulowania przy następnej zmianie.
  CancelToken? _inFlight;

  /// Czy kontroler został już zwolniony.
  ///
  /// Liczenie trasy jest asynchroniczne i potrafi wrócić po zamknięciu
  /// ekranu; wtedy nie ma komu oddać wyniku ani kogo powiadomić.
  bool _disposed = false;
  int _requestSerial = 0;
  bool _routing = false;
  String? _error;

  // ---------------------------------------------------------------- stan

  List<RouteWaypoint> get waypoints => List.unmodifiable(_waypoints);
  List<GeoPoint> get drawnSketch => List.unmodifiable(_drawnSketch);
  RoutePreferences get preferences => _preferences;
  RoutedPath get path => _path;
  RouteAnalysis get analysis => _analysis;
  BuilderMode get mode => _mode;
  bool get isRouting => _routing;
  String? get error => _error;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasRoute => _path.points.length >= 2;
  bool get isEmpty => _waypoints.isEmpty && _drawnSketch.isEmpty;

  /// Czy trasa jest prowizoryczna, bo router nie odpowiedział.
  bool get isStraightLine => hasRoute && !_path.mapMatched;

  List<GeoPoint> get points => _path.points;

  double get distanceMeters => _path.distanceMeters;

  Duration get estimatedDuration {
    if (_path.duration > Duration.zero) return _path.duration;
    return _analysis.estimatedDuration(
      assumedSpeedKmh: _preferences.assumedSpeedKmh,
    );
  }

  // ------------------------------------------------------------- edycja

  void setMode(BuilderMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Dodaje punkt na końcu trasy.
  void addWaypoint(GeoPoint point, {String name = ''}) {
    _pushHistory();
    final next = [..._waypoints];
    if (next.isEmpty) {
      next.add(
        RouteWaypoint(point: point, name: name, kind: WaypointKind.start),
      );
    } else {
      // Ostatni punkt zawsze jest metą, więc poprzedni staje się pośrednim.
      if (next.length >= 2) {
        next[next.length - 1] = next.last.copyWith(kind: WaypointKind.via);
      }
      next.add(
        RouteWaypoint(point: point, name: name, kind: WaypointKind.finish),
      );
    }
    _apply(next);
  }

  /// Wstawia punkt pośredni w konkretne miejsce — używane, gdy użytkownik
  /// złapie trasę pomiędzy istniejącymi punktami.
  void insertWaypoint(int index, GeoPoint point) {
    if (index < 0 || index > _waypoints.length) return;
    _pushHistory();
    final next = [..._waypoints]
      ..insert(index, RouteWaypoint(point: point, kind: WaypointKind.via));
    _apply(next);
  }

  void moveWaypoint(int index, GeoPoint point) {
    if (index < 0 || index >= _waypoints.length) return;
    _pushHistory();
    final next = [..._waypoints];
    next[index] = next[index].copyWith(point: point, name: '');
    _apply(next);
  }

  void removeWaypoint(int index) {
    if (index < 0 || index >= _waypoints.length) return;
    _pushHistory();
    final next = [..._waypoints]..removeAt(index);
    _apply(next);
  }

  void reorderWaypoint(int from, int to) {
    if (from < 0 || from >= _waypoints.length) return;
    if (to < 0 || to >= _waypoints.length || from == to) return;
    _pushHistory();
    final next = [..._waypoints];
    final moved = next.removeAt(from);
    next.insert(to, moved);
    _apply(next);
  }

  void renameWaypoint(int index, String name) {
    if (index < 0 || index >= _waypoints.length) return;
    _waypoints[index] = _waypoints[index].copyWith(name: name);
    notifyListeners();
    onDraftChanged?.call(this);
  }

  /// Odwraca kierunek trasy.
  void reverse() {
    if (_waypoints.length < 2) return;
    _pushHistory();
    _apply(_waypoints.reversed.toList());
  }

  /// Domyka trasę w pętlę, dorzucając powrót do startu.
  void closeLoop() {
    if (_waypoints.length < 2) return;
    final start = _waypoints.first;
    final finish = _waypoints.last;
    if (haversineMeters(start.point, finish.point) < 50) return;
    _pushHistory();
    _apply([
      ..._waypoints,
      RouteWaypoint(
        point: start.point,
        name: start.name,
        kind: WaypointKind.finish,
      ),
    ]);
  }

  /// Robi z trasy przejazd tam i z powrotem.
  void outAndBack() {
    if (_waypoints.length < 2) return;
    _pushHistory();
    final back = _waypoints.reversed.skip(1).toList();
    _apply([..._waypoints, ...back]);
  }

  void clear() {
    if (isEmpty) return;
    _pushHistory();
    _drawnSketch = [];
    _apply([]);
  }

  void setPreferences(RoutePreferences preferences) {
    if (preferences.toJson().toString() == _preferences.toJson().toString()) {
      return;
    }
    _pushHistory();
    _preferences = preferences;
    _scheduleRecompute();
    notifyListeners();
    onDraftChanged?.call(this);
  }

  // ------------------------------------------------------------ rysowanie

  /// Przyjmuje szkic narysowany palcem i zamienia go na trasę po drogach.
  Future<void> applySketch(List<GeoPoint> sketch) async {
    if (sketch.length < 2) return;
    _pushHistory();
    _drawnSketch = List.unmodifiable(sketch);
    _routing = true;
    _error = null;
    notifyListeners();

    final serial = ++_requestSerial;
    try {
      final snapped = await _sketchSolver(sketch, _preferences);
      if (serial != _requestSerial) return;

      // Ze szkicu zostają punkty kontrolne, żeby dało się go dalej edytować
      // jak zwykłą trasę.
      final anchors = samplePolyline(simplifyPolyline(snapped.points, 80), 12);
      _waypoints = [
        for (var i = 0; i < anchors.length; i++)
          RouteWaypoint(
            point: anchors[i],
            kind: i == 0
                ? WaypointKind.start
                : i == anchors.length - 1
                ? WaypointKind.finish
                : WaypointKind.via,
          ),
      ];
      _setPath(snapped);
    } finally {
      if (serial == _requestSerial) {
        _routing = false;
        notifyListeners();
        onDraftChanged?.call(this);
      }
    }
  }

  // -------------------------------------------------------- cofanie zmian

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_waypoints, _preferences, _drawnSketch));
    final snapshot = _undo.removeLast();
    _preferences = snapshot.preferences;
    _drawnSketch = snapshot.drawnSketch;
    _apply(snapshot.waypoints, recordHistory: false);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_waypoints, _preferences, _drawnSketch));
    final snapshot = _redo.removeLast();
    _preferences = snapshot.preferences;
    _drawnSketch = snapshot.drawnSketch;
    _apply(snapshot.waypoints, recordHistory: false);
  }

  // ------------------------------------------------------------ wczytanie

  /// Wczytuje istniejącą trasę do edycji.
  void loadExisting({
    required String name,
    required String description,
    required List<String> tags,
    required List<RouteWaypoint> waypoints,
    required List<GeoPoint> points,
    required RoutePreferences preferences,
    RoutePrivacy privacy = RoutePrivacy.private,
  }) {
    this.name = name;
    this.description = description;
    this.tags = List.of(tags);
    this.privacy = privacy;
    _preferences = preferences;
    _waypoints = List.of(waypoints);
    _undo.clear();
    _redo.clear();
    _setPath(
      RoutedPath(
        points: points,
        maneuvers: const [],
        distanceMeters: totalDistanceMeters(points),
        duration: Duration.zero,
      ),
    );
  }

  /// Stan kreatora do zapisania jako szkic.
  Map<String, dynamic> toDraft() => {
    'name': name,
    'description': description,
    'tags': tags,
    'privacy': privacy.name,
    'preferences': _preferences.toJson(),
    'waypoints': [for (final waypoint in _waypoints) waypoint.toJson()],
  };

  /// Odtwarza kreator ze szkicu i od razu przelicza trasę.
  void restoreDraft(Map<String, dynamic> draft) {
    name = draft['name'] as String? ?? '';
    description = draft['description'] as String? ?? '';
    tags = (draft['tags'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    privacy = RoutePrivacy.parse(draft['privacy'] as String?);
    final preferences = draft['preferences'];
    if (preferences is Map) {
      _preferences = RoutePreferences.fromJson(
        Map<String, dynamic>.from(preferences),
      );
    }
    final waypoints = draft['waypoints'];
    if (waypoints is List) {
      _waypoints = [
        for (final entry in waypoints.whereType<Map>())
          RouteWaypoint.fromJson(Map<String, dynamic>.from(entry)),
      ];
    }
    _undo.clear();
    _redo.clear();
    if (_waypoints.length >= 2) {
      _scheduleRecompute(immediate: true);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- prywatne

  void _apply(List<RouteWaypoint> next, {bool recordHistory = true}) {
    _waypoints = _normalise(next);
    if (_waypoints.length < 2) {
      _setPath(RoutedPath.empty);
      notifyListeners();
      onDraftChanged?.call(this);
      return;
    }
    _scheduleRecompute();
    notifyListeners();
    onDraftChanged?.call(this);
  }

  /// Pierwszy punkt jest startem, ostatni metą, reszta pośrednia.
  List<RouteWaypoint> _normalise(List<RouteWaypoint> waypoints) {
    if (waypoints.isEmpty) return const [];
    return [
      for (var i = 0; i < waypoints.length; i++)
        waypoints[i].copyWith(
          kind: i == 0
              ? WaypointKind.start
              : i == waypoints.length - 1
              ? WaypointKind.finish
              : WaypointKind.via,
        ),
    ];
  }

  void _pushHistory() {
    _undo.add(
      _Snapshot(List.of(_waypoints), _preferences, List.of(_drawnSketch)),
    );
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _scheduleRecompute({bool immediate = false}) {
    _recomputeTimer?.cancel();
    if (_waypoints.length < 2) return;
    if (immediate) {
      unawaited(_recompute());
      return;
    }
    _recomputeTimer = Timer(recomputeDelay, () => unawaited(_recompute()));
  }

  Future<void> _recompute() async {
    if (_disposed) return;
    final serial = ++_requestSerial;
    // Poprzednia seria prób przestała być potrzebna w chwili, w której
    // powstała ta. Mówimy jej o tym, zamiast czekać, aż sama się skończy.
    _inFlight?.cancel('nowe ułożenie punktów');
    final cancelToken = CancelToken();
    _inFlight = cancelToken;

    _routing = true;
    _error = null;
    notifyListeners();
    try {
      final path = await _solver(_waypoints, _preferences, cancelToken);
      if (_disposed || serial != _requestSerial) return;
      _setPath(path);
    } on RoutingException catch (e) {
      if (_disposed || serial != _requestSerial) return;
      _error = e.message;
    } catch (_) {
      if (_disposed || serial != _requestSerial) return;
      _error = 'Nie udało się policzyć trasy.';
    } finally {
      // Kreator zamknięty w trakcie liczenia: wynik wraca do nikogo.
      // Bez tej bramki `notifyListeners` leciał na zwolnionym obiekcie —
      // w debugu asercja, w wydaniu cichy wyjątek w tle.
      if (!_disposed && serial == _requestSerial) {
        _inFlight = null;
        _routing = false;
        notifyListeners();
      }
    }
  }

  void _setPath(RoutedPath path) {
    _path = path;
    // Analiza jest liczona raz na wynik trasowania, a nie w build().
    _analysis = path.points.length >= 2
        ? RouteAnalyzer.analyze(path.points)
        : RouteAnalysis.empty;
  }

  /// Podmienia geometrię na wersję z wysokością, bez ruszania waypointów.
  void attachElevation(List<GeoPoint> points) {
    if (points.length != _path.points.length) return;
    _setPath(
      RoutedPath(
        points: points,
        maneuvers: _path.maneuvers,
        distanceMeters: _path.distanceMeters,
        duration: _path.duration,
        mapMatched: _path.mapMatched,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _recomputeTimer?.cancel();
    // Zamknięty kreator nie ma komu oddać wyniku.
    _inFlight?.cancel('kreator zamknięty');
    _inFlight = null;
    super.dispose();
  }
}
