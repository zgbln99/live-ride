/// Co zawodnik miał na myśli, wpisując jedno zdanie.
///
/// „Do Poczdamu przez Wannsee", „50 km pętla", „40 km płasko", „około dwie
/// godziny". To są całe polecenia, jakich ludzie używają, mówiąc o jeździe —
/// i dokładnie tego dotąd brakowało: żeby zaplanować trasę, trzeba było
/// najpierw ręcznie klikać punkty na mapie.
///
/// Parser jest DETERMINISTYCZNY i lokalny. Żadnego modelu językowego: te
/// polecenia mają skończoną liczbę kształtów, a odpowiedź musi przyjść
/// natychmiast, także bez zasięgu. Czego nie rozumie, tego nie zgaduje —
/// zostaje wtedy zwykłym wyszukiwaniem miejsca.
library;

import '../models/route/route_preferences.dart';

/// Kształt trasy.
enum RouteShape {
  /// Z punktu A do punktu B.
  destination,

  /// Wyjazd z domu i powrót do domu inną drogą.
  loop,

  /// Tam i tą samą drogą z powrotem.
  outAndBack,
}

/// Czy trasa ma być płaska, pofalowana, czy bez znaczenia.
///
/// Osobne od [RoutePreferences.avoidHills], bo „chcę podjazdy" nie jest
/// przeciwieństwem „unikaj wzniesień" — router umie tylko to drugie, a nas
/// interesuje też wybór spośród kilku wygenerowanych wariantów.
enum ElevationPreference { any, flat, hilly }

/// Czego trasa ma unikać. Tylko to, co router naprawdę umie omijać.
enum RouteAvoid { ferries, mainRoads, unpaved }

/// Rozłożone na części polecenie.
class RouteIntent {
  const RouteIntent({
    required this.text,
    this.destination,
    this.via = const [],
    this.distanceMeters,
    this.duration,
    this.shape = RouteShape.destination,
    this.surface,
    this.elevation = ElevationPreference.any,
    this.mood,
    this.avoid = const {},
  });

  /// Co zawodnik wpisał, bez zmian.
  final String text;

  /// Dokąd. Null przy poleceniu opartym wyłącznie o dystans albo czas.
  final String? destination;

  /// Przez jakie miejsca po drodze.
  final List<String> via;

  final double? distanceMeters;
  final Duration? duration;
  final RouteShape shape;

  /// Null znaczy „bez znaczenia" — wtedy zostaje ustawienie z profilu.
  final SurfacePreference? surface;

  final ElevationPreference elevation;

  /// Null znaczy „bez znaczenia".
  final RouteMood? mood;

  final Set<RouteAvoid> avoid;

  /// Nakłada polecenie na ustawienia zawodnika.
  ///
  /// Preferencje z profilu są podkładem, a nie konkurencją: zdanie mówi
  /// o TEJ jeździe i zmienia tylko to, co w nim padło.
  RoutePreferences applyTo(RoutePreferences base) => base.copyWith(
    surface: surface ?? base.surface,
    mood: mood ?? base.mood,
    avoidHills: elevation == ElevationPreference.flat ? true : base.avoidHills,
    avoidFerries: avoid.contains(RouteAvoid.ferries) ? true : base.avoidFerries,
    avoidBusyRoads:
        avoid.contains(RouteAvoid.mainRoads) ? true : base.avoidBusyRoads,
    returnToStart: returnsHome ? true : base.returnToStart,
  );

  /// Czy z tego polecenia da się cokolwiek zbudować.
  bool get isUsable =>
      destination != null || distanceMeters != null || duration != null;

  /// Czy trasa ma wrócić tam, skąd wyjechaliśmy.
  bool get returnsHome =>
      shape == RouteShape.loop || shape == RouteShape.outAndBack;

  /// Warianty nazwy do wysłania geokoderowi, w kolejności prób.
  ///
  /// Polski dopełniacz („do Poczdamu") nie jest nazwą, którą zna mapa.
  /// Zamiast udawać odmianę gramatyczną, podajemy kilka kandydatów
  /// i pozwalamy geokoderowi wybrać ten, który istnieje.
  static List<String> candidatesFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const [];
    final out = <String>[trimmed];

    void add(String value) {
      if (value.length >= 3 && !out.contains(value)) out.add(value);
    }

