import '../core/geo.dart';
import '../data/database.dart';
import 'route/route_analysis.dart';
import 'route/route_preferences.dart';
import 'route/route_waypoint.dart';

export 'route/route_preferences.dart' show RoutePrivacy, RouteSource;

/// Kształt trasy, wyliczany z geometrii.
enum RouteShape {
  loop('Pętla'),
  outAndBack('Tam i z powrotem'),
  pointToPoint('Z punktu do punktu');

  const RouteShape(this.label);

  final String label;

  static RouteShape parse(String? value) => RouteShape.values.firstWhere(
    (shape) => shape.name == value,
    orElse: () => RouteShape.pointToPoint,
  );
}

/// Lekki rekord trasy trzymany na liście.
///
/// Karty rysują się z tego i tylko z tego — otwarcie zakładki Trasy nie może
/// wczytywać geometrii wszystkich tras.
class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.name,
    required this.distanceMeters,
    required this.ascentMeters,
    required this.pointCount,
    required this.createdAt,
    required this.updatedAt,
    required this.preview,
    this.description = '',
    this.tags = const [],
    this.descentMeters = 0,
    this.lastUsedAt,
    this.source = RouteSource.builder,
    this.privacy = RoutePrivacy.private,
    this.shareToken,
    this.shape = RouteShape.pointToPoint,
    this.preferences = const RoutePreferences(),
    this.syncStatus = SyncStatus.local,
  });

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final double distanceMeters;
  final double ascentMeters;
  final double descentMeters;
  final int pointCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final RouteSource source;
  final RoutePrivacy privacy;
  final String? shareToken;
  final RouteShape shape;
  final RoutePreferences preferences;
  final SyncStatus syncStatus;

  /// Mocno uproszczona linia do miniatur na kartach.
  final List<GeoPoint> preview;

  bool get isImported => source == RouteSource.imported;
  bool get isShared => privacy != RoutePrivacy.private && shareToken != null;

  RouteSummary copyWith({
    String? name,
    String? description,
    List<String>? tags,
    DateTime? lastUsedAt,
    DateTime? updatedAt,
    RoutePrivacy? privacy,
    String? shareToken,
    SyncStatus? syncStatus,
  }) => RouteSummary(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    distanceMeters: distanceMeters,
    ascentMeters: ascentMeters,
    descentMeters: descentMeters,
    pointCount: pointCount,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    preview: preview,
    source: source,
    privacy: privacy ?? this.privacy,
    shareToken: shareToken ?? this.shareToken,
    shape: shape,
    preferences: preferences,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}

/// Pełna trasa: geometria, punkty użytkownika i preferencje trasowania.
class RideRoute {
  RideRoute({
    required this.id,
    required this.name,
    required this.points,
    this.description = '',
    this.tags = const [],
    this.waypoints = const [],
    this.preferences = const RoutePreferences(),
    this.privacy = RoutePrivacy.private,
    this.source = RouteSource.builder,
    this.shareToken,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastUsedAt,
    this.syncStatus = SyncStatus.local,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       cumulativeMeters = cumulativeDistances(points);

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final List<GeoPoint> points;
  final List<RouteWaypoint> waypoints;
  final RoutePreferences preferences;
  final RoutePrivacy privacy;
  final RouteSource source;
  final String? shareToken;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final SyncStatus syncStatus;
  final List<double> cumulativeMeters;

  RouteAnalysis? _analysis;

  /// Analiza trasy liczona raz i zapamiętana.
  ///
  /// Wykrywanie podjazdów na 100-kilometrowej trasie to zauważalna praca —
  /// nie ma prawa dziać się w `build()` przy każdej klatce.
  RouteAnalysis get analysis => _analysis ??= RouteAnalyzer.analyze(points);

  double get distanceMeters =>
      cumulativeMeters.isEmpty ? 0 : cumulativeMeters.last;

  double get ascentMeters => analysis.ascentMeters;
  double get descentMeters => analysis.descentMeters;
  List<Climb> get climbs => analysis.climbs;

  bool get isImported => source == RouteSource.imported;

  GeoPoint get start =>
      points.isEmpty ? const GeoPoint(lat: 52.23, lon: 21.01) : points.first;

  GeoPoint get finish => points.isEmpty ? start : points.last;

  GeoPoint get center =>
      GeoBounds.of(points)?.center ?? const GeoPoint(lat: 52.23, lon: 21.01);

  RouteShape get shape {
    if (points.length < 4) return RouteShape.pointToPoint;
    final closing = haversineMeters(points.first, points.last);
    if (closing < 250) return RouteShape.loop;
    final middle = points[points.length ~/ 2];
    if (haversineMeters(points.first, middle) > distanceMeters * 0.2 &&
        closing < distanceMeters * 0.08) {
      return RouteShape.outAndBack;
    }
    return RouteShape.pointToPoint;
  }

  Duration estimatedDuration() =>
      analysis.estimatedDuration(assumedSpeedKmh: preferences.assumedSpeedKmh);

  RideRoute copyWith({
    String? name,
    String? description,
    List<String>? tags,
    List<GeoPoint>? points,
    List<RouteWaypoint>? waypoints,
    RoutePreferences? preferences,
    RoutePrivacy? privacy,
    RouteSource? source,
    String? shareToken,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    SyncStatus? syncStatus,
  }) => RideRoute(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    points: points ?? this.points,
    waypoints: waypoints ?? this.waypoints,
    preferences: preferences ?? this.preferences,
    privacy: privacy ?? this.privacy,
    source: source ?? this.source,
    shareToken: shareToken ?? this.shareToken,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  RouteSummary toSummary() => RouteSummary(
    id: id,
    name: name,
    description: description,
    tags: tags,
    distanceMeters: distanceMeters,
    ascentMeters: ascentMeters,
    descentMeters: descentMeters,
    pointCount: points.length,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lastUsedAt: lastUsedAt,
    preview: samplePolyline(simplifyPolyline(points, 25), 120),
    source: source,
    privacy: privacy,
    shareToken: shareToken,
    shape: shape,
    preferences: preferences,
    syncStatus: syncStatus,
  );
}
