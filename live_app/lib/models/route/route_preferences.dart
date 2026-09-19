import '../../i18n/strings.dart';

/// Typ roweru, który decyduje o bazowym profilu routingu Valhalli.
enum BikeProfile {
  road('road', 'Szosa'),
  gravel('hybrid', 'Gravel'),
  mountain('mountain', 'MTB'),
  trekking('cross', 'Trekking'),
  city('city', 'Miejski');

  const BikeProfile(this.valhallaType, this.label);

  /// Wartość `bicycle_type` w Valhalli.
  final String valhallaType;
  final String label;

  static BikeProfile parse(String? value) => BikeProfile.values.firstWhere(
    (profile) => profile.name == value,
    orElse: () => BikeProfile.road,
  );
}

/// Charakter trasy: szybko czy spokojnie.
enum RouteMood {
  fast('Szybka', 0.0),
  balanced('Zrównoważona', 0.5),
  quiet('Spokojna', 1.0);

  const RouteMood(this.label, this.useRoadsBias);

  final String label;

  /// Mapuje się na `use_roads` Valhalli: 0 = boczne drogi, 1 = główne.
  final double useRoadsBias;

  static RouteMood parse(String? value) => RouteMood.values.firstWhere(
    (mood) => mood.name == value,
    orElse: () => RouteMood.balanced,
  );
}

/// Preferowana nawierzchnia.
enum SurfacePreference {
  paved('Asfalt', 0.9),
  mixed('Mieszana', 0.4),
  unpaved('Szuter', 0.05);

  const SurfacePreference(this.label, this.badSurfaceAvoidance);

  final String label;

  /// Mapuje się na `avoid_bad_surfaces` Valhalli: im bardziej asfalt, tym
  /// mocniej unikamy nawierzchni szutrowych.
  final double badSurfaceAvoidance;

  static SurfacePreference parse(String? value) =>
      SurfacePreference.values.firstWhere(
        (surface) => surface.name == value,
        orElse: () => SurfacePreference.mixed,
      );
}

/// Pełny zestaw preferencji trasowania.
///
/// Model jest rozszerzalny celowo: Valhalla dziś nie honoruje wszystkiego
/// (np. tuneli), więc pola, których backend nie obsłuży, są przekazywane
/// w [toValhallaCosting] tylko wtedy, gdy mają odpowiednik, a reszta i tak
/// jest zapisana przy trasie i widoczna dla użytkownika.
class RoutePreferences {
  const RoutePreferences({
    this.profile = BikeProfile.road,
    this.mood = RouteMood.balanced,
    this.surface = SurfacePreference.mixed,
    this.preferBikePaths = true,
    this.avoidBusyRoads = true,
    this.avoidFerries = false,
    this.avoidMotorways = true,
    this.avoidTunnels = false,
    this.avoidHills = false,
    this.returnToStart = false,
  });

  final BikeProfile profile;
  final RouteMood mood;
  final SurfacePreference surface;
  final bool preferBikePaths;
  final bool avoidBusyRoads;
  final bool avoidFerries;
  final bool avoidMotorways;

  /// Valhalla nie ma dedykowanego przełącznika na tunele; zapisujemy
  /// preferencję i pokazujemy ją przy trasie, zamiast udawać, że działa.
  final bool avoidTunnels;

  final bool avoidHills;
  final bool returnToStart;

  /// Średnia prędkość zakładana przy szacowaniu czasu, w km/h.
  double get assumedSpeedKmh => switch (profile) {
    BikeProfile.road => 24,
    BikeProfile.gravel => 20,
    BikeProfile.mountain => 16,
    BikeProfile.trekking => 18,
    BikeProfile.city => 16,
  };

