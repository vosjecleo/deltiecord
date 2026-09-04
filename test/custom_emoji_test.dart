import 'dart:typed_data';

import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'custom emoji aliases are trimmed, unique and retain media identity',
    () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final items = [
        StickerDraftItem(
          shortcode: 'old',
          bytes: bytes,
          mimeType: 'image/png',
          width: 32,
          height: 24,
        ),
      ];

      final renamed = applyCustomEmojiAliases(items, const ['  party_cat  ']);

      expect(renamed.single.shortcode, 'party_cat');
      expect(renamed.single.bytes, same(bytes));
      expect(renamed.single.assetType, StickerAssetType.emoji);
    },
  );

  test('custom emoji aliases reject invalid and duplicate names', () {
    final item = StickerDraftItem(
      shortcode: 'old',
      bytes: Uint8List.fromList([1]),
      mimeType: 'image/png',
    );

    expect(
      () => applyCustomEmojiAliases([item], const ['not valid']),
      throwsStateError,
    );
    expect(
      () => applyCustomEmojiAliases([item, item], const ['Cat', 'cat']),
      throwsStateError,
    );
  });

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
      expect(message.html, contains('data-deltiecord-emoji-pack="pack-one"'));
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

  test('oversized custom emoji is fitted and centred without stretching', () {
    final source = image.Image(width: 256, height: 128, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(255, 0, 0, 255));
    final prepared = prepareCustomEmojiAsset(
      Uint8List.fromList(image.encodePng(source)),
      'image/png',
      filter: CustomEmojiResizeFilter.bicubic,
    );

    expect(prepared.resized, isTrue);
    expect(prepared.mimeType, 'image/png');
    expect((prepared.width, prepared.height), (128, 128));
    final decoded = image.decodePng(prepared.bytes)!;
    expect(decoded.getPixel(64, 0).a, 0);
    expect(decoded.getPixel(64, 31).a, 0);
    expect(decoded.getPixel(64, 32).a, greaterThan(0));
    expect(decoded.getPixel(64, 95).a, greaterThan(0));
    expect(decoded.getPixel(64, 96).a, 0);
  });

  test('safe custom emoji retains its original bytes and animation type', () {
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 64, height: 48)),
    );
    final prepared = prepareCustomEmojiAsset(
      bytes,
      'image/png',
      filter: CustomEmojiResizeFilter.bilinear,
    );

    expect(prepared.resized, isFalse);
    expect(identical(prepared.bytes, bytes), isTrue);
    expect((prepared.width, prepared.height), (64, 48));
  });

  test('transparent padding is trimmed only when explicitly requested', () {
    final source = image.Image(width: 64, height: 64, numChannels: 4);
    image.fillRect(
      source,
      x1: 20,
      y1: 20,
      x2: 43,
      y2: 43,
      color: image.ColorRgba8(255, 0, 0, 255),
    );
    final bytes = Uint8List.fromList(image.encodePng(source));

    final untouched = prepareCustomEmojiAsset(
      bytes,
      'image/png',
      filter: CustomEmojiResizeFilter.bicubic,
    );
    final trimmed = prepareCustomEmojiAsset(
      bytes,
      'image/png',
      filter: CustomEmojiResizeFilter.bicubic,
      trimTransparentPadding: true,
    );

    expect(identical(untouched.bytes, bytes), isTrue);
    expect(untouched.resized, isFalse);
    expect(trimmed.resized, isTrue);
    expect((trimmed.width, trimmed.height), (128, 128));
    final decoded = image.decodePng(trimmed.bytes)!;
    expect(decoded.getPixel(64, 0).a, greaterThan(0));
    expect(decoded.getPixel(64, 127).a, greaterThan(0));
    expect(decoded.getPixel(0, 64).a, greaterThan(0));
    expect(decoded.getPixel(127, 64).a, greaterThan(0));
  });

  test('trimming rejects a wholly transparent custom emoji', () {
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 32, height: 32, numChannels: 4)),
    );

    expect(
      () => prepareCustomEmojiAsset(
        bytes,
        'image/png',
        filter: CustomEmojiResizeFilter.bilinear,
        trimTransparentPadding: true,
      ),
      throwsStateError,
    );
  });
}
