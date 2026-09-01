part of 'chat_shell.dart';

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.backend,
    required this.controller,
    required this.composerFocus,
    required this.sending,
    required this.replyingTo,
    required this.editingMessage,
    required this.onSend,
    required this.onReply,
    required this.onEdit,
    required this.onCancelComposerAction,
    required this.onAttach,
    required this.onGif,
    required this.onPasteImage,
    required this.onDropAttachments,
    required this.pendingAttachments,
    required this.onRemoveAttachment,
    required this.onToggleAttachmentSpoiler,
    required this.mentionSuggestions,
    required this.mentionSelectionIndex,
    required this.onMentionSelected,
    required this.onMentionSelectionChanged,
    required this.onShowMembers,
    required this.onShowProfile,
    required this.composerKey,
    super.key,
  });

  final ChatBackend backend;
  final QuillController controller;
  final FocusNode composerFocus;
  final bool sending;
  final ChatMessage? replyingTo;
  final ChatMessage? editingMessage;
  final VoidCallback onSend;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final VoidCallback onCancelComposerAction;
  final VoidCallback onAttach;
  final VoidCallback onGif;
  final Future<bool> Function() onPasteImage;
  final ValueChanged<List<AttachmentDraft>> onDropAttachments;
  final List<AttachmentDraft> pendingAttachments;
  final ValueChanged<int> onRemoveAttachment;
  final ValueChanged<int> onToggleAttachmentSpoiler;
  final List<MentionSuggestion> mentionSuggestions;
  final int mentionSelectionIndex;
  final ValueChanged<String> onMentionSelected;
  final ValueChanged<int> onMentionSelectionChanged;
  final VoidCallback onShowMembers;
  final ValueChanged<(RoomMemberSummary, Offset?)> onShowProfile;
  final GlobalKey<_RichComposerState> composerKey;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  static const _jumpToPresentScrollThreshold = 360.0;

  final _scrollController = ScrollController();
  final _timelineViewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<GlobalKey, String> _messageIdsByKey = {};
  String? _roomId;
  bool _loadingAnchoredHistory = false;
  bool _draggingFiles = false;
  bool _scrolledAwayFromPresent = false;
  DateTime _timelineUserInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _suppressPaginationUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _navigationGeneration = 0;
  int _timelineInputGeneration = 0;
  int? _timelineLayoutFingerprint;
  int _layoutAnchorGeneration = 0;
  String? _newestMessageId;
  String? _highlightedMessageId;
  VoidCallback? _dismissMessageActions;

  @override
  void initState() {
    super.initState();
    _roomId = widget.backend.selectedRoom?.id;
    _newestMessageId = widget.backend.messages.firstOrNull?.id;
    _scrollController.addListener(_loadTimelineNearEdges);
    _focusComposerAfterBuild();
  }

  void _focusComposerAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.sending) widget.composerFocus.requestFocus();
    });
  }

  void _loadTimelineNearEdges() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final scrolledAway = position.pixels > _jumpToPresentScrollThreshold;
    if (scrolledAway != _scrolledAwayFromPresent && mounted) {
      setState(() => _scrolledAwayFromPresent = scrolledAway);
    }
    // Content insertion, eviction, and anchor restoration all update scroll
    // metrics. Only paginate automatically while the user is actively moving
    // toward that edge; otherwise one page can recursively trigger another.
    final isUserDriven = DateTime.now().isBefore(_timelineUserInputUntil);
    final paginationSuppressed = DateTime.now().isBefore(
      _suppressPaginationUntil,
    );
    if (!paginationSuppressed &&
        isUserDriven &&
        position.userScrollDirection == ScrollDirection.reverse &&
        position.pixels >= position.maxScrollExtent - 240) {
      _loadOlderAnchored();
    } else if (!paginationSuppressed &&
        isUserDriven &&
        position.userScrollDirection == ScrollDirection.forward &&
        position.pixels <= 240 &&
        widget.backend.canLoadMoreFuture) {
      _loadNewerAnchored();
    }
  }

  void _noteTimelineUserInput(PointerEvent _) {
    _timelineInputGeneration++;
    _timelineUserInputUntil = DateTime.now().add(const Duration(seconds: 1));
  }

  (String, double)? _captureVisibleAnchor() {
    final viewport = _timelineViewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    (String, double)? closest;
    var closestDistance = double.infinity;
    for (final entry in _messageKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final offset = renderObject.localToGlobal(Offset.zero);
      final bottom = offset.dy + renderObject.size.height;
      if (bottom < viewportTop || offset.dy > viewportBottom) {
        continue;
      }
      // Anchor the row nearest the leading viewport edge. Unlike a centre
      // heuristic this remains deterministic when very tall media spans most
      // of the screen.
      final distance = (offset.dy - viewportTop).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = (entry.key, offset.dy);
      }
    }
    return closest;
  }

  void _restoreVisibleAnchor((String, double)? anchor) {
    if (anchor == null || !_scrollController.hasClients) return;
    final renderObject = _messageKeys[anchor.$1]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final newOffset = renderObject.localToGlobal(Offset.zero).dy;
    // The timeline is reversed. Increasing the scroll offset moves a retained
    // row toward the bottom, so compensate with the inverse displacement.
    final corrected =
        (_scrollController.position.pixels - (newOffset - anchor.$2)).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
    _scrollController.jumpTo(corrected);
  }

  Future<void> _loadPageAnchored(
    Future<void> Function(String? anchorEventId) load,
  ) async {
    if (_loadingAnchoredHistory || !_scrollController.hasClients) return;
    _loadingAnchoredHistory = true;
    _suppressPaginationUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    final anchor = _captureVisibleAnchor();
    final inputGeneration = _timelineInputGeneration;
    try {
      await load(anchor?.$1);
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || inputGeneration != _timelineInputGeneration) return;
      _restoreVisibleAnchor(anchor);
    } catch (_) {
      // The backend reports its user-facing pagination error separately.
    } finally {
      _loadingAnchoredHistory = false;
    }
  }

  Future<void> _loadOlderAnchored() => _loadPageAnchored(
    (anchorEventId) =>
        widget.backend.loadMoreHistory(anchorEventId: anchorEventId),
  );

  Future<void> _loadNewerAnchored() => _loadPageAnchored(
    (anchorEventId) =>
        widget.backend.loadMoreFuture(anchorEventId: anchorEventId),
  );

  int _layoutFingerprint(List<ChatMessage> messages) => Object.hashAll(
    messages.map(
      (message) => Object.hash(
        message.id,
        message.reply?.eventId,
        message.linkPreviews.length,
        message.linkPreview?.width,
        message.linkPreview?.height,
        message.reactions.length,
      ),
    ),
  );

  void _preserveAnchorAcrossMetadataLayout(List<ChatMessage> messages) {
    final next = _layoutFingerprint(messages);
    final previous = _timelineLayoutFingerprint;
    _timelineLayoutFingerprint = next;
    if (previous == null ||
        previous == next ||
        _loadingAnchoredHistory ||
        !_scrolledAwayFromPresent ||
        DateTime.now().isBefore(_timelineUserInputUntil)) {
      return;
    }
    final anchor = _captureVisibleAnchor();
    if (anchor == null) return;
    final generation = ++_layoutAnchorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutAnchorGeneration) return;
      _restoreVisibleAnchor(anchor);
    });
  }

  Future<void> _jumpToFirstUnread() async {
    final eventId = widget.backend.firstUnreadMessageId;
    if (eventId == null || !_scrollController.hasClients) return;
    await _jumpToEvent(eventId);
  }

  Future<void> _returnToPresent() async {
    // Reconstruct the recent timeline even when the button was triggered only
    // by local scrolling. This prevents a pruned/stale recent window from
    // masquerading as the current room state.
    await widget.backend.jumpToPresent();
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: widget.backend.preferences.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
    if (mounted && _scrolledAwayFromPresent) {
      setState(() => _scrolledAwayFromPresent = false);
    }
  }

  @override
  void didUpdateWidget(covariant _Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roomId = widget.backend.selectedRoom?.id;
    final newestMessageId = widget.backend.messages.firstOrNull?.id;
    final receivedNewHead =
        _roomId == roomId &&
        _newestMessageId != null &&
        newestMessageId != null &&
        newestMessageId != _newestMessageId;
    final wasAtPresent =
        !_scrolledAwayFromPresent &&
        (!_scrollController.hasClients || _scrollController.offset <= 48);
    if (_roomId != roomId) {
      _roomId = roomId;
      _scrolledAwayFromPresent = false;
      _messageKeys.clear();
      _messageIdsByKey.clear();
      _navigationGeneration++;
      _highlightedMessageId = null;
      _newestMessageId = newestMessageId;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _focusComposerAfterBuild();
    } else if (oldWidget.sending && !widget.sending) {
      _focusComposerAfterBuild();
    }
    _newestMessageId = newestMessageId;
    if (receivedNewHead && wasAtPresent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _roomId != roomId || !_scrollController.hasClients) {
          return;
        }
        // In a reversed timeline offset zero is the present. A live event is
        // already inserted there, so keep the viewport pinned without an
        // animated correction that can flash the previous row first.
        _scrollController.jumpTo(0);
      });
    }
  }

  GlobalKey _messageKeyFor(String eventId) {
    final key = _messageKeys.putIfAbsent(eventId, GlobalKey.new);
    _messageIdsByKey[key] = eventId;
    return key;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This removes the message for everyone in the room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.backend.redactMessage(message.id);
    _focusComposerAfterBuild();
  }

  Future<void> _pickReaction(ChatMessage message) async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => const EmojiPickerDialog(),
    );
    if (emoji != null) await widget.backend.toggleReaction(message.id, emoji);
    _focusComposerAfterBuild();
  }

  Future<void> showSearch() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _RoomSearchDialog(backend: widget.backend, onSelected: _jumpToEvent),
    );
    _focusComposerAfterBuild();
  }

  Future<void> _showPins() async {
    final messages = await widget.backend.loadPinnedMessages();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pinned messages'),
        content: SizedBox(
          width: 460,
          child: messages.isEmpty
              ? const Text('No pinned messages')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final message in messages)
                      ListTile(
                        dense: true,
                        title: Text(message.sender),
                        subtitle: Text(message.body),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          _jumpToEvent(message.id);
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
    _focusComposerAfterBuild();
  }

  Future<void> _jumpToEvent(String eventId) async {
    final generation = ++_navigationGeneration;
    _suppressPaginationUntil = DateTime.now().add(const Duration(seconds: 1));
    if (!await _scrollToMessage(eventId, generation)) {
      await widget.backend.jumpToEvent(eventId);
      if (!mounted || generation != _navigationGeneration) return;
      await _scrollToMessage(eventId, generation, waitForBuild: true);
    }
    if (!mounted || generation != _navigationGeneration) return;
    await _blinkMessage(eventId, generation);
  }

  Future<bool> _scrollToMessage(
    String eventId,
    int generation, {
    bool waitForBuild = false,
  }) async {
    final attempts = waitForBuild ? 8 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!mounted || generation != _navigationGeneration) return false;
      final targetContext = _messageKeys[eventId]?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: widget.backend.preferences.reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
        );
        return true;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  Future<void> _blinkMessage(String eventId, int generation) async {
    for (var pulse = 0; pulse < 2; pulse++) {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _highlightedMessageId = eventId);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _highlightedMessageId = null);
      if (pulse == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 110));
      }
    }
  }

  void showMembers() {
    widget.onShowMembers();
    _focusComposerAfterBuild();
  }

  bool dismissTemporaryUi() {
    final dismiss = _dismissMessageActions;
    if (dismiss == null) return false;
    _dismissMessageActions = null;
    dismiss();
    return true;
  }

  void _registerMessageActions(VoidCallback dismiss) {
    _dismissMessageActions?.call();
    _dismissMessageActions = dismiss;
  }

  DropOperation _onDropOver(DropOverEvent event) {
    if (!_draggingFiles) setState(() => _draggingFiles = true);
    return event.session.allowedOperations.contains(DropOperation.copy)
        ? DropOperation.copy
        : DropOperation.none;
  }

  void _onDropLeave(DropEvent _) {
    if (_draggingFiles) setState(() => _draggingFiles = false);
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final attachments = <AttachmentDraft>[];
    try {
      for (final item in event.session.items) {
        final reader = item.dataReader;
        if (reader == null) continue;
        final suggestedName = await reader.getSuggestedName();
        final completed = Completer<AttachmentDraft?>();
        final progress = reader.getFile(null, (file) async {
          try {
            final bytes = await file.readAll();
            final name = file.fileName ?? suggestedName ?? 'attachment';
            completed.complete(
              AttachmentDraft(
                bytes: bytes,
                name: name,
                mimeType:
                    lookupMimeType(name, headerBytes: bytes) ??
                    'application/octet-stream',
                spoiler: false,
              ),
            );
          } catch (_) {
            completed.complete(null);
          }
        }, onError: (_) => completed.complete(null));
        if (progress == null) continue;
        final attachment = await completed.future;
        if (attachment != null) attachments.add(attachment);
      }
      widget.onDropAttachments(attachments);
    } finally {
      if (mounted) setState(() => _draggingFiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final room = backend.selectedRoom!;
    final messages = backend.messages;
    _preserveAnchorAcrossMetadataLayout(messages);
    final retainedIds = messages.map((message) => message.id).toSet();
    _messageKeys.removeWhere((eventId, _) => !retainedIds.contains(eventId));
    _messageIdsByKey
      ..clear()
      ..addEntries(
        _messageKeys.entries.map((entry) => MapEntry(entry.value, entry.key)),
      );
    final messageIndexes = <String, int>{
      for (var index = 0; index < messages.length; index++)
        messages[index].id: index,
    };
    final mediaMessages = messages
        .where(
          (message) =>
              message.attachment?.kind == AttachmentKind.image ||
              message.attachment?.kind == AttachmentKind.video,
        )
        .toList(growable: false);
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onPerformDrop: _onPerformDrop,
      onDropLeave: _onDropLeave,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: context.deltiecord.surface,
                    border: Border(
                      bottom: BorderSide(color: context.deltiecord.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      _RoomIcon(room: room, size: 30),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: DeltiecordTypeScale.bigUi,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (room.isDirect)
                              _ConversationPresence(presence: room.presence)
                            else if (room.topic.isNotEmpty)
                              Text(
                                room.topic,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: DeltiecordTypeScale.normal,
                                  color: context.deltiecord.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${backend.selectedRoomMembers.length}',
                        style: TextStyle(
                          fontSize: DeltiecordTypeScale.normal,
                          color: context.deltiecord.muted,
                        ),
                      ),
                      if (backend.firstUnreadMessageId != null)
                        IconButton(
                          tooltip: 'Jump to first unread',
                          onPressed: _jumpToFirstUnread,
                          icon: const Icon(
                            Icons.mark_chat_unread_outlined,
                            size: 19,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Search',
                        onPressed: showSearch,
                        icon: const Icon(Icons.search, size: 19),
                      ),
                      IconButton(
                        tooltip: 'Pinned messages',
                        onPressed: _showPins,
                        icon: const Icon(Icons.push_pin_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Members',
                        onPressed: widget.onShowMembers,
                        icon: const Icon(Icons.people_outline, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Start MatrixRTC call',
                        onPressed: () => backend.joinVoiceRoom(room.id),
                        icon: const Icon(Icons.video_call_outlined, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Copy room link',
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: 'https://matrix.to/#/${room.id}'),
                        ),
                        icon: const Icon(Icons.link, size: 19),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Notification options',
                        icon: Icon(
                          backend.selectedRoomMuted
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_none,
                          size: 19,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'mute':
                              backend.setSelectedRoomMuted(
                                !backend.selectedRoomMuted,
                              );
                            case 'previews':
                              backend.setNotificationPreviewsEnabled(
                                !backend.notificationPreviewsEnabled,
                              );
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'mute',
                            child: Text(
                              backend.selectedRoomMuted
                                  ? 'Unmute this room'
                                  : 'Mute this room',
                            ),
                          ),
                          CheckedPopupMenuItem(
                            value: 'previews',
                            checked: backend.notificationPreviewsEnabled,
                            child: const Text('Show message previews'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (backend.error case final error?)
                  MaterialBanner(
                    content: Text(error),
                    actions: [
                      TextButton(
                        onPressed: backend.clearError,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Stack(
                    key: const Key('conversation-timeline-area'),
                    children: [
                      Positioned.fill(
                        child: KeyedSubtree(
                          key: _timelineViewportKey,
                          child: Listener(
                            onPointerDown: _noteTimelineUserInput,
                            onPointerMove: _noteTimelineUserInput,
                            onPointerSignal: _noteTimelineUserInput,
                            child: backend.timelineLoading && messages.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : backend.messages.isEmpty
                                ? const Center(child: Text('No messages yet'))
                                : ListView.builder(
                                    key: const Key('message-timeline'),
                                    controller: _scrollController,
                                    reverse: true,
                                    physics: const ClampingScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      10,
                                      0,
                                      14,
                                    ),
                                    itemCount:
                                        messages.length +
                                        (backend.historyLoading ||
                                                backend.canLoadMoreHistory
                                            ? 1
                                            : 0),
                                    findChildIndexCallback: (key) {
                                      final messageId = key is GlobalKey
                                          ? _messageIdsByKey[key]
                                          : null;
                                      if (messageId == null) return null;
                                      return messageIndexes[messageId];
                                    },
                                    itemBuilder: (context, index) {
                                      if (index == messages.length) {
                                        return SizedBox(
                                          height: 64,
                                          child: Center(
                                            child: backend.historyLoading
                                                ? const SizedBox.square(
                                                    dimension: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : TextButton.icon(
                                                    onPressed:
                                                        _loadOlderAnchored,
                                                    icon: const Icon(
                                                      Icons.history,
                                                      size: 17,
                                                    ),
                                                    label: const Text(
                                                      'Load older messages',
                                                    ),
                                                  ),
                                          ),
                                        );
                                      }
                                      final message = messages[index];
                                      final older = index + 1 < messages.length
                                          ? messages[index + 1]
                                          : null;
                                      final startsGroup =
                                          older == null ||
                                          older.sender != message.sender ||
                                          message.timestamp.difference(
                                                older.timestamp,
                                              ) >
                                              const Duration(minutes: 7) ||
                                          message.reply != null;
                                      return Column(
                                        key: _messageKeyFor(message.id),
                                        children: [
                                          if (message.id ==
                                              backend.firstUnreadMessageId)
                                            const _UnreadDivider(),
                                          _MessageRow(
                                            message: message,
                                            highlighted:
                                                _highlightedMessageId ==
                                                message.id,
                                            startsGroup: startsGroup,
                                            onReply: () =>
                                                widget.onReply(message),
                                            onEdit:
                                                message.own && !message.redacted
                                                ? () => widget.onEdit(message)
                                                : null,
                                            onDelete: message.canRedact
                                                ? () => _deleteMessage(message)
                                                : null,
                                            onReact:
                                                message.redacted ||
                                                    message.system
                                                ? null
                                                : () => _pickReaction(message),
                                            onRetry: message.failed
                                                ? () => backend.retryMessage(
                                                    message.id,
                                                  )
                                                : null,
                                            onCancel:
                                                message.pending ||
                                                    message.failed
                                                ? () => backend
                                                      .cancelPendingMessage(
                                                        message.id,
                                                      )
                                                : null,
                                            onToggleReaction: (key) =>
                                                backend.toggleReaction(
                                                  message.id,
                                                  key,
                                                ),
                                            onJumpToReply: _jumpToEvent,
                                            mediaMessages: mediaMessages,
                                            backend: backend,
                                            onShowProfile: widget.onShowProfile,
                                            onActionsShown:
                                                _registerMessageActions,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                      if (backend.timelineLoading && messages.isNotEmpty)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (backend.canLoadMoreFuture)
                        Positioned(
                          right: 16,
                          bottom: 58,
                          child: FilledButton.tonalIcon(
                            key: const Key('load-newer-messages'),
                            onPressed: backend.historyLoading
                                ? null
                                : _loadNewerAnchored,
                            icon: backend.historyLoading
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.update, size: 17),
                            label: const Text('Load newer messages'),
                          ),
                        ),
                      if (!backend.atTimelinePresent ||
                          _scrolledAwayFromPresent)
                        Positioned(
                          right: 16,
                          bottom: 12,
                          child: FilledButton.tonalIcon(
                            onPressed: _returnToPresent,
                            icon: const Icon(
                              Icons.vertical_align_bottom,
                              size: 17,
                            ),
                            label: Text(
                              room.unreadCount > 0
                                  ? 'Jump to present (${room.unreadCount})'
                                  : 'Jump to present',
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: IgnorePointer(
                          child: ClipRect(
                            child: AnimatedSlide(
                              duration: backend.preferences.reducedMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                              curve: Curves.easeOut,
                              offset: backend.typingUserNames.isEmpty
                                  ? const Offset(0, -1)
                                  : Offset.zero,
                              child: AnimatedOpacity(
                                duration: backend.preferences.reducedMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 100),
                                opacity: backend.typingUserNames.isEmpty
                                    ? 0
                                    : 1,
                                child: Container(
                                  key: const Key('typing-indicator'),
                                  height: 24,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: context.deltiecord.panel,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: context.deltiecord.divider,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    backend.typingUserNames.isEmpty
                                        ? ''
                                        : _typingLabel(backend.typingUserNames),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: DeltiecordTypeScale.normal,
                                      color: context.deltiecord.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.replyingTo case final message?)
                  _ComposerContext(
                    label: 'Replying to ${message.sender}',
                    body: message.body,
                    onCancel: widget.onCancelComposerAction,
                  )
                else if (widget.editingMessage case final message?)
                  _ComposerContext(
                    label: 'Editing message',
                    body: message.body,
                    onCancel: widget.onCancelComposerAction,
                  ),
                if (widget.mentionSuggestions.isNotEmpty)
                  _MentionPicker(
                    suggestions: widget.mentionSuggestions,
                    selectedIndex: widget.mentionSelectionIndex,
                    onSelected: widget.onMentionSelected,
                  ),
                _RichComposer(
                  key: widget.composerKey,
                  controller: widget.controller,
                  focusNode: widget.composerFocus,
                  roomName: room.name,
                  // The editor remains live while this only gates attachment
                  // and submit controls for the in-flight request.
                  enabled: !widget.sending,
                  sendWithCtrlEnter: backend.preferences.sendWithCtrlEnter,
                  onSend: widget.onSend,
                  onAttach: widget.onAttach,
                  onGif: widget.onGif,
                  onPasteImage: widget.onPasteImage,
                  pendingAttachments: widget.pendingAttachments,
                  onRemoveAttachment: widget.onRemoveAttachment,
                  onToggleAttachmentSpoiler: widget.onToggleAttachmentSpoiler,
                  mentionSuggestions: widget.mentionSuggestions,
                  mentionSelectionIndex: widget.mentionSelectionIndex,
                  onMentionSelected: widget.onMentionSelected,
                  onMentionSelectionChanged: widget.onMentionSelectionChanged,
                  maxHeight: max(
                    _bottomPanelHeightFor(context),
                    (MediaQuery.sizeOf(context).height - 56) / 3,
                  ),
                ),
              ],
            ),
          ),
          if (_draggingFiles)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0xaa111216),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: context.deltiecord.elevated,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      child: const Text('Drop files to attach'),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _typingLabel(List<String> names) {
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length == 2) {
      return '${names.first} and ${names.last} are typing…';
    }
    return '${names.first}, ${names[1]} and ${names.length - 2} others are typing…';
  }
}

class _ConversationPresence extends StatelessWidget {
  const _ConversationPresence({required this.presence});

  final UserPresence presence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (presence) {
      UserPresence.online => ('Online', const Color(0xff43b581)),
      UserPresence.away => ('Away', const Color(0xffffc857)),
      UserPresence.offline => ('Offline', const Color(0xff747680)),
    };
    return Semantics(
      label: 'Presence: $label',
      child: Row(
        key: ValueKey('conversation-presence-${presence.name}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: DeltiecordTypeScale.small,
              color: context.deltiecord.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomSearchDialog extends StatefulWidget {
  const _RoomSearchDialog({required this.backend, required this.onSelected});

  final ChatBackend backend;
  final ValueChanged<String> onSelected;

  @override
  State<_RoomSearchDialog> createState() => _RoomSearchDialogState();
}

class _RoomSearchDialogState extends State<_RoomSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = const [];
  bool _searching = false;
  String? _error;
  int _generation = 0;

  void _queryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.backend.searchRoomHistory(query);
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'Search failed. Try again.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search this room'),
    content: SizedBox(
      width: 520,
      height: 430,
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search message history',
            ),
            onChanged: _queryChanged,
            onSubmitted: (_) {
              _debounce?.cancel();
              _search();
            },
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final message = _results[index];
                return ListTile(
                  dense: true,
                  title: Text(message.sender),
                  subtitle: Text(
                    message.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelected(message.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Close'),
      ),
    ],
  );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, size: 46),
        SizedBox(height: 12),
        Text('Choose a room to start chatting'),
      ],
    ),
  );
}
