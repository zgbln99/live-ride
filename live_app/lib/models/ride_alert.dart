/// Rodzaje powiadomień w czasie jazdy.
enum AlertKind {
  drink('Picie', 'Napij się'),
  eat('Jedzenie', 'Zjedz coś'),
  distanceInterval('Co ile kilometrów', 'Kolejny odcinek'),
  timeInterval('Co ile minut', 'Kolejny kwadrans'),
  heartRateHigh('Wysokie tętno', 'Tętno wysoko'),
  powerHigh('Wysoka moc', 'Moc wysoko'),
  cadenceLow('Niska kadencja', 'Niska kadencja'),
  offRoute('Zjazd z trasy', 'Jesteś poza trasą'),
  climbAhead('Podjazd przed tobą', 'Podjazd'),
  sensorBattery('Bateria sensora', 'Słaba bateria sensora'),
  rain('Deszcz', 'Zanosi się na deszcz'),
  sunset('Zachód słońca', 'Zaraz zmrok');

  const AlertKind(this.label, this.headline);

  /// Nazwa w ustawieniach.
  final String label;

  /// Nagłówek pokazywany zawodnikowi.
  final String headline;

  static AlertKind? parse(String? value) {
    for (final kind in AlertKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

enum AlertSeverity { info, warning, critical }

/// Jedno powiadomienie gotowe do pokazania.
class RideAlert {
  const RideAlert({
    required this.kind,
    required this.message,
    required this.at,
    this.severity = AlertSeverity.info,
  });

  final AlertKind kind;
  final String message;
  final DateTime at;
  final AlertSeverity severity;

  String get headline => kind.headline;
}

/// Ustawienia jednego powiadomienia.
///
/// [everyMinutes], [everyKilometers] i [threshold] mają sens tylko dla części
/// rodzajów; reszta je ignoruje.
class AlertRule {
  const AlertRule({
    required this.kind,
    this.enabled = false,
    this.everyMinutes,
    this.everyKilometers,
    this.threshold,
  });

  final AlertKind kind;
  final bool enabled;
  final int? everyMinutes;
  final double? everyKilometers;
  final double? threshold;

  AlertRule copyWith({
    bool? enabled,
    Object? everyMinutes = _keep,
    Object? everyKilometers = _keep,
    Object? threshold = _keep,
  }) => AlertRule(
    kind: kind,
    enabled: enabled ?? this.enabled,
    everyMinutes: everyMinutes == _keep
        ? this.everyMinutes
        : everyMinutes as int?,
    everyKilometers: everyKilometers == _keep
        ? this.everyKilometers
        : everyKilometers as double?,
    threshold: threshold == _keep ? this.threshold : threshold as double?,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'enabled': enabled,
    'every_minutes': everyMinutes,
    'every_km': everyKilometers,
    'threshold': threshold,
  };

  static AlertRule? fromJson(Map<String, dynamic> json) {
    final kind = AlertKind.parse(json['kind'] as String?);
    if (kind == null) return null;
    return AlertRule(
      kind: kind,
      enabled: json['enabled'] as bool? ?? false,
      everyMinutes: (json['every_minutes'] as num?)?.toInt(),
      everyKilometers: (json['every_km'] as num?)?.toDouble(),
      threshold: (json['threshold'] as num?)?.toDouble(),
    );
  }
}

const Object _keep = Object();

/// Komplet ustawień powiadomień.
///
/// Domyślnie włączone są tylko te, które nie potrzebują żadnego sensora i
/// nikomu nie przeszkadzają: picie, jedzenie i zjazd z trasy.
class AlertSettings {
  const AlertSettings({this.rules = const {}});

  final Map<AlertKind, AlertRule> rules;

  static const AlertSettings defaults = AlertSettings(
    rules: {
      AlertKind.drink: AlertRule(
        kind: AlertKind.drink,
        enabled: true,
        everyMinutes: 20,
      ),
      AlertKind.eat: AlertRule(
        kind: AlertKind.eat,
        enabled: true,
        everyMinutes: 45,
      ),
      AlertKind.offRoute: AlertRule(kind: AlertKind.offRoute, enabled: true),
      AlertKind.climbAhead: AlertRule(
        kind: AlertKind.climbAhead,
        enabled: true,
      ),
      AlertKind.sensorBattery: AlertRule(
        kind: AlertKind.sensorBattery,
        enabled: true,
        threshold: 15,
      ),
    },
  );

  AlertRule ruleFor(AlertKind kind) =>
      rules[kind] ?? AlertRule(kind: kind, enabled: false);

  bool isEnabled(AlertKind kind) => ruleFor(kind).enabled;

  AlertSettings withRule(AlertRule rule) =>
      AlertSettings(rules: {...rules, rule.kind: rule});

  Map<String, dynamic> toJson() => {
    'rules': rules.values.map((rule) => rule.toJson()).toList(),
  };

  factory AlertSettings.fromJson(Map<String, dynamic> json) {
    final rules = <AlertKind, AlertRule>{};
    for (final entry in (json['rules'] as List<dynamic>? ?? const [])) {
      if (entry is! Map<String, dynamic>) continue;
      final rule = AlertRule.fromJson(entry);
      if (rule != null) rules[rule.kind] = rule;
    }
    return rules.isEmpty ? defaults : AlertSettings(rules: rules);
  }
}
