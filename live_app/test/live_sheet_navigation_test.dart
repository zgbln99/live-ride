import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/data/database.dart';
import 'package:live_ride/i18n/strings.dart';
import 'package:live_ride/screens/live_sheet.dart';
import 'package:live_ride/services/app_services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Wyjście z arkusza LIVE otwartego W TRAKCIE JAZDY.
///
/// Arkusz jest ekranem ustawień postawionym NA liczniku, a nie zamiast niego.
/// Do tej pory nie miał żadnego jawnego wyjścia: jedyny `Navigator.pop`
/// w pliku należał do okienka dołączania kodem, a nie do arkusza. Zostawało
/// zjechanie palcem w dół — na iPhonie w rękawiczkach trafione raz na trzy
/// próby, a na Androidzie nieoczywiste, że w ogóle istnieje.
///
/// Te testy pilnują dokładnie jednej rzeczy: że wyjście ZAMYKA ARKUSZ i nic
/// poza nim. Transmisja, licznik i nawigacja mają przeżyć każde z nich.

/// Transport, który oddaje sensowną sesję i milczy na resztę.
class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.path.endsWith('/live-rides')
        ? '{"id":"s1","participant_id":"p1","share_token":"tok",'
              '"join_token":"JOIN1234","status":"active","visibility":"unlisted"}'
        : '{}';
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

/// Radio BLE, którego w teście nie ma.
///
/// `CentralManager()` sięga do kanału platformy i rzuca wyjątkiem, zanim
/// cokolwiek zdąży się narysować. Arkusz LIVE nie pyta radia o nic — pyta
/// o to, czy czujnik JEST podłączony — więc atrapa bez zachowania wystarcza.
class _NoRadio implements CentralManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AppServices buildServices() {
  final api = ApiClient();
  api.dio = Dio(BaseOptions(baseUrl: 'https://ride.example/api/v1'))
    ..httpClientAdapter = _StubAdapter();
  return AppServices.create(
    api,
    bluetooth: _NoRadio(),
    database: LiveRideDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ),
  );
}

