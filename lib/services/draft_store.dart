import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class StoredDraft {
  const StoredDraft({required this.delta});

  final List<dynamic> delta;
}

/// Persists private, room-scoped composer documents outside Matrix state.
///
/// Writes are debounced and the file is owner-only on Unix. Reply/edit targets
/// remain transient UI state so reopening a stale draft cannot modify or send
/// an unrelated event.
class DraftStore {
  DraftStore([this._file]);

  Timer? _saveTimer;
  File? _file;
  final Map<String, StoredDraft> _drafts = {};

  Future<void> initialize() async {
    if (_file == null) {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(path.join(support.path, 'deltiecord'));
      await directory.create(recursive: true);
      _file = File(path.join(directory.path, 'drafts.json'));
    } else {
      await _file!.parent.create(recursive: true);
    }
    if (!await _file!.exists()) return;
    try {
      final decoded =
          jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map && value['delta'] is List) {
          _drafts[entry.key] = StoredDraft(
            delta: List<dynamic>.from(value['delta'] as List),
          );
        }
      }
    } catch (_) {
      // A corrupt local draft file must never block login or room loading.
    }
  }

  StoredDraft? read(String roomId) => _drafts[roomId];

  void write(String roomId, List<dynamic> delta) {
    if (!_containsContent(delta)) {
      _drafts.remove(roomId);
    } else {
      _drafts[roomId] = StoredDraft(delta: delta);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _persist);
  }

  bool _containsContent(List<dynamic> delta) => delta.any((operation) {
    if (operation is! Map) return false;
    final insert = operation['insert'];
    return switch (insert) {
      String value => value.trim().isNotEmpty,
      Map() => true,
      _ => false,
    };
  });

  void remove(String roomId) {
    _drafts.remove(roomId);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 100), _persist);
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    final data = {
      for (final entry in _drafts.entries)
        entry.key: {'delta': entry.value.delta},
    };
    await file.writeAsString(jsonEncode(data), flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', file.path]);
    }
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    await _persist();
  }
}
