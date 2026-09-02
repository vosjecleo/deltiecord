import 'dart:math';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

Future<void> showSavedMessages(
  BuildContext context,
  ChatBackend backend, {
  Future<void> Function(String roomId, String eventId)? onOpen,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: SizedBox(
      width: 620,
      height: 600,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Saved'),
                Tab(text: 'Scheduled'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _MessageList(
                    emptyLabel: 'No saved messages yet.',
                    messages: backend.bookmarkedMessages,
                    onOpen: onOpen == null
                        ? null
                        : (message) async {
                            final roomId = backend.roomIdForMessage(message.id);
                            if (roomId == null) return;
                            Navigator.pop(context);
                            await onOpen(roomId, message.id);
                          },
                  ),
                  ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (backend.scheduledMessages.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No scheduled messages.')),
                        ),
                      for (final message in backend.scheduledMessages)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.schedule_send_outlined),
                            title: Text(
                              message.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Sends ${message.sendAt.toLocal()} · ${message.roomId}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Cancel scheduled message',
                              onPressed: () async {
                                await backend.cancelScheduledMessage(
                                  message.id,
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> showRoomMediaGallery(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
}) {
  final images = backend.messages
      .where((message) => message.attachment?.kind == AttachmentKind.image)
      .toList();
  final videos = backend.messages
      .where((message) => message.attachment?.kind == AttachmentKind.video)
      .toList();
  final files = backend.messages
      .where(
        (message) =>
            message.attachment != null &&
            message.attachment?.kind != AttachmentKind.image &&
            message.attachment?.kind != AttachmentKind.video,
      )
      .toList();
  final links = backend.messages
      .where(
        (message) =>
            message.linkPreviews.isNotEmpty ||
            RegExp(r'https?://', caseSensitive: false).hasMatch(message.body),
      )
      .toList();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: SizedBox(
        width: 720,
        height: 640,
        child: DefaultTabController(
          length: 4,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Images'),
                  Tab(text: 'Videos'),
                  Tab(text: 'Files'),
                  Tab(text: 'Links'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _MessageList(
                      emptyLabel: 'No loaded images.',
                      messages: images,
                      onOpen: (message) =>
                          _open(dialogContext, onOpen, message),
                    ),
                    _MessageList(
                      emptyLabel: 'No loaded videos.',
                      messages: videos,
                      onOpen: (message) =>
                          _open(dialogContext, onOpen, message),
                    ),
                    _MessageList(
                      emptyLabel: 'No loaded files.',
                      messages: files,
                      onOpen: (message) =>
                          _open(dialogContext, onOpen, message),
                    ),
                    _MessageList(
                      emptyLabel: 'No loaded links.',
                      messages: links,
                      onOpen: (message) =>
                          _open(dialogContext, onOpen, message),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'This gallery covers the loaded room history. Load older '
                  'messages in the timeline to extend it.',
                  style: TextStyle(color: dialogContext.deltiecord.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showPinnedMessages(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
}) async {
  final messages = await backend.loadPinnedMessages();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: min(520, MediaQuery.sizeOf(sheetContext).height * 0.72),
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.push_pin_outlined),
              title: Text('Pinned messages'),
            ),
            Expanded(
              child: _MessageList(
                emptyLabel: 'No pinned messages.',
                messages: messages,
                onOpen: (message) async {
                  Navigator.pop(sheetContext);
                  await onOpen(message.id);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showUnifiedInbox(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(InboxItemSummary item) onOpen,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Dialog(
    child: SizedBox(
      width: 680,
      height: 640,
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.inbox_outlined),
            title: Text('Inbox'),
            subtitle: Text('Mentions, replies, reactions, calls, and invites'),
          ),
          const Divider(height: 1),
          Expanded(
            child: backend.unifiedInbox.isEmpty
                ? const Center(child: Text('You are all caught up.'))
                : ListView.builder(
                    itemCount: backend.unifiedInbox.length,
                    itemBuilder: (context, index) {
                      final item = backend.unifiedInbox[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: item.avatarBytes == null
                              ? null
                              : MemoryImage(item.avatarBytes!),
                          child: item.avatarBytes == null
                              ? Icon(_inboxIcon(item.kind))
                              : null,
                        ),
                        title: Text(item.roomName),
                        subtitle: Text(
                          item.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: item.kind == InboxItemKind.invite
                            ? PopupMenuButton<String>(
                                tooltip: 'Invitation actions',
                                onSelected: (value) async {
                                  if (value == 'accept') {
                                    await backend.acceptRoomInvite(item.roomId);
                                  } else {
                                    await backend.rejectRoomInvite(item.roomId);
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'accept',
                                    child: Text('Accept'),
                                  ),
                                  PopupMenuItem(
                                    value: 'decline',
                                    child: Text('Decline'),
                                  ),
                                ],
                              )
                            : Text(_inboxLabel(item.kind)),
                        onTap: () async {
                          if (item.kind == InboxItemKind.invite) {
                            await backend.acceptRoomInvite(item.roomId);
                          }
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          await onOpen(item);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _open(
  BuildContext context,
  Future<void> Function(String eventId) onOpen,
  ChatMessage message,
) async {
  Navigator.pop(context);
  await onOpen(message.id);
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.emptyLabel,
    required this.messages,
    required this.onOpen,
  });

  final String emptyLabel;
  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage>? onOpen;

  @override
  Widget build(BuildContext context) => messages.isEmpty
      ? Center(child: Text(emptyLabel))
      : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return Card(
              child: ListTile(
                leading: message.avatarBytes == null
                    ? const Icon(Icons.message_outlined)
                    : CircleAvatar(
                        backgroundImage: MemoryImage(message.avatarBytes!),
                      ),
                title: Text(message.sender),
                subtitle: Text(
                  message.attachment?.name ?? message.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${message.timestamp.toLocal()}'),
                onTap: onOpen == null ? null : () => onOpen!(message),
              ),
            );
          },
        );
}

IconData _inboxIcon(InboxItemKind kind) => switch (kind) {
  InboxItemKind.mention => Icons.alternate_email,
  InboxItemKind.reply => Icons.reply,
  InboxItemKind.reaction => Icons.add_reaction_outlined,
  InboxItemKind.missedCall => Icons.call_missed,
  InboxItemKind.invite => Icons.mail_outline,
};

String _inboxLabel(InboxItemKind kind) => switch (kind) {
  InboxItemKind.mention => 'Mention',
  InboxItemKind.reply => 'Reply',
  InboxItemKind.reaction => 'Reaction',
  InboxItemKind.missedCall => 'Missed call',
  InboxItemKind.invite => 'Invite',
};
