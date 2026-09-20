import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/i18n/maneuver_pl.dart';
import 'package:live_ride/models/navigation_plan.dart';

/// Nawigacja po polsku.
///
/// Zgłoszenie z fizycznego telefonu brzmiało: „Turn left onto Burgenlandstraße"
/// w aplikacji, która poza tym jest w całości po polsku. Do routera idzie
/// `language: pl-PL`, ale to prośba, nie gwarancja — i te testy pilnują, że
/// angielski nie przecieka na ekran żadną drogą.

/// Wszystkie kody manewrów, które Valhalla potrafi zwrócić dla roweru.
const List<int> _allTypes = [
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  37,
  38,
];

/// Angielskie słowa, których rowerzysta nie ma prawa zobaczyć.
const List<String> _forbidden = [
  'turn',
  'continue',
  'keep',
  'bear',
  'head',
  'merge',
  'exit',
  'enter',
  'roundabout',
  'destination',
  'arrive',
  'straight',
  'slight',
  'sharp',
  'onto',
  'stay',
  'left',
  'right',
  'ferry',
];

void main() {
  group('każdy typ manewru dostaje polskie zdanie', () {
    test('bez ani jednego angielskiego słowa', () {
      for (final type in _allTypes) {
        final text = maneuverInstructionPl(type: type);
        expect(text, isNotEmpty, reason: 'typ $type nie dostał instrukcji');
        for (final word in _forbidden) {
          expect(
            text.toLowerCase(),
            isNot(contains(word)),
            reason: 'typ $type → „$text" zawiera „$word"',
          );
        }
      }
    });

    test('także w formie krótkiej', () {
      for (final type in _allTypes) {
        final short = maneuverShortPl(type: type);
        expect(short, isNotEmpty);
        for (final word in _forbidden) {
          expect(short.toLowerCase(), isNot(contains(word)));
        }
      }
    });

    test('nieznany kod nie milczy', () {
      // Rowerzysta ma przed sobą zakręt niezależnie od tego, czy rozumiemy
      // numer, który przysłał router.
      expect(maneuverInstructionPl(type: 999), 'Jedź dalej');
      expect(
        maneuverInstructionPl(type: 999, streetNames: ['Polna']),
        'Jedź dalej, Polna',
      );
    });
  });

  group('zdania z briefu', () {
    test(
      'Turn left onto Burgenlandstraße → Skręć w lewo w Burgenlandstraße',
      () {
        expect(
          maneuverInstructionPl(
            type: ValhallaManeuver.left,
            streetNames: ['Burgenlandstraße'],
            routerInstruction: 'Turn left onto Burgenlandstraße.',
          ),
          'Skręć w lewo w Burgenlandstraße',
        );
      },
    );

    test('Turn right → Skręć w prawo', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.right,
          routerInstruction: 'Turn right.',
        ),
        'Skręć w prawo',
      );
    });

    test('Continue straight → Jedź prosto', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.continues,
          routerInstruction: 'Continue straight.',
        ),
        'Jedź prosto',
      );
    });

    test('Make a U-turn → Zawróć', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.uturnLeft,
          routerInstruction: 'Make a U-turn.',
        ),
        'Zawróć',
      );
    });

    test('roundabout → Na rondzie wybierz 2. zjazd', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.roundaboutEnter,
          roundaboutExit: 2,
          routerInstruction: 'Enter the roundabout and take the 2nd exit.',
        ),
        'Na rondzie wybierz 2. zjazd',
      );
    });

    test('rondo bez numeru zjazdu nie zmyśla numeru', () {
      expect(
        maneuverInstructionPl(type: ValhallaManeuver.roundaboutEnter),
        'Wjedź na rondo',
      );
    });

    test('Destination is on the right → Cel po prawej stronie', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.destinationRight,
          routerInstruction: 'Your destination is on the right.',
        ),
        'Cel znajduje się po prawej stronie',
      );
    });

    test('Keep left → Trzymaj się lewej strony', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.stayLeft,
          routerInstruction: 'Keep left at the fork.',
        ),
        'Trzymaj się lewej strony',
      );
    });

    test('Bear right → Lekko w prawo', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.slightRight,
          routerInstruction: 'Bear right onto the path.',
        ),
        'Lekko w prawo',
      );
    });
  });

  group('nazwy ulic zostają nietknięte', () {
    test('niemiecka nazwa przechodzi znak w znak', () {
      const street = 'Burgenlandstraße';
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.left,
          streetNames: [street],
        ),
        contains(street),
      );
    });

    test('nazwa, która wygląda jak angielskie słowo, nie jest tłumaczona', () {
      // „Left Bank Road" to nazwa, a nie polecenie skrętu.
      final text = maneuverInstructionPl(
        type: ValhallaManeuver.right,
        streetNames: ['Left Bank Road'],
      );
      expect(text, 'Skręć w prawo w Left Bank Road');
    });

    test('pierwsza niepusta nazwa wygrywa', () {
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.left,
          streetNames: ['  ', 'Polna', 'Leśna'],
        ),
        'Skręć w lewo w Polna',
      );
    });
  });

  group('kiedy ufamy routerowi', () {
    test('poprawny polski tekst przechodzi bez zmian', () {
      const text = 'Skręć w prawo w Świętokrzyską';
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.right,
          routerInstruction: text,
        ),
        text,
      );
      expect(looksPolish(text), isTrue);
    });

    test('polska instrukcja bez ogonków też jest polska', () {
      // Decyduje czasownik, nie znaki diakrytyczne: „Skręć w prawo w Main
      // Street" jest poprawne, a nazwa ulicy nie ma polskich liter.
      expect(looksPolish('Skręć w prawo w Main Street'), isTrue);
    });

    test('angielska instrukcja z polską nazwą ulicy jest odrzucana', () {
      // Tu jest odwrotnie: pełno ogonków, a zdanie angielskie.
      expect(looksPolish('Turn left onto Świętokrzyska'), isFalse);
    });

    test('pusty i biały tekst nie jest instrukcją', () {
      expect(looksPolish(''), isFalse);
      expect(looksPolish('   '), isFalse);
      expect(looksPolish('Burgenlandstraße'), isFalse);
    });

    test('angielskie słowo wewnątrz nazwy nie odrzuca polskiego zdania', () {
      // „Trzymaj się prawej strony, Exit Road" — „Exit" jest tu nazwą.
      // Tego akurat nie umiemy odróżnić i świadomie wolimy złożyć własne
      // zdanie, niż pokazać cudze. Test opisuje ten wybór, żeby nikt nie
      // uznał go za przypadek.
      expect(looksPolish('Trzymaj się prawej strony, Exit Road'), isFalse);
      expect(
        maneuverInstructionPl(
          type: ValhallaManeuver.stayRight,
          streetNames: ['Exit Road'],
          routerInstruction: 'Trzymaj się prawej strony, Exit Road',
        ),
        'Trzymaj się prawej strony, Exit Road',
      );
    });
  });

  group('model manewru', () {
    NavManeuver parse(Map<String, dynamic> json) => NavManeuver.fromJson(json);

    test('instructionPl bierze się z typu, gdy router mówi po angielsku', () {
      final maneuver = parse({
        'instruction': 'Turn left onto Burgenlandstraße.',
        'type': 15,
        'street_names': ['Burgenlandstraße'],
        'begin_shape_index': 4,
      });
      expect(maneuver.instructionPl, 'Skręć w lewo w Burgenlandstraße');
      expect(maneuver.shortInstructionPl, 'Skręć w lewo');
    });

    test('rozpoznaje cel podróży po kodzie, nie po tekście', () {
      for (final type in [4, 5, 6]) {
        expect(parse({'type': type}).isDestination, isTrue);
      }
      expect(parse({'type': 10}).isDestination, isFalse);
    });
  });
}
