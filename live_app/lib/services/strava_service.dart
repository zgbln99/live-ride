import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../core/api_client.dart';
import '../data/settings_dao.dart';
import '../i18n/strings.dart';
import '../models/integration.dart';
import '../models/ride_record.dart';

/// Klient Stravy: logowanie OAuth i wysyłka przejazdów.
///
/// Strava, w odróżnieniu od Spotify, nie wspiera PKCE — wymiana kodu na token
/// wymaga sekretu aplikacji. W aplikacji rozdawanej wszystkim byłby to błąd;
/// tutaj sekret podaje sam zawodnik i leży wyłącznie na jego urządzeniu, więc
/// należy do niego, a nie do wszystkich naraz. Bez podanych poświadczeń nic
/// się nie łączy i ekran mówi to wprost.
class StravaService extends ChangeNotifier {
  StravaService({Dio? client, SettingsDao? settings, AuthOpener? opener})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: apiBase,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      _settings = settings,
      _open = opener ?? _defaultOpener;

  static const String apiBase = 'https://www.strava.com/api/v3';

  /// Mobilny punkt autoryzacji Stravy.
  ///
  /// Wersja webowa (`/oauth/authorize`) jest pomyślana dla przeglądarki na
  /// serwerze i odrzuca własne schematy adresów. Ta przyjmuje je i potrafi
  /// przerzucić logowanie do zainstalowanej aplikacji Strava, zamiast kazać
  /// wpisywać hasło w oknie przeglądarki.
  static const String authorizeUrl =
      'https://www.strava.com/oauth/mobile/authorize';
  static const String tokenUrl = 'https://www.strava.com/oauth/token';
  static const String callbackScheme = 'liveride';

  /// Ścieżka, po której poznajemy, że wracamy właśnie ze Stravy.
  ///
  /// Spotify wraca tym samym schematem, więc rozróżnienie musi być w adresie,
  /// a nie w tym, które okno akurat otworzyliśmy.
  static const String callbackPath = '/strava-callback';

  /// Adres powrotny po zalogowaniu.
  ///
  /// Host MUSI odpowiadać polu „Authorization Callback Domain" w ustawieniach
  /// aplikacji Strava — i to jest cały powód, dla którego wygląda tak dziwnie.
  /// Strava sprawdza domenę adresu powrotnego, a `liveride://strava-callback`
  /// ma jako domenę „strava-callback", czyli coś, czego nie da się tam wpisać.
  /// Stąd błąd `redirect_uri invalid` przy każdej próbie połączenia.
  ///
  /// Host bierze się z tego samego originu, pod którym stoi Live Ride, żeby
  /// nie było dwóch miejsc do zmieniania przy przeprowadzce serwera.
  static String get redirectUri => 'liveride://$callbackHost$callbackPath';

  /// Domena, którą trzeba wpisać w ustawieniach aplikacji Strava.
  static String get callbackHost {
    final origin = Uri.tryParse(ApiClient.serverOrigin);
    final host = origin?.host ?? '';
    // Gdyby origin był popsuty, lepiej pokazać wprost, że nie ma czego wpisać,
    // niż wysłać do Stravy adres z pustym hostem i dostać ten sam błąd.
    return host.isEmpty ? 'live-ride.invalid' : host;
  }

  static const String settingsKey = 'integration_strava';

  /// Zakres: zapis aktywności i odczyt profilu, nic więcej.
  static const String scope = 'activity:write,read';

  final Dio _dio;
  final SettingsDao? _settings;
  final AuthOpener _open;

  IntegrationCredentials _credentials = const IntegrationCredentials(
    provider: IntegrationProvider.strava,
  );
  IntegrationStatus _status = IntegrationStatus.unconfigured;
  String? _lastError;
  IntegrationUpload? _lastUpload;

  IntegrationCredentials get credentials => _credentials;
  IntegrationStatus get status => _status;
  String? get lastError => _lastError;
  IntegrationUpload? get lastUpload => _lastUpload;
  bool get isConnected => _status == IntegrationStatus.connected;

  Future<void> restore() async {
    final stored = await _settings?.readJson(settingsKey);
    if (stored != null) {
      final restored = IntegrationCredentials.fromJson(stored);
      if (restored != null) _credentials = restored;
    }
    _status = _credentials.status;
    notifyListeners();
  }

