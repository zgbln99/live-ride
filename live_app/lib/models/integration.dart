/// Zewnętrzny serwis, do którego da się wysłać przejazd.
enum IntegrationProvider {
  strava('Strava'),
  komoot('Komoot'),
  garmin('Garmin Connect');

  const IntegrationProvider(this.label);

  final String label;

  /// Czy serwis ma publiczne API, z którego może korzystać aplikacja
  /// napisana przez kogoś z zewnątrz.
  ///
  /// Strava ma. Komoot i Garmin nie: ich API są zamknięte dla partnerów
  /// i nie da się o nie poprosić jako osoba prywatna. Udawanie, że
  /// przycisk „Połącz" coś zrobi, byłoby kłamstwem — zamiast tego Live
  /// Ride oferuje to, co naprawdę działa: plik.
  bool get hasPublicApi => this == IntegrationProvider.strava;

  /// Czy do działania potrzebny jest sekret aplikacji.
  bool get needsClientSecret => this == IntegrationProvider.strava;

  static IntegrationProvider? parse(String? value) {
    for (final provider in IntegrationProvider.values) {
      if (provider.name == value) return provider;
    }
    return null;
  }
}

/// Stan połączenia z serwisem.
enum IntegrationStatus {
  /// Brak client ID / sekretu — nie ma czym się logować.
  unconfigured,

  /// Skonfigurowane, ale niezalogowane.
  signedOut,

  connecting,
  connected,

  /// Serwis nie udostępnia publicznego API.
  unavailable,
}

/// Zapisane poświadczenia jednego serwisu.
///
/// Sekret leży wyłącznie na urządzeniu zawodnika. To jedyny układ, w którym
/// sekret w aplikacji mobilnej jest do obrony: należy do tej jednej osoby,
/// a nie do wszystkich użytkowników naraz.
class IntegrationCredentials {
  const IntegrationCredentials({
    required this.provider,
    this.clientId = '',
    this.clientSecret = '',
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.athleteName,
  });

  final IntegrationProvider provider;
  final String clientId;
  final String clientSecret;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? athleteName;

  bool get isConfigured =>
      clientId.trim().isNotEmpty &&
      (!provider.needsClientSecret || clientSecret.trim().isNotEmpty);

  bool get hasToken => (accessToken ?? '').isNotEmpty;

  /// Token uznajemy za wygasły minutę wcześniej, żeby nie trafić w okno,
  /// w którym wygaśnie w locie.
  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)));
  }

  IntegrationStatus get status {
    if (!provider.hasPublicApi) return IntegrationStatus.unavailable;
    if (!isConfigured) return IntegrationStatus.unconfigured;
    if (!hasToken) return IntegrationStatus.signedOut;
    return IntegrationStatus.connected;
  }

  IntegrationCredentials copyWith({
    String? clientId,
    String? clientSecret,
    Object? accessToken = _keep,
    Object? refreshToken = _keep,
    Object? expiresAt = _keep,
    Object? athleteName = _keep,
  }) => IntegrationCredentials(
    provider: provider,
    clientId: clientId ?? this.clientId,
    clientSecret: clientSecret ?? this.clientSecret,
    accessToken: accessToken == _keep
        ? this.accessToken
        : accessToken as String?,
    refreshToken: refreshToken == _keep
        ? this.refreshToken
        : refreshToken as String?,
    expiresAt: expiresAt == _keep ? this.expiresAt : expiresAt as DateTime?,
    athleteName: athleteName == _keep
        ? this.athleteName
        : athleteName as String?,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'client_id': clientId,
    'client_secret': clientSecret,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt?.toIso8601String(),
    'athlete_name': athleteName,
  };

  static IntegrationCredentials? fromJson(Map<String, dynamic> json) {
    final provider = IntegrationProvider.parse(json['provider'] as String?);
    if (provider == null) return null;
    return IntegrationCredentials(
      provider: provider,
      clientId: json['client_id'] as String? ?? '',
      clientSecret: json['client_secret'] as String? ?? '',
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      athleteName: json['athlete_name'] as String?,
    );
  }
}

const Object _keep = Object();

/// Stan wysyłki jednego przejazdu.
enum UploadState { queued, uploading, processing, done, failed }

class IntegrationUpload {
  const IntegrationUpload({
    required this.provider,
    required this.rideId,
    required this.state,
    this.remoteId,
    this.error,
  });

  final IntegrationProvider provider;
  final String rideId;
  final UploadState state;
  final String? remoteId;
  final String? error;

  IntegrationUpload copyWith({
    UploadState? state,
    String? remoteId,
    String? error,
  }) => IntegrationUpload(
    provider: provider,
    rideId: rideId,
    state: state ?? this.state,
    remoteId: remoteId ?? this.remoteId,
    error: error ?? this.error,
  );
}
