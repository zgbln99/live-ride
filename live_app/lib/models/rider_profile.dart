import 'ride_data_field.dart';
import 'ride_pages.dart';

/// Rider identity and app-wide preferences.
///
/// [displayName] is what spectators see. It falls back to the account username
/// so a rider is never published as a generic "Rider".
class RiderProfile {
  const RiderProfile({
    this.displayName = '',
    this.username = '',
    this.accountEmail = '',
    this.metricUnits = true,
    this.headingUp = true,
    this.keepScreenAwake = true,
    this.weatherEnabled = true,
    this.autoLive = false,
    this.autoPause = true,
    this.autoPauseSpeedKmh = defaultAutoPauseSpeedKmh,
    this.autoPauseDelaySeconds = defaultAutoPauseDelaySeconds,
    this.autoPauseTuning = autoPauseTuningVersion,
    this.bio = '',
    this.location = '',
    this.avatarPath = '',
    this.weightKg,
    this.heightCm,
    this.birthYear,
    this.ftpWatts,
    this.maxHeartRate,
    this.restingHeartRate,
    this.layout = RideFieldLayout.four,
    this.fields = const <RideDataField>[
      RideDataField.speed,
      RideDataField.heartRate,
      RideDataField.distance,
      RideDataField.elapsed,
    ],
    this.pages = const <RideDataPage>[],
  });

  final String displayName;
  final String username;

  /// Adres e-mail konta, wyłącznie do pokazania w sekcji KONTO.
  ///
  /// Trzymany lokalnie, żeby ekran profilu nie musiał pytać serwera przy
  /// każdym wejściu — i żeby po utracie zasięgu nadal było widać, na jakie
  /// konto telefon jest zalogowany.
  final String accountEmail;

  final bool metricUnits;
  final bool headingUp;
  final bool keepScreenAwake;
  final bool weatherEnabled;
  final bool autoLive;

  /// Automatyczna pauza na światłach i postojach.
  final bool autoPause;

  /// Poniżej tej prędkości zawodnik liczy się jako stojący.
  ///
  /// To nie jest „wolna jazda": 0,7 km/h to szum dopplerowski stojącego
  /// odbiornika. Jazda pod górę z prędkością 2 km/h to nadal jazda.
  final double autoPauseSpeedKmh;

  /// Ile sekund postoju, zanim licznik się zatrzyma. Zero sekund robiłoby
  /// pauzę na każdym hamowaniu przed zakrętem.
  final int autoPauseDelaySeconds;

  /// Wersja strojenia auto-pauzy, która zapisała te dwie liczby powyżej.
  ///
  /// Pierwsza wersja uznawała za postój wszystko poniżej 3 km/h, więc
  /// zatrzymywała licznik na podjeździe. Nikt tych wartości nie mógł wtedy
  /// zmienić — nie było na to ekranu — więc przy wczytaniu starszego profilu
  /// nadpisujemy je nowymi, zamiast zostawiać usterkę na koncie.
  final int autoPauseTuning;

  /// Próg „stoję" — ten sam, z którym jeździ [AutoPauseDetector].
  static const double defaultAutoPauseSpeedKmh = 0.7;

  /// Ile sekund bezruchu przed zatrzymaniem licznika.
  static const int defaultAutoPauseDelaySeconds = 3;

  /// Podbijaj przy każdej zmianie domyślnego strojenia auto-pauzy.
  static const int autoPauseTuningVersion = 2;

  /// Krótki opis pokazywany na profilu i w widoku LIVE.
  final String bio;
  final String location;

  /// Ścieżka do pliku awatara na urządzeniu. Pusta, gdy zawodnik go nie ustawił.
  final String avatarPath;

  /// Dane fizjologiczne. Wszystkie opcjonalne — bez nich aplikacja po prostu
  /// nie pokazuje tego, czego nie da się policzyć (kalorii, stref, IF).
  final double? weightKg;
  final double? heightCm;
  final int? birthYear;
  final int? ftpWatts;
  final int? maxHeartRate;
  final int? restingHeartRate;

  final RideFieldLayout layout;
  final List<RideDataField> fields;

  /// Strony komputera rowerowego, przesuwane palcem w bok.
  ///
  /// Pusta lista znaczy „jeszcze nie ustawione" — wtedy [ridePages] składa
  /// jedną stronę ze starych [layout] i [fields], żeby nikt nie stracił
  /// swojego układu przy aktualizacji.
  final List<RideDataPage> pages;

  List<RideDataPage> get ridePages => pages.isNotEmpty
      ? pages
      : [RideDataPage(name: 'Jazda', layout: layout, fields: activeFields)];

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

  int? get age {
    final year = birthYear;
    if (year == null || year < 1900) return null;
    final age = DateTime.now().year - year;
    return age > 0 && age < 120 ? age : null;
  }

  /// Tętno maksymalne z profilu, a gdy go nie ma — oszacowanie z wieku.
  ///
  /// Zwraca null, gdy nie ma ani jednego, ani drugiego: wtedy stref nie
  /// pokazujemy wcale, zamiast pokazywać zmyślone.
  int? get effectiveMaxHeartRate {
    if (maxHeartRate != null && maxHeartRate! > 100) return maxHeartRate;
    final years = age;
    if (years == null) return null;
    return (220 - years).round();
  }