  Future<void> setCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    _credentials = _credentials.copyWith(
      clientId: clientId.trim(),
      clientSecret: clientSecret.trim(),
    );
    await _persist();
  }

  Future<void> disconnect() async {
    _credentials = _credentials.copyWith(
      accessToken: null,
      refreshToken: null,
      expiresAt: null,
      athleteName: null,
    );
    _lastError = null;
    await _persist();
  }

  Future<void> forget() async {
    _credentials = const IntegrationCredentials(
      provider: IntegrationProvider.strava,
    );
    await _persist();
  }

  Future<void> _persist() async {
    _status = _credentials.status;
    notifyListeners();
    await _settings?.writeJson(settingsKey, _credentials.toJson());
  }

  /// Przeprowadza logowanie w przeglądarce systemowej.
  Future<bool> connect() async {
    if (!_credentials.isConfigured) {
      _fail(S.stravaNeedsCredentials);
      return false;
    }
    _status = IntegrationStatus.connecting;
    _lastError = null;
    notifyListeners();

    final state = _randomState();
    final url = Uri.parse(authorizeUrl).replace(
      queryParameters: {
        'client_id': _credentials.clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': scope,
        'state': state,
      },
    );

    try {
      final result = await _open(url.toString(), callbackScheme);
      final returned = Uri.parse(result);

      // Ten sam schemat obsługuje Spotify. Sprawdzamy ścieżkę, zanim
      // uznamy cudzy kod autoryzacji za swój.
      if (!_isOurCallback(returned)) {
        _fail(S.stravaAuthFailed);
        return false;
      }
      // Porównanie stanu chroni przed podrzuceniem cudzego kodu. Idzie
      // PRZED odczytaniem czegokolwiek innego z adresu.
      if (returned.queryParameters['state'] != state) {
        _fail(S.stravaStateMismatch);
        return false;
      }
      final error = returned.queryParameters['error'];
      if (error != null) {
        _fail(
          error == 'access_denied' ? S.stravaAccessDenied : S.stravaAuthFailed,
        );
        return false;
      }
      final code = returned.queryParameters['code'];
      if (code == null || code.isEmpty) {
        _fail(S.stravaNoCode);
        return false;
      }
      return await _exchange(code);
    } on PlatformException {
      _status = _credentials.status;
      notifyListeners();
      return false;
    } catch (e) {
      _fail(e.toString());
      return false;
    }
  }

  /// Czy ten adres powrotny należy do Stravy, a nie do innej integracji.
  ///
  /// Schemat `liveride://` obsługuje też Spotify. Jedno okno logowania jest
  /// otwarte naraz, więc pomyłka jest mało prawdopodobna — ale „mało
  /// prawdopodobna" to za mało, gdy chodzi o cudzy kod autoryzacji.
  @visibleForTesting
  static bool isOurCallback(Uri returned) =>
      returned.scheme == callbackScheme &&
      (returned.path == callbackPath ||
          returned.host == callbackPath.substring(1));

  bool _isOurCallback(Uri returned) => isOurCallback(returned);

  Future<bool> _exchange(String code) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        tokenUrl,
        data: {
          'client_id': _credentials.clientId,
          'client_secret': _credentials.clientSecret,
          'code': code,
          'grant_type': 'authorization_code',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      _applyToken(response.data);
      await _persist();
      return isConnected;
    } on DioException catch (e) {
      _fail(_describe(e));
      return false;
    }
  }

  /// Odświeża token, gdy wygasł. Zwraca false, gdy trzeba zalogować się od nowa.
  Future<bool> ensureFreshToken() async {
    if (!_credentials.hasToken) return false;
    if (!_credentials.isExpired) return true;
    final refresh = _credentials.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      _fail(S.stravaSignInAgain);
      return false;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        tokenUrl,
        data: {
          'client_id': _credentials.clientId,
          'client_secret': _credentials.clientSecret,
          'refresh_token': refresh,
          'grant_type': 'refresh_token',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      _applyToken(response.data);
      await _persist();
      return isConnected;
    } on DioException catch (e) {
      _fail(_describe(e));
      await disconnect();
      return false;
    }
  }

  /// Wstawia token tak, jakby przyszedł ze Stravy.
  ///
  /// Wyłącznie dla testów odświeżania: inaczej trzeba by przejść całe
  /// logowanie w przeglądarce, żeby sprawdzić, co się dzieje po wygaśnięciu.
  @visibleForTesting
  Future<void> applyTokenForTest(Map<String, dynamic> data) async {
    _applyToken(data);
    await _persist();
  }

  void _applyToken(Map<String, dynamic>? data) {
    if (data == null) return;
    final expiresAt = data['expires_at'];
    final athlete = data['athlete'];
    _credentials = _credentials.copyWith(
      accessToken: data['access_token'] as String?,
      refreshToken:
          data['refresh_token'] as String? ?? _credentials.refreshToken,
      expiresAt: expiresAt is num
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt() * 1000)
          : null,
      athleteName: athlete is Map
          ? [
              athlete['firstname'],
              athlete['lastname'],
            ].whereType<String>().join(' ').trim()
          : _credentials.athleteName,
    );
  }

  /// Wysyła plik przejazdu.
  ///
  /// Strava przyjmuje plik i przetwarza go asynchronicznie, więc po wysyłce
  /// trzeba odpytać o wynik — inaczej „wysłano" znaczyłoby tylko „serwer
  /// odebrał bajty", a nie „aktywność powstała".
  Future<IntegrationUpload> uploadRide(
    RecordedRide ride,
    File file, {
    String dataType = 'tcx',
  }) async {
    final upload = IntegrationUpload(
      provider: IntegrationProvider.strava,
      rideId: ride.id,
      state: UploadState.uploading,
    );
    _lastUpload = upload;
    notifyListeners();

    if (!await ensureFreshToken()) {
      return _finishUpload(
        upload.copyWith(
          state: UploadState.failed,
          error: _lastError ?? S.stravaSignInAgain,
        ),
      );
    }

    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.last,
        ),
        'data_type': dataType,
        'name': ride.name,
        'activity_type': 'ride',
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/uploads',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer ${_credentials.accessToken}'},
        ),
      );
      final id = response.data?['id_str'] ?? response.data?['id'];
      if (id == null) {
        return _finishUpload(
          upload.copyWith(state: UploadState.failed, error: S.stravaNoUploadId),
        );
      }
      return _finishUpload(
        await _awaitProcessing(
          upload.copyWith(state: UploadState.processing, remoteId: '$id'),
        ),
      );
    } on DioException catch (e) {
      return _finishUpload(
        upload.copyWith(state: UploadState.failed, error: _describe(e)),
      );
    }
  }

  /// Odpytuje Stravę, aż plik zostanie przetworzony albo odrzucony.
  Future<IntegrationUpload> _awaitProcessing(
    IntegrationUpload upload, {
    int attempts = 6,
    Duration interval = const Duration(seconds: 3),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(attempt == 0 ? Duration.zero : interval);
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '/uploads/${upload.remoteId}',
          options: Options(
            headers: {'Authorization': 'Bearer ${_credentials.accessToken}'},
          ),
        );
        final data = response.data ?? const {};
        final error = data['error'];
        if (error is String && error.isNotEmpty) {
          return upload.copyWith(state: UploadState.failed, error: error);
        }
        final activityId = data['activity_id'];
        if (activityId != null) {
          return upload.copyWith(
            state: UploadState.done,
            remoteId: '$activityId',
          );
        }
      } on DioException catch (e) {
        return upload.copyWith(state: UploadState.failed, error: _describe(e));
      }
    }
    // Strava czasem przetwarza dłużej; to nie błąd, tylko brak odpowiedzi
    // w rozsądnym czasie.
    return upload.copyWith(state: UploadState.processing);
  }

  IntegrationUpload _finishUpload(IntegrationUpload upload) {
    _lastUpload = upload;
    if (upload.state == UploadState.failed) _lastError = upload.error;
    notifyListeners();
    return upload;
  }

  void _fail(String message) {
    _lastError = message;
    _status = _credentials.status;
    notifyListeners();
  }

  String _describe(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) return S.stravaSignInAgain;
    if (status == 429) return S.stravaRateLimited;
    if (status == 400) {
      // Strava opisuje błąd konfiguracji w `errors[]`, a w `message` daje
      // samo „Bad Request". Pokazanie tego użytkownikowi nie mówi nic;
      // pokazanie surowego JSON-a mówi jeszcze mniej.
      final configuration = _configurationProblem(error.response?.data);
      if (configuration != null) return configuration;
      return S.stravaRejected;
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => S.stravaTimeout,
      _ => S.stravaUnreachable,
    };
  }

  /// Zamienia `errors[]` ze Stravy w zdanie, po którym wiadomo, co zrobić.
  ///
  /// Odpowiedź wygląda tak:
  /// `{"message":"Bad Request","errors":[{"resource":"Application",
  ///   "field":"redirect_uri","code":"invalid"}]}`
  ///
  /// Samo „Bad Request" nie prowadzi donikąd, a pole `redirect_uri` mówi
  /// wprost, że rozjechała się domena adresu powrotnego.
  @visibleForTesting
  static String? configurationProblem(Object? body) {
    if (body is! Map) return null;
    final errors = body['errors'];
    if (errors is! List) return null;
    for (final entry in errors) {
      if (entry is! Map) continue;
      switch (entry['field']) {
        case 'redirect_uri':
          return S.stravaBadRedirect(callbackHost);
        case 'client_id':
        case 'client_secret':
          return S.stravaBadClient;
      }
    }
    return null;
  }

  static String? _configurationProblem(Object? body) =>
      configurationProblem(body);

  static String _randomState() {
    final random = math.Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<String> _defaultOpener(String url, String scheme) =>
      FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: scheme);
}

/// Wstrzykiwane otwarcie przeglądarki — pozwala testować flow bez telefonu.
typedef AuthOpener = Future<String> Function(String url, String scheme);
