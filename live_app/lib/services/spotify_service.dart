import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../models/music.dart';
import 'local_store.dart';

/// Raised for anything a rider needs to read, rather than a stack trace.
class SpotifyException implements Exception {
  const SpotifyException(this.message, {this.needsPremium = false});

  final String message;

  /// True when the Spotify account cannot do this at all, so the UI offers an
  /// explanation instead of a retry button.
  final bool needsPremium;

  @override
  String toString() => message;
}

enum SpotifyStatus { unconfigured, signedOut, connecting, connected }

/// Spotify sign-in and playback control.
///
/// Authorization Code with PKCE, which is the flow Spotify documents for
/// mobile apps: no client secret is compiled into the app, and the browser
/// session runs in ASWebAuthenticationSession on iOS so the rider's Spotify
/// cookie is never handed to Live Ride.
///
/// Playback uses the Web API player endpoints, which control whatever device
/// the account is playing on — including the Spotify app on the same phone.
class SpotifyService extends ChangeNotifier {
  SpotifyService({Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  /// The custom scheme registered in Info.plist by `bootstrap.sh`. It must
  /// match the redirect URI registered in the Spotify dashboard exactly.
  static const String redirectUri = 'liveride://spotify-callback';
  static const String callbackScheme = 'liveride';

  static const String _authorizeUrl = 'https://accounts.spotify.com/authorize';
  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  static const String _apiBase = 'https://api.spotify.com/v1';

  /// Read now-playing, control playback, and list something to start from.
  static const List<String> scopes = [
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
    'user-read-recently-played',
    'playlist-read-private',
  ];

  /// Optional build-time client id. A rider can also paste one into the app,
  /// which is what makes this testable on a device without a rebuild.
  static const String buildTimeClientId = String.fromEnvironment(
    'LIVE_RIDE_SPOTIFY_CLIENT_ID',
  );

  final Dio _dio;
  final LocalStore _store = LocalStore('spotify');

  String _clientId = buildTimeClientId;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? _displayName;
  String? _product;
  String? _lastError;

  SpotifyStatus _status = SpotifyStatus.signedOut;
  NowPlaying? _nowPlaying;
  List<SpotifyDevice> _devices = const [];
  List<MusicItem> _shortcuts = const [];
  Timer? _pollTimer;
  bool _polling = false;

  // ---------------------------------------------------------------- getters

  SpotifyStatus get status => _status;
  String get clientId => _clientId;
  bool get isConfigured => _clientId.trim().isNotEmpty;
  bool get isConnected => _status == SpotifyStatus.connected;
  String? get displayName => _displayName;
  String? get lastError => _lastError;
  NowPlaying? get nowPlaying => _nowPlaying;
  List<SpotifyDevice> get devices => _devices;
  List<MusicItem> get shortcuts => _shortcuts;

  /// Spotify only allows playback control on Premium accounts.
  bool get isPremium => _product == null || _product == 'premium';

  // ------------------------------------------------------------- lifecycle

  Future<void> restore() async {
    final config = await _store.readJson('config.json');
    final storedId = (config?['client_id'] as String? ?? '').trim();
    if (storedId.isNotEmpty) _clientId = storedId;

    final session = await _store.readJson('session.json');
    _accessToken = session?['access_token'] as String?;
    _refreshToken = session?['refresh_token'] as String?;
    final expiry = session?['expires_at'] as String?;
    _expiresAt = expiry == null ? null : DateTime.tryParse(expiry);
    _displayName = session?['display_name'] as String?;
    _product = session?['product'] as String?;

    _status = !isConfigured
        ? SpotifyStatus.unconfigured
        : _refreshToken == null
        ? SpotifyStatus.signedOut
        : SpotifyStatus.connected;
    notifyListeners();

    if (_status == SpotifyStatus.connected) {
      unawaited(refreshNowPlaying());
    }
  }

  Future<void> setClientId(String value) async {
    _clientId = value.trim();
    await _store.writeJson('config.json', {'client_id': _clientId});
    if (!isConfigured) {
      _status = SpotifyStatus.unconfigured;
    } else if (_refreshToken == null) {
      _status = SpotifyStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> _saveSession() async {
    await _store.writeJson('session.json', {
      'access_token': _accessToken,
      'refresh_token': _refreshToken,
      'expires_at': _expiresAt?.toIso8601String(),
      'display_name': _displayName,
      'product': _product,
    });
  }

  // ------------------------------------------------------------------- auth

  /// Runs the PKCE flow. Throws [SpotifyException] with a readable message.
  Future<void> connect() async {
    if (!isConfigured) {
      throw const SpotifyException(
        'Add your Spotify client ID first. Create a free app at '
        'developer.spotify.com, add $redirectUri as a redirect URI, then '
        'paste the client ID here.',
      );
    }

    _status = SpotifyStatus.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final verifier = _createVerifier();
      final challenge = _challengeFor(verifier);
      final state = _randomString(16);

      final authUrl = Uri.parse(_authorizeUrl).replace(
        queryParameters: {
          'client_id': _clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'code_challenge_method': 'S256',
          'code_challenge': challenge,
          'scope': scopes.join(' '),
          'state': state,
        },
      );

      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: callbackScheme,
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );

      final returned = Uri.parse(result);
      final error = returned.queryParameters['error'];
      if (error != null) {
        throw SpotifyException(
          error == 'access_denied'
              ? 'Spotify access was declined.'
              : 'Spotify returned "$error".',
        );
      }
      if (returned.queryParameters['state'] != state) {
        throw const SpotifyException(
          'The Spotify response did not match this request and was ignored.',
        );
      }
      final code = returned.queryParameters['code'];
      if (code == null) {
        throw const SpotifyException(
          'Spotify did not return an authorization code.',
        );
      }

      await _exchange({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': _clientId,
        'code_verifier': verifier,
      });

      await _loadProfile();
      _status = SpotifyStatus.connected;
      notifyListeners();
      await refreshNowPlaying();
    } on SpotifyException {
      _status = _refreshToken == null
          ? SpotifyStatus.signedOut
          : SpotifyStatus.connected;
      notifyListeners();
      rethrow;
    } catch (e) {
      _status = SpotifyStatus.signedOut;
      _lastError = _describe(e);
      notifyListeners();
      throw SpotifyException(_lastError!);
    }
  }

  Future<void> disconnect() async {
    stopPolling();
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _displayName = null;
    _product = null;
    _nowPlaying = null;
    _devices = const [];
    _shortcuts = const [];
    _status = isConfigured
        ? SpotifyStatus.signedOut
        : SpotifyStatus.unconfigured;
    await _store.deleteFile('session.json');
    notifyListeners();
  }

  Future<void> _exchange(Map<String, String> form) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _tokenUrl,
      data: form,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final data = response.data;
    if (response.statusCode != 200 || data == null) {
      final description = data?['error_description'] ?? data?['error'];
      throw SpotifyException(
        'Spotify refused the sign-in'
        '${description == null ? '.' : ': $description.'}',
      );
    }
    _accessToken = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (refresh != null) _refreshToken = refresh;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
    await _saveSession();
  }

  /// Returns a usable access token, refreshing it when it is about to expire.
  Future<String> _token() async {
    final expiry = _expiresAt;
    final token = _accessToken;
    if (token != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return token;
    }
    final refresh = _refreshToken;
    if (refresh == null) {
      throw const SpotifyException('Sign in to Spotify again.');
    }
    await _exchange({
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
      'client_id': _clientId,
    });
    final refreshed = _accessToken;
    if (refreshed == null) {
      throw const SpotifyException('Spotify did not return a new token.');
    }
    return refreshed;
  }

  // ------------------------------------------------------------------- api

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final token = await _token();
    final response = await _dio.request<dynamic>(
      '$_apiBase$path',
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer $token'},
        contentType: Headers.jsonContentType,
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 401) {
      throw const SpotifyException('Spotify signed you out. Connect again.');
    }
    if (status == 403) {
      throw const SpotifyException(
        'Spotify Premium is required to control playback from another app.',
        needsPremium: true,
      );
    }
    if (status == 429) {
      throw const SpotifyException(
        'Spotify is rate limiting; try again shortly.',
      );
    }
    return response;
  }

