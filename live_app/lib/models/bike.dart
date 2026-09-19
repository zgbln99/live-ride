/// Rodzaj roweru.
enum BikeKind {
  road('Szosowy'),
  gravel('Gravel'),
  mtb('MTB'),
  trekking('Trekkingowy'),
  city('Miejski'),
  ebike('Elektryczny');

  const BikeKind(this.label);

  final String label;

  static BikeKind parse(String? value) => BikeKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => BikeKind.road,
  );
}

/// Rower w garażu.
class Bike {
  const Bike({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.weightKg,
    this.wheelCircumferenceMm,
    this.photoPath,
    this.odometerMeters = 0,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final BikeKind kind;
  final DateTime createdAt;
  final double? weightKg;

  /// Obwód koła w milimetrach — potrzebny, gdy prędkość liczy czujnik BLE.
  final int? wheelCircumferenceMm;

  final String? photoPath;
  final double odometerMeters;
  final bool isDefault;

  double get odometerKilometers => odometerMeters / 1000;

  Bike copyWith({
    String? name,
    BikeKind? kind,
    double? weightKg,
    int? wheelCircumferenceMm,
    String? photoPath,
    double? odometerMeters,
    bool? isDefault,
  }) => Bike(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    createdAt: createdAt,
    weightKg: weightKg ?? this.weightKg,
    wheelCircumferenceMm: wheelCircumferenceMm ?? this.wheelCircumferenceMm,
    photoPath: photoPath ?? this.photoPath,
    odometerMeters: odometerMeters ?? this.odometerMeters,
    isDefault: isDefault ?? this.isDefault,
  );
}

/// Rodzaj komponentu objętego serwisem.
enum ComponentKind {
  chain('Łańcuch'),
  cassette('Kaseta'),
  brakePads('Klocki hamulcowe'),
  discs('Tarcze'),
  tyres('Opony'),
  sealant('Uszczelniacz tubeless'),
  suspension('Amortyzator'),
  bottomBracket('Suport'),
  cables('Linki i pancerze'),
  custom('Własny');

  const ComponentKind(this.label);

  final String label;

  static ComponentKind parse(String? value) => ComponentKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => ComponentKind.custom,
  );

  /// Domyślny przebieg serwisowy w kilometrach — punkt wyjścia, który
  /// użytkownik może zmienić.
  int? get defaultLimitKm => switch (this) {
    ComponentKind.chain => 3000,
    ComponentKind.cassette => 9000,
    ComponentKind.brakePads => 2000,
    ComponentKind.discs => 12000,
    ComponentKind.tyres => 5000,
    ComponentKind.sealant => null,
    ComponentKind.suspension => 8000,
    ComponentKind.bottomBracket => 15000,
    ComponentKind.cables => 6000,
    ComponentKind.custom => null,
  };

  /// Domyślny limit czasowy w dniach — np. uszczelniacz schnie niezależnie
  /// od przebiegu.
  int? get defaultLimitDays => switch (this) {
    ComponentKind.sealant => 120,
    _ => null,
  };
}

/// Komponent z przypisanym limitem serwisowym.
class BikeComponent {
  const BikeComponent({
    required this.id,
    required this.bikeId,
    required this.name,
    required this.kind,
    required this.installedAt,
    required this.odometerAtInstallMeters,
    this.limitMeters,
    this.limitDays,
  });

  final String id;
  final String bikeId;
  final String name;
  final ComponentKind kind;
  final DateTime installedAt;
  final double odometerAtInstallMeters;
  final double? limitMeters;
  final int? limitDays;

  /// Ile komponent przejechał, przy aktualnym stanie licznika roweru.
  double usedMeters(double bikeOdometerMeters) =>
      (bikeOdometerMeters - odometerAtInstallMeters).clamp(
        0,
        double.maxFinite,
      );

  int usedDays(DateTime now) => now.difference(installedAt).inDays;

  /// Zużycie w zakresie 0–1+, po tym z dwóch limitów, który jest bliżej.
  /// Null, gdy komponent nie ma ustawionego żadnego limitu.
  double? wear(double bikeOdometerMeters, DateTime now) {
    final byDistance = limitMeters == null || limitMeters! <= 0
        ? null
        : usedMeters(bikeOdometerMeters) / limitMeters!;
    final byTime = limitDays == null || limitDays! <= 0
        ? null
        : usedDays(now) / limitDays!;
    if (byDistance == null) return byTime;
    if (byTime == null) return byDistance;
    return byDistance > byTime ? byDistance : byTime;
  }

  bool isDue(double bikeOdometerMeters, DateTime now) =>
      (wear(bikeOdometerMeters, now) ?? 0) >= 1.0;

  bool isSoon(double bikeOdometerMeters, DateTime now) {
    final value = wear(bikeOdometerMeters, now);
    return value != null && value >= 0.85 && value < 1.0;
  }
}
