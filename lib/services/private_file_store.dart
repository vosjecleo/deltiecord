import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

/// Creates an application-private directory and tightens desktop Unix modes.
///
/// Android/iOS application directories are sandboxed by the OS. Linux and
/// macOS need an explicit owner-only mode because the process umask is outside
/// Deltiecord's control.
Future<void> ensurePrivateDirectory(Directory directory) async {
  await directory.create(recursive: true);
  if (Platform.isLinux || Platform.isMacOS) {
    final result = await Process.run('chmod', ['700', directory.path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not secure private application directory',
        directory.path,
      );
    }
  }
}

/// Atomically replaces a private UTF-8 file where the host supports rename.
///
/// The temporary is owner-only before message text is written. Windows cannot
/// replace an existing file with `rename`, so it uses a same-directory backup
/// and restores it if the replacement fails.
Future<void> writePrivateTextFile(File target, String contents) async {
  await ensurePrivateDirectory(target.parent);
  final random = Random.secure();
  final suffix = List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temporary = File(
    path.join(target.parent.path, '.${path.basename(target.path)}.$suffix.tmp'),
  );
  File? backup;
  try {
    await temporary.create(exclusive: true);
    await _secureFile(temporary);
    await temporary.writeAsString(contents, flush: true);
    if (Platform.isWindows && await target.exists()) {
      backup = File('${target.path}.$suffix.backup');
      await target.rename(backup.path);
    }
    await temporary.rename(target.path);
    await _secureFile(target);
    if (backup != null && await backup.exists()) await backup.delete();
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    if (backup != null && await backup.exists() && !await target.exists()) {
      await backup.rename(target.path);
    }
    rethrow;
  }
}

Future<void> deletePrivateFile(File? file) async {
  if (file != null && await file.exists()) await file.delete();
}

Future<void> _secureFile(File file) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  final result = await Process.run('chmod', ['600', file.path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not secure private application file',
      file.path,
    );
  }
}
