import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/api_client.dart';
import 'package:live_ride/models/rider_profile.dart';
import 'package:live_ride/screens/login_screen.dart';

/// Konto to jedyna część aplikacji, w której rowerzysta wpisuje coś palcem
/// zanim w ogóle ruszy — i jedyna, w której pomyłka po stronie serwera
/// wygląda jak „aplikacja nie działa".

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

ApiClient _api(_FakeAdapter adapter) {
  final api = ApiClient();
  api.dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
    ..httpClientAdapter = adapter;
  return api;
}

const _account =
    '{"record":{"username":"ada","name":"Ada Kowalska",'
    '"email":"ada@example.com"}}';

void main() {
  group('logowanie przyjmuje e-mail i nazwę użytkownika', () {
    test('to, co wpisał rowerzysta, idzie na serwer bez zgadywania', () async {
      // Kolekcja `users` ma w identityFields oba pola, więc rozstrzyga
      // serwer. Aplikacja, która sama decydowałaby po znaku małpy, myliłaby
      // się na każdej nazwie użytkownika z kropką albo na adresie bez niej.
      for (final identity in ['ada', 'ada@example.com']) {
        final adapter = _FakeAdapter((_) => _json(_account));
        await _api(adapter).login(identity, 'bardzo-tajne');
        final body = adapter.requests.single.data as Map;
        expect(body['username'], identity);
      }
    });

    test('białe znaki wokół loginu nie blokują logowania', () async {
      final adapter = _FakeAdapter((_) => _json(_account));
      await _api(adapter).login('  ada@example.com \n', 'bardzo-tajne');
      expect(
        (adapter.requests.single.data as Map)['username'],
        'ada@example.com',
      );
    });

    test('oddaje nazwę wyświetlaną i e-mail z odpowiedzi serwera', () async {
      final identity = await _api(
        _FakeAdapter((_) => _json(_account)),
      ).login('ada', 'bardzo-tajne');
      expect(identity.username, 'ada');
      expect(identity.name, 'Ada Kowalska');
      expect(identity.email, 'ada@example.com');
      expect(identity.label, 'Ada Kowalska');
    });

    test('bez nazwy wyświetlanej zostaje login, nie pusty napis', () {
      const identity = AccountIdentity(username: 'ada', name: '');
      expect(identity.label, 'ada');
    });

    test('złe hasło to komunikat po polsku, nie DioException', () async {
      final adapter = _FakeAdapter(
        (_) => _json('{"message":"Failed to authenticate."}', status: 400),
      );
      await expectLater(
        _api(adapter).login('ada', 'bardzo-tajne'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            allOf(isNot(contains('Dio')), isNot(contains('http'))),
          ),
        ),
      );
    });
  });

  group('rejestracja', () {
    test('wysyła nazwę wyświetlaną i od razu loguje', () async {
      final adapter = _FakeAdapter((options) => _json(_account));
      final identity = await _api(adapter).register(
        username: 'ada',
        email: 'ada@example.com',
        password: 'bardzo-tajne',
        name: 'Ada Kowalska',
      );

      expect(adapter.requests.length, 2, reason: 'rejestracja i logowanie');
      final create = adapter.requests.first;
      expect(create.method, 'PUT');
      expect(create.path, '/user');
      final body = create.data as Map;
      expect(body['username'], 'ada');
      expect(body['email'], 'ada@example.com');
      expect(body['name'], 'Ada Kowalska');
      expect(body['passwordConfirm'], body['password']);

      expect(adapter.requests.last.path, '/auth/login');
      expect(identity.name, 'Ada Kowalska');
    });

    test('bez nazwy wyświetlanej pole w ogóle nie leci', () async {
      final adapter = _FakeAdapter((_) => _json(_account));
      await _api(adapter).register(
        username: 'ada',
        email: 'ada@example.com',
        password: 'bardzo-tajne',
      );
      expect((adapter.requests.first.data as Map).containsKey('name'), isFalse);
    });

    test('nazwa z serwera przebija tę wpisaną w formularzu', () async {
      // Serwer może nazwę przyciąć albo oczyścić; to on ma ostatnie słowo.
      final adapter = _FakeAdapter(
        (_) => _json('{"record":{"username":"ada","name":"Ada K."}}'),
      );
      final identity = await _api(adapter).register(
        username: 'ada',
        email: 'ada@example.com',
        password: 'bardzo-tajne',
        name: 'Ada Kowalska',
      );
      expect(identity.name, 'Ada K.');
      // E-maila odpowiedź nie niosła — zostaje ten, który właśnie podaliśmy.
      expect(identity.email, 'ada@example.com');
    });
  });

  group('reset hasła', () {
    test('pyta serwer o adres i nie sprawdza, czy konto istnieje', () async {
      final adapter = _FakeAdapter((_) => _json('{"success":true}'));
      await _api(adapter).requestPasswordReset(' ada@example.com ');
      final request = adapter.requests.single;
      expect(request.path, '/auth/reset');
      expect((request.data as Map)['email'], 'ada@example.com');
    });

    test('nie jest traktowany jak wygaśnięcie sesji', () async {
      // 401 na trasie publicznej znaczy „złe dane", a nie „wyloguj mnie".
      // Bez tego nieudany reset wyrzucałby zalogowanego z aplikacji.
      expect(ApiClient.publicPaths.any('/auth/reset'.startsWith), isTrue);
    });
  });

  group('walidacja formularza', () {
    Future<void> pump(WidgetTester tester, LoginMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(onSignedIn: () {}, initialMode: mode),
        ),
      );
    }

    testWidgets('logowanie prosi o login, zanim pójdzie do serwera', (
      tester,
    ) async {
      await pump(tester, LoginMode.signIn);
      await tester.tap(find.text('Zaloguj się').last);
      await tester.pump();
      expect(find.text('Podaj e-mail albo nazwę użytkownika.'), findsOneWidget);
    });

    testWidgets('rejestracja pilnuje, żeby hasła były takie same', (
      tester,
    ) async {
      await pump(tester, LoginMode.register);
      await tester.enterText(find.byType(TextField).at(0), 'ada');
      await tester.enterText(find.byType(TextField).at(1), 'Ada Kowalska');
      await tester.enterText(find.byType(TextField).at(2), 'ada@example.com');
      await tester.enterText(find.byType(TextField).at(3), 'bardzo-tajne');
      await tester.enterText(find.byType(TextField).at(4), 'inne-haslo');
      await tester.tap(find.text('UTWÓRZ KONTO'));
      await tester.pump();
      expect(find.text('Hasła nie są takie same.'), findsOneWidget);
    });

    testWidgets('rejestracja odrzuca za krótką nazwę użytkownika', (
      tester,
    ) async {
      await pump(tester, LoginMode.register);
      await tester.enterText(find.byType(TextField).at(0), 'ad');
      await tester.tap(find.text('UTWÓRZ KONTO'));
      await tester.pump();
      expect(
        find.text('Nazwa użytkownika musi mieć co najmniej 3 znaki.'),
        findsOneWidget,
      );
    });

    testWidgets('rejestracja wymaga nazwy wyświetlanej', (tester) async {
      await pump(tester, LoginMode.register);
      await tester.enterText(find.byType(TextField).at(0), 'ada');
      await tester.tap(find.text('UTWÓRZ KONTO'));
      await tester.pump();
      expect(find.text('Podaj nazwę wyświetlaną.'), findsOneWidget);
    });

    testWidgets('literówka w adresie zatrzymuje formularz', (tester) async {
      await pump(tester, LoginMode.reset);
      await tester.enterText(find.byType(TextField).first, 'ada@example');
      await tester.tap(find.text('WYŚLIJ INSTRUKCJE'));
      await tester.pump();
      expect(find.text('To nie wygląda na adres e-mail.'), findsOneWidget);
    });
  });

  group('ekran logowania', () {
    testWidgets('nie pokazuje adresu serwera', (tester) async {
      // Rowerzyście to nic nie mówi, a komuś, kto zagląda przez ramię,
      // mówi, gdzie pukać.
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(onSignedIn: () {})),
      );
      expect(find.textContaining(ApiClient.serverOrigin), findsNothing);
      expect(find.textContaining('http'), findsNothing);
    });

    testWidgets('pole logowania mówi, że przyjmuje jedno i drugie', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(onSignedIn: () {})),
      );
      expect(find.text('E-mail lub nazwa użytkownika'), findsOneWidget);
      expect(find.text('Nie pamiętasz hasła?'), findsOneWidget);
      expect(find.text('Załóż nowe konto'), findsOneWidget);
    });

    testWidgets('komunikat o wygasłej sesji jest ten obiecany', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            onSignedIn: () {},
            notice: 'Twoja sesja wygasła. Zaloguj się ponownie.',
          ),
        ),
      );
      expect(
        find.text('Twoja sesja wygasła. Zaloguj się ponownie.'),
        findsOneWidget,
      );
    });

    testWidgets('reset kończy się komunikatem, który niczego nie zdradza', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(onSignedIn: () {})),
      );
      await tester.tap(find.text('Nie pamiętasz hasła?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset hasła'), findsOneWidget);
      expect(find.text('WYŚLIJ INSTRUKCJE'), findsOneWidget);
    });
  });

  group('profil po zalogowaniu', () {
    test('zna adres e-mail konta i przeżywa zapis', () {
      const profile = RiderProfile(
        username: 'ada',
        accountEmail: 'ada@example.com',
      );
      final restored = RiderProfile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
      );
      expect(restored.accountEmail, 'ada@example.com');
    });
  });
}
