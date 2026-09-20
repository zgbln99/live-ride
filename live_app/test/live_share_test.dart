import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/models/live_privacy.dart';
import 'package:live_ride/services/live_service.dart';
import 'package:live_ride/services/profile_service.dart';

/// Transport, który zapisuje żądania i oddaje przygotowaną odpowiedź.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter([this.body = '{}']);

  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _api(_RecordingAdapter adapter) {
  final api = ApiClient();
  api.dio = Dio(BaseOptions(baseUrl: 'https://ride.example/api/v1'))
    ..httpClientAdapter = adapter;
  return api;
}

LiveSessionController _controller(ApiClient api) =>
    LiveSessionController(api, ProfileService());

void main() {
  group('adres publicznego podglądu', () {
    test('link LIVE zachowuje kształt /live/<token>', () {
      final api = ApiClient();
      expect(api.viewerUrl('abc123'), '${ApiClient.serverOrigin}/live/abc123');
    });

    test('link trasy to osobna strona /route/<token>', () {
      final api = ApiClient();
      expect(api.routeUrl('def456'), '${ApiClient.serverOrigin}/route/def456');
      // Dwa różne rodzaje linków, ale jeden origin — żadnych alternatywnych
      // domen dla podglądu.
      expect(api.routeUrl('x'), startsWith(ApiClient.serverOrigin));
    });
  });

  group('tekst udostępnienia', () {
    test('używa nazwy zawodnika z profilu, a nie wpisanej na sztywno', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"JOIN"}',
      );
      final api = _api(adapter);
      final profile = ProfileService();
      final live = LiveSessionController(api, profile);

      await live.create(title: 'Sobota');
      final message = live.shareMessage();

      expect(message, contains(profile.riderName));
      expect(message, contains('jedzie teraz na rowerze 🚴'));
      expect(message, contains(api.viewerUrl('tok')));
      // Żadnego „Marek" wpisanego w kod.
      expect(
        message.contains('Marek') && profile.riderName != 'Marek',
        isFalse,
      );
    });
  });

  group('widoczność linku', () {
    test('nieznana wartość z serwera nie upublicznia jazdy', () {
      expect(LiveShareVisibility.parse('public'), LiveShareVisibility.public);
      expect(
        LiveShareVisibility.parse('disabled'),
        LiveShareVisibility.disabled,
      );
      expect(
        LiveShareVisibility.parse('unlisted'),
        LiveShareVisibility.unlisted,
      );
      for (final value in [null, '', 'wszyscy', 'PUBLIC']) {
        expect(
          LiveShareVisibility.parse(value),
          LiveShareVisibility.unlisted,
          reason: 'wartość $value',
        );
      }
    });

    test('ustawienia przechodzą przez JSON', () {
      const settings = LiveShareSettings(
        visibility: LiveShareVisibility.public,
        expiry: LiveShareExpiry.hours24,
      );
      final restored = LiveShareSettings.fromJson(settings.toJson());
      expect(restored.visibility, LiveShareVisibility.public);
      expect(restored.expiry, LiveShareExpiry.hours24);
    });

    test('uszkodzony zapis wraca na najostrożniejsze ustawienie', () {
      final restored = LiveShareSettings.fromJson({
        'visibility': 'nonsens',
        'expiry': 'nigdy-przenigdy',
      });
      expect(restored.visibility, LiveShareVisibility.unlisted);
      expect(restored.expiry, LiveShareExpiry.never);
    });

    test('wygasanie zna godziny albo koniec jazdy, nigdy obu naraz', () {
      expect(LiveShareExpiry.never.hours, isNull);
      expect(LiveShareExpiry.never.expiresOnEnd, isFalse);
      expect(LiveShareExpiry.onEnd.expiresOnEnd, isTrue);
      expect(LiveShareExpiry.onEnd.hours, isNull);
      expect(LiveShareExpiry.hours6.hours, 6);
      expect(LiveShareExpiry.hours6.expiresOnEnd, isFalse);
      expect(LiveShareExpiry.days7.hours, 168);
    });

    test('zmiana widoczności leci na serwer razem z wygasaniem', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"JOIN"}',
      );
      final live = _controller(_api(adapter));
      await live.create();

      adapter.requests.clear();
      await live.updateShare(
        const LiveShareSettings(
          visibility: LiveShareVisibility.public,
          expiry: LiveShareExpiry.hours6,
        ),
      );

      final share = adapter.requests.firstWhere(
        (request) => request.path.endsWith('/share'),
      );
      final body = share.data as Map<String, dynamic>;
      expect(body['visibility'], 'public');
      expect(body['expire_on_end'], isFalse);
      expect(body['expire_in_hours'], 6);
    });

    test(
      'wyłączony link jest zapamiętany lokalnie mimo błędu serwera',
      () async {
        final live = _controller(_api(_RecordingAdapter()));
        // Bez aktywnej sesji nie ma dokąd wysłać, ale wybór ma zostać.
        final ok = await live.updateShare(
          const LiveShareSettings(visibility: LiveShareVisibility.disabled),
        );
        expect(ok, isTrue);
        expect(live.share.visibility, LiveShareVisibility.disabled);
      },
    );

    test('nowy token zastępuje stary w kontrolerze', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"stary","join_token":"JOIN"}',
      );
      final api = _api(adapter);
      final live = _controller(api);
      await live.create();
      expect(live.viewerUrl, endsWith('/live/stary'));

      // Kolejna odpowiedź niesie już nowy token.
      final rotating = _RecordingAdapter('{"share_token":"nowy"}');
      api.dio.httpClientAdapter = rotating;
      expect(await live.rotateShareLink(), isTrue);
      expect(live.viewerUrl, endsWith('/live/nowy'));

      // Poza rotacją na ten transport mogą trafić zaległe żądania z
      // tworzenia sesji (prywatność leci bez czekania), więc filtrujemy.
      final request = rotating.requests.firstWhere(
        (candidate) => candidate.path.endsWith('/share'),
      );
      expect((request.data as Map)['rotate_token'], isTrue);
    });
  });

  group('trasa przypięta do sesji', () {
    test('start LIVE wysyła client_id wczytanej trasy', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok",'
        '"join_token":"JOIN","has_route":true}',
      );
      final live = _controller(_api(adapter));

      final session = await live.create(routeClientId: 'route_42');
      expect(session.hasRoute, isTrue);

      final create = adapter.requests.first;
      expect((create.data as Map)['route_client_id'], 'route_42');
    });

    test('bez trasy pole w ogóle nie leci', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"JOIN"}',
      );
      final live = _controller(_api(adapter));
      await live.create();

      final create = adapter.requests.first;
      expect((create.data as Map).containsKey('route_client_id'), isFalse);
    });
  });

  group('telemetria niesie stan zawodnika', () {
    test('bateria nie opuszcza telefonu bez zgody', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"JOIN"}',
      );
      final live = _controller(_api(adapter));
      await live.create();

      // Domyślnie bateria nie jest udostępniana.
      expect(live.privacy.shareBattery, isFalse);
    });

    test('prywatność zna pole baterii', () {
      const privacy = LivePrivacy(shareBattery: true);
      expect(privacy.toJson()['share_battery'], isTrue);
      expect(
        LivePrivacy.fromJson({'share_battery': true}).shareBattery,
        isTrue,
      );
      // Brak pola w starym zapisie znaczy „nie udostępniam".
      expect(LivePrivacy.fromJson(const {}).shareBattery, isFalse);
    });
  });

  group('pierwsza telemetria po udostępnieniu', () {
    /// Same żądania telemetryczne — `create` wysyła też prywatność.
    List<RequestOptions> telemetry(_RecordingAdapter adapter) => adapter
        .requests
        .where((request) => request.path.endsWith('/telemetry'))
        .toList();

    Map<dynamic, dynamic> lastPoint(_RecordingAdapter adapter) {
      final body = telemetry(adapter).last.data as Map;
      return (body['points'] as List).last as Map;
    }

    /// Pozycja udawana tak, jak przychodzi z systemu.
    Position fix({double lat = 52.23, double lon = 21.01}) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.utc(2026, 5, 1, 9),
      accuracy: 5,
      altitude: 110,
      altitudeAccuracy: 3,
      heading: 92,
      headingAccuracy: 5,
      speed: 0,
      speedAccuracy: 1,
    );

    test('force omija odczekanie między próbkami', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"J"}',
      );
      final live = _controller(_api(adapter));
      await live.create();
      // `create` dosyła jeszcze ustawienia prywatności w tle; interesują nas
      // wyłącznie żądania telemetryczne.
      await pumpEventQueue();

      // Zwykła próbka przechodzi…
      await live.pushPosition(fix(), distanceMeters: 0);
      // …a druga, tuż po niej, zostaje zdławiona.
      await live.pushPosition(fix(), distanceMeters: 0);
      expect(telemetry(adapter).length, 1);

      // Chyba że to ta jedna, która ma dolecieć natychmiast.
      await live.pushPosition(fix(), distanceMeters: 0, force: true);
      expect(telemetry(adapter).length, 2);
    });

    test('stojący zawodnik wysyła pozycję, choć nie przejechał metra', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"J"}',
      );
      final live = _controller(_api(adapter));
      await live.create();
      // `create` dosyła jeszcze ustawienia prywatności w tle; interesują nas
      // wyłącznie żądania telemetryczne.
      await pumpEventQueue();

      await live.pushPosition(
        fix(),
        distanceMeters: 0,
        state: 'stopped',
        force: true,
      );

      final point = lastPoint(adapter);
      expect(point['latitude'], 52.23);
      expect(point['longitude'], 21.01);
      expect(point['state'], 'stopped');
      expect(point['distance_m'], 0);
    });

    test('postoje jadą razem z próbką, rozbite na dwa rodzaje', () async {
      final adapter = _RecordingAdapter(
        '{"id":"s1","participant_id":"p1","share_token":"tok","join_token":"J"}',
      );
      final live = _controller(_api(adapter));
      await live.create();
      // `create` dosyła jeszcze ustawienia prywatności w tle; interesują nas
      // wyłącznie żądania telemetryczne.
      await pumpEventQueue();

      await live.pushPosition(
        fix(),
        distanceMeters: 1200,
        autoPausedSeconds: 130,
        manualPausedSeconds: 45,
        force: true,
      );

      final point = lastPoint(adapter);
      expect(point['auto_paused_seconds'], 130);
      expect(point['manual_paused_seconds'], 45);
    });
  });
}