  /// Watty na kilogram przy progu — tylko gdy znamy i FTP, i wagę.
  double? get wattsPerKilogram {
    final ftp = ftpWatts;
    final weight = weightKg;
    if (ftp == null || weight == null || weight <= 0) return null;
    return ftp / weight;
  }

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
    String? accountEmail,
    bool? metricUnits,
    bool? headingUp,
    bool? keepScreenAwake,
    bool? weatherEnabled,
    bool? autoLive,
    bool? autoPause,
    double? autoPauseSpeedKmh,
    int? autoPauseDelaySeconds,
    int? autoPauseTuning,
    String? bio,
    String? location,
    String? avatarPath,
    Object? weightKg = _keep,
    Object? heightCm = _keep,
    Object? birthYear = _keep,
    Object? ftpWatts = _keep,
    Object? maxHeartRate = _keep,
    Object? restingHeartRate = _keep,
    RideFieldLayout? layout,
    List<RideDataField>? fields,
    List<RideDataPage>? pages,
  }) => RiderProfile(
    displayName: displayName ?? this.displayName,
    username: username ?? this.username,
    accountEmail: accountEmail ?? this.accountEmail,
    metricUnits: metricUnits ?? this.metricUnits,
    headingUp: headingUp ?? this.headingUp,
    keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    weatherEnabled: weatherEnabled ?? this.weatherEnabled,
    autoLive: autoLive ?? this.autoLive,
    autoPause: autoPause ?? this.autoPause,
    autoPauseSpeedKmh: autoPauseSpeedKmh ?? this.autoPauseSpeedKmh,
    autoPauseDelaySeconds: autoPauseDelaySeconds ?? this.autoPauseDelaySeconds,
    autoPauseTuning: autoPauseTuning ?? this.autoPauseTuning,
    bio: bio ?? this.bio,
    location: location ?? this.location,
    avatarPath: avatarPath ?? this.avatarPath,
    weightKg: weightKg == _keep ? this.weightKg : weightKg as double?,
    heightCm: heightCm == _keep ? this.heightCm : heightCm as double?,
    birthYear: birthYear == _keep ? this.birthYear : birthYear as int?,
    ftpWatts: ftpWatts == _keep ? this.ftpWatts : ftpWatts as int?,
    maxHeartRate: maxHeartRate == _keep
        ? this.maxHeartRate
        : maxHeartRate as int?,
    restingHeartRate: restingHeartRate == _keep
        ? this.restingHeartRate
        : restingHeartRate as int?,
    layout: layout ?? this.layout,
    fields: fields ?? this.fields,
    pages: pages ?? this.pages,
  );

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'username': username,
    'account_email': accountEmail,
    'metric_units': metricUnits,
    'heading_up': headingUp,
    'keep_screen_awake': keepScreenAwake,
    'weather_enabled': weatherEnabled,
    'auto_live': autoLive,
    'auto_pause': autoPause,
    'auto_pause_speed': autoPauseSpeedKmh,
    'auto_pause_delay': autoPauseDelaySeconds,
    'auto_pause_tuning': autoPauseTuning,
    'bio': bio,
    'location': location,
    'avatar_path': avatarPath,
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'birth_year': birthYear,
    'ftp_watts': ftpWatts,
    'max_heart_rate': maxHeartRate,
    'resting_heart_rate': restingHeartRate,
    'layout': layout.name,
    'fields': fields.map((f) => f.name).toList(),
    'pages': pages.map((page) => page.toJson()).toList(),
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
    final tuning = (json['auto_pause_tuning'] as num?)?.toInt() ?? 1;
    return RiderProfile(
      displayName: json['display_name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      accountEmail: json['account_email'] as String? ?? '',
      metricUnits: json['metric_units'] as bool? ?? true,
      headingUp: json['heading_up'] as bool? ?? true,
      keepScreenAwake: json['keep_screen_awake'] as bool? ?? true,
      weatherEnabled: json['weather_enabled'] as bool? ?? true,
      autoLive: json['auto_live'] as bool? ?? false,
      autoPause: json['auto_pause'] as bool? ?? true,
      autoPauseSpeedKmh: tuning < autoPauseTuningVersion
          ? defaultAutoPauseSpeedKmh
          : (json['auto_pause_speed'] as num?)?.toDouble() ??
                defaultAutoPauseSpeedKmh,
      autoPauseDelaySeconds: tuning < autoPauseTuningVersion
          ? defaultAutoPauseDelaySeconds
          : (json['auto_pause_delay'] as num?)?.toInt() ??
                defaultAutoPauseDelaySeconds,
      autoPauseTuning: autoPauseTuningVersion,
      bio: json['bio'] as String? ?? '',
      location: json['location'] as String? ?? '',
      avatarPath: json['avatar_path'] as String? ?? '',
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      birthYear: (json['birth_year'] as num?)?.toInt(),
      ftpWatts: (json['ftp_watts'] as num?)?.toInt(),
      maxHeartRate: (json['max_heart_rate'] as num?)?.toInt(),
      restingHeartRate: (json['resting_heart_rate'] as num?)?.toInt(),
      layout:
          RideFieldLayout.values
              .where((value) => value.name == layoutName)
              .firstOrNull ??
          RideFieldLayout.four,
      fields: rawFields.isEmpty ? const RiderProfile().fields : rawFields,
      pages: (json['pages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RideDataPage.fromJson)
          .toList(),
    );
  }
}

/// Znacznik „nie zmieniaj tego pola" dla [RiderProfile.copyWith], dzięki
/// któremu da się też wyczyścić wartość, podając jawnie null.
const Object _keep = Object();

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
