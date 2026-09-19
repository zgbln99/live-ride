import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/models/live_privacy.dart';

void main() {
  group('prywatność LIVE', () {
    test('domyślnie widać pozycję i prędkość, ale nie tętno i moc', () {
      const privacy = LivePrivacy();
      expect(privacy.sharePosition, isTrue);
      expect(privacy.shareSpeed, isTrue);
      expect(privacy.shareHeartRate, isFalse);
      expect(privacy.sharePower, isFalse);
      expect(privacy.sharesAnything, isTrue);
    });

    test('wyłączenie wszystkiego jest rozpoznawane', () {
      const privacy = LivePrivacy(sharePosition: false, shareSpeed: false);
      expect(privacy.sharesAnything, isFalse);
    });

    test('copyWith zmienia jedno pole i nie rusza reszty', () {
      const privacy = LivePrivacy();
      final next = privacy.copyWith(shareHeartRate: true);
      expect(next.shareHeartRate, isTrue);
      expect(next.sharePosition, privacy.sharePosition);
      expect(next.sharePower, privacy.sharePower);
    });

    test('przechodzi przez JSON', () {
      const privacy = LivePrivacy(
        sharePosition: true,
        shareSpeed: false,
        shareHeartRate: true,
        sharePower: true,
      );
      final restored = LivePrivacy.fromJson(privacy.toJson());
      expect(restored.shareSpeed, isFalse);
      expect(restored.shareHeartRate, isTrue);
      expect(restored.sharePower, isTrue);
    });
  });

  group('wiadomości', () {
    test('wpis bez treści nie powstaje', () {
      expect(LiveMessage.fromJson({'id': 'm1'}), isNull);
      expect(LiveMessage.fromJson({'body': 'cześć'}), isNull);
    });

    test('czas bez strefy nie wywala parsowania', () {
      final message = LiveMessage.fromJson({
        'id': 'm1',
        'body': 'Czekam na was',
        'sent_at': 'to nie jest data',
        'display_name': 'Marek',
      })!;
      expect(message.body, 'Czekam na was');
      expect(message.author, 'Marek');
      expect(message.sentAt, isNotNull);
    });

    test('szybkie wiadomości mają niepustą treść', () {
      for (final message in QuickMessage.values) {
        expect(message.body.trim(), isNotEmpty);
        expect(message.body.length, lessThanOrEqualTo(280));
      }
    });
  });
}
