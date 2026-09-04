import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/chat_models.dart';

const _familiarAliases = <String, List<String>>{
  '😭': ['sob', 'cry', 'loudly_crying'],
  '😂': ['joy', 'tears_of_joy'],
  '🤣': ['rofl'],
  '❤️': ['heart', 'love'],
  '👍': ['thumbsup', '+1'],
  '👎': ['thumbsdown', '-1'],
  '💀': ['skull', 'dead'],
  '🙏': ['pray', 'please'],
  '🔥': ['fire', 'lit'],
  '🎉': ['tada', 'party'],
  '👀': ['eyes'],
  '🤔': ['thinking'],
  '😅': ['sweat_smile'],
  '😎': ['sunglasses'],
};

String _normalizeEmojiSearchTerm(String value) =>
    value.toLowerCase().replaceAll('_', ' ').trim();

enum EmojiCategory {
  custom('Custom'),
  smileysAndPeople('Smileys & people'),
  animalsAndNature('Animals & nature'),
  foodAndDrink('Food & drink'),
  travelAndPlaces('Travel & places'),
  activities('Activities'),
  objects('Objects'),
  symbols('Symbols'),
  flags('Flags');

  const EmojiCategory(this.label);

  final String label;

  static EmojiCategory? fromName(String? value) {
    if (value == null) return null;
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    for (final category in values) {
      if (category.name.toLowerCase() == normalized ||
          category.label.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') ==
              normalized) {
        return category;
      }
    }
    return null;
  }
}

class EmojiEntry {
  const EmojiEntry({
    required this.emoji,
    required this.name,
    required this.aliases,
    required this.category,
    this.customEmoji,
  });

  final String emoji;
  final String name;
  final List<String> aliases;
  final EmojiCategory category;
  final StickerSummary? customEmoji;

  bool get isCustom => customEmoji != null;
  String get insertionText => customEmoji?.customEmoji?.fallback ?? emoji;
  String get favouriteKey => customEmoji?.mxcUri.toString() ?? emoji;

  bool matches(String query) {
    final normalized = _normalizeEmojiSearchTerm(query);
    if (normalized.isEmpty) return true;
    return name.toLowerCase().contains(normalized) ||
        aliases.any(
          (alias) => _normalizeEmojiSearchTerm(alias).contains(normalized),
        );
  }

  int score(String query) {
    final normalized = _normalizeEmojiSearchTerm(query);
    final lowerName = name.toLowerCase();
    if (aliases.any(
      (alias) => _normalizeEmojiSearchTerm(alias) == normalized,
    )) {
      return 0;
    }
    if (lowerName == normalized) return 1;
    if (aliases.any(
      (alias) => _normalizeEmojiSearchTerm(alias).startsWith(normalized),
    )) {
      return 2;
    }
    if (lowerName.startsWith(normalized)) return 3;
    return 4;
  }
}

List<EmojiEntry> customEmojiEntries(Iterable<StickerPackSummary> packs) => [
  for (final pack in packs)
    for (final sticker in pack.stickers)
      if (sticker.assetType == StickerAssetType.emoji)
        EmojiEntry(
          emoji: sticker.customEmoji!.fallback,
          name: sticker.name,
          aliases: [sticker.name, pack.name],
          category: EmojiCategory.custom,
          customEmoji: sticker,
        ),
];

/// Lazily loaded local Unicode emoji catalogue and alias search index.
///
/// Search never requires the network. Project-specific names and aliases live
/// in `assets/emoji/aliases.json` so they can be maintained without changing
/// completion logic.
class EmojiRepository {
  EmojiRepository._();

  static final instance = EmojiRepository._();
  Future<List<EmojiEntry>>? _loading;

  Future<List<EmojiEntry>> load() => _loading ??= _load();

  String? familiarEmoji(String alias) {
    final normalized = _normalizeEmojiSearchTerm(alias);
    for (final entry in _familiarAliases.entries) {
      if (entry.value.any(
        (candidate) => candidate.replaceAll('_', ' ') == normalized,
      )) {
        return entry.key;
      }
    }
    return null;
  }

