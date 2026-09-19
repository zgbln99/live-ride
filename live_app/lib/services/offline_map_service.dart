import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';

import '../core/api_client.dart';
import '../core/geo.dart';

/// Postęp pobierania jednego regionu.
class OfflineDownload {
  const OfflineDownload({
    required this.routeId,
    required this.routeName,
    required this.progress,
    this.finished = false,
    this.error,
  });

  final String routeId;
  final String routeName;

  /// Zakres 0–1.
  final double progress;

  final bool finished;
  final String? error;
}

/// Mapy offline wokół tras.
///
/// Silnik mapy sam trzyma kafelki w swojej bazie; ten serwis tylko mówi mu,
/// co pobrać, i pilnuje, żeby dało się to odwołać i usunąć. Nic tu nie
/// udaje — gdy platforma nie wspiera trybu offline (web), ekran to mówi.
class OfflineMapService extends ChangeNotifier {
  OfflineMapService({OfflineManager? manager}) : _injected = manager;

  /// Zoomy, które naprawdę przydają się w jeździe.
  ///
  /// Poniżej 10 to widok kraju, którego i tak nie ma sensu trzymać, a powyżej
  /// 15 liczba kafelków rośnie czterokrotnie na poziom i pobranie trasy
  /// przestaje mieścić się w limicie.
  static const double minZoom = 10;
  static const double maxZoom = 15;

  /// Ile kilometrów wokół trasy pobieramy.
  static const double paddingMeters = 1500;

  final OfflineManager? _injected;
  OfflineManager? _manager;

  List<OfflineRegion> _regions = const [];
  OfflineDownload? _current;
  StreamSubscription<DownloadProgress>? _subscription;
  String? _lastError;

  bool get isSupported => _injected != null || OfflineManager.isSupported;
  List<OfflineRegion> get regions => List.unmodifiable(_regions);
  OfflineDownload? get current => _current;
  String? get lastError => _lastError;
  bool get isDownloading => _current != null && !_current!.finished;

  /// Czy trasa ma pobrany region.
  bool hasRegionFor(String routeId) =>
      _regions.any((region) => region.metadata['route_id'] == routeId);

  OfflineRegion? regionFor(String routeId) {
    for (final region in _regions) {
      if (region.metadata['route_id'] == routeId) return region;
    }
    return null;
  }

  Future<OfflineManager?> _ensureManager() async {
    if (_injected != null) return _injected;
    if (_manager != null) return _manager;
    if (!OfflineManager.isSupported) return null;
    try {
      _manager = await OfflineManager.createInstance();
      return _manager;
    } on PlatformException catch (e) {
      _lastError = e.message;
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> refresh() async {
    final manager = await _ensureManager();
    if (manager == null) return;
    try {
      _regions = await manager.listOfflineRegions();
      _lastError = null;
    } on PlatformException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Pobiera mapę wokół trasy.
  Future<void> downloadForRoute({
    required String routeId,
    required String routeName,
    required List<GeoPoint> points,
    String? styleUrl,
  }) async {
    if (isDownloading) return;
    final manager = await _ensureManager();
    if (manager == null) {
      _lastError = 'offline_unsupported';
      notifyListeners();
      return;
    }
    final bounds = paddedBounds(points);
    if (bounds == null) return;

    _current = OfflineDownload(
      routeId: routeId,
      routeName: routeName,
      progress: 0,
    );
    _lastError = null;
    notifyListeners();

    await _subscription?.cancel();
    final completer = Completer<void>();
    _subscription = manager
        .downloadRegion(
          mapStyleUrl: styleUrl ?? ApiClient.mapStyleUrl,
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
          pixelDensity: 2,
          metadata: {'route_id': routeId, 'route_name': routeName},
        )
        .listen(
          (progress) {
            // Na początku pobierania liczba kafelków jest szacunkowa,
            // więc procent potrafi skakać — dopóki nie jest znana na
            // pewno, nie pokazujemy go jako skończonego.
            final total = progress.totalTiles;
            _current = OfflineDownload(
              routeId: routeId,
              routeName: routeName,
              progress: total <= 0
                  ? 0
                  : (progress.loadedTiles / total).clamp(0.0, 1.0),
              finished: progress.downloadCompleted,
            );
            notifyListeners();
          },
          onError: (Object error) {
            _current = OfflineDownload(
              routeId: routeId,
              routeName: routeName,
              progress: 0,
              finished: true,
              error: error.toString(),
            );
            _lastError = error.toString();
            notifyListeners();
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            _current = _current == null
                ? null
                : OfflineDownload(
                    routeId: routeId,
                    routeName: routeName,
                    progress: 1,
                    finished: true,
                  );
            notifyListeners();
            if (!completer.isCompleted) completer.complete();
          },
        );

    await completer.future;
    await refresh();
  }

  Future<void> cancelDownload() async {
    await _subscription?.cancel();
    _subscription = null;
    _current = null;
    notifyListeners();
  }

  Future<void> deleteRegion(int regionId) async {
    final manager = await _ensureManager();
    if (manager == null) return;
    try {
      await manager.deleteRegion(regionId: regionId);
    } on PlatformException catch (e) {
      _lastError = e.message;
    }
    await refresh();
  }

  /// Prostokąt wokół trasy z zapasem, żeby zjazd z trasy nie wyszedł poza
  /// pobrany obszar.
  @visibleForTesting
  static LngLatBounds? paddedBounds(List<GeoPoint> points) {
    final bounds = GeoBounds.of(points);
    if (bounds == null) return null;
    const metersPerDegreeLat = 110540.0;
    final latPadding = paddingMeters / metersPerDegreeLat;
    final lonPadding = paddingMeters / 111320.0;
    return LngLatBounds(
      longitudeWest: bounds.minLon - lonPadding,
      longitudeEast: bounds.maxLon + lonPadding,
      latitudeSouth: bounds.minLat - latPadding,
      latitudeNorth: bounds.maxLat + latPadding,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _manager?.dispose();
    super.dispose();
  }
}
