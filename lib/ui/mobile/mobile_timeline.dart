import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/emoji_repository.dart';
import '../../services/giphy_service.dart';
import '../deltiecord_theme.dart';
import 'mobile_media.dart';
import 'mobile_profile_sheet.dart';
import 'mobile_widgets.dart';

class MobileTimelineView extends StatefulWidget {
  const MobileTimelineView({
    required this.backend,
    required this.room,
    required this.onOpenNavigation,
    required this.onOpenDetails,
    required this.onOpenSettings,
    required this.initialDraft,
    required this.onDraftChanged,
    super.key,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback onOpenNavigation;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenSettings;
  final String initialDraft;
  final ValueChanged<String> onDraftChanged;

  @override
  State<MobileTimelineView> createState() => _MobileTimelineViewState();
}

class _MobileTimelineViewState extends State<MobileTimelineView> {
  late final TextEditingController _composer;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _giphy = GiphyService();
  final List<AttachmentDraft> _attachments = [];
  ChatMessage? _reply;
  ChatMessage? _edit;
  bool _sending = false;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController(text: widget.initialDraft)
      ..addListener(_composerChanged);
    _scroll.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant MobileTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id == widget.room.id) return;
    _composer
      ..removeListener(_composerChanged)
      ..text = widget.initialDraft
      ..addListener(_composerChanged);
    _reply = null;
    _edit = null;
    _attachments.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _composerChanged() {
    widget.onDraftChanged(_composer.text);
    unawaited(backend.setComposerTyping(_composer.text.isNotEmpty));
  }

  void _handleScroll() {
    if (!_scroll.hasClients || backend.historyLoading) return;
    if (_scroll.position.extentAfter < 180 && backend.canLoadMoreHistory) {
      unawaited(backend.loadMoreHistory());
    }
    if (_scroll.position.extentBefore < 180 && backend.canLoadMoreFuture) {
      unawaited(backend.loadMoreFuture());
    }
  }

  @override
  void dispose() {
    _composer
      ..removeListener(_composerChanged)
      ..dispose();
    _focus.dispose();
    _scroll.dispose();
    _giphy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = backend.messages;
    return Scaffold(
      key: const ValueKey('mobile-timeline'),
      appBar: AppBar(
        toolbarHeight: 64,
        leading: IconButton(
          key: const ValueKey('mobile-open-navigation'),
          onPressed: widget.onOpenNavigation,
          icon: const Icon(Icons.menu),
        ),
        titleSpacing: 0,
        title: InkWell(
          key: const ValueKey('mobile-open-details'),
          onTap: widget.onOpenDetails,
          child: Row(
            children: [
              MobileAvatar(
                bytes: widget.room.avatarBytes,
                fallback: widget.room.name,
                presence: widget.room.isDirect ? widget.room.presence : null,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.room.topic.isNotEmpty
                          ? widget.room.topic
                          : widget.room.isDirect
                          ? mobilePresenceLabel(widget.room.presence)
                          : '${backend.selectedRoomMembers.length} members',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.room.isDirect)
            IconButton(
              tooltip: 'Call',
              onPressed: () => backend.joinVoiceRoom(widget.room.id),
              icon: const Icon(Icons.call_outlined),
            ),
          IconButton(
            tooltip: 'Search',
            onPressed: _showSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: backend.selectedRoomMuted ? 'Unmute room' : 'Mute room',
            onPressed: () =>
                backend.setSelectedRoomMuted(!backend.selectedRoomMuted),
            icon: Icon(
              backend.selectedRoomMuted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (backend.connectionStatus != ConnectionStatus.online)
            MaterialBanner(
              content: Text(
                backend.connectionStatus == ConnectionStatus.offline
                    ? 'Offline — messages will be queued'
                    : 'Reconnecting…',
              ),
              actions: const [SizedBox.shrink()],
            ),
          if (backend.typingUserNames.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              color: context.deltiecord.elevated,
              child: Text('${backend.typingUserNames.join(', ')} is typing…'),
            ),
          Expanded(
            child: backend.timelineLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                ? const Center(child: Text('No messages yet'))
                : Stack(
                    children: [
                      ListView.builder(
                        key: const ValueKey('mobile-message-timeline'),
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(6, 10, 6, 110),
                        itemCount:
                            messages.length +
                            ((backend.canLoadMoreHistory ||
                                    backend.historyLoading)
                                ? 1
                                : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return Center(
                              child: backend.historyLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    )
                                  : TextButton.icon(
                                      onPressed: backend.loadMoreHistory,
                                      icon: const Icon(Icons.history),
                                      label: const Text('Load older messages'),
                                    ),
                            );
                          }
                          final message = messages[index];
                          final older = index + 1 < messages.length
                              ? messages[index + 1]
                              : null;
                          final grouped =
                              older != null &&
                              older.senderId == message.senderId &&
                              message.timestamp.difference(older.timestamp) <
                                  const Duration(minutes: 7) &&
                              message.reply == null;
                          return _MobileMessageRow(
                            key: ValueKey(message.id),
                            backend: backend,
                            message: message,
                            grouped: grouped,
                            onReply: () => setState(() {
                              _reply = message;
                              _edit = null;
                              _focus.requestFocus();
                            }),
                            onEdit: message.own && !message.redacted
                                ? () => setState(() {
                                    _edit = message;
                                    _reply = null;
                                    _composer.text = message.body;
                                    _composer.selection =
                                        TextSelection.collapsed(
                                          offset: _composer.text.length,
                                        );
                                    _focus.requestFocus();
                                  })
                                : null,
                            onProfile: message.senderId == null
                                ? null
                                : () => showMobileProfileSheet(
                                    context,
                                    backend,
                                    message.senderId!,
                                    onEditOwnProfile: widget.onOpenSettings,
                                  ),
                          );
                        },
                      ),
                      if (!backend.atTimelinePresent)
                        Positioned(
                          right: 14,
                          bottom: 10,
                          child: FilledButton.icon(
                            onPressed: () async {
                              await backend.jumpToPresent();
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                            },
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('Present'),
                          ),
                        ),
                    ],
                  ),
          ),
          _MobileComposer(
            controller: _composer,
            focusNode: _focus,
            sending: _sending,
            attachments: _attachments,
            contextMessage: _edit ?? _reply,
            editing: _edit != null,
            onClearContext: () => setState(() {
              _reply = null;
              _edit = null;
            }),
            onRemoveAttachment: (attachment) =>
                setState(() => _attachments.remove(attachment)),
            onAdd: _showAddMenu,
            onEmoji: _showEmojiPicker,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (_sending || (text.isEmpty && _attachments.isEmpty)) return;
    final roomId = widget.room.id;
    final submittedText = text;
    final submittedAttachments = List<AttachmentDraft>.from(_attachments);
    final reply = _reply;
    final edit = _edit;
    _composer.clear();
    setState(() {
      _sending = true;
      _attachments.clear();
      _reply = null;
      _edit = null;
    });
    try {
      if (submittedAttachments.isEmpty) {
        await backend.sendMessage(
          submittedText,
          roomId: roomId,
          replyToMessageId: reply?.id,
          editMessageId: edit?.id,
        );
      } else {
        for (var index = 0; index < submittedAttachments.length; index++) {
          final item = submittedAttachments[index];
          await backend.sendAttachment(
            AttachmentDraft(
              bytes: item.bytes,
              name: item.name,
              mimeType: item.mimeType,
              spoiler: item.spoiler,
              caption: index == 0 && submittedText.isNotEmpty
                  ? submittedText
                  : null,
            ),
            roomId: roomId,
            replyToMessageId: index == 0 ? reply?.id : null,
          );
        }
      }
    } catch (_) {
      if (mounted &&
          backend.selectedRoom?.id == roomId &&
          _composer.text.isEmpty) {
        _composer.text = submittedText;
        setState(() {
          _attachments.insertAll(0, submittedAttachments);
          _reply = reply;
          _edit = edit;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Image or video'),
              onTap: () => Navigator.pop(context, 'media'),
            ),
            ListTile(
              leading: const Icon(Icons.gif_box_outlined),
              title: const Text('GIF'),
              onTap: () => Navigator.pop(context, 'gif'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'gif') return _showGifPicker();
    if (choice == null) return;
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: choice == 'media' ? FileType.media : FileType.any,
    );
    if (result == null) return;
    final drafts = result.files
        .where((file) => file.bytes != null)
        .map(
          (file) => AttachmentDraft(
            bytes: file.bytes!,
            name: file.name,
            mimeType:
                lookupMimeType(file.name, headerBytes: file.bytes) ??
                'application/octet-stream',
            spoiler: false,
          ),
        );
    setState(() => _attachments.addAll(drafts));
  }

  Future<void> _showEmojiPicker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _MobileEmojiPicker(),
    );
    if (emoji == null) return;
    final selection = _composer.selection;
    final offset = selection.isValid ? selection.start : _composer.text.length;
    _composer.text = _composer.text.replaceRange(offset, offset, emoji);
    _composer.selection = TextSelection.collapsed(
      offset: offset + emoji.length,
    );
    _focus.requestFocus();
  }

  Future<void> _showGifPicker() async {
    final gif = await showModalBottomSheet<GifSearchResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MobileGifPicker(service: _giphy),
    );
    if (gif == null) return;
    final bytes = await _giphy.download(gif);
    if (!mounted) return;
    setState(() {
      _attachments.add(
        AttachmentDraft(
          bytes: bytes,
          name: 'giphy-${DateTime.now().millisecondsSinceEpoch}.gif',
          mimeType: 'image/gif',
          spoiler: false,
        ),
      );
    });
  }

  Future<void> _showSearch() async {
    final controller = TextEditingController();
    var results = const <ChatMessage>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => FractionallySizedBox(
          heightFactor: 0.88,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (query) async {
                    final found = await backend.searchRoomHistory(query);
                    setState(() => results = found);
                  },
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(results[index].sender),
                      subtitle: Text(results[index].body, maxLines: 2),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await backend.jumpToEvent(results[index].id);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }
}

class _MobileMessageRow extends StatelessWidget {
  const _MobileMessageRow({
    required this.backend,
    required this.message,
    required this.grouped,
    required this.onReply,
    required this.onEdit,
    required this.onProfile,
    super.key,
  });
  final ChatBackend backend;
  final ChatMessage message;
  final bool grouped;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('swipe-${message.id}'),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) async {
      onReply();
      return false;
    },
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Icon(Icons.reply),
    ),
    child: InkWell(
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, grouped ? 1 : 7, 8, grouped ? 1 : 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: grouped
                  ? null
                  : GestureDetector(
                      onTap: onProfile,
                      child: MobileAvatar(
                        bytes: message.avatarBytes,
                        fallback: message.sender,
                        size: 40,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!grouped)
                    GestureDetector(
                      onTap: onProfile,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              message.sender,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            MaterialLocalizations.of(context).formatTimeOfDay(
                              TimeOfDay.fromDateTime(message.timestamp),
                              alwaysUse24HourFormat:
                                  backend.preferences.use24HourTime,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (message.pending) ...[
                            const SizedBox(width: 5),
                            const SizedBox.square(
                              dimension: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (message.reply case final reply?)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: context.deltiecord.elevated,
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        '${reply.sender}: ${reply.body}',
                        maxLines: 2,
                      ),
                    ),
                  if (!message.redacted)
                    SelectableText(message.body)
                  else
                    const Text(
                      'Message deleted',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  if (message.attachment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: MobileAttachmentView(
                        backend: backend,
                        message: message,
                      ),
                    ),
                  if (message.linkPreview case final preview?)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: MobileLinkPreviewCard(preview: preview),
                    ),
                  if (message.reactions.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final reaction in message.reactions)
                          ActionChip(
                            label: Text('${reaction.key} ${reaction.count}'),
                            onPressed: () => backend.toggleReaction(
                              message.id,
                              reaction.key,
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
  );

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () => Navigator.pop(context, 'react'),
            ),
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (message.canRedact)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy event link'),
              onTap: () => Navigator.pop(context, 'link'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'reply':
        onReply();
      case 'edit':
        onEdit?.call();
      case 'delete':
        await backend.redactMessage(message.id);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
      case 'link':
        await Clipboard.setData(
          ClipboardData(
            text:
                'https://matrix.to/#/${backend.selectedRoom?.id}/${message.id}',
          ),
        );
      case 'react':
        if (!context.mounted) return;
        final emoji = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => const _MobileEmojiPicker(),
        );
        if (emoji != null) await backend.toggleReaction(message.id, emoji);
    }
  }
}

class _MobileComposer extends StatelessWidget {
  const _MobileComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.attachments,
    required this.contextMessage,
    required this.editing,
    required this.onClearContext,
    required this.onRemoveAttachment,
    required this.onAdd,
    required this.onEmoji,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final List<AttachmentDraft> attachments;
  final ChatMessage? contextMessage;
  final bool editing;
  final VoidCallback onClearContext;
  final ValueChanged<AttachmentDraft> onRemoveAttachment;
  final VoidCallback onAdd;
  final VoidCallback onEmoji;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      key: const ValueKey('mobile-composer'),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: context.deltiecord.elevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contextMessage case final message?)
            ListTile(
              dense: true,
              title: Text(
                editing ? 'Editing message' : 'Replying to ${message.sender}',
              ),
              subtitle: Text(
                message.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: onClearContext,
                icon: const Icon(Icons.close),
              ),
            ),
          if (attachments.isNotEmpty)
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final attachment = attachments[index];
                  return InputChip(
                    avatar: const Icon(Icons.attach_file, size: 18),
                    label: SizedBox(
                      width: 100,
                      child: Text(
                        attachment.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: () => onRemoveAttachment(attachment),
                  );
                },
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 48,
                    maxHeight: MediaQuery.sizeOf(context).height / 3,
                  ),
                  child: TextField(
                    key: const ValueKey('mobile-composer-field'),
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onEmoji,
                icon: const Icon(Icons.emoji_emotions_outlined),
              ),
              IconButton(
                onPressed: sending ? null : onSend,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MobileEmojiPicker extends StatefulWidget {
  const _MobileEmojiPicker();

  @override
  State<_MobileEmojiPicker> createState() => _MobileEmojiPickerState();
}

class _MobileEmojiPickerState extends State<_MobileEmojiPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.72,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search emoji',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<EmojiEntry>>(
              future: EmojiRepository.instance.search(_query, limit: 300),
              builder: (context, snapshot) {
                final entries = snapshot.data;
                if (entries == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => IconButton(
                    tooltip:
                        ':${entries[index].aliases.firstOrNull ?? entries[index].name}:',
                    onPressed: () =>
                        Navigator.pop(context, entries[index].emoji),
                    icon: Text(
                      entries[index].emoji,
                      style: const TextStyle(fontSize: 27),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _MobileGifPicker extends StatefulWidget {
  const _MobileGifPicker({required this.service});
  final GiphyService service;

  @override
  State<_MobileGifPicker> createState() => _MobileGifPickerState();
}

class _MobileGifPickerState extends State<_MobileGifPicker> {
  Timer? _debounce;
  Future<List<GifSearchResult>>? _results;

  @override
  void initState() {
    super.initState();
    _results = widget.service.trending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.78,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search GIFs',
            ),
            onChanged: (query) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() {
                    _results = query.trim().isEmpty
                        ? widget.service.trending()
                        : widget.service.search(query.trim());
                  });
                }
              });
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<GifSearchResult>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('GIF search unavailable'));
                }
                final results = snapshot.data;
                if (results == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) => InkWell(
                    onTap: () => Navigator.pop(context, results[index]),
                    child: Image.network(
                      results[index].previewUrl.toString(),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
