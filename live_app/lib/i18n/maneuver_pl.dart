/// Polskie instrukcje nawigacyjne, składane u nas.
///
/// Do routera idzie `language: pl-PL`, ale to jest prośba, nie gwarancja.
/// Valhalla oddaje polski tylko dla tych typów manewrów, dla których ma
/// tłumaczenie w swoim pliku językowym, a przy nietypowej konfiguracji
/// serwera albo starszym obrazie oddaje angielski. Skutek widać było na
/// ekranie: „Turn left onto Burgenlandstraße" w aplikacji, która poza tym
/// jest w całości po polsku.
///
/// Dlatego tekst z routera jest tu traktowany jak podpowiedź, a nie jak
/// wynik. Gdy wygląda na polski — używamy go, bo zna odmianę nazwy ulicy
/// i drobiazgi, których sami nie odtworzymy. Gdy wygląda na angielski,
/// jest pusty albo niepewny — składamy instrukcję sami z tego, co niesie
/// sam manewr: typu, nazw ulic i numeru zjazdu z ronda.
///
/// Nazw ulic nie tłumaczymy. „Burgenlandstraße" zostaje „Burgenlandstraße";
/// rowerzysta szuka tego napisu na tabliczce, a nie w słowniku.
library;

/// Kody manewrów Valhalli, nazwane.
///
/// Surowe liczby w `switch` są nie do sprawdzenia wzrokiem — a pomyłka
/// między 15 (w lewo) a 16 (lekko w lewo) wysyła rowerzystę w złą ulicę.
abstract final class ValhallaManeuver {
  static const int none = 0;
  static const int start = 1;
  static const int startRight = 2;
  static const int startLeft = 3;
  static const int destination = 4;
  static const int destinationRight = 5;
  static const int destinationLeft = 6;
  static const int becomes = 7;
  static const int continues = 8;
  static const int slightRight = 9;
  static const int right = 10;
  static const int sharpRight = 11;
  static const int uturnRight = 12;
  static const int uturnLeft = 13;
  static const int sharpLeft = 14;
  static const int left = 15;
  static const int slightLeft = 16;
  static const int rampStraight = 17;
  static const int rampRight = 18;
  static const int rampLeft = 19;
  static const int exitRight = 20;
  static const int exitLeft = 21;
  static const int stayStraight = 22;
  static const int stayRight = 23;
  static const int stayLeft = 24;
  static const int merge = 25;
  static const int roundaboutEnter = 26;
  static const int roundaboutExit = 27;
  static const int ferryEnter = 28;
  static const int ferryExit = 29;
  static const int transitConnectionStart = 30;
  static const int mergeRight = 37;
  static const int mergeLeft = 38;
}

/// Składa polską instrukcję dla jednego manewru.
///
/// Osobna funkcja, a nie metoda modelu, bo używają jej cztery różne miejsca —
/// ekran jazdy, nagłówek nawigacji, Dynamic Island i Lock Screen — i wszystkie
/// mają mówić dokładnie to samo. Rozjazd między ekranem a ekranem blokady
/// byłby gorszy niż jeden wspólny błąd.
String maneuverInstructionPl({
  required int type,
  List<String> streetNames = const [],
  int? roundaboutExit,
  String? routerInstruction,
}) {
  final fromRouter = (routerInstruction ?? '').trim();
  if (looksPolish(fromRouter)) return fromRouter;
  return _compose(
    type: type,
    street: _firstStreet(streetNames),
    roundaboutExit: roundaboutExit,
  );
}

/// Krótka forma do wąskich miejsc: Dynamic Island i pasek nad mapą.
///
/// Bez nazwy ulicy — tam, gdzie mieści się jedna linijka, ważniejsze jest
/// „w lewo" niż „w Burgenlandstraße". Nazwa i tak stoi obok, w osobnym polu.
String maneuverShortPl({required int type, int? roundaboutExit}) =>
    _compose(type: type, street: '', roundaboutExit: roundaboutExit);

/// Czy tekst z routera można pokazać rowerzyście.
///
/// Rozstrzyga obecność angielskich słów kluczowych, a nie polskich znaków:
/// „Skręć w prawo w Main Street" jest poprawną polską instrukcją bez ani
/// jednego ogonka, a „Turn left onto Świętokrzyska" ma ich pełno i jest
/// angielska. Liczy się CZASOWNIK, bo to on niesie polecenie.
bool looksPolish(String instruction) {
  final text = instruction.trim();
  if (text.isEmpty) return false;
  final lower = text.toLowerCase();
  for (final marker in _englishMarkers) {
    if (RegExp('(^|[^a-ząćęłńóśźż])$marker([^a-ząćęłńóśźż]|\$)')
        .hasMatch(lower)) {
      return false;
    }
  }
  // Musi zawierać choć jedno polskie słowo instrukcji — inaczej to może być
  // sama nazwa ulicy albo tekst w trzecim języku.
  return _polishMarkers.any(lower.contains);
}

