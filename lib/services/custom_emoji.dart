import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:html/parser.dart' as html_parser;

import '../models/chat_models.dart';

const _editorEmojiHost = 'emoji.deltiecord.invalid';

enum CustomEmojiResizeFilter { bilinear, bicubic }

final class PreparedCustomEmoji {
  const PreparedCustomEmoji({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.resized,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final bool resized;
}

List<StickerDraftItem> applyCustomEmojiAliases(
  List<StickerDraftItem> items,
  List<String> aliases,
) {
  if (items.length != aliases.length) {
    throw StateError('Every custom emoji needs an alias.');
  }
  final trimmed = aliases.map((alias) => alias.trim()).toList(growable: false);
  if (trimmed.any(
    (alias) => !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$').hasMatch(alias),
  )) {
    throw StateError('Use 1–100 letters, numbers, underscores or hyphens.');
  }
  if (trimmed.map((alias) => alias.toLowerCase()).toSet().length !=
      trimmed.length) {
    throw StateError('Every emoji alias in a pack must be unique.');
  }
  return [
    for (var index = 0; index < items.length; index++)
      StickerDraftItem(
        shortcode: trimmed[index],
        bytes: items[index].bytes,
        mimeType: items[index].mimeType,
        width: items[index].width,
        height: items[index].height,
        assetType: StickerAssetType.emoji,
      ),
  ];
}

/// Converts an oversized static emoji into a centred 128×128 PNG.
///
/// The longest edge is reduced to 128 without changing the aspect ratio; the
/// other edge is centred on transparent pixels. Assets already within the
/// emoji limits are returned byte-for-byte so GIF/WebP animation is retained.
PreparedCustomEmoji prepareCustomEmojiAsset(
  Uint8List bytes,
  String mimeType, {
  required CustomEmojiResizeFilter filter,
}) {
  if (!const {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  }.contains(mimeType)) {
    throw StateError('Custom emoji must be PNG, JPEG, GIF or WebP.');
  }
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw StateError('Source emoji images must be at most 5 MiB.');
  }
  final decoder = image.findDecoderForData(bytes);
  final header = decoder?.startDecode(bytes);
  if (header == null ||
      header.width <= 0 ||
      header.height <= 0 ||
      header.width > 4096 ||
      header.height > 4096 ||
      header.width * header.height > 16 * 1024 * 1024) {
    throw StateError('Custom emoji has unsafe or unsupported dimensions.');
  }
  if (header.width <= StickerPackDraft.maximumEmojiDimension &&
      header.height <= StickerPackDraft.maximumEmojiDimension &&
      bytes.length <= StickerPackDraft.maximumEmojiBytes) {
    return PreparedCustomEmoji(
      bytes: bytes,
      mimeType: mimeType,
      width: header.width,
      height: header.height,
      resized: false,
    );
  }

  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw StateError('Could not decode custom emoji.');
  final oriented = image.bakeOrientation(decoded);
  const target = StickerPackDraft.maximumEmojiDimension;
  final scale = target / max(oriented.width, oriented.height);
  final resizedWidth = max(1, (oriented.width * scale).round());
  final resizedHeight = max(1, (oriented.height * scale).round());
  final resized = image.copyResize(
    oriented,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: switch (filter) {
      CustomEmojiResizeFilter.bilinear => image.Interpolation.linear,
      CustomEmojiResizeFilter.bicubic => image.Interpolation.cubic,
    },
  );
  final canvas = image.Image(width: target, height: target, numChannels: 4);
  image.compositeImage(
    canvas,
    resized,
    dstX: (target - resizedWidth) ~/ 2,
    dstY: (target - resizedHeight) ~/ 2,
  );
  final encoded = Uint8List.fromList(image.encodePng(canvas, level: 6));
  if (encoded.length > StickerPackDraft.maximumEmojiBytes) {
    throw StateError('Resized emoji still exceeds 256 KiB.');
  }
  return PreparedCustomEmoji(
    bytes: encoded,
    mimeType: 'image/png',
    width: target,
    height: target,
    resized: true,
  );
}

StickerAssetType stickerAssetTypeFromImagePackItem(Map<String, Object?> item) {
  final explicit = item['net.deltiecord.asset_type'];
  final usage = (item['usage'] as List? ?? const []).whereType<String>();
  // Versions before custom emoji advertised both usages for every sticker.
  // Only an unambiguous standard usage or our explicit marker opts in.
  return explicit == 'emoji' ||
          (usage.contains('emoticon') && !usage.contains('sticker'))
      ? StickerAssetType.emoji
      : StickerAssetType.sticker;
}

({int width, int height}) validateCustomEmojiAsset(
  Uint8List bytes,
  String mimeType,
) {
  if (!const {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  }.contains(mimeType)) {
    throw StateError('Custom emoji must be PNG, JPEG, GIF or WebP.');
  }
  if (bytes.isEmpty || bytes.length > StickerPackDraft.maximumEmojiBytes) {
    throw StateError('Each custom emoji must be at most 256 KiB.');
  }
  // Header parsing obtains canvas bounds without allocating decoded pixels,
  // so a compressed image cannot trigger a large decode before rejection.
  final decoder = image.findDecoderForData(bytes);
  final dimensions = decoder?.startDecode(bytes);
  if (dimensions == null ||
      dimensions.width <= 0 ||
      dimensions.height <= 0 ||
      dimensions.width > StickerPackDraft.maximumEmojiDimension ||
      dimensions.height > StickerPackDraft.maximumEmojiDimension) {
    throw StateError('Custom emoji must be at most 128×128 pixels.');
  }
  return (width: dimensions.width, height: dimensions.height);
}

String customEmojiEditorLink(CustomEmojiReference emoji) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'id': emoji.id.toString(),
            'name': emoji.name,
            if (emoji.packId != null) 'pack': emoji.packId,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'https://$_editorEmojiHost/v1/$payload';
}

