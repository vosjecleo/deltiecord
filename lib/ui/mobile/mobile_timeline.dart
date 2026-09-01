import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/emoji_completion.dart';
import '../../services/emoji_repository.dart';
import '../../services/giphy_service.dart';
import '../deltiecord_theme.dart';
import '../matrix_html_text.dart';
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
  int _timelineInputGeneration = 0;
  int? _timelineLayoutFingerprint;
  int _layoutAnchorGeneration = 0;
  int _navigationGeneration = 0;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  Completer<void>? _highlightWaiter;
  List<EmojiEntry> _emojiMatches = const [];
  int _emojiSelection = 0;
  int? _emojiStart;
  int _emojiGeneration = 0;
  bool _replacingEmoji = false;
  MediaRecorder? _voiceRecorder;
  String? _voiceRecordingPath;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController(text: widget.initialDraft)
      ..addListener(_composerChanged);
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
    _reply = null;
    _edit = null;
    _attachments.clear();
    _messageKeys.clear();
    _messageIdsByKey.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reportTimelineAtPresent(),
    );
  }

  void _composerChanged() {
    widget.onDraftChanged(_composer.text);
    unawaited(backend.setComposerTyping(_composer.text.isNotEmpty));
    if (!_replacingEmoji) _updateEmojiCompletion();
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
      final generation = ++_emojiGeneration;
      final familiar = EmojiRepository.instance.familiarEmoji(completion.query);
      if (familiar != null) {
        _replaceEmojiCompletion(completion.start, cursor, familiar);
        return;
      }
      EmojiRepository.instance.exactAlias(completion.query).then((entry) {
        if (!mounted || generation != _emojiGeneration || entry == null) return;
        _replaceEmojiCompletion(completion.start, cursor, entry.emoji);
      });
      return;
    }

    final generation = ++_emojiGeneration;
    final familiar = EmojiRepository.instance.familiarMatches(completion.query);
    setState(() {
      _emojiStart = completion.start;
      _emojiMatches = familiar;
      _emojiSelection = 0;
    });
    EmojiRepository.instance.search(completion.query, limit: 3).then((matches) {
      if (!mounted || generation != _emojiGeneration) return;
      setState(() {
        _emojiStart = completion.start;
        _emojiMatches = matches;
        _emojiSelection = matches.isEmpty
            ? 0
            : _emojiSelection.clamp(0, matches.length - 1);
      });
    });
  }

  void _replaceEmojiCompletion(int start, int end, String emoji) {
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
    _replaceEmojiCompletion(start, end, entry.emoji);
    _focus.requestFocus();
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
    _timelineInputGeneration++;
    _timelineUserInputUntil = DateTime.now().add(const Duration(seconds: 1));
  }

  Future<void> _loadTimelinePage({required bool older}) async {
    if (_pageLoadInFlight) return;
    _pageLoadInFlight = true;
    _suppressPaginationUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    final anchor = _captureScrollAnchor();
    final inputGeneration = _timelineInputGeneration;
    try {
      if (older) {
        await backend.loadMoreHistory(anchorEventId: anchor?.eventId);
      } else {
        await backend.loadMoreFuture(anchorEventId: anchor?.eventId);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || inputGeneration != _timelineInputGeneration) return;
      _restoreScrollAnchor(anchor);
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
    final recorder = _voiceRecorder;
    if (recorder != null) unawaited(recorder.stop());
    final recordingPath = _voiceRecordingPath;
    if (recordingPath != null) {
      unawaited(
        File(recordingPath).delete().then<void>((_) {}, onError: (_) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = backend.messages;
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
        messages.length < backend.preferences.timelineChunkSize &&
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
                : messages.isEmpty &&
                      !backend.canLoadMoreHistory &&
                      !backend.historyLoading
                ? const Center(child: Text('No messages yet'))
                : Stack(
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
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
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
                                              _composer.text = message.body;
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
                      if (!backend.atTimelinePresent)
                        Positioned(
                          right: 14,
                          bottom: 10,
                          child: FilledButton.icon(
                            onPressed: () async {
                              await backend.jumpToPresent();
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                              backend.setConversationAtPresent(true);
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
            emojiMatches: _emojiMatches,
            emojiCompletionActive: _emojiStart != null,
            emojiSelection: _emojiSelection,
            onEmojiSelected: _acceptEmojiCompletion,
            onEmojiSelectionChanged: (index) =>
                setState(() => _emojiSelection = index),
            onDismissEmojiCompletion: _clearEmojiCompletion,
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
          previousCount < backend.preferences.timelineChunkSize &&
          backend.canLoadMoreHistory &&
          emptyPasses < 4) {
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
    final text = _composer.text.trim();
    if (_sending || (text.isEmpty && _attachments.isEmpty)) return;
    final roomId = widget.room.id;
    final submittedText = text;
    final submittedAttachments = List<AttachmentDraft>.from(_attachments);
    final reply = _reply;
    final edit = _edit;
    _composer.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
    // Android IMEs can retain a latched Shift/Caps composing state after the
    // controller is merely cleared. Reconnecting the field on the next frame
    // starts the next message with a fresh editing session.
    _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
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
              leading: const Icon(Icons.mic_none),
              title: const Text('Record voice message'),
              subtitle: const Text(
                'Transcription requires an on-device recognizer',
              ),
              onTap: () => Navigator.pop(context, 'voice'),
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
    if (choice == 'voice') {
      await _recordVoiceMessage();
      return;
    }
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

  Future<void> _recordVoiceMessage() async {
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/deltiecord-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    final recorder = MediaRecorder(albumName: 'Deltiecord');
    _voiceRecorder = recorder;
    _voiceRecordingPath = path;
    final startedAt = DateTime.now();
    try {
      await recorder.start(path, audioChannel: RecorderAudioChannel.INPUT);
      if (!mounted) {
        await recorder.stop();
        return;
      }
      final send = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recording voice message'),
          content: const Row(
            children: [
              Icon(Icons.mic, color: Colors.redAccent),
              SizedBox(width: 10),
              Expanded(child: Text('Speak now. Stop to attach the recording.')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
      );
      await recorder.stop();
      _voiceRecorder = null;
      _voiceRecordingPath = null;
      final file = File(path);
      if (send != true || !await file.exists()) {
        if (await file.exists()) await file.delete();
        return;
      }
      final bytes = await file.readAsBytes();
      await file.delete();
      if (!mounted || bytes.isEmpty) return;
      setState(() {
        _attachments.add(
          AttachmentDraft(
            bytes: bytes,
            name: 'voice-message.m4a',
            mimeType: 'audio/mp4',
            spoiler: false,
            voiceMessage: true,
            durationMilliseconds: DateTime.now()
                .difference(startedAt)
                .inMilliseconds,
          ),
        );
      });
    } catch (exception) {
      try {
        await recorder.stop();
      } catch (_) {}
      _voiceRecorder = null;
      _voiceRecordingPath = null;
      final file = File(path);
      if (await file.exists()) await file.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record audio: $exception')),
        );
      }
    }
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
        child: ColoredBox(
          color: highlighted ? context.deltiecord.hover : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
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
                      if (message.reply case final reply?)
                        InkWell(
                          key: ValueKey('mobile-reply-${message.id}'),
                          onTap: () => onJumpToReply(reply.eventId),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                CustomPaint(
                                  size: const Size(18, 18),
                                  painter: _MobileReplyConnector(
                                    color: context.deltiecord.muted,
                                  ),
                                ),
                                const SizedBox(width: 4),
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
                                          text: reply.body,
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
                      if (!message.redacted)
                        message.formattedBody != null
                            ? MatrixHtmlText(
                                html: message.formattedBody!,
                                fallback: message.body,
                                selectable: false,
                              )
                            : MatrixPlainText(
                                text: message.body,
                                selectable: false,
                              )
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
                                label: Text(
                                  '${reaction.key} ${reaction.count}',
                                ),
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
      ..moveTo(size.width, size.height * 0.75)
      ..lineTo(size.width * 0.45, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.15,
        size.height * 0.75,
        size.width * 0.15,
        size.height * 0.45,
      )
      ..lineTo(size.width * 0.15, 0);
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
    required this.emojiMatches,
    required this.emojiCompletionActive,
    required this.emojiSelection,
    required this.onEmojiSelected,
    required this.onEmojiSelectionChanged,
    required this.onDismissEmojiCompletion,
  });
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
  final List<EmojiEntry> emojiMatches;
  final bool emojiCompletionActive;
  final int emojiSelection;
  final ValueChanged<EmojiEntry> onEmojiSelected;
  final ValueChanged<int> onEmojiSelectionChanged;
  final VoidCallback onDismissEmojiCompletion;

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
              side: BorderSide(color: context.deltiecord.divider),
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
                      child: Text(
                        '${widget.emojiMatches[index].emoji}  :${widget.emojiMatches[index].aliases.firstOrNull ?? widget.emojiMatches[index].name}:',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          decoration: BoxDecoration(
            color: context.deltiecord.elevated,
            border: Border.all(color: Colors.black, width: 1),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: widget.onAdd,
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
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onEmoji,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  IconButton(
                    onPressed: widget.sending ? null : widget.onSend,
                    icon: widget.sending
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
  const _MobileEmojiPicker();

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
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final results = await EmojiRepository.instance.search(
      _query.text,
      limit: _query.text.trim().isEmpty ? null : 160,
    );
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
                  for (final category in EmojiCategory.values)
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
                      SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 52,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final entry = entries[index];
                          return IconButton(
                            key: ValueKey('mobile-emoji-picker-${entry.emoji}'),
                            tooltip:
                                '${entry.name}  :${entry.aliases.firstOrNull ?? entry.name}:',
                            onPressed: () =>
                                Navigator.pop(context, entry.emoji),
                            icon: Text(
                              entry.emoji,
                              style: const TextStyle(fontSize: 27),
                            ),
                          );
                        }, childCount: entries.length),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _mobileEmojiCategoryIcon(EmojiCategory category) => switch (category) {
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
