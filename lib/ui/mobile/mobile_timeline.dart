import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/emoji_completion.dart';
import '../../services/emoji_repository.dart';
import '../../services/custom_emoji.dart';
import '../../services/favourite_reactions_store.dart';
import '../../services/giphy_service.dart';
import '../deltiecord_theme.dart';
import '../advanced_chat_dialogs.dart';
import '../advanced_chat_views.dart';
import '../matrix_html_text.dart';
import '../poll_card.dart';
import '../typing_indicator.dart';
import '../room_search_panel.dart';
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
    required this.initialCustomEmojis,
    required this.onDraftChanged,
    super.key,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback onOpenNavigation;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenSettings;
  final String initialDraft;
  final List<CustomEmojiTextSpan> initialCustomEmojis;
  final ValueChanged<({String text, List<CustomEmojiTextSpan> emojis})>
  onDraftChanged;

  @override
  State<MobileTimelineView> createState() => _MobileTimelineViewState();
}

class _MobileTimelineViewState extends State<MobileTimelineView> {
  late final TextEditingController _composer;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final GlobalKey _timelineViewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<GlobalKey, String> _messageIdsByKey = {};
  final _giphy = GiphyService();
  final List<AttachmentDraft> _attachments = [];
  ChatMessage? _reply;
  ChatMessage? _edit;
  bool _sending = false;
  bool _autoFillingInitialChunk = false;
  bool _pageLoadInFlight = false;
  bool _restoringScrollAnchor = false;
  DateTime _timelineUserInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _suppressPaginationUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int? _timelineLayoutFingerprint;
  int _layoutAnchorGeneration = 0;
  int _navigationGeneration = 0;
  bool _scrolledAwayFromPresent = false;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  Completer<void>? _highlightWaiter;
  List<EmojiEntry> _emojiMatches = const [];
  int _emojiSelection = 0;
  int? _emojiStart;
  int _emojiGeneration = 0;
  bool _replacingEmoji = false;
  late List<CustomEmojiTextSpan> _customEmojiSpans;
  late String _previousComposerText;
  List<MentionSuggestion> _mentionMatches = const [];
  int? _mentionStart;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController(text: widget.initialDraft)
      ..addListener(_composerChanged);
    _customEmojiSpans = List.of(widget.initialCustomEmojis);
    _previousComposerText = widget.initialDraft;
    _scroll.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reportTimelineAtPresent(),
    );
  }

  @override
  void didUpdateWidget(covariant MobileTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id == widget.room.id) return;
    backend.setConversationAtPresent(false);
    _composer
      ..removeListener(_composerChanged)
      ..text = widget.initialDraft
      ..addListener(_composerChanged);
    _customEmojiSpans = List.of(widget.initialCustomEmojis);
    _previousComposerText = widget.initialDraft;
    _reply = null;
    _edit = null;
    _attachments.clear();
    _scrolledAwayFromPresent = false;
    _messageKeys.clear();
    _messageIdsByKey.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reportTimelineAtPresent(),
    );
  }

  void _composerChanged() {
    _customEmojiSpans = reconcileCustomEmojiSpans(
      _previousComposerText,
      _composer.text,
      _customEmojiSpans,
    );
    _previousComposerText = _composer.text;
    widget.onDraftChanged((
      text: _composer.text,
      emojis: List.unmodifiable(_customEmojiSpans),
    ));
    unawaited(backend.setComposerTyping(_composer.text.isNotEmpty));
    if (!_replacingEmoji) _updateEmojiCompletion();
    _updateMentionCompletion();
  }

  void _updateMentionCompletion() {
    final cursor = _composer.selection.isValid
        ? _composer.selection.extentOffset.clamp(0, _composer.text.length)
        : _composer.text.length;
    final before = _composer.text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    if (match == null) {
      if (_mentionMatches.isNotEmpty || _mentionStart != null) {
        setState(() {
          _mentionMatches = const [];
          _mentionStart = null;
        });
      }
      return;
    }
    final query = (match.group(1) ?? '').toLowerCase();
    final matches = backend.mentionSuggestions
        .where(
          (suggestion) =>
              suggestion.displayName.toLowerCase().contains(query) ||
              suggestion.matrixId.toLowerCase().contains(query),
        )
        .take(6)
        .toList(growable: false);
    setState(() {
      _mentionStart = match.start + (match.group(0)!.startsWith(' ') ? 1 : 0);
      _mentionMatches = matches;
    });
  }

  void _acceptMention(MentionSuggestion suggestion) {
    final start = _mentionStart;
    if (start == null) return;
    final cursor = _composer.selection.extentOffset.clamp(
      start,
      _composer.text.length,
    );
    final replacement = '${suggestion.matrixId} ';
    _composer.value = TextEditingValue(
      text: _composer.text.replaceRange(start, cursor, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    setState(() {
      _mentionMatches = const [];
      _mentionStart = null;
    });
    _focus.requestFocus();
  }

  void _updateEmojiCompletion() {
    final selection = _composer.selection;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, _composer.text.length)
        : _composer.text.length;
    final completion = findEmojiCompletion(_composer.text, cursor);
    if (completion == null) {
      _clearEmojiCompletion();
      return;
    }
    if (completion.closed) {
      final custom = customEmojiEntries(backend.stickerPacks)
          .where(
            (entry) =>
                entry.name.toLowerCase() == completion.query.toLowerCase(),
          )
          .firstOrNull;
      if (custom != null) {
        _replaceEmojiCompletion(completion.start, cursor, custom);
        return;
      }
      final generation = ++_emojiGeneration;
      final familiar = EmojiRepository.instance.familiarEmoji(completion.query);
      if (familiar != null) {
        _replaceUnicodeEmojiCompletion(completion.start, cursor, familiar);
        return;
      }
      EmojiRepository.instance.exactAlias(completion.query).then((entry) {
        if (!mounted || generation != _emojiGeneration || entry == null) return;
        _replaceUnicodeEmojiCompletion(completion.start, cursor, entry.emoji);
      });
      return;
    }

    final generation = ++_emojiGeneration;
    final custom = customEmojiEntries(backend.stickerPacks)
        .where((entry) => entry.matches(completion.query))
        .take(3)
        .toList(growable: false);
    final familiar = EmojiRepository.instance.familiarMatches(completion.query);
    setState(() {
      _emojiStart = completion.start;
      _emojiMatches = [...custom, ...familiar].take(3).toList();
      _emojiSelection = 0;
    });
    EmojiRepository.instance.search(completion.query, limit: 3).then((matches) {
      if (!mounted || generation != _emojiGeneration) return;
      setState(() {
        _emojiStart = completion.start;
        _emojiMatches = [...custom, ...matches].take(3).toList();
        _emojiSelection = matches.isEmpty
            ? 0
            : _emojiSelection.clamp(0, matches.length - 1);
      });
    });
  }

  void _replaceUnicodeEmojiCompletion(int start, int end, String emoji) {
    _replacingEmoji = true;
    _composer.value = TextEditingValue(
      text: _composer.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _replacingEmoji = false;
    _clearEmojiCompletion();
  }

  void _acceptEmojiCompletion(EmojiEntry entry) {
    final start = _emojiStart;
    if (start == null) return;
    final selection = _composer.selection;
    final end = selection.isValid
        ? selection.extentOffset.clamp(start, _composer.text.length)
        : _composer.text.length;
    _replaceEmojiCompletion(start, end, entry);
    _focus.requestFocus();
  }

  void _replaceEmojiCompletion(int start, int end, EmojiEntry entry) {
    final replacement = entry.insertionText;
    _replacingEmoji = true;
    _composer.value = TextEditingValue(
      text: _composer.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    if (entry.customEmoji?.customEmoji case final custom?) {
      _customEmojiSpans.add(
        CustomEmojiTextSpan(
          start: start,
          end: start + replacement.length,
          emoji: custom,
        ),
      );
    }
    _replacingEmoji = false;
    _clearEmojiCompletion();
    widget.onDraftChanged((
      text: _composer.text,
      emojis: List.unmodifiable(_customEmojiSpans),
    ));
  }

  void _clearEmojiCompletion() {
    _emojiGeneration++;
    if (_emojiMatches.isEmpty && _emojiStart == null) return;
    setState(() {
      _emojiMatches = const [];
      _emojiStart = null;
      _emojiSelection = 0;
    });
  }

  void _handleScroll() {
    if (!_scroll.hasClients || _restoringScrollAnchor) return;
    final position = _scroll.position;
    final jumpThreshold = (position.viewportDimension * 0.75).clamp(
      320.0,
      640.0,
    );
    final scrolledAway = position.pixels > jumpThreshold;
    if (scrolledAway != _scrolledAwayFromPresent && mounted) {
      setState(() => _scrolledAwayFromPresent = scrolledAway);
    }
    backend.setConversationAtPresent(
      position.pixels <= 48 && backend.atTimelinePresent,
    );
    if (backend.historyLoading || _pageLoadInFlight) return;
    if (DateTime.now().isAfter(_timelineUserInputUntil) ||
        DateTime.now().isBefore(_suppressPaginationUntil)) {
      return;
    }
    if (position.userScrollDirection == ScrollDirection.reverse &&
        position.pixels >= position.maxScrollExtent - 180 &&
        backend.canLoadMoreHistory) {
      unawaited(_loadTimelinePage(older: true));
    } else if (position.userScrollDirection == ScrollDirection.forward &&
        position.pixels <= 180 &&
        backend.canLoadMoreFuture) {
      unawaited(_loadTimelinePage(older: false));
    }
  }

  void _noteTimelineUserInput(PointerEvent _) {
    _timelineUserInputUntil = DateTime.now().add(const Duration(seconds: 1));
  }

  Future<void> _loadTimelinePage({required bool older}) async {
    if (_pageLoadInFlight) return;
    _pageLoadInFlight = true;
    _suppressPaginationUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    try {
      if (older) {
        await backend.loadMoreHistory();
      } else {
        await backend.loadMoreFuture();
      }
    } finally {
      _pageLoadInFlight = false;
    }
  }

  _TimelineScrollAnchor? _captureScrollAnchor() {
    final viewport = _timelineViewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    _TimelineScrollAnchor? best;
    var bestDistance = double.infinity;
    for (final entry in _messageKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom <= viewportTop || top >= viewportBottom) continue;
      final distance = (top - viewportTop).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = _TimelineScrollAnchor(entry.key, top);
      }
    }
    return best;
  }

  void _restoreScrollAnchor(_TimelineScrollAnchor? anchor) {
    if (anchor == null || !mounted || !_scroll.hasClients) return;
    final box = _messageKeys[anchor.eventId]?.currentContext
        ?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final displacement = box.localToGlobal(Offset.zero).dy - anchor.screenTop;
    if (displacement.abs() < 0.5) return;
    _restoringScrollAnchor = true;
    final position = _scroll.position;
    // This is a reversed list: compensate retained-row displacement in the
    // inverse direction, matching the desktop timeline's stable anchoring.
    _scroll.jumpTo(
      (position.pixels - displacement).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _restoringScrollAnchor = false;
  }

  Future<void> _jumpToEvent(String eventId) async {
    final generation = ++_navigationGeneration;
    _suppressPaginationUntil = DateTime.now().add(const Duration(seconds: 1));
    if (!await _scrollToMessage(eventId, generation)) {
      await backend.jumpToEvent(eventId);
      if (!mounted || generation != _navigationGeneration) return;
      await _scrollToMessage(eventId, generation, waitForBuild: true);
    }
    if (!mounted || generation != _navigationGeneration) return;
    for (var pulse = 0; pulse < 2; pulse++) {
      setState(() => _highlightedMessageId = eventId);
      await _waitForHighlight(const Duration(milliseconds: 180));
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _highlightedMessageId = null);
      if (pulse == 0) {
        await _waitForHighlight(const Duration(milliseconds: 110));
      }
    }
  }

  Future<void> _waitForHighlight(Duration duration) {
    _highlightTimer?.cancel();
    final previous = _highlightWaiter;
    if (previous != null && !previous.isCompleted) previous.complete();
    final waiter = Completer<void>();
    _highlightWaiter = waiter;
    _highlightTimer = Timer(duration, () {
      if (!waiter.isCompleted) waiter.complete();
      if (identical(_highlightWaiter, waiter)) {
        _highlightWaiter = null;
        _highlightTimer = null;
      }
    });
    return waiter.future;
  }

  Future<bool> _scrollToMessage(
    String eventId,
    int generation, {
    bool waitForBuild = false,
  }) async {
    final attempts = waitForBuild ? 8 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!mounted || generation != _navigationGeneration) return false;
      final target = _messageKeys[eventId]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: backend.preferences.reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
        );
        return true;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

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
    final scrolledAway = _scroll.hasClients && _scroll.position.pixels > 48;
    if (previous == null ||
        previous == next ||
        _pageLoadInFlight ||
        !scrolledAway ||
        DateTime.now().isBefore(_timelineUserInputUntil)) {
      return;
    }
    final anchor = _captureScrollAnchor();
    if (anchor == null) return;
    final generation = ++_layoutAnchorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutAnchorGeneration) return;
      _restoreScrollAnchor(anchor);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    final waiter = _highlightWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    backend.setConversationAtPresent(false);
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
    final physicalPixel = 1 / MediaQuery.devicePixelRatioOf(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reportTimelineAtPresent(),
    );
    _preserveAnchorAcrossMetadataLayout(messages);
    final currentMessageIds = messages.map((message) => message.id).toSet();
    final staleMessageIds = _messageKeys.keys
        .where((messageId) => !currentMessageIds.contains(messageId))
        .toList(growable: false);
    for (final messageId in staleMessageIds) {
      final key = _messageKeys.remove(messageId);
      if (key != null) _messageIdsByKey.remove(key);
    }
    final messageIndexes = <String, int>{
      for (var index = 0; index < messages.length; index++)
        messages[index].id: index,
    };
    if (!_autoFillingInitialChunk &&
        !backend.timelineLoading &&
        !backend.historyLoading &&
        (messages.length < backend.preferences.timelineChunkSize ||
            (_scroll.hasClients && _scroll.position.maxScrollExtent <= 8)) &&
        backend.canLoadMoreHistory) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillInitialChunk());
    }
    return Scaffold(
      key: const ValueKey('mobile-timeline'),
      appBar: AppBar(
        toolbarHeight: 64,
        leading: IconButton(
          key: const ValueKey('mobile-open-navigation'),
          onPressed: widget.onOpenNavigation,
          icon: MobileAttentionBadge(
            count: backend.totalAttentionCount,
            child: const Icon(Icons.menu),
          ),
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
            tooltip: 'Notification settings',
            onPressed: () =>
                showRoomNotificationControls(context, backend, widget.room),
            icon: Icon(
              backend.selectedRoomMuted
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              switch (value) {
                case 'gallery':
                  await showRoomSearchSheet(
                    context,
                    backend,
                    onOpen: _jumpToEvent,
                    initialSection: RoomSearchSection.media,
                  );
                case 'saved':
                  await showSavedMessages(
                    context,
                    backend,
                    onOpen: (roomId, eventId) async {
                      if (backend.selectedRoom?.id != roomId) {
                        await backend.selectRoom(roomId);
                      }
                      await backend.jumpToEvent(eventId);
                    },
                  );
                case 'pinned':
                  await showPinnedMessages(
                    context,
                    backend,
                    onOpen: _jumpToEvent,
                  );
                case 'inbox':
                  await showUnifiedInbox(
                    context,
                    backend,
                    onOpen: (item) async {
                      if (backend.selectedRoom?.id != item.roomId) {
                        await backend.selectRoom(item.roomId);
                      }
                      if (item.eventId != null) {
                        await backend.jumpToEvent(item.eventId!);
                      }
                    },
                  );
                case 'unread':
                  await backend.markRoomUnread(
                    widget.room.id,
                    !widget.room.markedUnread,
                  );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'gallery', child: Text('Media and links')),
              PopupMenuItem(value: 'saved', child: Text('Saved and scheduled')),
              PopupMenuItem(value: 'pinned', child: Text('Pinned messages')),
              PopupMenuItem(value: 'inbox', child: Text('Inbox')),
              PopupMenuItem(
                value: 'unread',
                child: Text('Toggle read / unread'),
              ),
            ],
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
          Expanded(
            child: backend.timelineLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty &&
                      !backend.canLoadMoreHistory &&
                      !backend.historyLoading
                ? const Center(child: Text('No messages yet'))
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      KeyedSubtree(
                        key: _timelineViewportKey,
                        child: Listener(
                          onPointerDown: _noteTimelineUserInput,
                          onPointerMove: _noteTimelineUserInput,
                          onPointerSignal: _noteTimelineUserInput,
                          child: ListView.builder(
                            key: const ValueKey('mobile-message-timeline'),
                            controller: _scroll,
                            reverse: true,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              6,
                              8,
                              6,
                              typingIndicatorHeight + 1,
                            ),
                            itemCount:
                                messages.length +
                                ((backend.canLoadMoreHistory ||
                                        backend.historyLoading)
                                    ? 1
                                    : 0),
                            findChildIndexCallback: (key) {
                              final messageId = key is GlobalKey
                                  ? _messageIdsByKey[key]
                                  : null;
                              return messageId == null
                                  ? null
                                  : messageIndexes[messageId];
                            },
                            itemBuilder: (context, index) {
                              if (index == messages.length) {
                                return SizedBox(
                                  height: 64,
                                  child: Center(
                                    child: backend.historyLoading
                                        ? const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(),
                                          )
                                        : TextButton.icon(
                                            onPressed: () =>
                                                _loadTimelinePage(older: true),
                                            icon: const Icon(Icons.history),
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
                              final grouped =
                                  older != null &&
                                  older.senderId == message.senderId &&
                                  message.timestamp.difference(
                                        older.timestamp,
                                      ) <
                                      const Duration(minutes: 7) &&
                                  message.reply == null &&
                                  DateUtils.isSameDay(
                                    older.timestamp.toLocal(),
                                    message.timestamp.toLocal(),
                                  );
                              final showDaySeparator =
                                  older == null ||
                                  !DateUtils.isSameDay(
                                    older.timestamp.toLocal(),
                                    message.timestamp.toLocal(),
                                  );
                              final rowKey = _messageKeys.putIfAbsent(
                                message.id,
                                () {
                                  final key = GlobalKey();
                                  _messageIdsByKey[key] = message.id;
                                  return key;
                                },
                              );
                              return KeyedSubtree(
                                key: rowKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showDaySeparator)
                                      _MobileDaySeparator(
                                        date: message.timestamp.toLocal(),
                                      ),
                                    _MobileMessageRow(
                                      backend: backend,
                                      message: message,
                                      grouped: grouped,
                                      highlighted:
                                          _highlightedMessageId == message.id,
                                      onJumpToReply: _jumpToEvent,
                                      onReply: () => setState(() {
                                        _reply = message;
                                        _edit = null;
                                        _focus.requestFocus();
                                      }),
                                      onEdit: message.own && !message.redacted
                                          ? () => setState(() {
                                              _edit = message;
                                              _reply = null;
                                              _customEmojiSpans = const [];
                                              _composer.text = message.body;
                                              _customEmojiSpans =
                                                  customEmojiSpansFromHtml(
                                                    message.formattedBody,
                                                    message.body,
                                                  );
                                              _previousComposerText =
                                                  message.body;
                                              _composer.selection =
                                                  TextSelection.collapsed(
                                                    offset:
                                                        _composer.text.length,
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
                                              onEditOwnProfile:
                                                  widget.onOpenSettings,
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (!backend.atTimelinePresent ||
                          _scrolledAwayFromPresent)
                        Positioned(
                          right: 14,
                          bottom: 10,
                          child: FilledButton.icon(
                            onPressed: () async {
                              if (!backend.atTimelinePresent) {
                                await backend.jumpToPresent();
                              }
                              if (_scroll.hasClients) {
                                await _scroll.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                              if (mounted && _scrolledAwayFromPresent) {
                                setState(
                                  () => _scrolledAwayFromPresent = false,
                                );
                              }
                              backend.setConversationAtPresent(true);
                            },
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('Present'),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        // Overlap by one physical pixel so fractional device
                        // scaling cannot expose a seam above the composer.
                        bottom: -physicalPixel,
                        child: TypingIndicator(names: backend.typingUserNames),
                      ),
                    ],
                  ),
          ),
          _MobileComposer(
            backend: backend,
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
            onToggleAttachmentSpoiler: (attachment) {
              final index = _attachments.indexOf(attachment);
              if (index < 0) return;
              setState(() {
                _attachments[index] = AttachmentDraft(
                  bytes: attachment.bytes,
                  name: attachment.name,
                  mimeType: attachment.mimeType,
                  spoiler: !attachment.spoiler,
                  caption: attachment.caption,
                );
              });
            },
            onAdd: _showAddMenu,
            onEmoji: _showEmojiPicker,
            onSend: _send,
            onSchedule: _scheduleCurrentMessage,
            emojiMatches: _emojiMatches,
            emojiCompletionActive: _emojiStart != null,
            emojiSelection: _emojiSelection,
            onEmojiSelected: _acceptEmojiCompletion,
            onEmojiSelectionChanged: (index) =>
                setState(() => _emojiSelection = index),
            onDismissEmojiCompletion: _clearEmojiCompletion,
            mentionMatches: _mentionMatches,
            onMentionSelected: _acceptMention,
          ),
        ],
      ),
    );
  }

  void _reportTimelineAtPresent() {
    if (!mounted) return;
    backend.setConversationAtPresent(
      backend.atTimelinePresent &&
          (!_scroll.hasClients || _scroll.position.pixels <= 48),
    );
  }

  Future<void> _fillInitialChunk() async {
    if (_autoFillingInitialChunk || !mounted) return;
    _autoFillingInitialChunk = true;
    try {
      var previousCount = backend.messages.length;
      var emptyPasses = 0;
      while (mounted &&
          backend.selectedRoom?.id == widget.room.id &&
          backend.canLoadMoreHistory &&
          emptyPasses < 4) {
        await WidgetsBinding.instance.endOfFrame;
        final viewportNeedsContent =
            _scroll.hasClients && _scroll.position.maxScrollExtent <= 8;
        if (!viewportNeedsContent &&
            previousCount >= backend.preferences.timelineChunkSize) {
          break;
        }
        await backend.loadMoreHistory();
        final currentCount = backend.messages.length;
        if (currentCount <= previousCount) {
          emptyPasses++;
          continue;
        }
        emptyPasses = 0;
        previousCount = currentCount;
      }
    } finally {
      _autoFillingInitialChunk = false;
    }
  }

  Future<void> _send() async {
    final serialized = serializeCustomEmojiText(
      _composer.text,
      _customEmojiSpans,
    );
    final text = serialized.plainText;
    if (_sending || (text.isEmpty && _attachments.isEmpty)) return;
    final roomId = widget.room.id;
    final submittedText = text;
    final submittedRawText = _composer.text;
    final submittedEmojiSpans = List<CustomEmojiTextSpan>.of(_customEmojiSpans);
    final submittedAttachments = List<AttachmentDraft>.from(_attachments);
    final reply = _reply;
    final edit = _edit;
    _composer.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
    _customEmojiSpans.clear();
    _previousComposerText = '';
    // Keep the existing Android input connection alive. Reconnecting it here
    // makes the keyboard visibly close and reopen after every sent message;
    // clearing the composing range is sufficient for the next draft.
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
          formattedBody: serialized.html,
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
              voiceMessage: item.voiceMessage,
              durationMilliseconds: item.durationMilliseconds,
              waveform: item.waveform,
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
        _composer.text = submittedRawText;
        _customEmojiSpans = submittedEmojiSpans;
        _previousComposerText = submittedRawText;
        widget.onDraftChanged((
          text: submittedRawText,
          emojis: List.unmodifiable(submittedEmojiSpans),
        ));
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

  Future<void> _scheduleCurrentMessage() async {
    final text = _composer.text.trim();
    if (_sending || text.isEmpty) return;
    if (_attachments.isNotEmpty || _edit != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Scheduled sending currently supports new text messages.',
          ),
        ),
      );
      return;
    }
    final sendAt = await showSchedulePicker(context);
    if (sendAt == null || !mounted) return;
    await backend.scheduleMessage(
      text,
      sendAt,
      roomId: widget.room.id,
      replyToMessageId: _reply?.id,
    );
    _composer.clear();
    setState(() => _reply = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message scheduled for ${sendAt.toLocal()}')),
      );
    }
  }

  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.deltiecord.surface,
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
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, 'camera-photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record video'),
              onTap: () => Navigator.pop(context, 'camera-video'),
            ),
            ListTile(
              leading: const Icon(Icons.gif_box_outlined),
              title: const Text('GIF'),
              onTap: () => Navigator.pop(context, 'gif'),
            ),
            ListTile(
              leading: const Icon(Icons.poll_outlined),
              title: const Text('Poll'),
              onTap: () => Navigator.pop(context, 'poll'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('Sticker pack'),
              onTap: () => Navigator.pop(context, 'sticker'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'gif') return _showGifPicker();
    if (choice == 'poll') {
      final poll = await showPollComposer(context);
      if (poll != null) await backend.sendPoll(poll, roomId: widget.room.id);
      return;
    }
    if (choice == 'sticker') {
      final sticker = await showStickerPicker(context, backend);
      if (sticker != null) {
        await backend.sendSticker(sticker, roomId: widget.room.id);
      }
      return;
    }
    if (choice == null) return;
    if (choice == 'camera-photo' || choice == 'camera-video') {
      await _captureMedia(video: choice == 'camera-video');
      return;
    }
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

  Future<void> _captureMedia({required bool video}) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.camera)
        : await picker.pickImage(source: ImageSource.camera);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final name = file.name.isEmpty
        ? '${video ? 'video' : 'photo'}-${DateTime.now().millisecondsSinceEpoch}'
        : file.name;
    setState(() {
      _attachments.add(
        AttachmentDraft(
          bytes: bytes,
          name: name,
          mimeType:
              lookupMimeType(name, headerBytes: bytes) ??
              (video ? 'video/mp4' : 'image/jpeg'),
          spoiler: false,
        ),
      );
    });
  }

  Future<void> _showEmojiPicker() async {
    await backend.refreshStickerPacks();
    if (!mounted) return;
    final emoji = await showModalBottomSheet<EmojiEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.deltiecord.surface,
      builder: (context) => _MobileEmojiPicker(backend: backend),
    );
    if (emoji == null) return;
    final selection = _composer.selection;
    final offset = selection.isValid ? selection.start : _composer.text.length;
    _replaceEmojiCompletion(offset, offset, emoji);
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
    final roomId = widget.room.id;
    final reply = _reply;
    setState(() => _sending = true);
    try {
      final bytes = await _giphy.download(gif);
      await backend.sendAttachment(
        AttachmentDraft(
          bytes: bytes,
          name: 'giphy-${DateTime.now().millisecondsSinceEpoch}.gif',
          mimeType: 'image/gif',
          spoiler: false,
        ),
        roomId: roomId,
        replyToMessageId: reply?.id,
      );
      if (mounted && backend.selectedRoom?.id == roomId) {
        setState(() => _reply = null);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showSearch() async {
    await showRoomSearchSheet(context, backend, onOpen: _jumpToEvent);
  }
}

final class _TimelineScrollAnchor {
  const _TimelineScrollAnchor(this.eventId, this.screenTop);

  final String eventId;
  final double screenTop;
}

class _MobileDaySeparator extends StatelessWidget {
  const _MobileDaySeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localDate = DateUtils.dateOnly(date);
    final today = DateUtils.dateOnly(DateTime.now());
    final label = localDate == today
        ? 'Today'
        : localDate == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : MaterialLocalizations.of(context).formatFullDate(localDate);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: context.deltiecord.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                color: context.deltiecord.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: context.deltiecord.divider)),
        ],
      ),
    );
  }
}