CustomEmojiReference? customEmojiFromEditorLink(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != _editorEmojiHost ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first != 'v1') {
    return null;
  }
  try {
    final payload = uri.pathSegments.last;
    final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final data = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (data is! Map) return null;
    final id = Uri.tryParse('${data['id'] ?? ''}');
    final name = '${data['name'] ?? ''}'.trim();
    if (id == null || !id.isScheme('mxc') || name.isEmpty) return null;
    return CustomEmojiReference(
      id: id,
      name: name,
      packId: data['pack'] as String?,
    );
  } catch (_) {
    return null;
  }
}

String customEmojiHtml(CustomEmojiReference emoji) =>
    '<img data-mx-emoticon height="32" '
    'src="${_escapeAttribute(emoji.id.toString())}" '
    'alt="${_escapeAttribute(emoji.fallback)}" '
    'title="${_escapeAttribute(emoji.fallback)}" '
    'data-deltiecord-emoji-id="${_escapeAttribute(emoji.id.toString())}">';

String _escapeAttribute(String value) =>
    htmlEscape.convert(value).replaceAll('&#47;', '/');

/// Replaces editor-only custom-emoji links emitted by flutter_quill with the
/// Matrix custom-emoji `<img data-mx-emoticon>` representation.
String replaceCustomEmojiEditorLinks(String html) => html.replaceAllMapped(
  RegExp(
    r'<a\s+href="(https://emoji\.deltiecord\.invalid/v1/[A-Za-z0-9_-]+)"[^>]*>.*?</a>',
    caseSensitive: false,
  ),
  (match) {
    final emoji = customEmojiFromEditorLink(match.group(1));
    return emoji == null ? match.group(0)! : customEmojiHtml(emoji);
  },
);

({String plainText, String? html}) serializeCustomEmojiText(
  String source,
  List<CustomEmojiTextSpan> spans,
) {
  final leading = source.length - source.trimLeft().length;
  final trailing = source.trimRight().length;
  if (trailing <= leading) return (plainText: '', html: null);
  final text = source.substring(leading, trailing);
  final valid =
      spans
          .where(
            (span) =>
                span.start >= leading &&
                span.end <= trailing &&
                span.start < span.end &&
                source.substring(span.start, span.end) == span.emoji.fallback,
          )
          .toList(growable: false)
        ..sort((a, b) => a.start.compareTo(b.start));
  if (valid.isEmpty) return (plainText: text, html: null);
  final output = StringBuffer();
  var cursor = leading;
  for (final span in valid) {
    if (span.start < cursor) continue;
    output.write(_escapeMessageText(source.substring(cursor, span.start)));
    output.write(customEmojiHtml(span.emoji));
    cursor = span.end;
  }
  output.write(_escapeMessageText(source.substring(cursor, trailing)));
  return (plainText: text, html: output.toString());
}

