import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Odbiera linki otwierane spoza aplikacji.
///
/// Na publicznej stronie trasy jest przycisk „Otwórz w Live Ride". Sam
/// schemat `liveride://` jest zarejestrowany w systemie od czasu logowania
/// do Spotify, ale bez tego nasłuchu system co najwyżej przełączyłby na
/// aplikację i nic więcej by się nie stało — przycisk byłby atrapą.
///
/// Rozpoznajemy dwa kształty tego samego adresu:
///
///   `liveride://route/<token>`        — z przycisku na stronie
///   `https://<serwer>/route/<token>`  — gdy link kliknięto w aplikacji,
///                                       która sama otwiera adresy w systemie
class DeepLinkService extends ChangeNotifier {
  DeepLinkService({AppLinks? links}) : _links = links ?? AppLinks();

  final AppLinks _links;
  StreamSubscription<Uri>? _subscription;

  /// Token trasy czekający na obsłużenie, albo null.
  ///
  /// Powłoka aplikacji zabiera go dokładnie raz — inaczej po każdym
  /// przerysowaniu pytałaby o ten sam import.
  String? _pendingRouteToken;
  String? get pendingRouteToken => _pendingRouteToken;

  /// Zaczyna nasłuchiwać i obsługuje link, którym aplikację uruchomiono.
  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = _links.uriLinkStream.listen(
      handle,
      // Zepsuty link nie ma prawa wywrócić startu aplikacji.
      onError: (Object error) => debugPrint('Live Ride: zły link: $error'),
    );
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) handle(initial);
    } catch (e) {
      debugPrint('Live Ride: nie udało się odczytać linku startowego: $e');
    }
  }

  /// Zabiera oczekujący token i od razu go czyści.
  String? takeRouteToken() {
    final token = _pendingRouteToken;
    _pendingRouteToken = null;
    return token;
  }

  @visibleForTesting
  void handle(Uri uri) {
    final token = routeTokenFrom(uri);
    if (token == null) return;
    _pendingRouteToken = token;
    notifyListeners();
  }

  /// Wyciąga token trasy z adresu albo zwraca null.
  ///
  /// Celowo wąsko: tylko ścieżka `route/` z tokenem. Adresy powrotne logowania
  /// (`liveride://spotify-callback`, `liveride://strava-callback`) obsługuje
  /// kto inny i nie mogą tu przypadkiem wpaść.
  @visibleForTesting
  static String? routeTokenFrom(Uri uri) {
    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];

    // `liveride://route/<token>` — „route" trafia do hosta, nie ścieżki.
    if (uri.scheme == 'liveride' && uri.host == 'route') {
      return segments.isEmpty ? null : segments.first;
    }
    if (segments.length >= 2 && segments[segments.length - 2] == 'route') {
      return segments.last;
    }
    return null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
