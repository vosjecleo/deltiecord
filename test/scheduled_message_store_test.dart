import 'dart:io';

import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/scheduled_message_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scheduled messages persist in chronological order per room', () async {
    final directory = await Directory.systemTemp.createTemp(
      'deltiecord-scheduled-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/scheduled.json');
    final later = DateTime.utc(2026, 9, 2, 14);
    final earlier = DateTime.utc(2026, 9, 2, 13);

    final store = ScheduledMessageStore(file);
    await store.initialize();
    await store.put(
      ScheduledMessageSummary(
        id: 'later',
        roomId: '!second:example.org',
        body: 'later message',
        sendAt: later,
      ),
    );
    await store.put(
      ScheduledMessageSummary(
        id: 'earlier',
        roomId: '!first:example.org',
        body: 'earlier reply',
        sendAt: earlier,
        replyToMessageId: r'$event',
      ),
    );

    final restored = ScheduledMessageStore(file);
    await restored.initialize();
    expect(restored.messages.map((message) => message.id), [
      'earlier',
      'later',
    ]);
    expect(restored.messages.first.roomId, '!first:example.org');
    expect(restored.messages.first.replyToMessageId, r'$event');

    await restored.remove('earlier');
    final afterRemoval = ScheduledMessageStore(file);
    await afterRemoval.initialize();
    expect(afterRemoval.messages.single.id, 'later');
  });

  test('corrupt queue data cannot block session restoration', () async {
    final directory = await Directory.systemTemp.createTemp(
      'deltiecord-scheduled-corrupt-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/scheduled.json');
    await file.writeAsString('{broken');

    final store = ScheduledMessageStore(file);
    await store.initialize();

    expect(store.messages, isEmpty);
  });
}
