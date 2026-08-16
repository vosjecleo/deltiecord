import 'dart:io';

import 'package:deltiecord/services/draft_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'drafts persist privately per room and empty documents are removed',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'deltiecord-draft-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/drafts.json');

      final writer = DraftStore(file);
      await writer.initialize();
      writer.write('!one:example.org', [
        {'insert': 'room one\n'},
      ]);
      writer.write('!two:example.org', [
        {'insert': 'room two\n'},
      ]);
      await writer.dispose();

      final reader = DraftStore(file);
      await reader.initialize();
      expect(
        reader.read('!one:example.org')?.delta.first['insert'],
        'room one\n',
      );
      expect(
        reader.read('!two:example.org')?.delta.first['insert'],
        'room two\n',
      );

      reader.write('!one:example.org', [
        {'insert': '\n'},
      ]);
      await reader.dispose();

      final finalReader = DraftStore(file);
      await finalReader.initialize();
      expect(finalReader.read('!one:example.org'), isNull);
      expect(finalReader.read('!two:example.org'), isNotNull);
      await finalReader.dispose();
    },
  );
}
