import '../models/chat_models.dart';

/// Parsed Discord-style search query used by cached and server results.
class MessageSearchQuery {
  const MessageSearchQuery({
    required this.terms,
    this.from,
    this.room,
    this.before,
    this.after,
    this.has,
  });

  factory MessageSearchQuery.parse(String query) {
    String? from;
    String? room;
    DateTime? before;
    DateTime? after;
    String? has;
    final terms = <String>[];
    for (final token in query.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final separator = token.indexOf(':');
      final key = separator < 0
          ? ''
          : token.substring(0, separator).toLowerCase();
      final value = separator < 0 ? '' : token.substring(separator + 1);
      switch (key) {
        case 'from':
          from = value.toLowerCase();
        case 'in':
          room = value.toLowerCase();
        case 'before':
          before = DateTime.tryParse(value)?.toUtc();
        case 'after':
          after = DateTime.tryParse(value)?.toUtc();
        case 'has'
            when const {'image', 'file', 'link', 'video'}.contains(value):
          has = value;
        default:
          terms.add(token.toLowerCase());
      }
    }
    return MessageSearchQuery(
      terms: terms,
      from: from,
      room: room,
      before: before,
      after: after,
      has: has,
    );
  }

  final List<String> terms;
  final String? from;
  final String? room;
  final DateTime? before;
  final DateTime? after;
  final String? has;

  String get serverTerm => terms.join(' ');
}

bool matchesMessageSearch({
  required String body,
  required String sender,
  required String query,
  String? senderId,
  String? roomName,
  DateTime? timestamp,
  ChatAttachment? attachment,
}) {
  final parsed = MessageSearchQuery.parse(query);
  if (parsed.terms.isEmpty &&
      parsed.from == null &&
      parsed.room == null &&
      parsed.before == null &&
      parsed.after == null &&
      parsed.has == null) {
    return false;
  }
  final searchable = '${sender.toLowerCase()}\n${body.toLowerCase()}';
  if (!parsed.terms.every(searchable.contains)) return false;
  if (parsed.from case final from?) {
    if (!sender.toLowerCase().contains(from) &&
        !(senderId?.toLowerCase().contains(from) ?? false)) {
      return false;
    }
  }
  if (parsed.room case final room?) {
    if (!(roomName?.toLowerCase().contains(room) ?? false)) return false;
  }
  final instant = timestamp?.toUtc();
  if (parsed.before != null &&
      (instant == null || !instant.isBefore(parsed.before!))) {
    return false;
  }
  if (parsed.after != null &&
      (instant == null || !instant.isAfter(parsed.after!))) {
    return false;
  }
  return switch (parsed.has) {
    'image' => attachment?.kind == AttachmentKind.image,
    'video' => attachment?.kind == AttachmentKind.video,
    'file' => attachment != null,
    'link' => RegExp(r'https?://', caseSensitive: false).hasMatch(body),
    _ => true,
  };
}
