import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/data/database.dart';
import 'package:live_ride/data/ride_dao.dart';
import 'package:live_ride/data/route_dao.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Testy wysyłki przejazdów chodzą po prawdziwym SQLite i prawdziwym kliencie
/// Dio z podmienionym transportem. Atrapa DAO nie sprawdziłaby tego, co
/// naprawdę boli: czy rekord ZOSTAJE w kolejce, gdy serwer go nie potwierdzi.
LiveRideDatabase inMemoryDatabase() =>
    LiveRideDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

/// Transport, który odpowiada tym, co mu każemy, i liczy żądania.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// Klient API z podmienionym transportem — bez sieci i bez ciasteczek.
ApiClient _api(_FakeAdapter adapter) {
  final api = ApiClient();
  api.dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
    ..httpClientAdapter = adapter;
  return api;
}

RecordedRide _ride(String id) => RecordedRide(
  id: id,
  name: 'Przejazd $id',
  startedAt: DateTime.utc(2026, 5, 1, 7),
  endedAt: DateTime.utc(2026, 5, 1, 8),
  elapsedSeconds: 3600,
  movingSeconds: 3400,
  distanceMeters: 30000,
  elevationGainMeters: 300,
  elevationLossMeters: 300,
  maxSpeedKmh: 48,
  points: [
    for (var i = 0; i < 5; i++)
      RecordedRidePoint(
        lat: 52.0 + i * 0.001,
        lon: 21.0 + i * 0.001,
        recordedAt: DateTime.utc(2026, 5, 1, 7).add(Duration(seconds: i)),
        distanceMeters: i * 10.0,
      ),
  ],
);

