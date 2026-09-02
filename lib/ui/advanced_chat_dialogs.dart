import 'dart:math';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

Future<PollDraft?> showPollComposer(BuildContext context) =>
    showDialog<PollDraft>(
      context: context,
      builder: (context) => const _PollComposerDialog(),
    );

Future<DateTime?> showSchedulePicker(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  final result = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return result.isAfter(now) ? result : now.add(const Duration(minutes: 1));
}

Future<void> showRoomNotificationControls(
  BuildContext context,
  ChatBackend backend,
  RoomSummary room,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          const ListTile(title: Text('Room notifications')),
          ListTile(
            leading: Icon(
              room.notificationMode == RoomNotificationMode.allMessages
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('All messages'),
            onTap: () => Navigator.pop(context, 'all'),
          ),
          ListTile(
            leading: Icon(
              room.notificationMode == RoomNotificationMode.mentionsOnly
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('Mentions only'),
            onTap: () => Navigator.pop(context, 'mentions'),
          ),
          ListTile(
            leading: Icon(
              room.notificationMode == RoomNotificationMode.muted
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: const Text('Mute'),
            onTap: () => Navigator.pop(context, 'mute'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Mute for 1 hour'),
            onTap: () => Navigator.pop(context, 'hour'),
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Mute until tomorrow'),
            onTap: () => Navigator.pop(context, 'tomorrow'),
          ),
          ListTile(
            leading: Icon(
              room.markedUnread
                  ? Icons.mark_chat_read_outlined
                  : Icons.mark_chat_unread_outlined,
            ),
            title: Text(room.markedUnread ? 'Mark read' : 'Mark unread'),
            onTap: () => Navigator.pop(context, 'unread'),
          ),
        ],
      ),
    ),
  );
  if (action == null) return;
  switch (action) {
    case 'all':
      await backend.setRoomNotificationMode(
        room.id,
        RoomNotificationMode.allMessages,
      );
    case 'mentions':
      await backend.setRoomNotificationMode(
        room.id,
        RoomNotificationMode.mentionsOnly,
      );
    case 'mute':
      await backend.setRoomNotificationMode(
        room.id,
        RoomNotificationMode.muted,
      );
    case 'hour':
      await backend.muteRoomUntil(
        room.id,
        DateTime.now().add(const Duration(hours: 1)),
      );
    case 'tomorrow':
      final now = DateTime.now();
      await backend.muteRoomUntil(
        room.id,
        DateTime(now.year, now.month, now.day + 1, 9),
      );
    case 'unread':
      await backend.markRoomUnread(room.id, !room.markedUnread);
  }
}

Future<StickerSummary?> showStickerPicker(
  BuildContext context,
  ChatBackend backend,
) async {
  await backend.refreshStickerPacks();
  if (!context.mounted) return null;
  return showModalBottomSheet<StickerSummary>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.72,
      child: backend.stickerPacks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No compatible sticker packs found. Install an '
                  'im.ponies user or room emote pack in a compatible Matrix client.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : DefaultTabController(
              length: backend.stickerPacks.length,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      for (final pack in backend.stickerPacks)
                        Tab(text: pack.name),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final pack in backend.stickerPacks)
                          GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 112,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                ),
                            itemCount: pack.stickers.length,
                            itemBuilder: (context, index) {
                              final sticker = pack.stickers[index];
                              return InkWell(
                                key: ValueKey(
                                  'sticker-${pack.id}-${sticker.id}',
                                ),
                                onTap: () => Navigator.pop(context, sticker),
                                borderRadius: DeltiecordCorners.borderRadius,
                                child: Tooltip(
                                  message: sticker.name,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: sticker.previewBytes == null
                                        ? Center(
                                            child: Text(
                                              sticker.name,
                                              textAlign: TextAlign.center,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )
                                        : Image.memory(
                                            sticker.previewBytes!,
                                            fit: BoxFit.contain,
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

class _PollComposerDialog extends StatefulWidget {
  const _PollComposerDialog();

  @override
  State<_PollComposerDialog> createState() => _PollComposerDialogState();
}

class _PollComposerDialogState extends State<_PollComposerDialog> {
  final _question = TextEditingController();
  final _answers = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _disclosed = false;

  @override
  void dispose() {
    _question.dispose();
    for (final answer in _answers) {
      answer.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final answers = _answers
        .map((controller) => controller.text.trim())
        .where((answer) => answer.isNotEmpty)
        .toList();
    if (_question.text.trim().isEmpty || answers.length < 2) return;
    Navigator.pop(
      context,
      PollDraft(
        question: _question.text.trim(),
        answers: answers,
        maxSelections: _multiple ? max(2, answers.length) : 1,
        disclosed: _disclosed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create poll'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('poll-question'),
              controller: _question,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Question'),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _answers.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: ValueKey('poll-answer-$index'),
                  controller: _answers[index],
                  decoration: InputDecoration(
                    labelText: 'Answer ${index + 1}',
                    suffixIcon: _answers.length > 2
                        ? IconButton(
                            onPressed: () => setState(() {
                              _answers.removeAt(index).dispose();
                            }),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                ),
              ),
            if (_answers.length < 12)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _answers.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add answer'),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _multiple,
              onChanged: (value) => setState(() => _multiple = value),
              title: const Text('Allow multiple answers'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _disclosed,
              onChanged: (value) => setState(() => _disclosed = value),
              title: const Text('Show who voted'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create poll')),
    ],
  );
}
