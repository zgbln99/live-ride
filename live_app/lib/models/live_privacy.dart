/// Co zawodnik udostępnia obserwującym.
///
/// Domyślnie widać pozycję i prędkość — bez nich śledzenie na żywo nie ma
/// sensu. Tętno i moc są osobiste i włącza się je świadomie.
class LivePrivacy {
  const LivePrivacy({
    this.sharePosition = true,
    this.shareSpeed = true,
    this.shareHeartRate = false,
    this.sharePower = false,
    this.shareBattery = false,
    this.locationDelaySeconds = 0,
    this.locationCoarse = false,
    this.hideStartMeters = 0,
    this.hideFinishMeters = 0,
  });

  final bool sharePosition;
  final bool shareSpeed;
  final bool shareHeartRate;
  final bool sharePower;

  /// Poziom baterii telefonu. Pytanie „czy on zaraz zniknie" jest sensowne,
  /// ale to też informacja o zawodniku, więc włącza się ją świadomie.
  final bool shareBattery;

  /// O ile sekund publiczna pozycja ma być opóźniona.
  ///
  /// Dotyczy WYŁĄCZNIE tego, co widzi obserwujący. Nagranie przejazdu, ślad
  /// zapisany w telefonie i statystyki są nietknięte — opóźnienie nie jest
  /// funkcją licznika, tylko funkcją transmisji.
  final int locationDelaySeconds;

  /// Czy publiczna pozycja ma być zaokrąglona do kratki zamiast do punktu.
  final bool locationCoarse;

  /// Promień wokół miejsca startu, z którego nie wychodzi żadna pozycja.
  final int hideStartMeters;

  /// To samo wokół mety zaplanowanej trasy.
  final int hideFinishMeters;

  /// Czy jakiekolwiek ograniczenie lokalizacji jest włączone.
  bool get limitsLocation =>
      locationDelaySeconds > 0 ||
      locationCoarse ||
      hideStartMeters > 0 ||
      hideFinishMeters > 0;

  /// Czy obserwujący zobaczy cokolwiek poza nazwą.
  bool get sharesAnything =>
      sharePosition ||
      shareSpeed ||
      shareHeartRate ||
      sharePower ||
      shareBattery;

  LivePrivacy copyWith({
    bool? sharePosition,
    bool? shareSpeed,
    bool? shareHeartRate,
    bool? sharePower,
    bool? shareBattery,
    int? locationDelaySeconds,
    bool? locationCoarse,
    int? hideStartMeters,
    int? hideFinishMeters,
  }) => LivePrivacy(
    sharePosition: sharePosition ?? this.sharePosition,
    shareSpeed: shareSpeed ?? this.shareSpeed,
    shareHeartRate: shareHeartRate ?? this.shareHeartRate,
    sharePower: sharePower ?? this.sharePower,
    shareBattery: shareBattery ?? this.shareBattery,
    locationDelaySeconds: locationDelaySeconds ?? this.locationDelaySeconds,
    locationCoarse: locationCoarse ?? this.locationCoarse,
    hideStartMeters: hideStartMeters ?? this.hideStartMeters,
    hideFinishMeters: hideFinishMeters ?? this.hideFinishMeters,
  );

  Map<String, dynamic> toJson() => {
    'share_position': sharePosition,
    'share_speed': shareSpeed,
    'share_heart_rate': shareHeartRate,
    'share_power': sharePower,
    'share_battery': shareBattery,
    'location_delay_seconds': locationDelaySeconds,
    'location_coarse': locationCoarse,
    'hide_start_m': hideStartMeters,
    'hide_finish_m': hideFinishMeters,
  };

  factory LivePrivacy.fromJson(Map<String, dynamic> json) => LivePrivacy(
    sharePosition: json['share_position'] as bool? ?? true,
    shareSpeed: json['share_speed'] as bool? ?? true,
    shareHeartRate: json['share_heart_rate'] as bool? ?? false,
    sharePower: json['share_power'] as bool? ?? false,
    shareBattery: json['share_battery'] as bool? ?? false,
    locationDelaySeconds: (json['location_delay_seconds'] as num?)?.toInt() ?? 0,
    locationCoarse: json['location_coarse'] as bool? ?? false,
    hideStartMeters: (json['hide_start_m'] as num?)?.toInt() ?? 0,
    hideFinishMeters: (json['hide_finish_m'] as num?)?.toInt() ?? 0,
  );
}

