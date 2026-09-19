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
  });

  final bool sharePosition;
  final bool shareSpeed;
  final bool shareHeartRate;
  final bool sharePower;

  /// Czy obserwujący zobaczy cokolwiek poza nazwą.
  bool get sharesAnything =>
      sharePosition || shareSpeed || shareHeartRate || sharePower;

  LivePrivacy copyWith({
    bool? sharePosition,
    bool? shareSpeed,
    bool? shareHeartRate,
    bool? sharePower,
  }) => LivePrivacy(
    sharePosition: sharePosition ?? this.sharePosition,
    shareSpeed: shareSpeed ?? this.shareSpeed,
    shareHeartRate: shareHeartRate ?? this.shareHeartRate,
    sharePower: sharePower ?? this.sharePower,
  );

  Map<String, dynamic> toJson() => {
    'share_position': sharePosition,
    'share_speed': shareSpeed,
    'share_heart_rate': shareHeartRate,
    'share_power': sharePower,
  };

  factory LivePrivacy.fromJson(Map<String, dynamic> json) => LivePrivacy(
    sharePosition: json['share_position'] as bool? ?? true,
    shareSpeed: json['share_speed'] as bool? ?? true,
    shareHeartRate: json['share_heart_rate'] as bool? ?? false,
    sharePower: json['share_power'] as bool? ?? false,
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
