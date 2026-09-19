import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/music.dart';

void main() {
  group('NowPlaying', () {
    Map<String, dynamic> playerBody({
      bool playing = true,
      int progress = 30000,
    }) => {
      'is_playing': playing,
      'progress_ms': progress,
      'shuffle_state': true,
      'repeat_state': 'context',
      'device': {
        'id': 'dev1',
        'name': 'iPhone',
        'type': 'Smartphone',
        'is_active': true,
        'volume_percent': 65,
      },
      'item': {
        'id': 'track1',
        'name': 'Windmills',
        'duration_ms': 210000,
        'artists': [
          {'name': 'Rider One'},
          {'name': 'Rider Two'},
        ],
        'album': {
          'name': 'Tailwind',
          'images': [
            {'url': 'https://example.com/art.jpg'},
          ],
        },
      },
    };

    test('reads the track, artists, album art and device', () {
      final track = NowPlaying.fromJson(playerBody());
      expect(track.title, 'Windmills');
      expect(track.artist, 'Rider One, Rider Two');
      expect(track.album, 'Tailwind');
      expect(track.artworkUrl, 'https://example.com/art.jpg');
      expect(track.deviceName, 'iPhone');
      expect(track.volumePercent, 65);
      expect(track.shuffle, isTrue);
      expect(track.isPlaying, isTrue);
    });

    test('survives a response with no track', () {
      final track = NowPlaying.fromJson({'is_playing': false});
      expect(track.title, 'Nothing');
      expect(track.artist, '');
      expect(track.artworkUrl, isNull);
      expect(track.fraction, 0);
    });

    test('advances progress between polls while playing', () async {
      final track = NowPlaying.fromJson(playerBody(progress: 30000));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(track.liveProgressMs, greaterThan(30000));
    });

    test('holds progress still while paused', () async {
      final track = NowPlaying.fromJson(
        playerBody(playing: false, progress: 30000),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(track.liveProgressMs, 30000);
    });

    test('never runs progress past the end of the track', () {
      final track = NowPlaying.fromJson(playerBody(progress: 210000));
      expect(track.fraction, 1.0);
      expect(track.liveProgressMs, lessThanOrEqualTo(210000));
    });
  });

  group('SpotifyDevice', () {
    test('reads the device list shape', () {
      final device = SpotifyDevice.fromJson({
        'id': 'abc',
        'name': 'Kitchen',
        'type': 'Speaker',
        'is_active': false,
        'volume_percent': 40,
      });
      expect(device.name, 'Kitchen');
      expect(device.type, 'Speaker');
      expect(device.isActive, isFalse);
      expect(device.volumePercent, 40);
    });
  });

  group('PKCE', () {
    // Spotify's documented PKCE example: the challenge is the base64url of
    // the SHA-256 of the verifier, with padding removed.
    test('derives the challenge the way Spotify expects', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

      expect(challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      expect(challenge.contains('='), isFalse);
      expect(challenge.contains('+'), isFalse);
      expect(challenge.contains('/'), isFalse);
    });
  });
}
