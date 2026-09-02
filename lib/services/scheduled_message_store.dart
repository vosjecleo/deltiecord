import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/chat_models.dart';

/// Private, durable queue for messages waiting to be sent by this device.
///
/// Homeserver delayed events are not yet universally available and cannot be
/// assumed to preserve Deltiecord's encrypted-send path. Queue entries are
/// therefore owner-only local data and are sent while the client is running,
/// or on the next launch after their due time.
class ScheduledMessageStore {
  ScheduledMessageStore([this._file]);

  File? _file;
  final Map<String, ScheduledMessageSummary> _messages = {};

  Future<void> initialize() async {
    if (_file == null) {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(path.join(support.path, 'deltiecord'));
      await directory.create(recursive: true);
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['700', directory.path]);
      }
      _file = File(path.join(directory.path, 'scheduled-messages.json'));
    } else {
      await _file!.parent.create(recursive: true);
    }
    final file = _file!;
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final value in decoded.whereType<Map>()) {
        final id = value['id'];
        final roomId = value['room_id'];
        final body = value['body'];
        final sendAt = DateTime.tryParse('${value['send_at']}');
        if (id is! String ||
            roomId is! String ||
            body is! String ||
            sendAt == null) {
          continue;
        }
        _messages[id] = ScheduledMessageSummary(
          id: id,
          roomId: roomId,
          body: body,
          sendAt: sendAt.toUtc(),
          replyToMessageId: value['reply_to'] as String?,
        );
      }
    } catch (_) {
      // A corrupt queue is ignored rather than blocking session restoration.
    }
  }

  List<ScheduledMessageSummary> get messages {
    final result = _messages.values.toList(growable: false);
    result.sort((a, b) => a.sendAt.compareTo(b.sendAt));
    return result;
  }

  Future<void> put(ScheduledMessageSummary message) async {
    _messages[message.id] = message;
    await _persist();
  }

  Future<void> remove(String id) async {
    _messages.remove(id);
    await _persist();
  }

  Future<void> clear() async {
    _messages.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    final encoded = jsonEncode([
      for (final message in messages)
        {
          'id': message.id,
          'room_id': message.roomId,
          'body': message.body,
          'send_at': message.sendAt.toUtc().toIso8601String(),
          if (message.replyToMessageId != null)
            'reply_to': message.replyToMessageId,
        },
    ]);
    await file.writeAsString(encoded, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', file.path]);
    }
  }
}
