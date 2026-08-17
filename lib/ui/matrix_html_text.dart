import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import 'deltiecord_theme.dart';

final _emojiPresentationPattern = RegExp(
  r'[\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{2194}-\u{21FF}\u{2300}-\u{23FF}\u{25A0}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F000}-\u{1FAFF}]',
  unicode: true,
);

List<InlineSpan> _emojiAwareTextSpans(
  BuildContext context,
  String text,
  TextStyle style,
) {
  if (text.isEmpty) return const [];
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  bool? bufferedEmoji;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: bufferedEmoji == true
            ? style.copyWith(fontFamily: context.deltiecordEmojiFont)
            : style,
      ),
    );
    buffer.clear();
  }

  for (final cluster in text.characters) {
    final isEmoji = _emojiPresentationPattern.hasMatch(cluster);
    if (bufferedEmoji != null && bufferedEmoji != isEmoji) flush();
    bufferedEmoji = isEmoji;
    buffer.write(cluster);
  }
  flush();
  return spans;
}

class MatrixPlainText extends StatefulWidget {
  const MatrixPlainText({
    required this.text,
    this.style,
    this.selectable = true,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  State<MatrixPlainText> createState() => _MatrixPlainTextState();
}

class _MatrixPlainTextState extends State<MatrixPlainText> {
  static final _urlPattern = RegExp(r'https?://[^\s<>]+');
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > offset) {
        spans.addAll(
          _emojiAwareTextSpans(
            context,
            widget.text.substring(offset, match.start),
            widget.style ?? const TextStyle(),
          ),
        );
      }
      final matched = match.group(0)!;
      final trailing =
          RegExp(r'[.,;:!?]+$').firstMatch(matched)?.group(0) ?? '';
      final linkText = trailing.isEmpty
          ? matched
          : matched.substring(0, matched.length - trailing.length);
      final uri = Uri.tryParse(linkText);
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (uri != null) launchUrl(uri);
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: linkText,
          style: const TextStyle(
            color: Color(0xffaeb7ff),
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ),
      );
      if (trailing.isNotEmpty) {
        spans.addAll(
          _emojiAwareTextSpans(
            context,
            trailing,
            widget.style ?? const TextStyle(),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < widget.text.length) {
      spans.addAll(
        _emojiAwareTextSpans(
          context,
          widget.text.substring(offset),
          widget.style ?? const TextStyle(),
        ),
      );
    }
    final span = TextSpan(style: widget.style, children: spans);
    return widget.selectable
        ? SelectableText.rich(span, contextMenuBuilder: _noContextMenu)
        : Text.rich(span);
  }
}

/// Compact renderer for Matrix's sanitized `org.matrix.custom.html` subset.
/// Unsupported elements degrade to their text children instead of creating
/// arbitrary widgets or executing external content.
class MatrixHtmlText extends StatefulWidget {
  const MatrixHtmlText({
    required this.html,
    required this.fallback,
    this.selectable = true,
    super.key,
  });

  final String html;
  final String fallback;
  final bool selectable;

  @override
  State<MatrixHtmlText> createState() => _MatrixHtmlTextState();
}

class _MatrixHtmlTextState extends State<MatrixHtmlText> {
  late final TapGestureRecognizer _spoilerTap = TapGestureRecognizer()
    ..onTap = () => setState(() => _spoilersRevealed = true);
  final List<TapGestureRecognizer> _linkRecognizers = [];
  bool _spoilersRevealed = false;

  @override
  void dispose() {
    _spoilerTap.dispose();
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = html_parser.parseFragment(widget.html);
    final spans = List<InlineSpan>.of(
      _nodes(document.nodes, const TextStyle(height: 1.28)),
    );
    // Block elements need separators between one another, but the final block
    // newline is layout metadata rather than visible message content. Keeping
    // it creates an empty row below rich messages such as underscored paths.
    if (spans.isNotEmpty) {
      final lastSpan = spans.last;
      if (lastSpan is TextSpan && lastSpan.text == '\n') spans.removeLast();
    }
    if (spans.isEmpty) {
      final span = TextSpan(
        children: _emojiAwareTextSpans(
          context,
          widget.fallback,
          const TextStyle(),
        ),
      );
      return widget.selectable
          ? SelectableText.rich(span, contextMenuBuilder: _noContextMenu)
          : Text.rich(span);
    }
    final span = TextSpan(children: spans);
    return widget.selectable
        ? SelectableText.rich(span, contextMenuBuilder: _noContextMenu)
        : Text.rich(span);
  }

  List<InlineSpan> _nodes(Iterable<dom.Node> nodes, TextStyle style) =>
      nodes.expand((node) => _node(node, style)).toList(growable: false);

  List<InlineSpan> _node(dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      return _emojiAwareTextSpans(context, node.data, style);
    }
    if (node is! dom.Element) return const [];
    final tag = node.localName;
    if (tag == 'mx-reply') return const [];
    if (tag == 'br') return const [TextSpan(text: '\n')];
    if (node.attributes.containsKey('data-mx-spoiler') && !_spoilersRevealed) {
      const concealedColor = Color(0xff777985);
      return [
        TextSpan(
          // Draw the real glyph run in the same colour as its background. The
          // spoiler therefore occupies exactly the size of the concealed text
          // at the current font scale instead of using a fixed-size badge.
          text: node.text,
          style: style.copyWith(
            color: concealedColor,
            backgroundColor: concealedColor,
          ),
          recognizer: _spoilerTap,
        ),
      ];
    }

    var childStyle = style;
    switch (tag) {
      case 'strong':
      case 'b':
        childStyle = style.copyWith(fontWeight: FontWeight.bold);
      case 'em':
      case 'i':
        childStyle = style.copyWith(fontStyle: FontStyle.italic);
      case 'u':
        childStyle = style.copyWith(decoration: TextDecoration.underline);
      case 'del':
      case 's':
        childStyle = style.copyWith(decoration: TextDecoration.lineThrough);
      case 'code':
        childStyle = style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: const Color(0xff191a1e),
        );
      case 'a':
        childStyle = style.copyWith(
          color: const Color(0xffaeb7ff),
          decoration: TextDecoration.underline,
        );
    }

    final children = _nodes(node.nodes, childStyle);
    if (tag == 'a') {
      final href = node.attributes['href'];
      final isMention =
          href?.contains('/#/user/@') == true ||
          node.text.trimLeft().startsWith('@');
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          final uri = href == null ? null : Uri.tryParse(href);
          if (uri != null && {'http', 'https'}.contains(uri.scheme)) {
            launchUrl(uri);
          }
        };
      _linkRecognizers.add(recognizer);
      return [
        TextSpan(
          children: children,
          style: isMention
              ? childStyle.copyWith(
                  backgroundColor: const Color(0xff3f456c),
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w600,
                )
              : childStyle,
          recognizer: recognizer,
        ),
      ];
    }
    if (tag == 'blockquote') {
      return [
        const TextSpan(
          text: '│ ',
          style: TextStyle(color: Color(0xff747fdb)),
        ),
        ...children,
        const TextSpan(text: '\n'),
      ];
    }
    if (tag == 'li') {
      return [
        const TextSpan(text: '• '),
        ...children,
        const TextSpan(text: '\n'),
      ];
    }
    if ({'p', 'div', 'pre'}.contains(tag)) {
      return [...children, const TextSpan(text: '\n')];
    }
    return children;
  }
}

Widget _noContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) => const SizedBox.shrink();
