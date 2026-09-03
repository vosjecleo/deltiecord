import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'private_file_store.dart';

/// Small bounded local index for favourite Unicode emoji and Matrix stickers.
/// Sticker media remains in the normal Matrix/media cache; this file stores
/// identifiers only and is removed with ordinary application data.
final class FavouriteReactionsStore extends ChangeNotifier {
  FavouriteReactionsStore._();

  static final instance = FavouriteReactionsStore._();
  static const _maximumPerKind = 100;

  File? _file;
  bool _loaded = false;
  final List<String> _emoji = [];
  final List<String> _stickers = [];

  List<String> get emoji => List.unmodifiable(_emoji);
  List<String> get stickers => List.unmodifiable(_stickers);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final support = await getApplicationSupportDirectory();
      _file = File(
        path.join(support.path, 'deltiecord', 'reaction_favourites.json'),
      );
      if (!await _file!.exists()) return;
      final value = jsonDecode(await _file!.readAsString());
      if (value is! Map) return;
      _emoji.addAll(
        (value['emoji'] as List? ?? const []).whereType<String>().take(
          _maximumPerKind,
        ),
      );
      _stickers.addAll(
        (value['stickers'] as List? ?? const []).whereType<String>().take(
          _maximumPerKind,
        ),
      );
    } catch (_) {
      _emoji.clear();
      _stickers.clear();
    }
  }

  bool isEmojiFavourite(String value) => _emoji.contains(value);
  bool isStickerFavourite(Uri value) => _stickers.contains(value.toString());

  Future<void> toggleEmoji(String value) async {
    await load();
    _toggle(_emoji, value);
    await _save();
  }

  Future<void> toggleSticker(Uri value) async {
    await load();
    _toggle(_stickers, value.toString());
    await _save();
  }

  void _toggle(List<String> values, String value) {
    if (values.remove(value)) {
      notifyListeners();
      return;
    }
    values.insert(0, value);
    if (values.length > _maximumPerKind) values.removeLast();
    notifyListeners();
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    await writePrivateTextFile(
      file,
      jsonEncode({'emoji': _emoji, 'stickers': _stickers}),
    );
  }
}
