import 'package:dio/dio.dart';
import 'package:wanderer/live_ride/live_ride_models.dart';

class LiveRideApi {
  const LiveRideApi(this._dio);

  final Dio _dio;

  Future<LiveRideSession> create({
    required String title,
    String? trailId,
    String? displayName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/live-rides',
      data: {
        'title': title,
        if (trailId != null && trailId.isNotEmpty) 'trail_id': trailId,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
    );
    return LiveRideSession.fromJson(response.data!);
  }

  Future<LiveRideSession> join(
    String joinToken, {
    String? displayName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/live-rides/join',
      data: {
        'join_token': joinToken.trim().toUpperCase(),
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
    );
    return LiveRideSession.fromJson(response.data!);
  }

  Future<void> sendTelemetry(
    String sessionId,
    List<LiveRideTelemetryPoint> points,
  ) async {
    if (points.isEmpty) return;
    if (points.length > 100) {
      throw ArgumentError.value(points.length, 'points.length', 'max 100');
    }
    await _dio.post<void>(
      '/live-rides/$sessionId/telemetry',
      data: {'points': points.map((point) => point.toJson()).toList()},
    );
  }

  String viewerUrl(String shareToken) {
    final apiBase = Uri.parse(_dio.options.baseUrl);
    var basePath = apiBase.path;
    if (basePath.endsWith('/api/v1')) {
      basePath = basePath.substring(0, basePath.length - '/api/v1'.length);
    } else if (basePath.endsWith('/api/v1/')) {
      basePath = basePath.substring(0, basePath.length - '/api/v1/'.length);
    }
    final path = '${basePath.replaceAll(RegExp(r'/$'), '')}/live/$shareToken';
    return apiBase.replace(path: path, query: null, fragment: null).toString();
  }

  Future<void> stop(String sessionId) async {
    await _dio.post<void>('/live-rides/$sessionId/stop');
  }
}
