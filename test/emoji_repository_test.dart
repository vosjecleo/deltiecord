import 'package:deltiecord/services/emoji_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local emoji search resolves familiar aliases without network',
    () async {
      final matches = await EmojiRepository.instance.search('sob', limit: 3);
      expect(matches, isNotEmpty);
      expect(matches.first.emoji, '😭');
    },
  );

  test('every local emoji has a canonical searchable name', () async {
    final entries = await EmojiRepository.instance.load();
    expect(entries.length, greaterThan(1800));
    expect(entries.every((entry) => entry.name.trim().isNotEmpty), isTrue);
  });

  test('closed-form familiar aliases resolve exactly', () async {
    expect((await EmojiRepository.instance.exactAlias('sob'))?.emoji, '😭');
    expect(
      (await EmojiRepository.instance.exactAlias('loudly_crying'))?.emoji,
      '😭',
    );
  });

  test('emoji catalogue exposes browse categories', () async {
    final entries = await EmojiRepository.instance.load();
    expect(
      entries.firstWhere((entry) => entry.emoji == '🐵').category,
      EmojiCategory.animalsAndNature,
    );
    expect(
      entries.firstWhere((entry) => entry.emoji == '🏁').category,
      EmojiCategory.flags,
    );
  });

  test('editable alias overrides provide the canonical display name', () async {
    final crying = (await EmojiRepository.instance.search('sob')).first;
    expect(crying.name, 'Loudly crying face');
  });
}
