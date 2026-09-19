import 'ride_data_field.dart';

/// Jedna strona komputera rowerowego.
///
/// Garmin nazywa to „data page": własny układ, własny zestaw pól, przesuwana
/// palcem w bok. Strona nie wie nic o ekranie — to czysty opis.
class RideDataPage {
  const RideDataPage({
    required this.name,
    required this.layout,
    required this.fields,
  });

  final String name;
  final RideFieldLayout layout;
  final List<RideDataField> fields;

  /// Pola przycięte albo uzupełnione do rozmiaru układu.
  List<RideDataField> get activeFields {
    final count = layout.fieldCount;
    final result = List<RideDataField>.of(fields);
    while (result.length < count) {
      result.add(
        RideDataField.values.firstWhere(
          (field) => !result.contains(field),
          orElse: () => RideDataField.distance,
        ),
      );
    }
    return result.sublist(0, count);
  }

  RideDataPage copyWith({
    String? name,
    RideFieldLayout? layout,
    List<RideDataField>? fields,
  }) => RideDataPage(
    name: name ?? this.name,
    layout: layout ?? this.layout,
    fields: fields ?? this.fields,
  );

  /// Podmienia jedno pole — to, co robi przytrzymanie pola na ekranie jazdy.
  RideDataPage withFieldAt(int index, RideDataField field) {
    final next = List<RideDataField>.of(activeFields);
    if (index < 0 || index >= next.length) return this;
    next[index] = field;
    return copyWith(fields: next);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'layout': layout.name,
    'fields': fields.map((field) => field.name).toList(),
  };

  factory RideDataPage.fromJson(Map<String, dynamic> json) => RideDataPage(
    name: json['name'] as String? ?? 'Strona',
    layout: RideFieldLayout.parse(json['layout'] as String?),
    fields: (json['fields'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map(RideDataField.parse)
        .whereType<RideDataField>()
        .toList(),
  );
}

/// Gotowe zestawy stron pod konkretny typ jazdy.
///
/// Presety nie wymyślają sensorów: zestaw treningowy pokazuje moc, bo taki
/// jest jego sens, ale bez miernika te pola pokażą „--", a nie zmyśloną
/// liczbę.
enum RidePagePreset {
  basic('Podstawowy'),
  training('Treningowy'),
  navigation('Nawigacja'),
  climbing('Góry'),
  racing('Wyścig');

  const RidePagePreset(this.label);

  final String label;

  List<RideDataPage> get pages => switch (this) {
    RidePagePreset.basic => const [
      RideDataPage(
        name: 'Jazda',
        layout: RideFieldLayout.four,
        fields: [
          RideDataField.speed,
          RideDataField.distance,
          RideDataField.elapsed,
          RideDataField.heartRate,
        ],
      ),
      RideDataPage(
        name: 'Podsumowanie',
        layout: RideFieldLayout.six,
        fields: [
          RideDataField.avgSpeed,
          RideDataField.maxSpeed,
          RideDataField.elevationGain,
          RideDataField.movingTime,
          RideDataField.avgHeartRate,
          RideDataField.clock,
        ],
      ),
    ],
    RidePagePreset.training => const [
      RideDataPage(
        name: 'Moc',
        layout: RideFieldLayout.four,
        fields: [
          RideDataField.power3s,
          RideDataField.heartRate,
          RideDataField.cadence,
          RideDataField.speed,
        ],
      ),
      RideDataPage(
        name: 'Obciążenie',
        layout: RideFieldLayout.six,
        fields: [
          RideDataField.normalizedPower,
          RideDataField.intensityFactor,
          RideDataField.trainingStress,
          RideDataField.avgPower,
          RideDataField.work,
          RideDataField.elapsed,
        ],
      ),
      RideDataPage(
        name: 'Strefy',
        layout: RideFieldLayout.four,
        fields: [
          RideDataField.powerZone,
          RideDataField.heartRateZone,
          RideDataField.powerPerKg,
          RideDataField.avgCadence,
        ],
      ),
    ],
    RidePagePreset.navigation => const [
      RideDataPage(
        name: 'Mapa',
        layout: RideFieldLayout.two,
        fields: [RideDataField.speed, RideDataField.distance],
      ),
      RideDataPage(
        name: 'Do mety',
        layout: RideFieldLayout.four,
        fields: [
          RideDataField.remaining,
          RideDataField.eta,
          RideDataField.elevationGain,
          RideDataField.elapsed,
        ],
      ),
    ],
    RidePagePreset.climbing => const [
      RideDataPage(
        name: 'Podjazd',
        layout: RideFieldLayout.four,
        fields: [
          RideDataField.gradient,
          RideDataField.vam,
          RideDataField.heartRate,
          RideDataField.cadence,
        ],
      ),
      RideDataPage(
        name: 'Wysokość',
        layout: RideFieldLayout.four,
        fields: [
          RideDataField.elevation,
          RideDataField.elevationGain,
          RideDataField.elevationLoss,
          RideDataField.distance,
        ],
      ),
    ],
    RidePagePreset.racing => const [
      RideDataPage(
        name: 'Wyścig',
        layout: RideFieldLayout.three,
        fields: [
          RideDataField.speed,
          RideDataField.distance,
          RideDataField.elapsed,
        ],
      ),
    ],
  };
}