/// Dozwolone opóźnienia publicznej lokalizacji.
///
/// Skończona lista zamiast suwaka: „17 sekund" nie znaczy nic więcej niż
/// „15 sekund", a wybór z czterech pozycji da się zrobić w rękawiczkach.
const List<int> liveLocationDelayChoices = [0, 15, 30, 60];

/// Dozwolone promienie ukrycia startu i mety.
const List<int> liveHideRadiusChoices = [0, 300, 500, 1000];

/// Kto może otworzyć publiczny link do jazdy.
enum LiveShareVisibility {
  /// Działa dla każdego, kto dostał adres. Nigdzie go nie ogłaszamy i
  /// wyszukiwarki mają zakaz indeksowania.
  unlisted('unlisted', 'Tylko z linku'),

  /// To samo plus zgoda na indeksowanie — świadomie publiczna jazda.
  public('public', 'Publiczna'),

  /// Link przestaje działać natychmiast, dla wszystkich.
  disabled('disabled', 'Wyłączone');

  const LiveShareVisibility(this.wire, this.label);

  final String wire;
  final String label;

  static LiveShareVisibility parse(String? value) =>
      LiveShareVisibility.values.firstWhere(
        (visibility) => visibility.wire == value,
        // Nieznana wartość z serwera nie może niczego upublicznić.
        orElse: () => LiveShareVisibility.unlisted,
      );
}

/// Po jakim czasie link do jazdy ma przestać działać.
enum LiveShareExpiry {
  never('Bez ograniczeń', null),
  onEnd('Po zakończeniu jazdy', null),
  hours6('Po 6 godzinach', 6),
  hours24('Po 24 godzinach', 24),
  days7('Po 7 dniach', 24 * 7);

  const LiveShareExpiry(this.label, this.hours);

  final String label;
  final int? hours;

  bool get expiresOnEnd => this == LiveShareExpiry.onEnd;
}

/// Ustawienia publicznego linku, trzymane osobno od prywatności pól.
///
/// Prywatność mówi, CO widać. To mówi, KTO i JAK DŁUGO.
class LiveShareSettings {
  const LiveShareSettings({
    this.visibility = LiveShareVisibility.unlisted,
    this.expiry = LiveShareExpiry.never,
  });

  final LiveShareVisibility visibility;
  final LiveShareExpiry expiry;

  LiveShareSettings copyWith({
    LiveShareVisibility? visibility,
    LiveShareExpiry? expiry,
  }) => LiveShareSettings(
    visibility: visibility ?? this.visibility,
    expiry: expiry ?? this.expiry,
  );

  Map<String, dynamic> toJson() => {
    'visibility': visibility.wire,
    'expiry': expiry.name,
  };

  factory LiveShareSettings.fromJson(Map<String, dynamic> json) =>
      LiveShareSettings(
        visibility: LiveShareVisibility.parse(json['visibility'] as String?),
        expiry: LiveShareExpiry.values.firstWhere(
          (value) => value.name == json['expiry'],
          orElse: () => LiveShareExpiry.never,
        ),
      );
}

/// Jedna wiadomość w jeździe grupowej.
class LiveMessage {
  const LiveMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.author,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final String author;

  static LiveMessage? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final body = json['body'] as String?;
    if (id == null || body == null) return null;
    return LiveMessage(
      id: id,
      body: body,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      author: json['display_name'] as String? ?? '',
    );
  }
}

/// Gotowe wiadomości do jednego kliknięcia.
///
/// W jeździe pisanie jest niemożliwe, więc liczy się to, co da się wysłać
/// jednym dotknięciem.
enum QuickMessage {
  waiting('Czekam na was'),
  goAhead('Jedźcie dalej'),
  slowDown('Zwolnijcie'),
  stopping('Zatrzymuję się'),
  flat('Kapeć'),
  needFood('Muszę coś zjeść'),
  onMyWay('Już jadę'),
  seeYouAtMeetup('Widzimy się na zbiórce');

  const QuickMessage(this.body);

  final String body;
}
