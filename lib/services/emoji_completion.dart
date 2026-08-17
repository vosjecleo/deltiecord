/// The active colon-alias immediately before the composer caret.
class EmojiCompletion {
  const EmojiCompletion({
    required this.start,
    required this.query,
    required this.closed,
  });

  final int start;
  final String query;
  final bool closed;
}

/// Finds a `:name` or `:name:` completion without interpreting text in code.
///
/// The conservative whitespace boundary also keeps completion out of URLs,
/// timestamps, and ordinary punctuation. A colon preceded by an odd number of
/// backslashes is escaped and intentionally remains literal.
EmojiCompletion? findEmojiCompletion(String text, int cursorOffset) {
  final cursor = cursorOffset.clamp(0, text.length);
  final before = text.substring(0, cursor);
  if (_insideCode(before)) return null;

  final match = RegExp(
    r'(?:^|\s):([a-zA-Z0-9_+-]{3,32})(:?)$',
  ).firstMatch(before);
  if (match == null) return null;
  final start = before.lastIndexOf(
    ':',
    before.length - 1 - (match.group(2)?.length ?? 0),
  );
  if (start < 0 || _isEscaped(before, start)) return null;
  return EmojiCompletion(
    start: start,
    query: match.group(1)!,
    closed: match.group(2) == ':',
  );
}

bool _insideCode(String text) {
  var fenced = false;
  var inline = false;
  for (var index = 0; index < text.length; index++) {
    if (text[index] != '`' || _isEscaped(text, index)) continue;
    var runLength = 1;
    while (index + runLength < text.length && text[index + runLength] == '`') {
      runLength++;
    }
    if (runLength >= 3 && !inline) {
      fenced = !fenced;
    } else if (!fenced && runLength == 1) {
      inline = !inline;
    }
    index += runLength - 1;
  }
  return fenced || inline;
}

bool _isEscaped(String text, int index) {
  var slashes = 0;
  for (var cursor = index - 1; cursor >= 0 && text[cursor] == r'\'; cursor--) {
    slashes++;
  }
  return slashes.isOdd;
}