List<CustomEmojiTextSpan> customEmojiSpansFromHtml(
  String? html,
  String fallback,
) {
  if (html == null || html.isEmpty || fallback.isEmpty) return const [];
  final document = html_parser.parseFragment(html);
  final spans = <CustomEmojiTextSpan>[];
  var cursor = 0;
  for (final element in document.querySelectorAll('img[data-mx-emoticon]')) {
    final id = Uri.tryParse(element.attributes['src'] ?? '');
    final token = element.attributes['alt'] ?? element.attributes['title'];
    if (id == null || !id.isScheme('mxc') || token == null || token.isEmpty) {
      continue;
    }
    final start = fallback.indexOf(token, cursor);
    if (start < 0) continue;
    final name = token.replaceAll(RegExp(r'^:|:$'), '');
    spans.add(
      CustomEmojiTextSpan(
        start: start,
        end: start + token.length,
        emoji: CustomEmojiReference(id: id, name: name),
      ),
    );
    cursor = start + token.length;
  }
  return spans;
}

String _escapeMessageText(String value) =>
    htmlEscape.convert(value).replaceAll('\n', '<br>');

/// Tracks custom-emoji spans through ordinary single-range text edits.
/// Editing any part of a fallback token intentionally converts it to text.
List<CustomEmojiTextSpan> reconcileCustomEmojiSpans(
  String before,
  String after,
  List<CustomEmojiTextSpan> spans,
) {
  if (before == after || spans.isEmpty) return List.of(spans);
  var prefix = 0;
  final shared = before.length < after.length ? before.length : after.length;
  while (prefix < shared &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before.codeUnitAt(before.length - suffix - 1) ==
          after.codeUnitAt(after.length - suffix - 1)) {
    suffix++;
  }
  final oldEnd = before.length - suffix;
  final delta = after.length - before.length;
  return [
    for (final span in spans)
      if (oldEnd <= span.start)
        CustomEmojiTextSpan(
          start: span.start + delta,
          end: span.end + delta,
          emoji: span.emoji,
        )
      else if (prefix >= span.end)
        span,
  ];
}

List<dynamic> customEmojiDraftDelta(
  String text,
  List<CustomEmojiTextSpan> spans,
) {
  final ordered = List<CustomEmojiTextSpan>.of(spans)
    ..sort((a, b) => a.start.compareTo(b.start));
  final operations = <Map<String, Object?>>[];
  var cursor = 0;
  for (final span in ordered) {
    if (span.start < cursor || span.end > text.length) continue;
    if (span.start > cursor) {
      operations.add({'insert': text.substring(cursor, span.start)});
    }
    operations.add({
      'insert': text.substring(span.start, span.end),
      'attributes': {
        'deltiecord_emoji': {
          'id': span.emoji.id.toString(),
          'name': span.emoji.name,
          if (span.emoji.packId != null) 'pack': span.emoji.packId,
        },
      },
    });
    cursor = span.end;
  }
  if (cursor < text.length) operations.add({'insert': text.substring(cursor)});
  operations.add({'insert': '\n'});
  return operations;
}

({String text, List<CustomEmojiTextSpan> emojis}) customEmojiDraftFromDelta(
  List<dynamic> delta,
) {
  final text = StringBuffer();
  final spans = <CustomEmojiTextSpan>[];
  for (final raw in delta.whereType<Map>()) {
    final insert = raw['insert'];
    if (insert is! String) continue;
    final isFinalNewline = identical(raw, delta.last) && insert == '\n';
    if (isFinalNewline) continue;
    final start = text.length;
    text.write(insert);
    final metadata = (raw['attributes'] as Map?)?['deltiecord_emoji'];
    if (metadata is! Map) continue;
    final id = Uri.tryParse('${metadata['id'] ?? ''}');
    final name = '${metadata['name'] ?? ''}'.trim();
    if (id == null || !id.isScheme('mxc') || name.isEmpty) continue;
    spans.add(
      CustomEmojiTextSpan(
        start: start,
        end: start + insert.length,
        emoji: CustomEmojiReference(
          id: id,
          name: name,
          packId: metadata['pack'] as String?,
        ),
      ),
    );
  }
  return (text: text.toString(), emojis: spans);
}
