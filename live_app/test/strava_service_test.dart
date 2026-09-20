import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/models/integration.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/services/strava_service.dart';

/// Podstawiony transport: zwraca to, co test każe, i zapamiętuje żądania.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: StravaService.apiBase));
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(
      _encode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

String _encode(Map<String, dynamic> body) {
  final buffer = StringBuffer('{');
  var first = true;
  body.forEach((key, value) {
    if (!first) buffer.write(',');
    first = false;
    buffer.write('"$key":');
    if (value is String) {
      buffer.write('"$value"');
    } else if (value is Map<String, dynamic>) {
      buffer.write(_encode(value));
    } else {
      buffer.write('$value');
    }
  });
  buffer.write('}');
  return buffer.toString();
}

RecordedRide _ride() => RecordedRide(
  id: 'ride-1',
  name: 'Poranna jazda',
  startedAt: DateTime(2026, 5, 1, 7),
  endedAt: DateTime(2026, 5, 1, 8),
  elapsedSeconds: 3600,
  movingSeconds: 3400,
  distanceMeters: 30000,
  elevationGainMeters: 300,
  points: const [],
);

void main() {
  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('strava');
    file = File('${temp.path}/ride.tcx')..writeAsStringSync('<xml/>');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('poświadczenia', () {
    test('bez client ID i sekretu nic nie jest skonfigurowane', () {
      const credentials = IntegrationCredentials(
        provider: IntegrationProvider.strava,
      );
      expect(credentials.isConfigured, isFalse);
      expect(credentials.status, IntegrationStatus.unconfigured);
    });

    test('samo client ID nie wystarcza Stravie', () {
      const credentials = IntegrationCredentials(
        provider: IntegrationProvider.strava,
        clientId: '12345',
      );
      expect(credentials.isConfigured, isFalse);
    });

    test('komplet daje stan „wylogowany", a nie „połączony"', () {
      const credentials = IntegrationCredentials(
        provider: IntegrationProvider.strava,
        clientId: '12345',
        clientSecret: 'sekret',
      );
      expect(credentials.isConfigured, isTrue);
      expect(credentials.status, IntegrationStatus.signedOut);
    });

    test('token bliski wygaśnięcia liczy się jako wygasły', () {
      final credentials = IntegrationCredentials(
        provider: IntegrationProvider.strava,
        clientId: '1',
        clientSecret: 's',
        accessToken: 'token',
        expiresAt: DateTime.now().add(const Duration(seconds: 20)),
      );
      expect(credentials.isExpired, isTrue);
    });

    test('serwisy bez publicznego API mówią to wprost', () {
      for (final provider in [
        IntegrationProvider.komoot,
        IntegrationProvider.garmin,
      ]) {
        expect(provider.hasPublicApi, isFalse);
        expect(
          IntegrationCredentials(provider: provider).status,
          IntegrationStatus.unavailable,
        );
      }
      expect(IntegrationProvider.strava.hasPublicApi, isTrue);
    });
  });

  group('logowanie', () {
    test('bez poświadczeń nie otwiera przeglądarki', () async {
      var opened = false;
      final service = StravaService(
        client: _dio(_StubAdapter((_) async => _json({}))),
        opener: (url, scheme) async {
          opened = true;
          return '';
        },
      );
      expect(await service.connect(), isFalse);
      expect(opened, isFalse);
      expect(service.lastError, isNotNull);
    });

    test('wymienia kod na token i zapamiętuje zawodnika', () async {
      final adapter = _StubAdapter(
        (options) async => _json({
          'access_token': 'abc',
          'refresh_token': 'ref',
          'expires_at': 4102444800,
          'athlete': {'firstname': 'Marek', 'lastname': 'P'},
        }),
      );
      late String openedUrl;
      final service = StravaService(
        client: _dio(adapter),
        opener: (url, scheme) async {
          openedUrl = url;
          final state = Uri.parse(url).queryParameters['state'];
          return '${StravaService.redirectUri}?code=kod&state=$state';
        },
      );
      await service.setCredentials(clientId: '123', clientSecret: 'sekret');

      expect(await service.connect(), isTrue);
      expect(service.isConnected, isTrue);
      expect(service.credentials.athleteName, 'Marek P');
      expect(openedUrl, contains('client_id=123'));
      expect(openedUrl, contains('activity%3Awrite'));
    });

    test('podmieniony state jest odrzucany', () async {
      final service = StravaService(
        client: _dio(_StubAdapter((_) async => _json({}))),
        opener: (url, scheme) async =>
            '${StravaService.redirectUri}?code=kod&state=obce',
      );
      await service.setCredentials(clientId: '123', clientSecret: 'sekret');
      expect(await service.connect(), isFalse);
      expect(service.isConnected, isFalse);
    });

    test('odmowa zgody nie wygląda jak błąd sieci', () async {
      final service = StravaService(
        client: _dio(_StubAdapter((_) async => _json({}))),
        opener: (url, scheme) async {
          final state = Uri.parse(url).queryParameters['state'];
          return '${StravaService.redirectUri}?error=access_denied&state=$state';
        },
      );
      await service.setCredentials(clientId: '123', clientSecret: 'sekret');
      expect(await service.connect(), isFalse);
      expect(service.lastError, contains('zgodziłeś'));
    });
  });

  group('wysyłka', () {
    Future<StravaService> connected(_StubAdapter adapter) async {
      final service = StravaService(
        client: _dio(adapter),
        opener: (url, scheme) async {
          final state = Uri.parse(url).queryParameters['state'];
          return '${StravaService.redirectUri}?code=kod&state=$state';
        },
      );
      await service.setCredentials(clientId: '123', clientSecret: 'sekret');
      await service.connect();
      return service;
    }

    test('czeka na przetworzenie, zanim powie „wysłano"', () async {
      var polls = 0;
      final adapter = _StubAdapter((options) async {
        if (options.path.contains('oauth/token')) {
          return _json({
            'access_token': 'abc',
            'refresh_token': 'ref',
            'expires_at': 4102444800,
          });
        }
        if (options.method == 'POST') return _json({'id_str': '99'});
        polls++;
        // Pierwsze odpytanie: jeszcze przetwarza.
        return polls == 1
            ? _json({'id_str': '99', 'activity_id': null})
            : _json({'id_str': '99', 'activity_id': 555});
      });

      final service = await connected(adapter);
      final upload = await service.uploadRide(_ride(), file);
      expect(upload.state, UploadState.done);
      expect(upload.remoteId, '555');
      expect(polls, greaterThanOrEqualTo(2));
    });

    test('błąd przetwarzania wraca jako komunikat Stravy', () async {
      final adapter = _StubAdapter((options) async {
        if (options.path.contains('oauth/token')) {
          return _json({'access_token': 'abc', 'expires_at': 4102444800});
        }
        if (options.method == 'POST') return _json({'id_str': '99'});
        return _json({'error': 'duplicate of activity 42'});
      });

      final service = await connected(adapter);
      final upload = await service.uploadRide(_ride(), file);
      expect(upload.state, UploadState.failed);
      expect(upload.error, contains('duplicate'));
    });

    test('bez tokenu wysyłka nie udaje, że poszła', () async {
      final service = StravaService(
        client: _dio(_StubAdapter((_) async => _json({}))),
      );
      await service.setCredentials(clientId: '123', clientSecret: 'sekret');
      final upload = await service.uploadRide(_ride(), file);
      expect(upload.state, UploadState.failed);
    });

    test('limit zapytań ma własny komunikat', () async {
      final adapter = _StubAdapter((options) async {
        if (options.path.contains('oauth/token')) {
          return _json({'access_token': 'abc', 'expires_at': 4102444800});
        }
        return _json({'message': 'Rate Limit Exceeded'}, status: 429);
      });
      final service = await connected(adapter);
      final upload = await service.uploadRide(_ride(), file);
      expect(upload.state, UploadState.failed);
      expect(upload.error, contains('ogranicza'));
    });
  });

  group('adres powrotny OAuth', () {
    test('host odpowiada domenie, którą wpisuje się w ustawieniach Stravy', () {
      // To jest cała przyczyna błędu z telefonu: Strava sprawdza DOMENĘ
      // adresu powrotnego, a `liveride://strava-callback` ma jako domenę
      // „strava-callback" — czegoś takiego nie da się tam wpisać.
      final uri = Uri.parse(StravaService.redirectUri);
      expect(uri.scheme, StravaService.callbackScheme);
      expect(uri.host, StravaService.callbackHost);
      expect(uri.path, StravaService.callbackPath);
      // Domena musi wyglądać jak domena, a nie jak nazwa akcji.
      expect(uri.host, contains('.'));
    });

    test('host bierze się z originu Live Ride, a nie z drugiego miejsca', () {
      final origin = Uri.parse(ApiClient.serverOrigin);
      expect(StravaService.callbackHost, origin.host);
    });

    test('logowanie idzie na mobilny punkt autoryzacji', () {
      // Wersja webowa odrzuca własne schematy adresów.
      expect(StravaService.authorizeUrl, contains('/oauth/mobile/authorize'));
    });

    test('ekran konfiguracji podaje domenę, a nie schemat', () {
      // Instrukcja kazała wcześniej wpisać „liveride" — czyli dokładnie tę
      // wartość, przez którą Strava odrzucała logowanie.
      final screen = File(
        'lib/screens/integrations_screen.dart',
      ).readAsStringSync();
      expect(screen, contains('StravaService.callbackHost'));
      expect(
        screen.contains("SelectableText(\n                'liveride'"),
        isFalse,
      );
    });

    test('nie koliduje z callbackiem Spotify', () {
      // Ten sam schemat, inna ścieżka. Bez tego rozróżnienia kod autoryzacji
      // jednej usługi mógłby trafić do drugiej.
      expect(
        StravaService.isOurCallback(
          Uri.parse('liveride://ride.example.test/strava-callback?code=x'),
        ),
        isTrue,
      );
      expect(
        StravaService.isOurCallback(
          Uri.parse('liveride://spotify-callback?code=x'),
        ),
        isFalse,
      );
      expect(
        StravaService.isOurCallback(
          Uri.parse('https://evil.example/strava-callback?code=x'),
        ),
        isFalse,
      );
    });
  });

  group('przebieg logowania', () {
    /// Serwis z podstawionym oknem logowania i transportem.
    ({StravaService service, List<String> opened}) wired(
      String Function(Uri authorize) respond, {
      Future<ResponseBody> Function(RequestOptions options)? token,
    }) {
      final opened = <String>[];
      final adapter = _StubAdapter(
        token ??
            (options) async => _json({
              'access_token': 'at',
              'refresh_token': 'rt',
              'expires_at':
                  DateTime.now()
                      .add(const Duration(hours: 6))
                      .millisecondsSinceEpoch ~/
                  1000,
              'athlete': {'firstname': 'Marek', 'lastname': 'P'},
            }),
      );
      final service = StravaService(
        client: _dio(adapter),
        opener: (url, scheme) async {
          opened.add(url);
          return respond(Uri.parse(url));
        },
      );
      return (service: service, opened: opened);
    }

    Future<void> configure(StravaService service) =>
        service.setCredentials(clientId: '12345', clientSecret: 'sekret');

    test('żądanie niesie poprawny redirect_uri i stan', () async {
      final wiring = wired(
        (authorize) =>
            '${StravaService.redirectUri}'
            '?state=${authorize.queryParameters['state']}&code=abc',
      );
      await configure(wiring.service);
      expect(await wiring.service.connect(), isTrue);

      final sent = Uri.parse(wiring.opened.single);
      expect(sent.queryParameters['redirect_uri'], StravaService.redirectUri);
      expect(sent.queryParameters['client_id'], '12345');
      expect(sent.queryParameters['state'], isNotEmpty);
      expect(sent.queryParameters['response_type'], 'code');
      expect(wiring.service.isConnected, isTrue);
    });

    test('stan wraca ten sam, którym wyszliśmy', () async {
      String? issued;
      final wiring = wired((authorize) {
        issued = authorize.queryParameters['state'];
        return '${StravaService.redirectUri}?state=$issued&code=abc';
      });
      await configure(wiring.service);
      await wiring.service.connect();

      expect(issued, isNotNull);
      expect(issued!.length, greaterThanOrEqualTo(16));
    });

    test('podmieniony stan przerywa logowanie', () async {
      // Bez tej kontroli ktoś mógłby podrzucić własny kod autoryzacji.
      final wiring = wired(
        (authorize) => '${StravaService.redirectUri}?state=cudzy&code=abc',
      );
      await configure(wiring.service);

      expect(await wiring.service.connect(), isFalse);
      expect(wiring.service.isConnected, isFalse);
      expect(wiring.service.lastError, isNotNull);
    });

    test('odmowa użytkownika to zwykła informacja, nie awaria', () async {
      final wiring = wired(
        (authorize) =>
            '${StravaService.redirectUri}'
            '?state=${authorize.queryParameters['state']}&error=access_denied',
      );
      await configure(wiring.service);

      expect(await wiring.service.connect(), isFalse);
      expect(wiring.service.lastError, 'Nie zgodziłeś się na dostęp.');
    });

    test('callback Spotify nie jest brany za odpowiedź Stravy', () async {
      final wiring = wired(
        (authorize) =>
            'liveride://spotify-callback'
            '?state=${authorize.queryParameters['state']}&code=abc',
      );
      await configure(wiring.service);

      expect(await wiring.service.connect(), isFalse);
      expect(wiring.service.isConnected, isFalse);
    });

    test('wymiana kodu na token zapisuje konto', () async {
      final wiring = wired(
        (authorize) =>
            '${StravaService.redirectUri}'
            '?state=${authorize.queryParameters['state']}&code=abc',
      );
      await configure(wiring.service);
      await wiring.service.connect();

      expect(wiring.service.credentials.accessToken, 'at');
      expect(wiring.service.credentials.refreshToken, 'rt');
      expect(wiring.service.credentials.athleteName, contains('Marek'));
    });

    test('bez poświadczeń nie otwiera nawet okna', () async {
      final wiring = wired((authorize) => '');
      expect(await wiring.service.connect(), isFalse);
      expect(wiring.opened, isEmpty);
      expect(wiring.service.lastError, isNotNull);
    });
  });

  group('odświeżanie tokenu', () {
    test('wygasły token wymienia się na nowy', () async {
      final adapter = _StubAdapter(
        (options) async => _json({
          'access_token': 'nowy',
          'refresh_token': 'rt2',
          'expires_at':
              DateTime.now()
                  .add(const Duration(hours: 6))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
      );
      final service = StravaService(client: _dio(adapter));
      await service.setCredentials(clientId: '1', clientSecret: 's');
      await service.applyTokenForTest({
        'access_token': 'stary',
        'refresh_token': 'rt1',
        'expires_at':
            DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });

      expect(await service.ensureFreshToken(), isTrue);
      expect(service.credentials.accessToken, 'nowy');
      final body = adapter.requests.last.data as Map;
      expect(body['grant_type'], 'refresh_token');
      expect(body['refresh_token'], 'rt1');
    });

    test('ważny token nie jest odświeżany bez potrzeby', () async {
      final adapter = _StubAdapter((options) async => _json({}));
      final service = StravaService(client: _dio(adapter));
      await service.setCredentials(clientId: '1', clientSecret: 's');
      await service.applyTokenForTest({
        'access_token': 'at',
        'refresh_token': 'rt',
        'expires_at':
            DateTime.now()
                .add(const Duration(hours: 5))
                .millisecondsSinceEpoch ~/
            1000,
      });

      expect(await service.ensureFreshToken(), isTrue);
      expect(adapter.requests, isEmpty);
    });
  });

  group('błędy konfiguracji mówią, co poprawić', () {
    test('odrzucony redirect_uri wskazuje domenę do wpisania', () {
      // Dokładna odpowiedź, którą zwraca Strava przy złej konfiguracji.
      final message = StravaService.configurationProblem({
        'message': 'Bad Request',
        'errors': [
          {
            'resource': 'Application',
            'field': 'redirect_uri',
            'code': 'invalid',
          },
        ],
      });

      expect(message, isNotNull);
      expect(message, contains(StravaService.callbackHost));
      expect(message, contains('Authorization Callback Domain'));
      // Żadnego surowego JSON-a ani angielskiego „Bad Request".
      expect(message, isNot(contains('Bad Request')));
      expect(message, isNot(contains('{')));
    });

    test('zły client_id prowadzi do ustawień aplikacji', () {
      final message = StravaService.configurationProblem({
        'errors': [
          {'field': 'client_id', 'code': 'invalid'},
        ],
      });
      expect(message, contains('Client ID'));
    });

    test('inny błąd nie udaje problemu z konfiguracją', () {
      expect(
        StravaService.configurationProblem({'message': 'Bad Request'}),
        isNull,
      );
      expect(StravaService.configurationProblem(null), isNull);
      expect(
        StravaService.configurationProblem({
          'errors': [
            {'field': 'activity', 'code': 'invalid'},
          ],
        }),
        isNull,
      );
    });
  });
}