  Future<void> _loadProfile() async {
    final response = await _request('GET', '/me');
    final data = response.data;
    if (data is Map) {
      _displayName = data['display_name'] as String?;
      _product = data['product'] as String?;
      await _saveSession();
    }
  }

  /// Polls the player while a music surface is on screen or a ride is running.
  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    if (!isConnected) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      interval,
      (_) => unawaited(refreshNowPlaying()),
    );
    unawaited(refreshNowPlaying());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refreshNowPlaying() async {
    if (!isConnected || _polling) return;
    _polling = true;
    try {
      final response = await _request('GET', '/me/player');
      // 204 means nothing is playing anywhere, which is a state, not a fault.
      if (response.statusCode == 204 || response.data == null) {
        _nowPlaying = null;
      } else if (response.data is Map) {
        _nowPlaying = NowPlaying.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
      _lastError = null;
    } on SpotifyException catch (e) {
      _lastError = e.message;
    } catch (e) {
      _lastError = _describe(e);
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  Future<void> refreshDevices() async {
    final response = await _request('GET', '/me/player/devices');
    final data = response.data;
    if (data is Map && data['devices'] is List) {
      _devices = (data['devices'] as List)
          .whereType<Map>()
          .map(
            (item) => SpotifyDevice.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
      notifyListeners();
    }
  }

  /// Recently played contexts, which is what a rider actually restarts.
  Future<void> refreshShortcuts() async {
    final items = <MusicItem>[];
    final seen = <String>{};
    try {
      final recent = await _request(
        'GET',
        '/me/player/recently-played',
        query: {'limit': 20},
      );
      final data = recent.data;
      if (data is Map && data['items'] is List) {
        for (final entry in (data['items'] as List).whereType<Map>()) {
          final context = entry['context'];
          final track = entry['track'];
          final uri = context is Map
              ? context['uri'] as String?
              : track is Map
              ? (track['album'] is Map
                    ? (track['album'] as Map)['uri'] as String?
                    : null)
              : null;
          if (uri == null || !seen.add(uri)) continue;
          final album = track is Map ? track['album'] : null;
          final images = album is Map ? album['images'] : null;
          String? artwork;
          if (images is List && images.isNotEmpty && images.last is Map) {
            artwork = (images.last as Map)['url'] as String?;
          }
          items.add(
            MusicItem(
              uri: uri,
              title: album is Map
                  ? (album['name'] as String? ?? 'Recently played')
                  : 'Recently played',
              subtitle: track is Map ? (track['name'] as String? ?? '') : '',
              artworkUrl: artwork,
            ),
          );
        }
      }
    } catch (_) {
      // Shortcuts are a convenience; a failure must not break the page.
    }

    try {
      final playlists = await _request(
        'GET',
        '/me/playlists',
        query: {'limit': 20},
      );
      final data = playlists.data;
      if (data is Map && data['items'] is List) {
        for (final entry in (data['items'] as List).whereType<Map>()) {
          final uri = entry['uri'] as String?;
          if (uri == null || !seen.add(uri)) continue;
          final images = entry['images'];
          String? artwork;
          if (images is List && images.isNotEmpty && images.first is Map) {
            artwork = (images.first as Map)['url'] as String?;
          }
          final owner = entry['owner'];
          items.add(
            MusicItem(
              uri: uri,
              title: entry['name'] as String? ?? 'Playlist',
              subtitle: owner is Map
                  ? 'Playlist · ${owner['display_name'] ?? ''}'
                  : 'Playlist',
              artworkUrl: artwork,
            ),
          );
        }
      }
    } catch (_) {}

    _shortcuts = List.unmodifiable(items);
    notifyListeners();
  }

  // -------------------------------------------------------------- playback

  Future<void> playPause() async {
    final playing = _nowPlaying?.isPlaying ?? false;
    await _control(playing ? 'pause' : 'play');
  }

  Future<void> next() => _control('next');

  Future<void> previous() => _control('previous');

  Future<void> setShuffle(bool value) async {
    await _request(
      'PUT',
      '/me/player/shuffle',
      query: {'state': value.toString()},
    );
    await refreshNowPlaying();
  }

  Future<void> setVolume(int percent) async {
    await _request(
      'PUT',
      '/me/player/volume',
      query: {'volume_percent': percent.clamp(0, 100).toString()},
    );
    await refreshNowPlaying();
  }

  Future<void> transferTo(SpotifyDevice device) async {
    await _request(
      'PUT',
      '/me/player',
      body: {
        'device_ids': [device.id],
        'play': true,
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refreshNowPlaying();
  }

  Future<void> playContext(MusicItem item) async {
    await _request('PUT', '/me/player/play', body: {'context_uri': item.uri});
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refreshNowPlaying();
  }

  Future<void> _control(String action) async {
    final method = action == 'next' || action == 'previous' ? 'POST' : 'PUT';
    final response = await _request(method, '/me/player/$action');
    if (response.statusCode == 404) {
      throw const SpotifyException(
        'Spotify has no active device. Start a track in the Spotify app once, '
        'then come back — Live Ride takes over from there.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await refreshNowPlaying();
  }

  // ------------------------------------------------------------------ PKCE

  String _createVerifier() => _randomString(96);

  String _challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  String _randomString(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _describe(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'Spotify timed out.',
        DioExceptionType.connectionError => 'No connection to Spotify.',
        _ => 'Spotify request failed.',
      };
    }
    final text = error.toString();
    if (text.contains('CANCELED') || text.contains('canceled')) {
      return 'Spotify sign-in was cancelled.';
    }
    return text;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
