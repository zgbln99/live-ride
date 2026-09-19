/// A normalised current-conditions snapshot.
///
/// Weather is strictly optional decoration on a ride: every consumer must cope
/// with this being null.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.apparentTemperatureCelsius,
    required this.windSpeedKmh,
    required this.windDirectionDegrees,
    required this.condition,
    required this.isDay,
    required this.observedAt,
    this.precipitationProbability,
    this.precipitationMm,
    this.locationLabel,
    this.sunrise,
    this.sunset,
  });

  final double temperatureCelsius;
  final double apparentTemperatureCelsius;
  final double windSpeedKmh;
  final double windDirectionDegrees;
  final WeatherCondition condition;
  final bool isDay;
  final DateTime observedAt;
  final int? precipitationProbability;
  final double? precipitationMm;
  final String? locationLabel;

  /// Wschód i zachód słońca na dziś w miejscu zawodnika. Null, gdy serwis
  /// ich nie podał — wtedy aplikacja nic o zmroku nie mówi.
  final DateTime? sunrise;
  final DateTime? sunset;

  /// Ile minut do zmroku. Null po zachodzie i bez danych.
  int? get minutesToSunset {
    final dusk = sunset;
    if (dusk == null) return null;
    final minutes = dusk.difference(DateTime.now()).inMinutes;
    return minutes < 0 ? null : minutes;
  }

  bool get isStale =>
      DateTime.now().difference(observedAt) > const Duration(minutes: 90);

  Map<String, dynamic> toJson() => {
    'temperature_c': temperatureCelsius,
    'apparent_c': apparentTemperatureCelsius,
    'wind_kmh': windSpeedKmh,
    'wind_dir': windDirectionDegrees,
    'condition': condition.name,
    'is_day': isDay,
    'observed_at': observedAt.toIso8601String(),
    'precip_probability': precipitationProbability,
    'precip_mm': precipitationMm,
    'sunrise': sunrise?.toIso8601String(),
    'sunset': sunset?.toIso8601String(),
  };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) =>
      WeatherSnapshot(
        temperatureCelsius: (json['temperature_c'] as num?)?.toDouble() ?? 0,
        apparentTemperatureCelsius:
            (json['apparent_c'] as num?)?.toDouble() ?? 0,
        windSpeedKmh: (json['wind_kmh'] as num?)?.toDouble() ?? 0,
        windDirectionDegrees: (json['wind_dir'] as num?)?.toDouble() ?? 0,
        condition:
            WeatherCondition.values
                .where((value) => value.name == json['condition'])
                .firstOrNull ??
            WeatherCondition.unknown,
        isDay: json['is_day'] as bool? ?? true,
        observedAt:
            DateTime.tryParse(json['observed_at'] as String? ?? '') ??
            DateTime.now(),
        precipitationProbability: (json['precip_probability'] as num?)?.toInt(),
        precipitationMm: (json['precip_mm'] as num?)?.toDouble(),
        sunrise: DateTime.tryParse(json['sunrise'] as String? ?? ''),
        sunset: DateTime.tryParse(json['sunset'] as String? ?? ''),
      );
}

enum WeatherCondition {
  clear('Bezchmurnie'),
  partlyCloudy('Częściowe zachmurzenie'),
  cloudy('Pochmurno'),
  fog('Mgła'),
  drizzle('Mżawka'),
  rain('Deszcz'),
  heavyRain('Ulewa'),
  snow('Śnieg'),
  thunderstorm('Burza'),
  unknown('--');

  const WeatherCondition(this.label);

  final String label;

  /// Czy warunki wymagają ostrzeżenia zawodnika przed startem.
  bool get isWet =>
      this == drizzle ||
      this == rain ||
      this == heavyRain ||
      this == snow ||
      this == thunderstorm;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
