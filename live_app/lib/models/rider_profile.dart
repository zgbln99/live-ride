import 'ride_data_field.dart';

/// Rider identity and app-wide preferences.
///
/// [displayName] is what spectators see. It falls back to the account username
/// so a rider is never published as a generic "Rider".
class RiderProfile {
  const RiderProfile({
    this.displayName = '',
    this.username = '',
    this.metricUnits = true,
    this.headingUp = true,
    this.keepScreenAwake = true,
    this.weatherEnabled = true,
    this.autoLive = false,
    this.layout = RideFieldLayout.four,
    this.fields = const <RideDataField>[
      RideDataField.speed,
      RideDataField.heartRate,
      RideDataField.distance,
      RideDataField.elapsed,
    ],
  });

  final String displayName;
  final String username;
  final bool metricUnits;
  final bool headingUp;
  final bool keepScreenAwake;
  final bool weatherEnabled;
  final bool autoLive;
  final RideFieldLayout layout;
  final List<RideDataField> fields;

  /// The name used for LIVE sessions, ride titles and the profile header.
  String get effectiveName {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final user = username.trim();
    if (user.isNotEmpty) return user;
    return 'Rider';
  }

  bool get hasIdentity =>
      displayName.trim().isNotEmpty || username.trim().isNotEmpty;

  /// The configured fields trimmed/padded to the selected layout size.
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

  RiderProfile copyWith({
    String? displayName,
    String? username,
    bool? metricUnits,
    bool? headingUp,
    bool? keepScreenAwake,
    bool? weatherEnabled,
    bool? autoLive,
    RideFieldLayout? layout,
    List<RideDataField>? fields,
  }) => RiderProfile(
    displayName: displayName ?? this.displayName,
    username: username ?? this.username,
    metricUnits: metricUnits ?? this.metricUnits,
    headingUp: headingUp ?? this.headingUp,
    keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    weatherEnabled: weatherEnabled ?? this.weatherEnabled,
    autoLive: autoLive ?? this.autoLive,
    layout: layout ?? this.layout,
    fields: fields ?? this.fields,
  );

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'username': username,
    'metric_units': metricUnits,
    'heading_up': headingUp,
    'keep_screen_awake': keepScreenAwake,
    'weather_enabled': weatherEnabled,
    'auto_live': autoLive,
    'layout': layout.name,
    'fields': fields.map((f) => f.name).toList(),
  };

  factory RiderProfile.fromJson(Map<String, dynamic> json) {
    final rawFields = (json['fields'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map(
          (name) => RideDataField.values
              .where((field) => field.name == name)
              .firstOrNull,
        )
        .whereType<RideDataField>()
        .toList();
    final layoutName = json['layout'] as String?;
    return RiderProfile(
      displayName: json['display_name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      metricUnits: json['metric_units'] as bool? ?? true,
      headingUp: json['heading_up'] as bool? ?? true,
      keepScreenAwake: json['keep_screen_awake'] as bool? ?? true,
      weatherEnabled: json['weather_enabled'] as bool? ?? true,
      autoLive: json['auto_live'] as bool? ?? false,
      layout:
          RideFieldLayout.values
              .where((value) => value.name == layoutName)
              .firstOrNull ??
          RideFieldLayout.four,
      fields: rawFields.isEmpty ? const RiderProfile().fields : rawFields,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
