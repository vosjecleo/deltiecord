import 'package:deltiecord/services/emoji_completion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds open and closed aliases at a word boundary', () {
    final open = findEmojiCompletion('hello :so', 9);
    expect(open?.query, 'so');
    expect(open?.start, 6);
    expect(open?.closed, isFalse);

    final closed = findEmojiCompletion(':sob:', 5);
    expect(closed?.query, 'sob');
    expect(closed?.closed, isTrue);
  });

  test('ignores escaped aliases, URLs, and timestamps', () {
    expect(findEmojiCompletion(r'\:sob', 5), isNull);
    expect(findEmojiCompletion('https://matrix.to/:sob', 22), isNull);
    expect(findEmojiCompletion('12:30', 5), isNull);
  });

  test('ignores aliases inside inline and fenced code', () {
    expect(findEmojiCompletion('`:sob', 5), isNull);
    const fenced = '```dart\nfinal value = :sob';
    expect(findEmojiCompletion(fenced, fenced.length), isNull);

    const afterFence = '```\n:sob\n```\n:sob';
    final result = findEmojiCompletion(afterFence, afterFence.length);
    expect(result?.query, 'sob');
  });
}
