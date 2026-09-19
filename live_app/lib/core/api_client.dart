import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ride_route.dart';

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
        participantId: json['participant_id'] as String,
        shareToken: json['share_token'] as String,
        joinToken: json['join_token'] as String,
      );
}

class ApiClient {
  static const String serverOrigin = 'https://ride.76-13-3-214.sslip.io';

  late final Dio dio;
  late final PersistCookieJar cookieJar;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/cookies'),
      ignoreExpires: false,
    );
    dio = Dio(
      BaseOptions(
        baseUrl: '$serverOrigin/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(CookieManager(cookieJar));
  }

  Future<bool> hasSession() async {
    // PersistCookieJar already drops expired cookies when ignoreExpires=false,
    // so the presence of pb_auth is enough to restore the local session.
    final cookies = await cookieJar.loadForRequest(Uri.parse(serverOrigin));
    return cookies.any((c) => c.name == 'pb_auth');
  }

  Future<void> login(String username, String password) async {
    await dio.post(
      '/auth/login',
      data: {'username': username.trim(), 'password': password},
    );
  }

  Future<void> register(String username, String email, String password) async {
    await dio.put(
      '/user',
      data: {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'passwordConfirm': password,
      },
    );
    await login(username, password);
  }

  Future<void> logout() async {
    await cookieJar.deleteAll();
  }

  Future<String> fetchMapStyle() async {
    final response = await dio.get('/map/style', queryParameters: {'theme': 'liberty'});
    final data = response.data;
    if (data is String) return data;
    if (data is Map || data is List) return jsonEncode(data);
    throw StateError('Map style response is invalid');
  }

  Future<NavigationPlan> buildNavigation(RideRoute route) async {
    final sampled = _sampleShape(route.points, 500);
    try {
      final response = await dio.post(
        '/valhalla/navigate',
        data: {
          'shape': [for (final p in sampled) {'lat': p.lat, 'lon': p.lon}],
          'costing': 'bicycle',
        },
      );
      final plan = NavigationPlan.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      if (plan.shape.length < 2) return NavigationPlan.fallback(route);
      return plan;
    } on DioException {
      return NavigationPlan.fallback(route);
    } catch (_) {
      return NavigationPlan.fallback(route);
    }
  }

  Future<LiveSession> createLive({
    required String title,
    String? displayName,
  }) async {
    final response = await dio.post(
      '/live-rides',
      data: {
        'title': title,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
    return LiveSession.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<LiveSession> joinLive(String code, {String? displayName}) async {
    final response = await dio.post(
      '/live-rides/join',
      data: {
        'join_token': code.trim().toUpperCase(),
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
    return LiveSession.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> sendTelemetry(String sessionId, Map<String, dynamic> point) async {
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

  List<RidePoint> _sampleShape(List<RidePoint> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / (maxPoints - 1)).ceil();
    final out = <RidePoint>[];
    for (var i = 0; i < points.length; i += step) {
      out.add(points[i]);
    }
    if (out.last != points.last) out.add(points.last);
    return out;
  }
}
