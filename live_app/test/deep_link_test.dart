import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/services/deep_link_service.dart';

void main() {
  group('link do trasy', () {
    test('rozpoznaje własny schemat aplikacji', () {
      expect(
        DeepLinkService.routeTokenFrom(Uri.parse('liveride://route/abc123')),
        'abc123',
      );
    });

    test('rozpoznaje zwykły adres strony', () {
      expect(
        DeepLinkService.routeTokenFrom(
          Uri.parse('https://ride.example.com/route/xyz789'),
        ),
        'xyz789',
      );
    });

    test('nie łapie adresów powrotnych logowania', () {
      // Spotify i Strava używają tego samego schematu; przejęcie ich adresu
      // zepsułoby logowanie do obu.
      for (final url in [
        'liveride://spotify-callback?code=1',
        'liveride://strava-callback?code=2',
      ]) {
        expect(
          DeepLinkService.routeTokenFrom(Uri.parse(url)),
          isNull,
          reason: url,
        );
      }
    });

    test('nie łapie podglądu jazdy na żywo', () {
      // Link LIVE otwiera się w przeglądarce i nie ma czego importować.
      expect(
        DeepLinkService.routeTokenFrom(
          Uri.parse('https://ride.example.com/live/abc123'),
        ),
        isNull,
      );
    });

    test('odrzuca adresy bez tokenu', () {
      for (final url in [
        'liveride://route',
        'liveride://route/',
        'https://ride.example.com/route',
        'https://ride.example.com/',
      ]) {
        expect(
          DeepLinkService.routeTokenFrom(Uri.parse(url)),
          isNull,
          reason: url,
        );
      }
    });
  });

  group('kolejka linków', () {
    test('token zabiera się dokładnie raz', () {
      final service = DeepLinkService();
      service.handle(Uri.parse('liveride://route/abc123'));

      expect(service.pendingRouteToken, 'abc123');
      expect(service.takeRouteToken(), 'abc123');
      // Drugie sięgnięcie nie może powtórzyć pytania o import.
      expect(service.takeRouteToken(), isNull);
      service.dispose();
    });

    test('nieznany link niczego nie kolejkuje', () {
      final service = DeepLinkService();
      service.handle(Uri.parse('liveride://spotify-callback'));
      expect(service.pendingRouteToken, isNull);
      service.dispose();
    });

    test('nowszy link zastępuje starszy', () {
      final service = DeepLinkService();
      service.handle(Uri.parse('liveride://route/pierwszy'));
      service.handle(Uri.parse('liveride://route/drugi'));
      expect(service.takeRouteToken(), 'drugi');
      service.dispose();
    });
  });
}
