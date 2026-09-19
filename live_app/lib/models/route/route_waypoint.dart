import '../../core/geo.dart';

/// Rola punktu w trasie.
enum WaypointKind {
  start('Start'),
  via('Punkt pośredni'),
  finish('Meta');

  const WaypointKind(this.label);

  final String label;

  static WaypointKind parse(String? value) => WaypointKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => WaypointKind.via,
  );
}

/// Punkt, który użytkownik postawił na mapie.
///
/// To nie jest to samo co punkt geometrii trasy: waypointów jest kilka
/// i użytkownik nimi steruje, a geometrii są tysiące i pochodzi z routera.
class RouteWaypoint {
  const RouteWaypoint({
    required this.point,
    this.name = '',
    this.kind = WaypointKind.via,
  });

  final GeoPoint point;
  final String name;
  final WaypointKind kind;

  double get lat => point.lat;
  double get lon => point.lon;

  RouteWaypoint copyWith({GeoPoint? point, String? name, WaypointKind? kind}) =>
      RouteWaypoint(
        point: point ?? this.point,
        name: name ?? this.name,
        kind: kind ?? this.kind,
      );

  /// Etykieta na mapie: „S”, numer albo „M”.
  String label(int index, int total) => switch (kind) {
    WaypointKind.start => 'S',
    WaypointKind.finish => 'M',
    WaypointKind.via => '$index',
  };

  Map<String, dynamic> toJson() => {
    'lat': point.lat,
    'lon': point.lon,
    'name': name,
    'kind': kind.name,
  };

  factory RouteWaypoint.fromJson(Map<String, dynamic> json) => RouteWaypoint(
    point: GeoPoint(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    ),
    name: json['name'] as String? ?? '',
    kind: WaypointKind.parse(json['kind'] as String?),
  );
}