    // Poczdamu → Poczdam, Krakowa → Krakow, Berlina → Berlin.
    if (trimmed.endsWith('u') || trimmed.endsWith('a')) {
      add(trimmed.substring(0, trimmed.length - 1));
    }
    // Warszawy → Warszawa, Gdyni → Gdynia.
    if (trimmed.endsWith('y') || trimmed.endsWith('i')) {
      add('${trimmed.substring(0, trimmed.length - 1)}a');
    }
    // Katowic → Katowice, Kielc → Kielce.
    if (trimmed.endsWith('c')) add('${trimmed}e');
    return out;
  }
}

const _distancePattern = r'(\d+(?:[.,]\d+)?)\s*(?:km|kilometr\w*)';
const _hoursPattern = r'(\d+(?:[.,]\d+)?)\s*(?:h\b|godz\w*)';
const _minutesPattern = r'(\d+)\s*(?:min\w*)';
const _clockPattern = r'(\d+):([0-5]\d)\s*(?:h\b|godz\w*)';

/// Rozkłada polecenie na części.
RouteIntent parseRouteIntent(String input) {
  final text = input.trim();
  if (text.isEmpty) return RouteIntent(text: input);
  final lower = text.toLowerCase();

  final distance = _distance(lower);
  final duration = _duration(lower);
  final shape = _shape(lower);
  final destination = _after(text, lower, 'do ');
  final via = _allAfter(text, lower, 'przez ');

  return RouteIntent(
    text: text,
    // Samo „Potsdam" też jest poleceniem — i najczęstszym.
    destination: destination ?? _bareDestination(text, lower, distance, duration),
    via: via,
    distanceMeters: distance,
    duration: duration,
    shape: shape,
    surface: _surface(lower),
    elevation: _elevation(lower),
    mood: _mood(lower),
    avoid: _avoid(lower),
  );
}

double? _distance(String lower) {
  final match = RegExp(_distancePattern).firstMatch(lower);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (value == null || value <= 0 || value > 500) return null;
  return value * 1000;
}

Duration? _duration(String lower) {
  final clock = RegExp(_clockPattern).firstMatch(lower);
  if (clock != null) {
    return Duration(
      hours: int.parse(clock.group(1)!),
      minutes: int.parse(clock.group(2)!),
    );
  }
  // „półtorej godziny" i „pół godziny" to zwroty, które ludzie wpisują
  // częściej niż „1,5 h".
  if (lower.contains('półtorej')) return const Duration(minutes: 90);
  if (RegExp(r'pół\s+godz').hasMatch(lower)) return const Duration(minutes: 30);

  var total = Duration.zero;
  final hours = RegExp(_hoursPattern).firstMatch(lower);
  if (hours != null) {
    final value = double.tryParse(hours.group(1)!.replaceAll(',', '.')) ?? 0;
    total += Duration(minutes: (value * 60).round());
  }
  final minutes = RegExp(_minutesPattern).firstMatch(lower);
  if (minutes != null) {
    total += Duration(minutes: int.parse(minutes.group(1)!));
  }
  if (total == Duration.zero) return null;
  if (total > const Duration(hours: 24)) return null;
  return total;
}

RouteShape _shape(String lower) {
  // „Pętla" wygrywa z „i wróć tutaj": pętla NIE jest tą samą drogą
  // z powrotem i dopisek o powrocie jej tego nie zmienia.
  if (lower.contains('pętl') || lower.contains('petl')) return RouteShape.loop;
  if (lower.contains('w kółko') || lower.contains('kółeczko')) {
    return RouteShape.loop;
  }
  if (lower.contains('z powrotem') || lower.contains('tam i spowrotem')) {
    return RouteShape.outAndBack;
  }
  return RouteShape.destination;
}

SurfacePreference? _surface(String lower) {
  if (lower.contains('gravel') ||
      lower.contains('szuter') ||
      lower.contains('żwir') ||
      lower.contains('szutr')) {
    return SurfacePreference.unpaved;
  }
  if (lower.contains('asfalt')) return SurfacePreference.paved;
  if (lower.contains('mieszan')) return SurfacePreference.mixed;
  return null;
}