  /// Returns the small set of conventional aliases without waiting for the
  /// complete local dataset to decode. This keeps composer completion instant
  /// on its first use while [search] loads the full catalogue in parallel.
  List<EmojiEntry> familiarMatches(String query, {int limit = 3}) {
    final normalized = _normalizeEmojiSearchTerm(query);
    if (normalized.isEmpty) return const [];
    final matches = <EmojiEntry>[];
    for (final aliasGroup in _familiarAliases.entries) {
      final aliases = aliasGroup.value;
      if (!aliases.any(
        (alias) => _normalizeEmojiSearchTerm(alias).contains(normalized),
      )) {
        continue;
      }
      matches.add(
        EmojiEntry(
          emoji: aliasGroup.key,
          name: aliases.first.replaceAll('_', ' '),
          aliases: aliases,
          category: EmojiCategory.smileysAndPeople,
        ),
      );
      if (matches.length == limit) break;
    }
    return matches;
  }

  Future<List<EmojiEntry>> _load() async {
    final sources = await Future.wait([
      rootBundle.loadString('assets/emoji/emojis.json'),
      rootBundle.loadString('assets/emoji/aliases.json'),
    ]);
    final decoded = jsonDecode(sources[0]) as Map<String, dynamic>;
    final overrides = jsonDecode(sources[1]) as Map<String, dynamic>;
    final entries = decoded.entries.toList(growable: false);
    final catalog = entries.indexed.map((indexedEntry) {
      final index = indexedEntry.$1;
      final entry = indexedEntry.$2;
      final data = entry.value as Map<String, dynamic>;
      final override = overrides[entry.key] as Map<String, dynamic>?;
      final aliases =
          (data['keywords'] as List? ?? const []).whereType<String>().toSet()
            ..addAll(_familiarAliases[entry.key] ?? const [])
            ..addAll(
              (override?['aliases'] as List? ?? const []).whereType<String>(),
            );
      return EmojiEntry(
        emoji: entry.key,
        name:
            override?['name'] as String? ??
            data['name'] as String? ??
            entry.key,
        aliases: aliases.toList(growable: false),
        category:
            EmojiCategory.fromName(override?['category'] as String?) ??
            _categoryForIndex(index),
      );
    }).toList();

    for (final overrideEntry in overrides.entries) {
      if (overrideEntry.key.startsWith('_') ||
          decoded.containsKey(overrideEntry.key) ||
          overrideEntry.value is! Map<String, dynamic>) {
        continue;
      }
      final data = overrideEntry.value as Map<String, dynamic>;
      catalog.add(
        EmojiEntry(
          emoji: overrideEntry.key,
          name: data['name'] as String? ?? overrideEntry.key,
          aliases: (data['aliases'] as List? ?? const [])
              .whereType<String>()
              .toList(growable: false),
          category:
              EmojiCategory.fromName(data['category'] as String?) ??
              EmojiCategory.symbols,
        ),
      );
    }
    return catalog;
  }

  // emojis.json follows the standard Unicode presentation order. Keeping the
  // boundaries here avoids duplicating the complete catalogue only to attach
  // one category string to every entry.
  EmojiCategory _categoryForIndex(int index) => switch (index) {
    < 543 => EmojiCategory.smileysAndPeople,
    < 763 => EmojiCategory.animalsAndNature,
    < 889 => EmojiCategory.foodAndDrink,
    < 1088 => EmojiCategory.travelAndPlaces,
    < 1150 => EmojiCategory.activities,
    < 1350 => EmojiCategory.objects,
    < 1644 => EmojiCategory.symbols,
    _ => EmojiCategory.flags,
  };

  Future<List<EmojiEntry>> search(String query, {int? limit}) async {
    final entries = await load();
    final matches = entries.where((entry) => entry.matches(query)).toList();
    matches.sort((a, b) {
      final score = a.score(query).compareTo(b.score(query));
      return score != 0 ? score : a.name.compareTo(b.name);
    });
    return limit == null || matches.length <= limit
        ? matches
        : matches.sublist(0, limit);
  }

  Future<EmojiEntry?> exactAlias(String alias) async {
    final normalized = _normalizeEmojiSearchTerm(alias);
    final entries = await load();
    return entries
        .where(
          (entry) =>
              _normalizeEmojiSearchTerm(entry.name) == normalized ||
              entry.aliases.any(
                (candidate) =>
                    _normalizeEmojiSearchTerm(candidate) == normalized,
              ),
        )
        .firstOrNull;
  }
}