void main() {
  sqfliteFfiInit();

  late LiveRideDatabase database;
  late RideDao rides;
  late RouteDao routes;

  setUp(() async {
    database = inMemoryDatabase();
    rides = RideDao(database);
    routes = RouteDao(database);
  });

  tearDown(() async => database.close());

  Future<SyncService> serviceWith(_FakeAdapter adapter) async =>
      SyncService(api: _api(adapter), rides: rides, routes: routes);

  group('wysyłka przejazdów', () {
    test('potwierdzony przejazd znika z kolejki', () async {
      await rides.save(_ride('ride_1'));
      expect((await rides.pendingSync()).length, 1);

      final adapter = _FakeAdapter(
        (_) => _json('{"synced":[{"client_id":"ride_1","id":"srv_1"}]}'),
      );
      final sync = await serviceWith(adapter);

      expect(await sync.flush(force: true), isTrue);
      expect(await rides.pendingSync(), isEmpty);
      expect(sync.failure, isNull);
      expect(sync.phase, SyncPhase.idle);
    });

    test(
      'ponowna wysyłka tego samego client_id nie tworzy duplikatu',
      () async {
        await rides.save(_ride('ride_1'));
        final adapter = _FakeAdapter(
          (_) => _json('{"synced":[{"client_id":"ride_1","id":"srv_1"}]}'),
        );
        final sync = await serviceWith(adapter);

        await sync.flush(force: true);
        // Drugi przebieg nie ma już czego wysyłać, więc nie leci żadne żądanie.
        await sync.flush(force: true);

        final rideRequests = adapter.requests
            .where((request) => request.path.endsWith('/sync/rides'))
            .toList();
        expect(rideRequests.length, 1);
        // A gdyby telefon wysłał to samo jeszcze raz, identyfikatorem
        // rozpoznawczym jest client_id nadany lokalnie.
        final payload = rideRequests.first.data as Map<String, dynamic>;
        final sent = (payload['rides'] as List).first as Map<String, dynamic>;
        expect(sent['client_id'], 'ride_1');
      },
    );

    test('częściowe powodzenie zostawia niepotwierdzone w kolejce', () async {
      for (final id in ['ride_1', 'ride_2', 'ride_3']) {
        await rides.save(_ride(id));
      }
      // Serwer przyjął dwa z trzech.
      final adapter = _FakeAdapter(
        (_) =>
            _json('{"synced":[{"client_id":"ride_1"},{"client_id":"ride_3"}]}'),
      );
      final sync = await serviceWith(adapter);

      await sync.flush(force: true);

      final pending = await rides.pendingSync();
      expect(pending.map((ride) => ride.id), ['ride_2']);
    });

    test('błąd sieci nie kasuje niczego z kolejki', () async {
      for (final id in ['ride_1', 'ride_2', 'ride_3']) {
        await rides.save(_ride(id));
      }
      final adapter = _FakeAdapter((options) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'brak sieci',
        );
      });
      final sync = await serviceWith(adapter);

      expect(await sync.flush(force: true), isFalse);
      expect((await rides.pendingSync()).length, 3);
      expect(sync.failure, SyncFailure.offline);
      expect(sync.phase, SyncPhase.offline);
    });

    test(
      'odpowiedź bez pola synced nie oznacza niczego jako wysłane',
      () async {
        await rides.save(_ride('ride_1'));
        final adapter = _FakeAdapter((_) => _json('{"ok":true}'));
        final sync = await serviceWith(adapter);

        await sync.flush(force: true);
        expect((await rides.pendingSync()).length, 1);
      },
    );

    test('nieprawidłowy JSON nie wywraca aplikacji ani kolejki', () async {
      await rides.save(_ride('ride_1'));
      final adapter = _FakeAdapter((_) => _json('to nie jest json'));
      final sync = await serviceWith(adapter);

      await sync.flush(force: true);
      expect((await rides.pendingSync()).length, 1);
      expect(sync.phase, isNot(SyncPhase.running));
    });
  });

  group('klasyfikacja błędów', () {
    DioException responseError(int status) => DioException.badResponse(
      statusCode: status,
      requestOptions: RequestOptions(path: '/live-rides/sync/rides'),
      response: Response(
        statusCode: status,
        requestOptions: RequestOptions(path: '/live-rides/sync/rides'),
      ),
    );

    test('brak sieci i przekroczone czasy to offline', () {
      final options = RequestOptions(path: '/x');
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          SyncService.classify(
            DioException(requestOptions: options, type: type),
          ),
          SyncFailure.offline,
          reason: type.name,
        );
      }
    });

    test('401 i 403 to wygasła sesja', () {
      expect(SyncService.classify(responseError(401)), SyncFailure.session);
      expect(SyncService.classify(responseError(403)), SyncFailure.session);
    });

    test('404 znaczy nieaktualny serwer, a nie brak przejazdu', () {
      // Endpoint synchronizacji zawsze istnieje po stronie aplikacji, więc
      // 404 mówi wyłącznie o tym, że serwer go nie zna.
      expect(
        SyncService.classify(responseError(404)),
        SyncFailure.outdatedServer,
      );
    });

    test('500 i błąd nieznanego typu to awaria serwera', () {
      expect(SyncService.classify(responseError(500)), SyncFailure.server);
      expect(SyncService.classify(responseError(502)), SyncFailure.server);
      expect(
        SyncService.classify(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.unknown,
          ),
        ),
        SyncFailure.server,
      );
    });
  });

  group('nic technicznego nie wychodzi z serwisu', () {
    Future<SyncService> failWith(DioException error) async {
      await rides.save(_ride('ride_1'));
      final sync = await serviceWith(_FakeAdapter((_) => throw error));
      await sync.flush(force: true);
      return sync;
    }

    test('powód awarii to wyliczenie, a nie tekst wyjątku', () async {
      final sync = await failWith(
        DioException.badResponse(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/live-rides/sync/rides'),
          response: Response(
            statusCode: 404,
            requestOptions: RequestOptions(path: '/live-rides/sync/rides'),
          ),
        ),
      );

      expect(sync.failure, SyncFailure.outdatedServer);
      // Surowy opis zostaje wyłącznie do logu i testów.
      expect(sync.technicalError, isNotNull);
      expect(sync.technicalError, contains('DioException'));
    });

    test('serwis nie wystawia żadnego pola z tekstem wyjątku do UI', () {
      // `technicalError` jest oznaczony @visibleForTesting; interfejs ma do
      // dyspozycji wyłącznie `failure`, `phase`, `pendingCount` i
      // `lastSuccess`. Ten test pilnuje, żeby nikt nie dołożył trzeciego
      // kanału z treścią wyjątku.
      final sync = SyncService(
        api: _api(_FakeAdapter((_) => _json('{}'))),
        rides: rides,
        routes: routes,
      );
      expect(sync.failure, isNull);
      expect(sync.phase, SyncPhase.idle);
      expect(sync.pendingCount, 0);
      expect(sync.lastSuccess, isNull);
    });
  });

  group('odczekanie po nieudanej próbie', () {
    test('zwykły przebieg czeka, wymuszony nie', () async {
      await rides.save(_ride('ride_1'));
      var attempts = 0;
      final adapter = _FakeAdapter((options) {
        attempts++;
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'brak sieci',
        );
      });
      final sync = await serviceWith(adapter);

      await sync.flush(force: true);
      expect(attempts, 1);

      // Telefon bez zasięgu nie ma się czym męczyć co sekundę.
      await sync.flush();
      expect(attempts, 1);

      // Ale zawodnik, który nacisnął „synchronizuj teraz", wie lepiej.
      await sync.flush(force: true);
      expect(attempts, 2);
    });
  });
}
