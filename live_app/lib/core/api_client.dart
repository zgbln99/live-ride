import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../models/navigation_plan.dart';
import '../models/ride_route.dart';
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
  });

  final String id;
  final String participantId;
  final String shareToken;
  final String joinToken;

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
    id: json['id'] as String,
    participantId: json['participant_id'] as String? ?? '',
    shareToken: json['share_token'] as String? ?? '',
    joinToken: json['join_token'] as String? ?? '',
  );
}

class AccountIdentity {
  const AccountIdentity({required this.username, required this.name});

  final String username;
  final String name;
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
  static const List<String> _publicPaths = [
    '/auth/login',
    '/auth/register',
    '/auth/logout',
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
              !_publicPaths.any(path.startsWith)) {
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

  /// Signs in and returns whatever identity the server knows about the rider,
  /// so the app never has to show a generic name.
  Future<AccountIdentity> login(String username, String password) async {
    try {
      final response = await dio.post(
        '/auth/login',
        data: {'username': username.trim(), 'password': password},
      );
      return _identityFrom(response.data, fallbackUsername: username.trim());
    } on DioException catch (e) {
      throw ApiException(_describe(e, unauthorized: S.wrongCredentials));
    }
  }

  Future<AccountIdentity> register(
    String username,
    String email,
    String password,
  ) async {
    try {
      await dio.put(
        '/user',
        data: {
          'username': username.trim(),
          'email': email.trim(),
          'password': password,
          'passwordConfirm': password,
        },
      );
    } on DioException catch (e) {
      throw ApiException(_describe(e, badRequest: S.usernameTaken));
    }
    return login(username, password);
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
        );
      }
    }
    return AccountIdentity(username: fallbackUsername, name: '');
  }

  Future<void> logout() async {
    await cookieJar.deleteAll();
  }

  /// The MapLibre style document, cached for the process lifetime.
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
  }) async {
    try {
      final response = await dio.post(
        '/live-rides',
        data: {
          'title': title,
          if (displayName != null && displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
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

  Future<void> stopLive(String sessionId) async {
    await dio.post('/live-rides/$sessionId/stop');
  }

  String viewerUrl(String shareToken) => '$serverOrigin/live/$shareToken';

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