ElevationPreference _elevation(String lower) {
  // Kolejność ma znaczenie: „bez dużych podjazdów" zawiera słowo „podjazd".
  if (lower.contains('płask') ||
      lower.contains('plask') ||
      RegExp(r'bez\s+(?:dużych\s+|wielkich\s+)?(?:podjazd|gór|wzni)')
          .hasMatch(lower)) {
    return ElevationPreference.flat;
  }
  if (lower.contains('podjazd') ||
      lower.contains('pagórk') ||
      lower.contains('góry') ||
      lower.contains('przewyższ')) {
    return ElevationPreference.hilly;
  }
  return ElevationPreference.any;
}

RouteMood? _mood(String lower) {
  if (lower.contains('spokojn') ||
      lower.contains('mało ruchu') ||
      lower.contains('bez ruchu')) {
    return RouteMood.quiet;
  }
  if (lower.contains('najszybciej') || lower.contains('najkrócej')) {
    return RouteMood.fast;
  }
  return null;
}

Set<RouteAvoid> _avoid(String lower) {
  final avoid = <RouteAvoid>{};
  if (lower.contains('prom')) avoid.add(RouteAvoid.ferries);
  if (RegExp(r'(?:bez|unikaj)\s+(?:głównych|ruchliwych)').hasMatch(lower) ||
      lower.contains('bez krajow')) {
    avoid.add(RouteAvoid.mainRoads);
  }
  if (lower.contains('nieutwardzon') || lower.contains('bez szutru')) {
    avoid.add(RouteAvoid.unpaved);
  }
  return avoid;
}

/// Wyciąga nazwę miejsca stojącą po słowie kluczowym.
String? _after(String text, String lower, String keyword) {
  final index = lower.indexOf(keyword);
  if (index < 0) return null;
  // Słowo kluczowe musi stać na początku wyrazu, inaczej „dojazd" wyglądałby
  // jak „do jazd".
  if (index > 0 && RegExp(r'\w').hasMatch(lower[index - 1])) return null;
  final rest = text.substring(index + keyword.length);
  return _placeName(rest);
}

List<String> _allAfter(String text, String lower, String keyword) {
  final names = <String>[];
  var from = 0;
  while (true) {
    final index = lower.indexOf(keyword, from);
    if (index < 0) break;
    from = index + keyword.length;
    if (index > 0 && RegExp(r'\w').hasMatch(lower[index - 1])) continue;
    final name = _placeName(text.substring(from));
    if (name != null) names.add(name);
  }
  return names;
}

/// Nazwy kończą się na przecinku albo na kolejnym słowie kluczowym.
///
/// Bez tego „do Poczdamu przez Wannsee" dałoby cel „Poczdamu przez Wannsee",
/// którego żaden geokoder nie zna.
const _stopWords = [
  ' przez ',
  ' i ',
  ' oraz ',
  ' potem ',
  ' a ',
  ',',
  ';',
];

String? _placeName(String rest) {
  var name = rest.trim();
  if (name.isEmpty) return null;
  final lower = name.toLowerCase();
  var cut = name.length;
  for (final stop in _stopWords) {
    final index = lower.indexOf(stop);
    if (index >= 0 && index < cut) cut = index;
  }
  name = name.substring(0, cut).trim();
  // Fragment, który jest wyłącznie liczbą albo preferencją, nie jest nazwą.
  name = name.replaceAll(RegExp(_distancePattern), '').trim();
  if (name.isEmpty) return null;
  if (RegExp(r'^[\d\s.,:-]+$').hasMatch(name)) return null;
  return name;
}

/// Polecenie bez słowa „do": samo „Potsdam" albo „Brama Brandenburska".
String? _bareDestination(
  String text,
  String lower,
  double? distance,
  Duration? duration,
) {
  // Gdy w zdaniu jest dystans albo czas, brak „do" znaczy „dobierz sam".
  if (distance != null || duration != null) return null;
  final cleaned = text
      .replaceAll(RegExp(r'\b(pętla|pętlę|petla|w kółko)\b', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'\b(asfalt\w*|gravel|szuter\w*|żwir\w*|płask\w*|spokojn\w*|'
          r'najszybciej|najkrócej|mieszan\w*)\b',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  if (cleaned.isEmpty) return null;
  if (RegExp(r'^[\d\s.,:-]+$').hasMatch(cleaned)) return null;
  // Całe zdanie z czasownikiem to nie jest nazwa miejsca.
  if (lower.contains('chcę') || lower.contains('jadę')) return null;
  return cleaned;
}
