import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';

import '../core/api_client.dart';
import '../core/geo.dart';
import '../data/settings_dao.dart';

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
/// Ile miejsca zajmuje pobrana mapa i kiedy ją pobrano.
///
/// MapLibre nie trzyma tych danych w [OfflineRegion], a zawodnik ma prawo
/// wiedzieć, ile zjadło mu pamięć telefonu. Rozmiar bierzemy z ostatniej
/// porcji postępu pobierania — to liczba bajtów, które faktycznie przyszły,
/// a nie oszacowanie.
class OfflineMapStats {
  const OfflineMapStats({
    required this.bytes,
    required this.downloadedAt,
    required this.routeName,
  });

  final int bytes;
  final DateTime downloadedAt;
  final String routeName;

  Map<String, dynamic> toJson() => {
    'bytes': bytes,
    'downloaded_at': downloadedAt.toIso8601String(),
    'route_name': routeName,
  };

  static OfflineMapStats? fromJson(Object? value) {
    if (value is! Map) return null;
    final bytes = value['bytes'];
    final downloadedAt = DateTime.tryParse(
      value['downloaded_at'] as String? ?? '',
    );
    if (bytes is! int || downloadedAt == null) return null;
    return OfflineMapStats(
      bytes: bytes,
      downloadedAt: downloadedAt,
      routeName: value['route_name'] as String? ?? '',
    );
  }
}

class OfflineMapService extends ChangeNotifier {
  OfflineMapService({OfflineManager? manager, SettingsDao? settings})
    : _injected = manager,
      _settings = settings;

  /// Klucz, pod którym trzymamy rozmiary i daty pobrań.
  static const String statsKey = 'offline_map_stats';

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
  final SettingsDao? _settings;
  OfflineManager? _manager;
  Map<String, OfflineMapStats> _stats = const {};

  List<OfflineRegion> _regions = const [];
  OfflineDownload? _current;
  StreamSubscription<DownloadProgress>? _subscription;
  String? _lastError;

  bool get isSupported => _injected != null || OfflineManager.isSupported;
  List<OfflineRegion> get regions => List.unmodifiable(_regions);
  OfflineDownload? get current => _current;
  String? get lastError => _lastError;
  bool get isDownloading => _current != null && !_current!.finished;

  /// Rozmiar i data pobrania mapy dla trasy, albo null, gdy ich nie znamy
  /// (np. mapa pobrana starszą wersją aplikacji).
  OfflineMapStats? statsFor(String routeId) => _stats[routeId];

  /// Łączny rozmiar map, o których coś wiemy.
  int get totalBytes =>
      _stats.values.fold(0, (sum, stats) => sum + stats.bytes);

  /// Wczytuje zapamiętane rozmiary i daty pobrań.
  Future<void> restoreStats() async {
    final stored = await _settings?.readJson(statsKey);
    if (stored == null) return;
    final parsed = <String, OfflineMapStats>{};
    for (final entry in stored.entries) {
      final stats = OfflineMapStats.fromJson(entry.value);
      if (stats != null) parsed[entry.key] = stats;
    }
    _stats = parsed;
    notifyListeners();
  }

  Future<void> _writeStats() async {
    await _settings?.writeJson(statsKey, {
      for (final entry in _stats.entries) entry.key: entry.value.toJson(),
    });
  }

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
    var downloadedBytes = 0;
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
            downloadedBytes = progress.loadedBytes;
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
    if (downloadedBytes > 0) {
      _stats = {
        ..._stats,
        routeId: OfflineMapStats(
          bytes: downloadedBytes,
          downloadedAt: DateTime.now(),
          routeName: routeName,
        ),
      };
      await _writeStats();
    }
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
    final routeId = _routeIdFor(regionId);
    try {
      await manager.deleteRegion(regionId: regionId);
    } on PlatformException catch (e) {
      _lastError = e.message;
    }
    if (routeId != null && _stats.containsKey(routeId)) {
      final next = Map<String, OfflineMapStats>.from(_stats)..remove(routeId);
      _stats = next;
      await _writeStats();
    }
    await refresh();
  }

  String? _routeIdFor(int regionId) {
    for (final region in _regions) {
      if (region.id != regionId) continue;
      final routeId = region.metadata['route_id'];
      return routeId is String ? routeId : null;
    }
    return null;
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
