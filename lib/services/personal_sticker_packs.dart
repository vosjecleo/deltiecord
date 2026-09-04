import 'dart:convert';
import 'dart:typed_data';

const matrixPersonalImagePackAccountDataType = 'im.ponies.user_emotes';
const deltiecordPersonalImagePackAccountDataPrefix =
    'net.deltiecord.user_emotes.';
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
  if (entropy.length < 12) {
    throw ArgumentError.value(entropy.length, 'entropy', 'needs 12 bytes');
  }
  final suffix = base64UrlEncode(entropy.sublist(0, 12)).replaceAll('=', '');
  return '$deltiecordPersonalImagePackAccountDataPrefix$suffix';
}