class _MobileMessageRow extends StatelessWidget {
  const _MobileMessageRow({
    required this.backend,
    required this.message,
    required this.grouped,
    required this.highlighted,
    required this.onJumpToReply,
    required this.onReply,
    required this.onEdit,
    required this.onProfile,
  });
  final ChatBackend backend;
  final ChatMessage message;
  final bool grouped;
  final bool highlighted;
  final ValueChanged<String> onJumpToReply;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        child: Center(
          child: Text(
            message.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.deltiecord.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    return Dismissible(
      key: ValueKey('swipe-${message.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.15},
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: message.pingedCurrentUser
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.11)
                : highlighted
                ? context.deltiecord.hover
                : Colors.transparent,
            border: message.pingedCurrentUser
                ? Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: grouped
                      ? null
                      : Padding(
                          padding: EdgeInsets.only(
                            top: message.reply == null ? 0 : 22,
                          ),
                          child: GestureDetector(
                            onTap: onProfile,
                            child: MobileAvatar(
                              bytes: message.avatarBytes,
                              fallback: message.sender,
                              size: 40,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    key: ValueKey('mobile-message-content-${message.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.reply case final reply?)
                        Transform.translate(
                          offset: const Offset(-48, 0),
                          child: InkWell(
                            key: ValueKey('mobile-reply-${message.id}'),
                            onTap: () => onJumpToReply(reply.eventId),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  CustomPaint(
                                    size: const Size(40, 20),
                                    painter: _MobileReplyConnector(
                                      color: context.deltiecord.muted,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${reply.sender}  ',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(
                                            text: reply.body.replaceAll(
                                              '\n',
                                              ' ',
                                            ),
                                            style: TextStyle(
                                              color: context.deltiecord.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
                                _mobileMessageTimestamp(
                                  context,
                                  message.timestamp,
                                  use24HourTime:
                                      backend.preferences.use24HourTime,
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.deltiecord.muted,
                                ),
                              ),
                              if (message.edited) ...[
                                const SizedBox(width: 5),
                                Text(
                                  '(edited)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.deltiecord.muted,
                                  ),
                                ),
                              ],
                              if (message.own &&
                                  !message.failed &&
                                  !message.pending) ...[
                                const SizedBox(width: 5),
                                GestureDetector(
                                  onTap: message.readBy.isEmpty
                                      ? null
                                      : () => _showReaders(context),
                                  child: Icon(
                                    message.readBy.isEmpty
                                        ? Icons.check
                                        : Icons.done_all,
                                    size: 12,
                                    color: context.deltiecord.muted,
                                  ),
                                ),
                              ],
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
                      if (!message.redacted &&
                          message.poll == null &&
                          message.body.isNotEmpty)
                        KeyedSubtree(
                          key: ValueKey('mobile-message-body-${message.id}'),
                          child: message.formattedBody != null
                              ? MatrixHtmlText(
                                  html: message.formattedBody!,
                                  fallback: message.body,
                                  selectable: false,
                                  backend: backend,
                                )
                              : MatrixPlainText(
                                  text: message.body,
                                  selectable: false,
                                ),
                        )
                      else if (message.redacted)
                        const Text(
                          'Message deleted',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      if (message.poll != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: PollCard(backend: backend, message: message),
                        ),
                      if (message.attachment != null)
                        Padding(
                          key: ValueKey(
                            'mobile-message-attachment-${message.id}',
                          ),
                          padding: const EdgeInsets.only(top: 5),
                          child: MobileAttachmentView(
                            backend: backend,
                            message: message,
                          ),
                        ),
                      for (final preview in message.linkPreviews)
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
                                label: reaction.customEmoji == null
                                    ? Text('${reaction.key} ${reaction.count}')
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CustomEmojiImage(
                                            backend: backend,
                                            emoji: reaction.customEmoji!,
                                            size: 18,
                                          ),
                                          Text(' ${reaction.count}'),
                                        ],
                                      ),
                                onPressed: () => backend.toggleReaction(
                                  message.id,
                                  reaction.key,
                                  customEmoji: reaction.customEmoji,
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
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (message.failed)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry send'),
                onTap: () => Navigator.pop(context, 'retry'),
              ),
            if (message.failed || message.pending)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Discard failed send'),
                onTap: () => Navigator.pop(context, 'discard'),
              ),
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
              leading: Icon(
                message.bookmarked ? Icons.bookmark : Icons.bookmark_border,
              ),
              title: Text(
                message.bookmarked ? 'Remove bookmark' : 'Save message',
              ),
              onTap: () => Navigator.pop(context, 'bookmark'),
            ),
            if (message.canRedact)
              ListTile(
                leading: Icon(
                  message.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(message.pinned ? 'Unpin message' : 'Pin message'),
                onTap: () => Navigator.pop(context, 'pin'),
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
      case 'retry':
        await backend.retryMessage(message.id);
      case 'discard':
        await backend.cancelPendingMessage(message.id);
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
      case 'bookmark':
        await backend.toggleMessageBookmarked(message.id);
      case 'pin':
        await backend.toggleMessagePinned(message.id);
      case 'react':
        if (!context.mounted) return;
        await backend.refreshStickerPacks();
        if (!context.mounted) return;
        final emoji = await showModalBottomSheet<EmojiEntry>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _MobileEmojiPicker(backend: backend),
        );
        if (emoji != null) {
          await backend.toggleReaction(
            message.id,
            emoji.emoji,
            customEmoji: emoji.customEmoji?.customEmoji,
          );
        }
    }
  }

  Future<void> _showReaders(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Read by')),
          for (final reader in message.readBy)
            ListTile(
              leading: const Icon(Icons.done_all, size: 18),
              title: Text(reader.displayName),
              subtitle: Text(reader.userId),
            ),
        ],
      ),
    ),
  );
}

class _MobileReplyConnector extends CustomPainter {
  const _MobileReplyConnector({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(size.width * 0.5, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.52)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.28,
        size.width * 0.72,
        size.height * 0.28,
      )
      ..lineTo(size.width, size.height * 0.28);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MobileReplyConnector oldDelegate) =>
      oldDelegate.color != color;
}

String _mobileMessageTimestamp(
  BuildContext context,
  DateTime timestamp, {
  required bool use24HourTime,
}) {
  final local = timestamp.toLocal();
  final material = MaterialLocalizations.of(context);
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: use24HourTime,
  );
  return DateUtils.isSameDay(local, DateTime.now())
      ? time
      : '${material.formatShortDate(local)} $time';
}

class _MobileComposer extends StatefulWidget {
  const _MobileComposer({
    required this.backend,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.attachments,
    required this.contextMessage,
    required this.editing,
    required this.onClearContext,
    required this.onRemoveAttachment,
    required this.onToggleAttachmentSpoiler,
    required this.onAdd,
    required this.onEmoji,
    required this.onSend,
    required this.onSchedule,
    required this.emojiMatches,
    required this.emojiCompletionActive,
    required this.emojiSelection,
    required this.onEmojiSelected,
    required this.onEmojiSelectionChanged,
    required this.onDismissEmojiCompletion,
    required this.mentionMatches,
    required this.onMentionSelected,
  });
  final ChatBackend backend;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final List<AttachmentDraft> attachments;
  final ChatMessage? contextMessage;
  final bool editing;
  final VoidCallback onClearContext;
  final ValueChanged<AttachmentDraft> onRemoveAttachment;
  final ValueChanged<AttachmentDraft> onToggleAttachmentSpoiler;
  final VoidCallback onAdd;
  final VoidCallback onEmoji;
  final VoidCallback onSend;
  final VoidCallback onSchedule;
  final List<EmojiEntry> emojiMatches;
  final bool emojiCompletionActive;
  final int emojiSelection;
  final ValueChanged<EmojiEntry> onEmojiSelected;
  final ValueChanged<int> onEmojiSelectionChanged;
  final VoidCallback onDismissEmojiCompletion;
  final List<MentionSuggestion> mentionMatches;
  final ValueChanged<MentionSuggestion> onMentionSelected;

  @override
  State<_MobileComposer> createState() => _MobileComposerState();
}

class _MobileComposerState extends State<_MobileComposer> {
  final _emojiOverlay = OverlayPortalController();
  final _emojiAnchor = LayerLink();

  @override
  void initState() {
    super.initState();
    _scheduleEmojiOverlaySync();
  }

  @override
  void didUpdateWidget(covariant _MobileComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleEmojiOverlaySync();
  }

  void _scheduleEmojiOverlaySync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shouldShow = widget.emojiCompletionActive;
      if (!shouldShow) {
        if (_emojiOverlay.isShowing) _emojiOverlay.hide();
      } else if (!_emojiOverlay.isShowing) {
        _emojiOverlay.show();
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.emojiMatches.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.onEmojiSelectionChanged(
        (widget.emojiSelection + 1) % widget.emojiMatches.length,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onEmojiSelected(widget.emojiMatches[widget.emojiSelection]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismissEmojiCompletion();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _emojiOverlay,
    overlayChildBuilder: (context) => CompositedTransformFollower(
      link: _emojiAnchor,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(48, -4),
      child: UnconstrainedBox(
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          width: min(320, MediaQuery.sizeOf(context).width - 72),
          child: Material(
            key: const ValueKey('mobile-emoji-completion-popup'),
            elevation: 8,
            color: context.deltiecord.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.emojiMatches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: Text('Searching emoji…')),
                  ),
                for (
                  var index = widget.emojiMatches.length - 1;
                  index >= 0;
                  index--
                )
                  InkWell(
                    key: ValueKey('mobile-emoji-completion-$index'),
                    onTap: () =>
                        widget.onEmojiSelected(widget.emojiMatches[index]),
                    child: Container(
                      color: index == widget.emojiSelection
                          ? context.deltiecord.hover
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          if (widget
                                  .emojiMatches[index]
                                  .customEmoji
                                  ?.customEmoji
                              case final custom?)
                            CustomEmojiImage(
                              backend: widget.backend,
                              emoji: custom,
                              size: 20,
                            )
                          else
                            Text(widget.emojiMatches[index].emoji),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ':${widget.emojiMatches[index].aliases.firstOrNull ?? widget.emojiMatches[index].name}:',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    child: CompositedTransformTarget(
      link: _emojiAnchor,
      child: SafeArea(
        top: false,
        child: Container(
          key: const ValueKey('mobile-composer'),
          margin: const EdgeInsets.fromLTRB(6, 1, 6, 8),
          decoration: BoxDecoration(
            color: context.deltiecord.island,
            borderRadius: DeltiecordCorners.borderRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.contextMessage case final message?)
                ListTile(
                  dense: true,
                  title: Text(
                    widget.editing
                        ? 'Editing message'
                        : 'Replying to ${message.sender}',
                  ),
                  subtitle: Text(
                    message.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: widget.onClearContext,
                    icon: const Icon(Icons.close),
                  ),
                ),
              if (widget.attachments.isNotEmpty)
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.attachments.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final attachment = widget.attachments[index];
                      return _PendingAttachmentPreview(
                        attachment: attachment,
                        onRemove: () => widget.onRemoveAttachment(attachment),
                        onToggleSpoiler: () =>
                            widget.onToggleAttachmentSpoiler(attachment),
                      );
                    },
                  ),
                ),
              if (widget.mentionMatches.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 210),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.mentionMatches.length,
                    itemBuilder: (context, index) {
                      final mention = widget.mentionMatches[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.alternate_email, size: 18),
                        title: Text(mention.displayName),
                        subtitle: Text(mention.matrixId),
                        onTap: () => widget.onMentionSelected(mention),
                      );
                    },
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: widget.onAdd,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 48,
                        maxHeight: MediaQuery.sizeOf(context).height / 3,
                      ),
                      child: Focus(
                        onKeyEvent: _handleKey,
                        child: TextField(
                          key: const ValueKey('mobile-composer-field'),
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          minLines: 1,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            border: InputBorder.none,
                            filled: false,
                            // EditableText keeps a four-pixel caret inset of
                            // its own. 6 + 48 + 4 + that caret inset lands on
                            // the 62px text column used by timeline messages.
                            contentPadding: EdgeInsets.only(left: 4, right: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onEmoji,
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 48,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  Semantics(
                    button: true,
                    label: 'Send; hold to send later',
                    child: InkResponse(
                      onTap: widget.sending ? null : widget.onSend,
                      onLongPress: widget.sending ? null : widget.onSchedule,
                      radius: 26,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: widget.sending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({
    required this.attachment,
    required this.onRemove,
    required this.onToggleSpoiler,
  });

  final AttachmentDraft attachment;
  final VoidCallback onRemove;
  final VoidCallback onToggleSpoiler;

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                attachment.spoiler
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              title: Text(
                attachment.spoiler ? 'Remove spoiler' : 'Mark as spoiler',
              ),
              onTap: () => Navigator.pop(context, 'spoiler'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove attachment'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == 'spoiler') onToggleSpoiler();
    if (action == 'remove') onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final isVideo = attachment.mimeType.startsWith('video/');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showActions(context),
      onLongPress: () => _showActions(context),
      child: SizedBox.square(
        dimension: 80,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: DeltiecordCorners.borderRadius,
              child: isImage
                  ? Image.memory(
                      attachment.bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : ColoredBox(
                      color: context.deltiecord.input,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isVideo
                                ? Icons.movie_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: IconButton.filled(
                tooltip: 'Remove attachment',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: _CloseGlyph(
                  size: 14,
                  color: deltiecordContrastingForeground(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseGlyph extends StatelessWidget {
  const _CloseGlyph({this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _CloseGlyphPainter(
        color: color ?? IconTheme.of(context).color ?? Colors.white,
      ),
    ),
  );
}

class _CloseGlyphPainter extends CustomPainter {
  const _CloseGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = max(1.8, size.shortestSide * 0.14)
      ..strokeCap = StrokeCap.round;
    final inset = size.shortestSide * 0.18;
    canvas
      ..drawLine(
        Offset(inset, inset),
        Offset(size.width - inset, size.height - inset),
        paint,
      )
      ..drawLine(
        Offset(size.width - inset, inset),
        Offset(inset, size.height - inset),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant _CloseGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MobileEmojiPicker extends StatefulWidget {
  const _MobileEmojiPicker({required this.backend});

  final ChatBackend backend;

  @override
  State<_MobileEmojiPicker> createState() => _MobileEmojiPickerState();
}

class _MobileEmojiPickerState extends State<_MobileEmojiPicker> {
  final _query = TextEditingController();
  List<EmojiEntry> _results = const [];
  EmojiCategory? _selectedCategory;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_search);
    _search();
    FavouriteReactionsStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final custom = customEmojiEntries(
      widget.backend.stickerPacks,
    ).where((entry) => entry.matches(_query.text)).toList(growable: false);
    if (mounted && generation == _generation) {
      setState(() => _results = custom);
    }
    final unicode = await EmojiRepository.instance.search(
      _query.text,
      limit: _query.text.trim().isEmpty ? null : 160,
    );
    final results = [...custom, ...unicode];
    if (mounted && generation == _generation) {
      setState(() => _results = results);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _selectedCategory == null
        ? _results
        : _results
              .where((entry) => entry.category == _selectedCategory)
              .toList(growable: false);
    final grouped = <EmojiCategory, List<EmojiEntry>>{};
    for (final entry in visible) {
      (grouped[entry.category] ??= []).add(entry);
    }
    final customByPack = <({String id, String name}), List<EmojiEntry>>{};
    for (final pack in widget.backend.stickerPacks) {
      final entries = visible
          .where(
            (entry) =>
                entry.isCustom &&
                pack.stickers.any(
                  (sticker) => sticker.mxcUri == entry.customEmoji?.mxcUri,
                ),
          )
          .toList(growable: false);
      if (entries.isNotEmpty) {
        customByPack[(id: pack.id, name: pack.name)] = entries;
      }
    }
    final favourites = FavouriteReactionsStore.instance.emoji;
    final favouriteEntries = _results
        .where((entry) => favourites.contains(entry.favouriteKey))
        .toList(growable: false);
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search names and aliases',
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _MobileEmojiCategoryButton(
                    label: 'All emoji',
                    icon: Icons.apps,
                    selected: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  for (final category in EmojiCategory.values)
                    _MobileEmojiCategoryButton(
                      label: category.label,
                      icon: _mobileEmojiCategoryIcon(category),
                      selected: _selectedCategory == category,
                      onTap: () => setState(() => _selectedCategory = category),
                    ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (_selectedCategory == null &&
                      _query.text.trim().isEmpty &&
                      favouriteEntries.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                        child: Text(
                          'Favourites',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                    _mobileEmojiGrid(favouriteEntries),
                  ],
                  if (_selectedCategory == null ||
                      _selectedCategory == EmojiCategory.custom)
                    for (final pack in customByPack.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                          child: Text(
                            pack.key.name,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                      _mobileEmojiGrid(pack.value),
                    ],
                  for (final category in EmojiCategory.values)
                    if (category != EmojiCategory.custom)
                      if (grouped[category] case final entries?) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                            child: Text(
                              category.label,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                        _mobileEmojiGrid(entries),
                      ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverGrid _mobileEmojiGrid(List<EmojiEntry> entries) => SliverGrid(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 52,
    ),
    delegate: SliverChildBuilderDelegate((context, index) {
      final entry = entries[index];
      final favourite = FavouriteReactionsStore.instance.isEmojiFavourite(
        entry.favouriteKey,
      );
      return InkWell(
        key: ValueKey('mobile-emoji-picker-${entry.favouriteKey}'),
        onTap: () => Navigator.pop(context, entry),
        onLongPress: () async {
          await FavouriteReactionsStore.instance.toggleEmoji(
            entry.favouriteKey,
          );
          if (mounted) setState(() {});
        },
        child: Stack(
          children: [
            Center(
              child: entry.customEmoji != null
                  ? CustomEmojiImage(
                      backend: widget.backend,
                      emoji: entry.customEmoji!.customEmoji!,
                      size: 30,
                    )
                  : Text(entry.emoji, style: const TextStyle(fontSize: 27)),
            ),
            if (favourite)
              const Positioned(
                right: 2,
                top: 2,
                child: Icon(Icons.star, size: 11),
              ),
          ],
        ),
      );
    }, childCount: entries.length),
  );
}

IconData _mobileEmojiCategoryIcon(EmojiCategory category) => switch (category) {
  EmojiCategory.custom => Icons.add_reaction_outlined,
  EmojiCategory.smileysAndPeople => Icons.mood,
  EmojiCategory.animalsAndNature => Icons.pets,
  EmojiCategory.foodAndDrink => Icons.restaurant,
  EmojiCategory.travelAndPlaces => Icons.travel_explore,
  EmojiCategory.activities => Icons.sports_esports,
  EmojiCategory.objects => Icons.lightbulb_outline,
  EmojiCategory.symbols => Icons.category_outlined,
  EmojiCategory.flags => Icons.flag_outlined,
};

class _MobileEmojiCategoryButton extends StatelessWidget {
  const _MobileEmojiCategoryButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    isSelected: selected,
    onPressed: onTap,
    icon: Icon(icon),
    selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
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
  List<GifSearchResult> _favourites = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _results = widget.service.trending();
    widget.service.favorites().then((value) {
      if (mounted) setState(() => _favourites = value);
    });
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
              _query = query.trim();
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() {
                    _results = _query.isEmpty
                        ? widget.service.trending()
                        : widget.service.search(_query);
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
                final loaded = snapshot.data;
                if (loaded == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final results = _query.isEmpty
                    ? [
                        ..._favourites,
                        ...loaded.where(
                          (gif) => !_favourites.any(
                            (favorite) => favorite.shareUrl == gif.shareUrl,
                          ),
                        ),
                      ]
                    : loaded;
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final gif = results[index];
                    final favourite = widget.service.isFavorite(gif);
                    return InkWell(
                      onTap: () => Navigator.pop(context, gif),
                      onLongPress: () => _toggleFavourite(gif),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            gif.previewUrl.toString(),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: IconButton.filledTonal(
                              tooltip: favourite
                                  ? 'Remove from favourites'
                                  : 'Add to favourites',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _toggleFavourite(gif),
                              icon: Icon(
                                favourite ? Icons.star : Icons.star_border,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _toggleFavourite(GifSearchResult gif) async {
    await widget.service.toggleFavorite(gif);
    final favourites = await widget.service.favorites();
    if (mounted) setState(() => _favourites = favourites);
  }
}