/// Angielskie słowa, po których poznajemy nieprzetłumaczoną instrukcję.
///
/// Wyłącznie takie, które nie są zarazem częścią nazw ulic w Polsce ani
/// w Niemczech — stąd brak „west", „park" czy „center".
const List<String> _englishMarkers = [
  'turn',
  'continue',
  'keep',
  'bear',
  'head',
  'drive',
  'walk',
  'bike',
  'merge',
  'exit',
  'enter',
  'take',
  'roundabout',
  'destination',
  'arrive',
  'straight',
  'slight',
  'sharp',
  'u-turn',
  'uturn',
  'onto',
  'toward',
  'towards',
  'stay',
  'ferry',
  'left',
  'right',
];

const List<String> _polishMarkers = [
  'skręć',
  'jedź',
  'zawróć',
  'trzymaj',
  'rondzie',
  'rondo',
  'zjazd',
  'cel',
  'kontynuuj',
  'wjedź',
  'włącz',
  'prosto',
  'lewo',
  'prawo',
  'meta',
  'start',
  'prom',
];

String _firstStreet(List<String> names) {
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

/// Zdanie złożone z samego typu manewru.
String _compose({
  required int type,
  required String street,
  int? roundaboutExit,
}) {
  switch (type) {
    case ValhallaManeuver.start:
    case ValhallaManeuver.startRight:
    case ValhallaManeuver.startLeft:
      return street.isEmpty ? 'Ruszaj' : 'Ruszaj $_in$street';

    case ValhallaManeuver.destination:
      return 'Cel podróży';
    case ValhallaManeuver.destinationRight:
      return 'Cel znajduje się po prawej stronie';
    case ValhallaManeuver.destinationLeft:
      return 'Cel znajduje się po lewej stronie';

    case ValhallaManeuver.becomes:
      return street.isEmpty ? 'Jedź dalej' : 'Droga przechodzi w $street';
    case ValhallaManeuver.continues:
      return _withStreet('Jedź prosto', street);

    case ValhallaManeuver.slightRight:
      return _turn('Lekko w prawo', street);
    case ValhallaManeuver.right:
      return _turn('Skręć w prawo', street);
    case ValhallaManeuver.sharpRight:
      return _turn('Ostro w prawo', street);
    case ValhallaManeuver.sharpLeft:
      return _turn('Ostro w lewo', street);
    case ValhallaManeuver.left:
      return _turn('Skręć w lewo', street);
    case ValhallaManeuver.slightLeft:
      return _turn('Lekko w lewo', street);

    case ValhallaManeuver.uturnRight:
    case ValhallaManeuver.uturnLeft:
      return street.isEmpty ? 'Zawróć' : 'Zawróć $_in$street';

    case ValhallaManeuver.rampStraight:
      return 'Jedź zjazdem prosto';
    case ValhallaManeuver.rampRight:
      return _withStreet('Zjedź w prawo', street);
    case ValhallaManeuver.rampLeft:
      return _withStreet('Zjedź w lewo', street);
    case ValhallaManeuver.exitRight:
      return _withStreet('Zjazd po prawej', street);
    case ValhallaManeuver.exitLeft:
      return _withStreet('Zjazd po lewej', street);

    case ValhallaManeuver.stayStraight:
      return _withStreet('Trzymaj się środkowego pasa', street);
    case ValhallaManeuver.stayRight:
      return _withStreet('Trzymaj się prawej strony', street);
    case ValhallaManeuver.stayLeft:
      return _withStreet('Trzymaj się lewej strony', street);

    case ValhallaManeuver.merge:
      return _withStreet('Włącz się do ruchu', street);
    case ValhallaManeuver.mergeRight:
      return _withStreet('Włącz się do ruchu z prawej', street);
    case ValhallaManeuver.mergeLeft:
      return _withStreet('Włącz się do ruchu z lewej', street);

    case ValhallaManeuver.roundaboutEnter:
      final exit = roundaboutExit;
      if (exit != null && exit > 0) {
        return 'Na rondzie wybierz $exit. zjazd';
      }
      return 'Wjedź na rondo';
    case ValhallaManeuver.roundaboutExit:
      return street.isEmpty ? 'Zjedź z ronda' : 'Zjedź z ronda $_in$street';

    case ValhallaManeuver.ferryEnter:
      return 'Wjedź na prom';
    case ValhallaManeuver.ferryExit:
      return 'Zjedź z promu';

    default:
      // Nieznany kod to nie jest powód, żeby milczeć — rowerzysta ma przed
      // sobą zakręt i potrzebuje czegokolwiek sensownego.
      return _withStreet('Jedź dalej', street);
  }
}

/// „w" przed nazwą ulicy. Osobna stała, bo powtarza się kilkanaście razy.
const String _in = 'w ';

String _turn(String action, String street) =>
    street.isEmpty ? action : '$action $_in$street';

String _withStreet(String action, String street) =>
    street.isEmpty ? action : '$action, $street';
