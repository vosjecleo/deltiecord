import 'dart:io';
import 'dart:typed_data';

import 'package:deltiecord/services/temporary_attachment_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses random names, sanitized extensions, and age cleanup', () async {
    final base = await Directory.systemTemp.createTemp('deltiecord-temp-test-');
    addTearDown(() => base.delete(recursive: true));
    final store = TemporaryAttachmentStore(root: base);
    final first = await store.create(
      bytes: Uint8List.fromList([1, 2, 3]),
      displayName: '../../unsafe name.PNG',
    );
    final second = await store.create(
      bytes: Uint8List.fromList([4]),
      displayName: 'secret.bad-extension-too-long',
    );

    expect(first.parent.path, endsWith('deltiecord-decrypted'));
    expect(first.path, isNot(equals(second.path)));
    expect(first.path, endsWith('.png'));
    expect(second.path, isNot(endsWith('.bad-extension-too-long')));
    expect(await first.readAsBytes(), [1, 2, 3]);

    await first.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    expect(await store.cleanup(), 1);
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);

    if (Platform.isLinux || Platform.isMacOS) {
      final directoryMode = (await Process.run('stat', [
        '-c',
        '%a',
        first.parent.path,
      ])).stdout.toString().trim();
      final fileMode = (await Process.run('stat', [
        '-c',
        '%a',
        second.path,
      ])).stdout.toString().trim();
      expect(directoryMode, '700');
      expect(fileMode, '600');
    }
  });
}
