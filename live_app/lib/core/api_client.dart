import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../models/navigation_plan.dart';
import '../models/ride_route.dart';
import '../services/routing_service.dart';
import 'geo.dart';

/// An error worth showing to a rider.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveSession {
  const LiveSession({
    required this.id,
    required this.participantId,
    required this.shareToken,
    required this.joinToken,
    this.visibility = 'unlisted',
    this.hasRoute = false,
  });

  final String id;
  final String participantId;
  final String shareToken;
  final String joinToken;

  /// „public", „unlisted" albo „disabled" — tak, jak mówi serwer.
  final String visibility;

  /// Czy do sesji przypięto zaplanowaną trasę. Bez niej publiczna strona nie
  /// ma czego narysować jako planu i nie pokaże ETA.
  final bool hasRoute;

  LiveSession copyWith({String? shareToken, String? visibility}) => LiveSession(
    id: id,
    participantId: participantId,
    shareToken: shareToken ?? this.shareToken,
    joinToken: joinToken,
    visibility: visibility ?? this.visibility,
    hasRoute: hasRoute,
  );

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
    id: json['id'] as String,
    participantId: json['participant_id'] as String? ?? '',
    shareToken: json['share_token'] as String? ?? '',
    joinToken: json['join_token'] as String? ?? '',
    visibility: json['visibility'] as String? ?? 'unlisted',
    hasRoute: json['has_route'] as bool? ?? false,
  );
}

class AccountIdentity {
  const AccountIdentity({
    required this.username,
    required this.name,
    this.email = '',
  });

  final String username;
  final String name;
  final String email;

  /// Nazwa, którą da się pokazać: wyświetlana, a gdy jej nie ma — login.
  String get label => name.trim().isNotEmpty ? name.trim() : username;
}

class ApiClient {
  /// Overridable at build time:
  /// `flutter run --dart-define=LIVE_RIDE_SERVER=https://ride.example.com`
  static const String serverOrigin = String.fromEnvironment(
    'LIVE_RIDE_SERVER',
    defaultValue: 'https://ride.76-13-3-214.sslip.io',
  );

  late final Dio dio;
  late final PersistCookieJar cookieJar;

  String? _mapStyle;

  /// Wołane, gdy serwer odrzuci żądanie z powodu wygasłej sesji.
  ///
  /// Klient nie wie, co z tym zrobić — wie tylko, że to się stało. Decyzję
  /// (pokazać logowanie, nie przerywając jazdy) podejmuje aplikacja.
  void Function()? onSessionExpired;