  RoutePreferences copyWith({
    BikeProfile? profile,
    RouteMood? mood,
    SurfacePreference? surface,
    bool? preferBikePaths,
    bool? avoidBusyRoads,
    bool? avoidFerries,
    bool? avoidMotorways,
    bool? avoidTunnels,
    bool? avoidHills,
    bool? returnToStart,
  }) => RoutePreferences(
    profile: profile ?? this.profile,
    mood: mood ?? this.mood,
    surface: surface ?? this.surface,
    preferBikePaths: preferBikePaths ?? this.preferBikePaths,
    avoidBusyRoads: avoidBusyRoads ?? this.avoidBusyRoads,
    avoidFerries: avoidFerries ?? this.avoidFerries,
    avoidMotorways: avoidMotorways ?? this.avoidMotorways,
    avoidTunnels: avoidTunnels ?? this.avoidTunnels,
    avoidHills: avoidHills ?? this.avoidHills,
    returnToStart: returnToStart ?? this.returnToStart,
  );

  /// Opcje kosztowe dla Valhalli.
  ///
  /// Nazwy pól są z dokumentacji Valhalli `costing_options.bicycle`.
  Map<String, dynamic> toValhallaCosting() {
    // `use_roads` 0 = boczne i ciche, 1 = szybkie i ruchliwe.
    var useRoads = mood.useRoadsBias;
    if (avoidBusyRoads) useRoads = (useRoads - 0.2).clamp(0.0, 1.0);
    if (preferBikePaths) useRoads = (useRoads - 0.15).clamp(0.0, 1.0);

    return {
      'bicycle_type': profile.valhallaType,
      'use_roads': double.parse(useRoads.toStringAsFixed(2)),
      'use_hills': avoidHills ? 0.1 : 0.5,
      'avoid_bad_surfaces': surface.badSurfaceAvoidance,
      'use_ferry': avoidFerries ? 0.0 : 0.5,
      'use_living_streets': preferBikePaths ? 0.7 : 0.5,
      'shortest': false,
    };
  }

  Map<String, dynamic> toJson() => {
    'profile': profile.name,
    'mood': mood.name,
    'surface': surface.name,
    'prefer_bike_paths': preferBikePaths,
    'avoid_busy_roads': avoidBusyRoads,
    'avoid_ferries': avoidFerries,
    'avoid_motorways': avoidMotorways,
    'avoid_tunnels': avoidTunnels,
    'avoid_hills': avoidHills,
    'return_to_start': returnToStart,
  };

  factory RoutePreferences.fromJson(Map<String, dynamic> json) =>
      RoutePreferences(
        profile: BikeProfile.parse(json['profile'] as String?),
        mood: RouteMood.parse(json['mood'] as String?),
        surface: SurfacePreference.parse(json['surface'] as String?),
        preferBikePaths: json['prefer_bike_paths'] as bool? ?? true,
        avoidBusyRoads: json['avoid_busy_roads'] as bool? ?? true,
        avoidFerries: json['avoid_ferries'] as bool? ?? false,
        avoidMotorways: json['avoid_motorways'] as bool? ?? true,
        avoidTunnels: json['avoid_tunnels'] as bool? ?? false,
        avoidHills: json['avoid_hills'] as bool? ?? false,
        returnToStart: json['return_to_start'] as bool? ?? false,
      );

  /// Krótki opis do karty trasy.
  String get summary {
    final parts = <String>[profile.label, mood.label];
    if (preferBikePaths) parts.add('ścieżki rowerowe');
    if (surface == SurfacePreference.paved) parts.add('asfalt');
    if (surface == SurfacePreference.unpaved) parts.add('szuter');
    return parts.join(' · ');
  }
}

/// Widoczność trasy.
enum RoutePrivacy {
  private('Prywatna'),
  unlisted('Tylko z linkiem'),
  public('Publiczna');

  const RoutePrivacy(this.label);

  final String label;

  static RoutePrivacy parse(String? value) => RoutePrivacy.values.firstWhere(
    (privacy) => privacy.name == value,
    orElse: () => RoutePrivacy.private,
  );
}

/// Skąd wzięła się trasa.
enum RouteSource {
  builder('Kreator'),
  imported('Import GPX'),
  recorded('Z przejazdu'),
  copied('Skopiowana');

  const RouteSource(this.label);

  final String label;

  static RouteSource parse(String? value) => RouteSource.values.firstWhere(
    (source) => source.name == value,
    orElse: () => RouteSource.builder,
  );
}

/// Czy dane słowo „punkt” odmienić — używane przez teksty tras.
String routePointsLabel(int count) => S.fieldsCount(count);
