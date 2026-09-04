import 'dart:convert';
import 'dart:typed_data';

const matrixPersonalImagePackAccountDataType = 'im.ponies.user_emotes';
const deltiecordPersonalImagePackAccountDataPrefix =
    'net.deltiecord.user_emotes.';
const deltiecordPersonalPackRegistryKey = 'net.deltiecord.packs';
const deltiecordPersonalPackIdKey = 'net.deltiecord.pack_id';
const maximumPersonalImagePacks = 64;

bool isPersonalImagePackAccountDataType(String type) =>
    type == matrixPersonalImagePackAccountDataType ||
    type.startsWith(deltiecordPersonalImagePackAccountDataPrefix);

String? personalImagePackIdForAccountDataType(String type) {
  if (type == matrixPersonalImagePackAccountDataType) return 'personal';
  if (!type.startsWith(deltiecordPersonalImagePackAccountDataPrefix)) {
    return null;
  }
  final suffix = type.substring(
    deltiecordPersonalImagePackAccountDataPrefix.length,
  );
  return suffix.isEmpty ? null : 'personal:$suffix';
}

bool accountDataContainsImagePack(Map<String, Object?>? content) =>
    content?['images'] is Map && (content!['images'] as Map).isNotEmpty;

/// Creates an opaque namespaced account-data type for one additional pack.
///
/// The caller supplies OS-generated entropy so separate devices cannot collide
/// when creating packs concurrently. Twelve bytes provide a 96-bit identifier
/// without putting the mutable pack name into its persistent identity.
String additionalPersonalImagePackAccountDataType(Uint8List entropy) {
  return '$deltiecordPersonalImagePackAccountDataPrefix${opaquePersonalPackId(entropy)}';
}

String opaquePersonalPackId(Uint8List entropy) {
  if (entropy.length < 12) {
    throw ArgumentError.value(entropy.length, 'entropy', 'needs 12 bytes');
  }
  return base64UrlEncode(entropy.sublist(0, 12)).replaceAll('=', '');
}

/// Returns the independently named packs stored in the interoperable Matrix
/// personal image-pack event.
///
/// Matrix clients that do not understand this extension still see all images
/// as one ordinary `im.ponies.user_emotes` pack. Deltiecord uses the opaque
/// per-item ID only to recover the original pack grouping; aliases remain
/// display metadata and may therefore overlap between packs.
List<({String id, Map<String, Object?> content})> splitPersonalImagePacks(
  Map<String, Object?> content,
) {
  final images = _objectMap(content['images']);
  if (images == null || images.isEmpty) return const [];
  final registry = _objectMap(content[deltiecordPersonalPackRegistryKey]);
  if (registry == null || registry.isEmpty) {
    return [(id: 'legacy', content: Map<String, Object?>.from(content))];
  }

  final result = <({String id, Map<String, Object?> content})>[];
  for (final packEntry in registry.entries) {
    final pack = _objectMap(packEntry.value);
    if (pack == null) continue;
    final packImages = <String, Object?>{};
    for (final imageEntry in images.entries) {
      final item = _objectMap(imageEntry.value);
      if (item?[deltiecordPersonalPackIdKey] == packEntry.key) {
        packImages[imageEntry.key] = item!;
      }
    }
    if (packImages.isEmpty) continue;
    result.add((
      id: packEntry.key,
      content: <String, Object?>{'pack': pack, 'images': packImages},
    ));
  }

  // Preserve content created by an older client even if a partially written
  // registry does not mention it. A malformed extension must not hide valid
  // standard Matrix stickers.
  final ungrouped = <String, Object?>{};
  for (final imageEntry in images.entries) {
    final item = _objectMap(imageEntry.value);
    final packId = item?[deltiecordPersonalPackIdKey];
    if (packId is! String || !registry.containsKey(packId)) {
      ungrouped[imageEntry.key] = imageEntry.value;
    }
  }
  if (ungrouped.isNotEmpty) {
    result.insert(0, (
      id: 'legacy',
      content: <String, Object?>{
        'pack': _objectMap(content['pack']) ?? <String, Object?>{},
        'images': ungrouped,
      },
    ));
  }
  return result;
}

/// Adds [newPack] without replacing any existing personal sticker/emoji pack.
Map<String, Object?> mergePersonalImagePack(
  Map<String, Object?>? existing,
  Map<String, Object?> newPack, {
  required String packId,
}) {
  if (packId.isEmpty || packId == 'legacy') {
    throw ArgumentError.value(packId, 'packId', 'must be opaque and non-empty');
  }
  final existingContent = Map<String, Object?>.from(existing ?? const {});
  final images = Map<String, Object?>.from(
    _objectMap(existingContent['images']) ?? const {},
  );
  final registry = Map<String, Object?>.from(
    _objectMap(existingContent[deltiecordPersonalPackRegistryKey]) ?? const {},
  );

  if (images.isNotEmpty && registry.isEmpty) {
    final legacyPack = Map<String, Object?>.from(
      _objectMap(existingContent['pack']) ?? const {},
    );
    registry['legacy'] = legacyPack;
    for (final entry in images.entries.toList(growable: false)) {
      final item = Map<String, Object?>.from(
        _objectMap(entry.value) ?? const {},
      );
      item[deltiecordPersonalPackIdKey] = 'legacy';
      images[entry.key] = item;
    }
  }
  if (registry.length >= maximumPersonalImagePacks) {
    throw StateError(
      'Personal sticker and emoji packs are limited to '
      '$maximumPersonalImagePacks packs.',
    );
  }

  final newImages = _objectMap(newPack['images']) ?? const {};
  for (final entry in newImages.entries) {
    final item = Map<String, Object?>.from(_objectMap(entry.value) ?? const {});
    item[deltiecordPersonalPackIdKey] = packId;
    // The map key is storage identity, not the user-facing shortcode. Prefix
    // it so equal aliases in separate packs cannot overwrite one another.
    images['$packId:${entry.key}'] = item;
  }
  registry[packId] = Map<String, Object?>.from(
    _objectMap(newPack['pack']) ?? const {},
  );

  final usages = <String>{};
  for (final value in registry.values) {
    final pack = _objectMap(value);
    usages.addAll((pack?['usage'] as List? ?? const []).whereType<String>());
  }
  return <String, Object?>{
    'pack': <String, Object?>{
      'display_name': registry.length == 1
          ? '${(_objectMap(registry.values.first)?['display_name']) ?? 'Stickers'}'
          : 'Personal sticker and emoji packs',
      'usage': usages.toList(growable: false),
    },
    'images': images,
    deltiecordPersonalPackRegistryKey: registry,
  };
}

Map<String, Object?> removePersonalImagePack(
  Map<String, Object?> existing, {
  required String packId,
}) {
  final split = splitPersonalImagePacks(existing);
  final retained = split.where((pack) => pack.id != packId).toList();
  if (retained.isEmpty) {
    return <String, Object?>{
      'pack': <String, Object?>{
        'display_name': 'Stickers',
        'usage': <String>[],
      },
      'images': <String, Object?>{},
    };
  }

  Map<String, Object?>? merged;
  for (final pack in retained) {
    final id = pack.id == 'legacy' ? 'migrated_legacy' : pack.id;
    merged = mergePersonalImagePack(merged, pack.content, packId: id);
  }
  return merged!;
}

Map<String, Object?>? _objectMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;
