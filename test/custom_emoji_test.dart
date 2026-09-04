import 'dart:typed_data';

import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  final first = CustomEmojiReference(
    id: Uri(scheme: 'mxc', host: 'one.test', path: '/same-id'),
    name: 'party',
    packId: 'pack-one',
  );
  final second = CustomEmojiReference(
    id: Uri(scheme: 'mxc', host: 'two.test', path: '/other-id'),
    name: 'party',
    packId: 'pack-two',
  );

  test('image packs allow up to 120 items', () {
    expect(StickerPackDraft.maximumItems, 120);
  });

  test('editor links round trip immutable IDs and fallback metadata', () {
    expect(
      customEmojiFromEditorLink(customEmojiEditorLink(first))?.id,
      first.id,
    );
    expect(
      customEmojiFromEditorLink(customEmojiEditorLink(first))?.fallback,
      ':party:',
    );
    expect(customEmojiEditorLink(first), isNot(customEmojiEditorLink(second)));
  });

  test(
    'plain composer text serializes custom emoji as Matrix inline media',
    () {
      const text = 'hello :party: world';
      final message = serializeCustomEmojiText(text, [
        CustomEmojiTextSpan(start: 6, end: 13, emoji: first),
      ]);

      expect(message.plainText, text);
      expect(message.html, contains('data-mx-emoticon'));
      expect(message.html, contains('mxc://one.test/same-id'));
      expect(message.html, contains('alt=":party:"'));
    },
  );

  test('editing a fallback removes its stale stable-ID association', () {
    final shifted = reconcileCustomEmojiSpans('x :party:', 'hello x :party:', [
      CustomEmojiTextSpan(start: 2, end: 9, emoji: first),
    ]);
    expect(shifted.single.start, 8);
    expect(shifted.single.end, 15);

    final removed = reconcileCustomEmojiSpans(
      'hello x :party:',
      'hello x :part:',
      shifted,
    );
    expect(removed, isEmpty);
  });

  test('draft delta retains stable custom emoji references', () {
    const text = 'a :party: b';
    final delta = customEmojiDraftDelta(text, [
      CustomEmojiTextSpan(start: 2, end: 9, emoji: first),
    ]);
    final restored = customEmojiDraftFromDelta(delta);

    expect(restored.text, text);
    expect(restored.emojis.single.emoji.id, first.id);
    expect(restored.emojis.single.emoji.packId, 'pack-one');
  });

  test('historical formatted messages restore editable stable references', () {
    final spans = customEmojiSpansFromHtml(
      'hello ${customEmojiHtml(first)} and ${customEmojiHtml(second)}',
      'hello :party: and :party:',
    );

    expect(spans.map((span) => span.start), [6, 18]);
    expect(spans.map((span) => span.emoji.id), [first.id, second.id]);
  });

  test('legacy dual-usage stickers do not silently become emoji', () {
    expect(
      stickerAssetTypeFromImagePackItem({
        'usage': ['sticker', 'emoticon'],
      }),
      StickerAssetType.sticker,
    );
    expect(
      stickerAssetTypeFromImagePackItem({
        'usage': ['emoticon'],
      }),
      StickerAssetType.emoji,
    );
    expect(
      stickerAssetTypeFromImagePackItem({
        'usage': ['sticker'],
        'net.deltiecord.asset_type': 'emoji',
      }),
      StickerAssetType.emoji,
    );
  });

  test('custom emoji dimensions are bounded before pixel decode', () {
    final valid = Uint8List.fromList(
      image.encodePng(image.Image(width: 128, height: 128)),
    );
    expect(validateCustomEmojiAsset(valid, 'image/png'), (
      width: 128,
      height: 128,
    ));

    final oversized = Uint8List.fromList(
      image.encodePng(image.Image(width: 129, height: 1)),
    );
    expect(
      () => validateCustomEmojiAsset(oversized, 'image/png'),
      throwsStateError,
    );
    expect(
      () => validateCustomEmojiAsset(valid, 'application/octet-stream'),
      throwsStateError,
    );
  });
}
