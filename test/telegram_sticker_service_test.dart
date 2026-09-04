import 'package:deltiecord/services/telegram_sticker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Telegram sticker-set input', () {
    test('accepts public links and short names', () {
      expect(telegramStickerSetName('Animals'), 'Animals');
      expect(
        telegramStickerSetName('https://t.me/addstickers/Animals'),
        'Animals',
      );
      expect(
        telegramStickerSetName('https://telegram.me/addstickers/Cats_2'),
        'Cats_2',
      );
      expect(
        telegramStickerSetName(
          '\u2068https://t.me/addstickers/CatPusheen/\u2069',
        ),
        'CatPusheen',
      );
      expect(
        telegramStickerSetName(
          'Copied pack: <https://www.t.me/addemoji/Cats_2?ref=share>',
        ),
        'Cats_2',
      );
    });

    test('rejects arbitrary origins and malformed names', () {
      expect(
        telegramStickerSetName('https://example.org/addstickers/Animals'),
        isNull,
      );
      expect(telegramStickerSetName('https://t.me/Animals'), isNull);
      expect(telegramStickerSetName('../Animals'), isNull);
      expect(telegramStickerSetName('_Animals'), isNull);
    });
  });

  test('Deltiecord and Telegram share the 120-item pack ceiling', () {
    expect(maximumStickerPackItems, 120);
  });
}