/// Zastępnik ekranu jazdy: ma tylko tyle, ile potrzeba, żeby sprawdzić,
/// że po zamknięciu arkusza wracamy WŁAŚNIE TU.
Widget host(AppServices services, LiveSheetSource source) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('EKRAN JAZDY'),
            ElevatedButton(
              onPressed: () =>
                  showLiveSheet(context, services, source: source),
              child: const Text('OTWÓRZ LIVE'),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Przewija tyle, ile trwa otwarcie albo zamknięcie arkusza.
///
/// `pumpAndSettle` nie nadaje się wszędzie: arkusz diagnostyki odpytuje
/// serwer co pięć sekund, a każde odpytanie planuje kolejną klatkę.
Future<void> settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('OTWÓRZ LIVE'));
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();

  group('wyjście z arkusza otwartego z licznika', () {
    testWidgets('A · krzyżyk wraca na ekran jazdy', (tester) async {
      final services = buildServices();
      await tester.pumpWidget(host(services, LiveSheetSource.rideComputer));
      await openSheet(tester);

      expect(find.text(S.backToNavigation), findsOneWidget);

      await tester.tap(find.byTooltip(S.close));
      await tester.pumpAndSettle();

      expect(find.text(S.backToNavigation), findsNothing);
      expect(find.text('EKRAN JAZDY'), findsOneWidget);
    });

    testWidgets('B · „wróć do nawigacji" nie rusza licznika', (tester) async {
      final services = buildServices();
      final before = services.recorder.state;
      await tester.pumpWidget(host(services, LiveSheetSource.rideComputer));
      await openSheet(tester);

      await tester.tap(find.text(S.backToNavigation));
      await tester.pumpAndSettle();

      expect(find.text('EKRAN JAZDY'), findsOneWidget);
      // G · stan licznika bez zmian. Wyjście z ustawień nie jest wyjściem
      // z jazdy i nie wolno mu niczego zatrzymać.
      expect(services.recorder.state, before);
      // …i nikt nie wyczyścił trasy ani nie odpiął czujników po drodze.
      expect(services.recorder.route, isNull);
      expect(services.heartRate.status, isNotNull);
    });

    testWidgets('E · systemowy wstecz zdejmuje tylko arkusz', (tester) async {
      final services = buildServices();
      await tester.pumpWidget(host(services, LiveSheetSource.rideComputer));
      await openSheet(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(S.backToNavigation), findsNothing);
      // Ekran jazdy zostaje. Wstecz ma zamknąć ustawienia, a nie przejazd.
      expect(find.text('EKRAN JAZDY'), findsOneWidget);
    });
  });

  group('wyjście z arkusza otwartego z zakładki LIVE', () {
    testWidgets('bez jazdy pod spodem przycisk nazywa się „gotowe"', (
      tester,
    ) async {
      final services = buildServices();
      await tester.pumpWidget(host(services, LiveSheetSource.liveTab));
      await openSheet(tester);

      // Nie ma do czego wracać, więc nie obiecujemy powrotu do nawigacji.
      expect(find.text(S.doneAction), findsOneWidget);
      expect(find.text(S.backToNavigation), findsNothing);

      await tester.tap(find.text(S.doneAction));
      await tester.pumpAndSettle();
      expect(find.text('EKRAN JAZDY'), findsOneWidget);
    });
  });

  group('arkusze zagnieżdżone zamykają wyłącznie siebie', () {
    /// Uruchamia LIVE z aktywną transmisją, żeby dojść do przycisków
    /// udostępniania, grupy i diagnostyki.
    ///
    /// Ekran jest celowo bardzo wysoki: arkusz z transmisją nie mieści się
    /// na telefonie i trzeba by go przewijać, a przewijanie w teście dokłada
    /// trzecią rzecz, która może się zepsuć, do sprawdzania dwóch pierwszych.
    /// Tutaj interesuje nas wyłącznie to, CO ZAMYKA CO.
    Future<AppServices> liveSheetWithSession(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final services = buildServices();
      // `runAsync`, bo start transmisji zapisuje ustawienia prywatności do
      // SQLite. Zwykły `await` w teście widgetowym siedzi w udawanym czasie
      // i nigdy nie doczeka się odpowiedzi prawdziwej bazy.
      await tester.runAsync(() => services.live.create(title: 'Test'));
      await tester.pumpWidget(host(services, LiveSheetSource.rideComputer));
      await openSheet(tester);
      return services;
    }

    testWidgets('C · diagnostyka wraca do LIVE, nie na licznik', (
      tester,
    ) async {
      final services = await liveSheetWithSession(tester);

      await tester.tap(find.text(S.liveDiagnostics));
      // Bez `pumpAndSettle`: diagnostyka odpytuje serwer co pięć sekund,
      // a każde odpytanie planuje klatkę — „poczekaj, aż się uspokoi"
      // nie skończyłoby się nigdy. Przewijamy tyle, ile trwa przejście.
      await settleSheet(tester);
      expect(find.text(S.diagnosticsSubtitle), findsOneWidget);

      // Dwa krzyżyki na ekranie: ten na wierzchu należy do diagnostyki.
      await tester.tap(find.byTooltip(S.close).last);
      await settleSheet(tester);

      expect(find.text(S.diagnosticsSubtitle), findsNothing);
      // Wracamy do LIVE, a nie dwa ekrany niżej.
      expect(find.text(S.backToNavigation), findsOneWidget);
      expect(services.live.isActive, isTrue);
    });

    testWidgets('D · udostępnianie wraca do LIVE', (tester) async {
      final services = await liveSheetWithSession(tester);

      await tester.tap(find.text(S.shareTheLink));
      await tester.pumpAndSettle();
      expect(find.text(S.shareLiveTitle), findsOneWidget);

      await tester.tap(find.byTooltip(S.close).last);
      await tester.pumpAndSettle();

      expect(find.text(S.shareLiveTitle), findsNothing);
      expect(find.text(S.backToNavigation), findsOneWidget);
      expect(services.live.isActive, isTrue);
    });

    testWidgets('F · zamknięcie LIVE nie kończy transmisji', (tester) async {
      final services = await liveSheetWithSession(tester);
      final sessionId = services.live.session!.id;

      await tester.tap(find.text(S.backToNavigation));
      await tester.pumpAndSettle();

      expect(find.text('EKRAN JAZDY'), findsOneWidget);
      // Zamknięcie ustawień to nie zakończenie jazdy na żywo.
      expect(services.live.isActive, isTrue);
      expect(services.live.session!.id, sessionId);
    });
  });
}
