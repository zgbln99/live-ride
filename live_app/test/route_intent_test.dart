import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/route_intent.dart';

/// Polecenia, jakimi ludzie naprawdę mówią o jeździe.
///
/// Parser jest deterministyczny i lokalny — bez modelu językowego. Te zdania
/// mają skończoną liczbę kształtów, a odpowiedź musi przyjść natychmiast,
/// także bez zasięgu.
void main() {
  group('cel podróży', () {
    test('sama nazwa miejsca jest celem', () {
      final intent = parseRouteIntent('Potsdam');
      expect(intent.destination, 'Potsdam');
      expect(intent.shape, RouteShape.destination);
      expect(intent.isUsable, isTrue);
    });

    test('nazwa wielowyrazowa zostaje w całości', () {
      expect(
        parseRouteIntent('Brama Brandenburska').destination,
        'Brama Brandenburska',
      );
    });

    test('„do X" oddziela cel od reszty zdania', () {
      final intent = parseRouteIntent('do Poczdamu');
      expect(intent.destination, 'Poczdamu');
    });

    test('„do X przez Y" daje trzy logiczne punkty', () {
      final intent = parseRouteIntent('do Poczdamu przez Wannsee');
      // Start bierze się z pozycji, więc w poleceniu są dwa: cel i punkt
      // pośredni. Bez rozdzielenia geokoder dostałby „Poczdamu przez
      // Wannsee", czego nie zna żadna mapa.
      expect(intent.destination, 'Poczdamu');
      expect(intent.via, ['Wannsee']);
    });

    test('kilka punktów pośrednich', () {
      final intent = parseRouteIntent(
        'do Poczdamu przez Wannsee, przez Kladow',
      );
      expect(intent.via, ['Wannsee', 'Kladow']);
    });

    test('„dojazd" to nie jest „do jazd"', () {
      // Słowo kluczowe musi stać na początku wyrazu.
      expect(parseRouteIntent('dojazd do pracy').destination, 'pracy');
    });

    test('dopełniacz dostaje kandydatów do sprawdzenia w geokoderze', () {
      // Nie udajemy odmiany gramatycznej — podajemy warianty i pozwalamy
      // mapie wybrać ten, który istnieje.
      expect(RouteIntent.candidatesFor('Poczdamu'), contains('Poczdam'));
      expect(RouteIntent.candidatesFor('Warszawy'), contains('Warszawa'));
      expect(RouteIntent.candidatesFor('Wannsee'), ['Wannsee']);
    });
  });

  group('dystans i czas', () {
    test('„50 km pętla" to pętla na pięćdziesiąt kilometrów', () {
      final intent = parseRouteIntent('50 km pętla');
      expect(intent.distanceMeters, 50000);
      expect(intent.shape, RouteShape.loop);
      expect(intent.destination, isNull);
      expect(intent.isUsable, isTrue);
    });

    test('przecinek dziesiętny działa tak samo jak kropka', () {
      expect(parseRouteIntent('42,3 km').distanceMeters, closeTo(42300, 1));
    });

    test('„około 2 godziny" to czas, nie dystans', () {
      final intent = parseRouteIntent('około 2 godziny');
      expect(intent.duration, const Duration(hours: 2));
      expect(intent.distanceMeters, isNull);
      expect(intent.destination, isNull);
    });

    test('„1:30 h" i „półtorej godziny" znaczą to samo', () {
      expect(parseRouteIntent('1:30 h').duration, const Duration(minutes: 90));
      expect(
        parseRouteIntent('półtorej godziny').duration,
        const Duration(minutes: 90),
      );
    });

    test('„90 min" też', () {
      expect(parseRouteIntent('90 min').duration, const Duration(minutes: 90));
    });

    test('absurdalny dystans jest odrzucany zamiast przyjmowany', () {
      expect(parseRouteIntent('5000 km').distanceMeters, isNull);
    });
  });

  group('kształt trasy', () {
    test('„i z powrotem" to tam i z powrotem', () {
      expect(
        parseRouteIntent('do jeziora i z powrotem').shape,
        RouteShape.outAndBack,
      );
    });

    test('„pętla" wygrywa z dopiskiem o powrocie', () {
      // Pętla NIE jest tą samą drogą z powrotem i dopisek tego nie zmienia.
      final intent = parseRouteIntent('pętla 70 km i wróć tutaj');
      expect(intent.shape, RouteShape.loop);
      expect(intent.distanceMeters, 70000);
      expect(intent.returnsHome, isTrue);
    });
  });

  group('preferencje', () {
    test('„60 km gravel"', () {
      final intent = parseRouteIntent('60 km gravel');
      expect(intent.distanceMeters, 60000);
      expect(intent.surface, SurfacePreference.gravel);
    });

    test('„80 km asfalt"', () {
      expect(parseRouteIntent('80 km asfalt').surface, SurfacePreference.paved);
    });

    test('„40 km płasko" prosi o mniejsze przewyższenie', () {
      final intent = parseRouteIntent('40 km płasko');
      expect(intent.elevation, ElevationPreference.flat);
    });

    test('„50 km z podjazdami" prosi o większe', () {
      expect(
        parseRouteIntent('50 km z podjazdami').elevation,
        ElevationPreference.hilly,
      );
    });

    test('„30 km bez dużych podjazdów" to nadal płasko', () {
      // Najłatwiejsza pomyłka parsera: to zdanie zawiera słowo „podjazd".
      expect(
        parseRouteIntent('30 km bez dużych podjazdów').elevation,
        ElevationPreference.flat,
      );
    });

    test('spokojne drogi i unikanie promów', () {
      final intent = parseRouteIntent('50 km spokojnymi drogami bez promów');
      expect(intent.traffic, TrafficPreference.quiet);
      expect(intent.avoid, contains(RouteAvoid.ferries));
    });
  });

  group('czego parser nie rozumie', () {
    test('puste polecenie nie udaje niczego', () {
      final intent = parseRouteIntent('   ');
      expect(intent.isUsable, isFalse);
      expect(intent.destination, isNull);
    });

    test('samo „asfalt" nie jest miejscem', () {
      expect(parseRouteIntent('asfalt').destination, isNull);
    });
  });
}