  /// Ścieżki, na których 401 nie znaczy „sesja wygasła", tylko „złe hasło".
  ///
  /// Bez tego nieudana próba logowania albo resetu hasła wyrzucałaby z
  /// aplikacji kogoś, kto jest zalogowany na innym koncie.
  @visibleForTesting
  static const List<String> publicPaths = [
    '/auth/login',
    '/auth/register',
    '/auth/logout',
    '/auth/reset',
    '/user',
  ];

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/cookies'),
      ignoreExpires: false,
    );
    dio = Dio(
      BaseOptions(
        baseUrl: '$serverOrigin/api/v1',
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
      ),
    );
    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          final status = error.response?.statusCode;
          final path = error.requestOptions.path;
          if ((status == 401 || status == 403) &&
              !publicPaths.any(path.startsWith)) {
            onSessionExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<bool> hasSession() async {
    // PersistCookieJar drops expired cookies when ignoreExpires is false, so
    // the presence of pb_auth is enough to restore the local session.
    final cookies = await cookieJar.loadForRequest(Uri.parse(serverOrigin));
    return cookies.any((cookie) => cookie.name == 'pb_auth');
  }

  /// Loguje i oddaje to, co serwer wie o rowerzyście, żeby aplikacja nigdy
  /// nie musiała pokazywać nazwy zastępczej.
  ///
  /// [identity] to e-mail ALBO nazwa użytkownika — kolekcja `users` ma oba
  /// pola w `identityFields`, więc rozstrzyga serwer, a nie zgadywanka po
  /// znaku małpy w polu tekstowym.
  Future<AccountIdentity> login(String identity, String password) async {
    final trimmed = identity.trim();
    try {
      final response = await dio.post(
        '/auth/login',
        data: {'username': trimmed, 'password': password},
      );
      return _identityFrom(response.data, fallbackUsername: trimmed);
    } on DioException catch (e) {
      throw ApiException(_describe(e, unauthorized: S.wrongCredentials));
    }
  }

  /// Zakłada konto i od razu loguje.
  ///
  /// [name] to nazwa wyświetlana — ta, którą znajomi widzą obok pozycji na
  /// publicznej stronie LIVE. Bez niej zostałby login, a on bywa techniczny.
  Future<AccountIdentity> register({
    required String username,
    required String email,
    required String password,
    String name = '',
  }) async {
    final trimmedName = name.trim();
    try {
      await dio.put(
        '/user',
        data: {
          'username': username.trim(),
          'email': email.trim(),
          'password': password,
          'passwordConfirm': password,
          if (trimmedName.isNotEmpty) 'name': trimmedName,
        },
      );
    } on DioException catch (e) {
      throw ApiException(_describe(e, badRequest: S.usernameTaken));
    }
    final identity = await login(username, password);
    // Serwer zna nazwę i e-mail od tej chwili, ale gdyby odpowiedź logowania
    // ich nie niosła, i tak wiemy, co właśnie wysłaliśmy.
    return AccountIdentity(
      username: identity.username,
      name: identity.name.isNotEmpty ? identity.name : trimmedName,
      email: identity.email.isNotEmpty ? identity.email : email.trim(),
    );
  }

  /// Prosi serwer o wiadomość z instrukcjami resetu hasła.
  ///
  /// Nie ma tu rozgałęzienia na „konto istnieje" i „nie istnieje", bo serwer
  /// celowo odpowiada tak samo na jedno i drugie: inaczej ten formularz byłby
  /// sprawdzarką, czy dany adres jest u nas zarejestrowany.
  Future<void> requestPasswordReset(String email) async {
    try {
      await dio.post('/auth/reset', data: {'email': email.trim()});
    } on DioException catch (e) {
      throw ApiException(_describe(e, badRequest: S.emailInvalid));
    }
  }

  AccountIdentity _identityFrom(
    Object? data, {
    required String fallbackUsername,
  }) {
    if (data is Map) {
      final record = data['record'];
      if (record is Map) {
        return AccountIdentity(
          username: (record['username'] as String? ?? fallbackUsername).trim(),
          name: (record['name'] as String? ?? '').trim(),
          email: (record['email'] as String? ?? '').trim(),
        );
      }
    }
    return AccountIdentity(username: fallbackUsername, name: '');
  }

  Future<void> logout() async {
    await cookieJar.deleteAll();
  }

  /// The MapLibre style document, cached for the process lifetime.
  /// Adres stylu mapy.
  ///
  /// Pobieranie map offline potrzebuje URL-a, a nie treści stylu: silnik
  /// mapy sam go odpytuje i rozwiązuje z niego adresy kafelków.
  static String get mapStyleUrl =>
      '$serverOrigin/api/v1/map/style?theme=liberty';

  Future<String> fetchMapStyle() async {
    final cached = _mapStyle;
    if (cached != null) return cached;
    try {
      final response = await dio.get(
        '/map/style',
        queryParameters: {'theme': 'liberty'},
      );
      final data = response.data;
      final style = data is String ? data : jsonEncode(data);
      _mapStyle = style;
      return style;
    } on DioException catch (e) {
      throw ApiException(_describe(e, generic: S.mapStyleFailed));
    }
  }

  /// Map-matches a route and returns turn-by-turn instructions.
  ///
  /// Falls back to the raw GPX geometry whenever the routing service cannot
  /// help: a rider with a GPX file must always be able to ride it.
  Future<NavigationPlan> buildNavigation(
    RideRoute route, {
    String language = 'en-US',
  }) async {
    if (route.points.length < 2) return NavigationPlan.fromRoute(route);
    final sampled = samplePolyline(simplifyPolyline(route.points, 8), 480);
    try {
      final response = await dio.post(
        '/valhalla/navigate',
        data: {
          'shape': [
            for (final point in sampled) {'lat': point.lat, 'lon': point.lon},
          ],
          'costing': 'bicycle',
          'language': language,
        },
      );
      final data = response.data;
      if (data is! Map) return NavigationPlan.fromRoute(route);
      final plan = NavigationPlan.fromJson(Map<String, dynamic>.from(data));
      if (plan.shape.length < 2) return NavigationPlan.fromRoute(route);
      // A map-match that drifts far from the imported file is worse than the
      // file itself; trust the rider's GPX in that case.
      final drift =
          (plan.totalMeters - route.distanceMeters).abs() /
          (route.distanceMeters == 0 ? 1 : route.distanceMeters);
      if (drift > 0.25) return NavigationPlan.fromRoute(route);
      return plan;
    } catch (_) {
      return NavigationPlan.fromRoute(route);
    }
  }

  Future<LiveSession> createLive({
    required String title,
    String? displayName,
    String? routeClientId,
    String visibility = 'unlisted',
    bool expireOnEnd = false,
  }) async {
    try {
      final response = await dio.post(
        '/live-rides',
        data: {
          'title': title,
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
          // Trasa po client_id: serwer sam sprawdzi, że należy do nadawcy.
          if (routeClientId != null && routeClientId.isNotEmpty)
            'route_client_id': routeClientId,
          'visibility': visibility,
          'expire_on_end': expireOnEnd,
        },
      );
      return LiveSession.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw ApiException(_describe(e, unauthorized: S.liveSignInAgain));
    }
  }

  Future<LiveSession> joinLive(String code, {String? displayName}) async {
    try {
      final response = await dio.post(
        '/live-rides/join',
        data: {
          'join_token': code.trim().toUpperCase(),
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
        },
      );
      return LiveSession.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw ApiException(
        _describe(
          e,
          notFound: S.liveCodeNotFound,
          badRequest: S.liveCodeInvalid,
        ),
      );
    }
  }

  Future<void> sendTelemetry(
    String sessionId,
    Map<String, dynamic> point,
  ) async {
    await dio.post(
      '/live-rides/$sessionId/telemetry',
      data: {
        'points': [point],
      },
    );
  }

  /// Zapisuje, co zawodnik udostępnia obserwującym.
  /// Doczepia albo podmienia trasę aktywnej sesji LIVE.
  ///
  /// [route] to pełny opis trasy w kształcie, którego używa synchronizacja.
  /// Wysyłamy go zamiast samego identyfikatora, bo trasa świeżo z kreatora,
  /// z pliku GPX albo z cudzego linku jeszcze nie istnieje na serwerze —
  /// a publiczna strona ma ją pokazać i tak, bez proszenia zawodnika, żeby
  /// „najpierw zsynchronizował".
  Future<bool> attachLiveRoute(
    String sessionId, {
    Map<String, dynamic>? route,
    String? routeClientId,
    bool detach = false,
  }) async {
    try {
      await dio.post<dynamic>(
        '/live-rides/$sessionId/route',
        data: {
          if (detach) 'detach': true,
          'route': ?route,
          if (routeClientId != null && routeClientId.isNotEmpty)
            'route_client_id': routeClientId,
        },
      );
      return true;
    } on DioException {
      // Trasa na publicznej stronie jest dodatkiem do jazdy, a nie jej
      // warunkiem. Nieudane doczepienie nie ma prawa niczego przerwać.
      return false;
    }
  }

  Future<void> setLivePrivacy(
    String sessionId,
    Map<String, dynamic> privacy,
  ) async {
    await dio.post('/live-rides/$sessionId/privacy', data: privacy);
  }

  /// Co serwer NAPRAWDĘ wie o tej jeździe.
  ///
  /// Aplikacja zna własne czujniki, ale nie zna stanu po drugiej stronie —
  /// a różnica między „wysłałem" a „przyjęto" to dokładnie ta klasa usterek,
  /// przez którą publiczna strona bywała pusta mimo działającego licznika.
  /// Null, gdy serwer jest nieosiągalny; ekran mówi wtedy wprost, że to
  /// łączność, a nie jazda.
  Future<Map<String, dynamic>?> liveDiagnostics(String sessionId) async {
    try {
      final response = await dio.get<dynamic>(
        '/live-rides/$sessionId/diagnostics',
      );
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on DioException {
      return null;
    }
  }

  Future<void> setLiveMeetup(
    String sessionId, {
    double? lat,
    double? lon,
    String label = '',
    bool clear = false,
  }) async {
    await dio.post(
      '/live-rides/$sessionId/meetup',
      data: clear
          ? {'clear': true}
          : {'latitude': lat, 'longitude': lon, 'label': label},
    );
  }

  Future<void> postLiveMessage(String sessionId, String body) async {
    await dio.post('/live-rides/$sessionId/messages', data: {'body': body});
  }

  /// Wiadomości grupy. Czyta je token udostępnienia, tak jak migawkę.
  Future<List<Map<String, dynamic>>> fetchLiveMessages(
    String shareToken,
  ) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/live/$shareToken/messages',
    );
    final messages = response.data?['messages'];
    if (messages is! List) return const [];
    return [
      for (final entry in messages)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }

  /// Zmienia widoczność publicznego linku, jego wygasanie albo sam token.
  ///
  /// Zwraca aktualny token: po `rotate` jest inny niż wcześniej i to on
  /// unieważnia wszystko, co już zostało rozesłane.
  Future<Map<String, dynamic>> setLiveShare(
    String sessionId, {
    String? visibility,
    bool? expireOnEnd,
    int? expireInHours,
    bool rotateToken = false,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/live-rides/$sessionId/share',
      data: {
        // Pominięte pole znaczy dla serwera „nie zmieniam" — dlatego null
        // wypada z żądania, zamiast lecieć jako wartość.
        'visibility': ?visibility,
        'expire_on_end': ?expireOnEnd,
        'expire_in_hours': ?expireInHours,
        if (rotateToken) 'rotate_token': true,
      },
    );
    return response.data ?? const {};
  }

  Future<void> stopLive(String sessionId) async {
    await dio.post('/live-rides/$sessionId/stop');
  }

  String viewerUrl(String shareToken) => '$serverOrigin/live/$shareToken';

  /// Publiczna strona trasy — druga strona, nie mylić z podglądem LIVE.
  String routeUrl(String shareToken) => '$serverOrigin/route/$shareToken';

  /// Pobiera trasę spod publicznego linku.
  ///
  /// Nie wymaga logowania po stronie serwera — tak jak strona WWW, którą ten
  /// sam token otwiera w przeglądarce.
  Future<RideRoute> fetchSharedRoute(String shareToken) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/live-routes/${Uri.encodeComponent(shareToken)}',
      );
      final data = response.data;
      if (data == null) throw ApiException(S.routeLinkNotFound);

      final polyline = data['polyline'] as String? ?? '';
      final points = decodeValhallaPolyline(polyline);
      if (points.length < 2) throw ApiException(S.routeLinkNotFound);

      return RideRoute(
        // Kopia dostaje własny identyfikator: od teraz to osobna trasa w
        // bibliotece, którą można zmieniać bez ruszania oryginału.
        id: 'shared_${DateTime.now().microsecondsSinceEpoch}',
        name: (data['name'] as String? ?? '').trim().isEmpty
            ? S.route
            : (data['name'] as String).trim(),
        description: data['description'] as String? ?? '',
        tags: [
          for (final tag in (data['tags'] as List? ?? const []))
            if (tag is String) tag,
        ],
        points: points,
        source: RouteSource.imported,
      );
    } on DioException catch (e) {
      throw ApiException(_describe(e, notFound: S.routeLinkNotFound));
    }
  }

  String _describe(
    DioException error, {
    String? unauthorized,
    String? notFound,
    String? badRequest,
    String? generic,
  }) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return S.serverTimeout;
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return S.serverUnreachable(serverOrigin);
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          return unauthorized ?? S.notSignedIn;
        }
        if (status == 404) return notFound ?? S.serverNotFound;
        if (status == 400) return badRequest ?? S.serverRejected;
        return S.serverError(status);
      case DioExceptionType.cancel:
        return S.requestCancelled;
      case DioExceptionType.badCertificate:
        return S.badCertificate;
      default:
        return generic ?? S.serverUnreachable(serverOrigin);
    }
  }
}
