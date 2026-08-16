import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

const spoilerEditorColor = '#010101';

// Serialization composes flutter_quill, vsc_quill_delta_to_html, and the Dart
// markdown package. No editor implementation is vendored; see CREDITS.md.
({String plainText, String? html}) serializeRichMessage(Document document) {
  final plainText = document.toPlainText().trimRight();
  final operations = document
      .toDelta()
      .toJson()
      .map((operation) => Map<String, dynamic>.from(operation))
      .toList(growable: false);
  final hasFormatting = operations.any(
    (operation) => (operation['attributes'] as Map?)?.isNotEmpty == true,
  );
  if (!hasFormatting) {
    return (plainText: plainText, html: _typedMarkupToHtml(plainText));
  }

  final converter = QuillDeltaToHtmlConverter(
    operations,
    ConverterOptions.forEmail(),
  );
  var html = converter.convert();
  // Quill has no Matrix spoiler attribute. A reserved editor-only background
  // color provides the WYSIWYG treatment, then becomes the standard Matrix
  // data-mx-spoiler element on the wire.
  html = html.replaceAll(
    RegExp(
      r'<span style="background-color:\s*(?:#010101|rgb\(1,\s*1,\s*1\));?">',
      caseSensitive: false,
    ),
    '<span data-mx-spoiler>',
  );
  return (plainText: plainText, html: html);
}

String? _typedMarkupToHtml(String text) {
  final hasMarkup = RegExp(
    r'(^|\n)\s*(?:>|[-*+]\s|\d+\.\s|```)|(^|[\s(])(?:\*\*?\S|_\S|`\S|~~\S|\|\|\S)|\[[^\]]+\]\(',
  ).hasMatch(text);
  if (!hasMarkup) return null;

  final spoilers = <String>[];
  final withTokens = text.replaceAllMapped(RegExp(r'\|\|(.+?)\|\|'), (match) {
    final token = 'DELTIECORDSPOILER${spoilers.length}TOKEN';
    spoilers.add(htmlEscape.convert(match.group(1)!));
    return token;
  });
  var html = markdown.markdownToHtml(
    withTokens,
    extensionSet: markdown.ExtensionSet.gitHubWeb,
  );
  for (var index = 0; index < spoilers.length; index++) {
    html = html.replaceAll(
      'DELTIECORDSPOILER${index}TOKEN',
      '<span data-mx-spoiler>${spoilers[index]}</span>',
    );
  }
  return html;
}
