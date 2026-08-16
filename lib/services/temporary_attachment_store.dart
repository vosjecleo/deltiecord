import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Owns decrypted files handed to external applications.
///
/// Files are deliberately not deleted immediately after launching: many
/// desktop applications continue reading them after the launcher returns.
/// Stale files are removed by age on startup and shutdown instead.
class TemporaryAttachmentStore {
  TemporaryAttachmentStore({Directory? root, Random? random})
    : _configuredRoot = root,
      _random = random ?? Random.secure();

  static final instance = TemporaryAttachmentStore();
  static const staleAge = Duration(hours: 24);

  final Directory? _configuredRoot;
  final Random _random;
  Directory? _root;

  Future<Directory> initialize() async {
    final existing = _root;
    if (existing != null) return existing;
    final base = _configuredRoot ?? await getTemporaryDirectory();
    final root = Directory(path.join(base.path, 'deltiecord-decrypted'));
    await root.create(recursive: true);
    await _applyUnixMode(root.path, '700');
    _root = root;
    await cleanup();
    return root;
  }

  Future<File> create({
    required Uint8List bytes,
    required String displayName,
  }) async {
    final root = await initialize();
    final extension = _safeExtension(displayName);
    for (var attempt = 0; attempt < 8; attempt++) {
      final name = List.generate(
        24,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final file = File(path.join(root.path, '$name$extension'));
      try {
        await file.create(exclusive: true);
        await file.writeAsBytes(bytes, flush: true);
        await _applyUnixMode(file.path, '600');
        return file;
      } on FileSystemException {
        // A random collision is extraordinarily unlikely, but exclusive create
        // keeps it safe and retrying avoids an overwrite in every case.
      }
    }
    throw const FileSystemException(
      'Could not create a private attachment file.',
    );
  }

  Future<int> cleanup({Duration olderThan = staleAge}) async {
    final root = _root ?? await initialize();
    final cutoff = DateTime.now().subtract(olderThan);
    var removed = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final modified = await entity.lastModified();
        if (modified.isAfter(cutoff)) continue;
        await entity.delete();
        removed++;
      } on FileSystemException {
        // External viewers may still hold a file or another process may have
        // raced cleanup. It remains eligible on the next startup.
      }
    }
    return removed;
  }

  String _safeExtension(String displayName) {
    final value = path.extension(path.basename(displayName)).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(value) ? value : '';
  }

  Future<void> _applyUnixMode(String target, String mode) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final result = await Process.run('chmod', [mode, target]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not secure temporary attachment',
        target,
      );
    }
  }
}
