import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'geo.dart';

/// Trasa przygotowana do narysowania na ekranie blokady.
///
/// Ekran blokady nie ma mapy i nie będzie jej miał: widget rysuje ścieżkę
/// w SwiftUI, a nie kafelki. Potrzebuje więc kształtu, a nie współrzędnych —
/// kilkudziesięciu punktów w kwadracie jednostkowym, gotowych do przeskalowania
/// na dowolny prostokąt.
///
/// Dlaczego nie pełna geometria: ActivityKit liczy każdy bajt stanu aktywności
/// i odrzuca zbyt duże aktualizacje. Trasa na sto kilometrów ma kilkanaście
/// tysięcy punktów; na pasku szerokim na trzysta punktów widać z nich może
/// sześćdziesiąt. Wysyłanie reszty to koszt bez obrazu.
@immutable
class RoutePreview {
  const RoutePreview({required this.points, required this.aspect});

  /// Punkty w kwadracie jednostkowym: x i y w zakresie 0–1.
  ///
  /// Y rośnie w dół, tak jak we współrzędnych ekranu — widget rysuje je
  /// wprost, bez odwracania osi po swojej stronie.
  final List<({double x, double y})> points;

  /// Stosunek szerokości do wysokości ORYGINAŁU.
  ///
  /// Bez niego trasa biegnąca z północy na południe rozciągnęłaby się na całą
  /// szerokość paska i wyglądała jak zupełnie inna droga.
  final double aspect;

  bool get isEmpty => points.length < 2;

  static const RoutePreview empty = RoutePreview(points: [], aspect: 1);

  /// Zapis do wysłania przez kanał metod.
  ///
  /// Pary „x,y" po przecinkach, w tysięcznych — trzy cyfry znaczące wystarczą
  /// dla ścieżki szerokiej na kilkaset pikseli, a skracają ładunek
  /// kilkukrotnie względem pełnych liczb zmiennoprzecinkowych.
  String encode() {
    if (isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < points.length; i++) {
      if (i > 0) buffer.write(';');
      buffer
        ..write((points[i].x * 1000).round())
        ..write(',')
        ..write((points[i].y * 1000).round());
    }
    return buffer.toString();
  }

  /// Odtwarza kształt z zapisu. Używane w testach i po stronie natywnej.
  static RoutePreview decode(String encoded, {double aspect = 1}) {
    if (encoded.isEmpty) return empty;
    final points = <({double x, double y})>[];
    for (final pair in encoded.split(';')) {
      final parts = pair.split(',');
      if (parts.length != 2) continue;
      final x = int.tryParse(parts[0]);
      final y = int.tryParse(parts[1]);
      if (x == null || y == null) continue;
      points.add((x: x / 1000, y: y / 1000));
    }
    return RoutePreview(points: points, aspect: aspect);
  }

  /// Ile najwyżej punktów wysyłamy.
  ///
  /// Sześćdziesiąt to tyle, ile da się rozróżnić na pasku ekranu blokady.
  /// Więcej nie zmienia obrazu, a zmienia rozmiar ładunku.
  static const int maxPoints = 60;

  /// Buduje podgląd z geometrii trasy.
  ///
  /// Skalowanie jest RÓWNOMIERNE w obu osiach: trasa zachowuje kształt,
  /// a nie wypełnia prostokąta. Rozciągnięta wyglądałaby jak inna droga,
  /// a rowerzysta ma ją rozpoznać jednym spojrzeniem.
  factory RoutePreview.fromRoute(List<GeoPoint> route) {
    if (route.length < 2) return empty;

    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLon = double.infinity;
    var maxLon = -double.infinity;
    for (final point in route) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }

    // Stopień długości jest krótszy niż stopień szerokości i im dalej na
    // północ, tym bardziej. Bez tej poprawki trasa w Polsce wychodzi o jakieś
    // czterdzieści procent za szeroka.
    final latScale = math.cos((minLat + maxLat) / 2 * math.pi / 180).abs();
    final width = (maxLon - minLon) * math.max(latScale, 0.05);
    final height = maxLat - minLat;
    final span = math.max(math.max(width, height), 1e-9);

    // Wyśrodkowanie krótszej osi: trasa ma leżeć na środku swojego pola.
    final offsetX = (span - width) / 2;
    final offsetY = (span - height) / 2;

    final thinned = _thin(route, maxPoints);
    final points = <({double x, double y})>[];
    for (final point in thinned) {
      final x =
          ((point.lon - minLon) * math.max(latScale, 0.05) + offsetX) / span;
      // Północ na górze: szerokość rośnie w górę, a y rośnie w dół.
      final y = 1 - ((point.lat - minLat) + offsetY) / span;
      points.add((x: x.clamp(0.0, 1.0), y: y.clamp(0.0, 1.0)));
    }

    return RoutePreview(
      points: points,
      aspect: height <= 0 ? 4 : (width / height).clamp(0.25, 4.0),
    );
  }

  /// Wybiera co n-ty punkt, zawsze zostawiając pierwszy i ostatni.
  ///
  /// Bez ostatniego ścieżka kończyłaby się przed metą, a znacznik celu
  /// wisiałby w powietrzu obok linii.
  static List<GeoPoint> _thin(List<GeoPoint> route, int limit) {
    if (route.length <= limit) return route;
    final step = (route.length - 1) / (limit - 1);
    return [
      for (var i = 0; i < limit - 1; i++) route[(i * step).round()],
      route.last,
    ];
  }
}
