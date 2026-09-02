import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mime/mime.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/giphy_service.dart';
import '../services/secret_redaction.dart';
import '../services/temporary_attachment_store.dart';
import '../services/timezone_catalog.dart';
import '../services/emoji_repository.dart';
import '../services/emoji_completion.dart';
import '../services/draft_store.dart';
import 'giphy_dialog.dart';
import 'emoji_picker_dialog.dart';
import 'settings_screen.dart';
import 'profile_dialog.dart';
import 'profile_card.dart';
import 'app_shortcuts.dart';
import 'rich_message.dart';
import 'matrix_html_text.dart';
import 'voice_room_view.dart';
import 'deltiecord_theme.dart';
import 'advanced_chat_dialogs.dart';
import 'advanced_chat_views.dart';
import 'poll_card.dart';
import 'member_management.dart';
import 'presence_controls.dart';
import 'space_settings_screen.dart';
import 'typing_indicator.dart';
import 'relative_activity_time.dart';

part 'chat_navigation.dart';
part 'conversation_view.dart';
part 'message_composer.dart';
part 'message_row.dart';
part 'message_media.dart';
part 'recipient_profile_panel.dart';
part 'member_sidebar.dart';

// The two bottom panels meet across separate widget trees. Keeping their
// geometry shared prevents one-pixel seams when either side is refactored.
const double _bottomPanelHeight = 68;
const double _composerControlHeight = 38;
const double _composerEditorHeight = 36;
const double _bottomPanelVerticalInset = 8;
const double _composerIslandVerticalInset = 7;

enum _SidePanelView { profile, members }

double _composerEditorHeightFor(BuildContext context) => max(
  _composerEditorHeight,
  MediaQuery.textScalerOf(context).scale(15) * 1.2 + 14,
);

double _composerControlHeightFor(BuildContext context) => max(
  _composerControlHeight,
  // The editor's one-pixel border sits outside constrained content.
  _composerEditorHeightFor(context) + 2,
);

double _bottomPanelHeightFor(BuildContext context) => max(
  _bottomPanelHeight,
  _composerControlHeightFor(context) +
      ((_bottomPanelVerticalInset + _composerIslandVerticalInset) * 2),
);

double _densityBetween(
  double value, {
  required double roomy,
  required double compact,
}) {
  return ui.lerpDouble(roomy, compact, value)!;
}

class ChatShell extends StatefulWidget {
  const ChatShell({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  late final QuillController _message;
  final _composerFocus = FocusNode(debugLabel: 'message composer');
  bool _sending = false;
  final List<AttachmentDraft> _pendingAttachments = [];
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  String? _mentionQuery;
  int? _mentionStart;
  int _mentionSelectionIndex = 0;
  bool _wasTyping = false;
  final GiphyService _giphy = GiphyService();
  final _composerKey = GlobalKey<_RichComposerState>();
  final _conversationKey = GlobalKey<_ConversationState>();
  final _draftStore = DraftStore();
  final Map<String, _RoomDraft> _memoryDrafts = {};
  String? _draftRoomId;
  bool _restoringDraft = false;
  bool _sidePanelVisible = true;
  bool _sidePanelAvailable = false;
  _SidePanelView _sidePanelView = _SidePanelView.profile;
  RoomMemberSummary? _sidePanelMember;
  bool? _reportedConversationVisible;

  @override
  void initState() {
    super.initState();
    _message = QuillController.basic(
      config: QuillControllerConfig(
        // Flutter Quill exposes native clipboard images through this API.
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(
          onImagePaste: (bytes) async {
            _queueClipboardImage(bytes);
            // Deltiecord sends pasted images as Matrix attachments instead of
            // inserting a local-only image embed into the text document.
            return null;
          },
          // ignore: experimental_member_use
          onGifPaste: (bytes) async {
            _queueAttachment(
              bytes: bytes,
              name: 'clipboard-${DateTime.now().millisecondsSinceEpoch}.gif',
              mimeType: 'image/gif',
            );
            return null;
          },
        ),
      ),
    );
    _message.addListener(_updateMentionQuery);
    _message.addListener(_saveActiveDraft);
    _draftRoomId = widget.backend.selectedRoom?.id;
    widget.backend.addListener(_handleBackendRoomChange);
    HardwareKeyboard.instance.addHandler(_handleGlobalShortcut);
    unawaited(_initializeDrafts());
  }

  bool _handleGlobalShortcut(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final keyboard = HardwareKeyboard.instance;
    for (final entry in widget.backend.preferences.shortcutBindings.entries) {
      if (!matchesRecordedShortcut(
        entry.value,
        event.logicalKey,
        control: keyboard.isControlPressed,
        shift: keyboard.isShiftPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
      )) {
        continue;
      }
      _invokeShortcut(entry.key);
      return true;
    }
    return false;
  }

  void _invokeShortcut(AppShortcutAction action) {
    switch (action) {
      case AppShortcutAction.openSettings:
        showDeltiecordSettings(context, widget.backend);
      case AppShortcutAction.toggleMicrophone:
        widget.backend.setVoiceMuted(!widget.backend.voiceMuted);
      case AppShortcutAction.toggleDeafen:
        widget.backend.setVoiceDeafened(!widget.backend.voiceDeafened);
      case AppShortcutAction.disconnectVoice:
        widget.backend.leaveVoiceRoom();
      case AppShortcutAction.openGifPicker:
        _showGifPicker();
      case AppShortcutAction.openEmojiPicker:
        _composerKey.currentState?.showEmojiPicker();
      case AppShortcutAction.openFilePicker:
        _attachFile();
      case AppShortcutAction.focusComposer:
        _composerFocus.requestFocus();
      case AppShortcutAction.searchRoom:
        _conversationKey.currentState?.showSearch();
      case AppShortcutAction.toggleMembers:
        _showMembersPanel();
    }
  }

  Future<void> _initializeDrafts() async {
    await _draftStore.initialize();
    if (!mounted) return;
    _restoreDraft(widget.backend.selectedRoom?.id);
  }

  void _handleBackendRoomChange() {
    final roomId = widget.backend.selectedRoom?.id;
    if (roomId == _draftRoomId) return;
    _storeCurrentDraft();
    HardwareKeyboard.instance.removeHandler(_handleGlobalShortcut);
    _restoreDraft(roomId);
    _sidePanelMember = null;
    _sidePanelView = widget.backend.selectedRoom?.isDirect == true
        ? _SidePanelView.profile
        : _SidePanelView.members;
  }

  void _showMembersPanel() {
    setState(() {
      _sidePanelMember = null;
      _sidePanelView = _SidePanelView.members;
      _sidePanelVisible = true;
    });
  }

  void _showProfilePanel(RoomMemberSummary member, [Offset? anchor]) {
    if (!_sidePanelAvailable) {
      showMemberProfile(context, widget.backend, member, anchor: anchor);
      return;
    }
    setState(() {
      _sidePanelMember = member;
      _sidePanelView = _SidePanelView.profile;
      _sidePanelVisible = true;
    });
  }

  void _showProfilePopover(RoomMemberSummary member, [Offset? anchor]) {
    showMemberProfile(context, widget.backend, member, anchor: anchor);
  }

  void _saveActiveDraft() {
    if (_restoringDraft) return;
    final roomId = _draftRoomId;
    if (roomId == null) return;
    _draftStore.write(roomId, _message.document.toDelta().toJson());
  }

  void _storeCurrentDraft() {
    final roomId = _draftRoomId;
    if (roomId == null) return;
    _memoryDrafts[roomId] = _RoomDraft(
      delta: _message.document.toDelta().toJson(),
      attachments: List.of(_pendingAttachments),
      replyingTo: _replyingTo,
      editingMessage: _editingMessage,
    );
    _saveActiveDraft();
  }

  void _restoreDraft(String? roomId) {
    _draftRoomId = roomId;
    final memory = roomId == null ? null : _memoryDrafts[roomId];
    final stored = roomId == null ? null : _draftStore.read(roomId);
    final delta = memory?.delta ?? stored?.delta;
    _restoringDraft = true;
    try {
      _message.document = delta == null || delta.isEmpty
          ? Document()
          : Document.fromJson(delta);
      final end = max(0, _message.document.length - 1);
      _message.updateSelection(
        TextSelection.collapsed(offset: end),
        ChangeSource.local,
      );
      if (mounted) {
        setState(() {
          _pendingAttachments
            ..clear()
            ..addAll(memory?.attachments ?? const []);
          _replyingTo = memory?.replyingTo;
          _editingMessage = memory?.editingMessage;
        });
      }
    } finally {
      _restoringDraft = false;
    }
  }

  void _updateMentionQuery() {
    final text = _message.document.toPlainText();
    final typing = text.trim().isNotEmpty;
    if (typing != _wasTyping) {
      _wasTyping = typing;
      unawaited(widget.backend.setComposerTyping(typing));
    }
    final cursor = _message.selection.extentOffset.clamp(0, text.length);
    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(beforeCursor);
    final query = match?.group(1);
    final start = match == null ? null : beforeCursor.lastIndexOf('@');
    if (query == _mentionQuery && start == _mentionStart) return;
    setState(() {
      _mentionQuery = query;
      _mentionStart = start;
      _mentionSelectionIndex = 0;
    });
  }

  void _insertMention(String targetId) {
    final start = _mentionStart;
    if (start == null) return;
    MentionSuggestion? suggestion;
    for (final candidate in _mentionSuggestions) {
      if (candidate.matrixId == targetId) {
        suggestion = candidate;
        break;
      }
    }
    if (suggestion == null) return;
    final mentionText = suggestion.isRoom
        ? '#${suggestion.displayName}'
        : suggestion.matrixId;
    final end = _message.selection.extentOffset;
    _message.replaceText(
      start,
      end - start,
      '$mentionText ',
      TextSelection.collapsed(offset: start + mentionText.length + 1),
    );
    if (suggestion.matrixId != '@everyone' && suggestion.matrixId != '@all') {
      _message.formatText(
        start,
        mentionText.length,
        LinkAttribute('https://matrix.to/#/${suggestion.matrixId}'),
      );
    }
    setState(() {
      _mentionQuery = null;
      _mentionStart = null;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _send() async {
    final sendingRoomId = widget.backend.selectedRoom?.id;
    final serialized = serializeRichMessage(_message.document);
    final text = serialized.plainText.trim();
    if ((text.isEmpty && _pendingAttachments.isEmpty) || _sending) return;
    final submittedDelta = _message.document.toDelta().toJson();
    final attachments = List<AttachmentDraft>.from(_pendingAttachments);
    final submittedReply = _replyingTo;
    final submittedEdit = _editingMessage;

    // Detach the submitted draft before awaiting the homeserver. Text entered
    // while this send is in flight now belongs to the next message and must
    // never be cleared by completion of the previous request.
    _restoringDraft = true;
    try {
      _message.clear();
    } finally {
      _restoringDraft = false;
    }
    setState(() {
      _sending = true;
      _pendingAttachments.clear();
      _replyingTo = null;
      _editingMessage = null;
    });
    if (sendingRoomId != null) {
      _memoryDrafts.remove(sendingRoomId);
      _draftStore.remove(sendingRoomId);
    }
    try {
      if (attachments.isEmpty) {
        await widget.backend.sendMessage(
          text,
          roomId: sendingRoomId,
          formattedBody: serialized.html,
          replyToMessageId: submittedReply?.id,
          editMessageId: submittedEdit?.id,
        );
      } else {
        for (var index = 0; index < attachments.length; index++) {
          final attachment = attachments[index];
          await widget.backend.sendAttachment(
            AttachmentDraft(
              bytes: attachment.bytes,
              name: attachment.name,
              mimeType: attachment.mimeType,
              spoiler: attachment.spoiler,
              caption: index == 0 && text.isNotEmpty ? text : null,
            ),
            roomId: sendingRoomId,
            replyToMessageId: index == 0 ? submittedReply?.id : null,
          );
        }
      }
    } catch (_) {
      final failedDraft = _RoomDraft(
        delta: submittedDelta,
        attachments: attachments,
        replyingTo: submittedReply,
        editingMessage: submittedEdit,
      );
      if (mounted && widget.backend.selectedRoom?.id == sendingRoomId) {
        final nextDelta = _message.document.toDelta();
        _restoringDraft = true;
        try {
          _message.document = Document.fromDelta(
            Document.fromJson(submittedDelta).toDelta().concat(nextDelta),
          );
          _message.updateSelection(
            TextSelection.collapsed(
              offset: max(0, _message.document.length - 1),
            ),
            ChangeSource.local,
          );
        } finally {
          _restoringDraft = false;
        }
        setState(() {
          _pendingAttachments.insertAll(0, attachments);
          _replyingTo ??= submittedReply;
          _editingMessage ??= submittedEdit;
        });
        _storeCurrentDraft();
      } else if (sendingRoomId != null) {
        _memoryDrafts[sendingRoomId] = failedDraft;
        _draftStore.write(sendingRoomId, submittedDelta);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _createPoll() async {
    final poll = await showPollComposer(context);
    if (poll == null || !mounted) return;
    await widget.backend.sendPoll(
      poll,
      roomId: widget.backend.selectedRoom?.id,
    );
    _composerFocus.requestFocus();
  }

  Future<void> _sendSticker() async {
    final sticker = await showStickerPicker(context, widget.backend);
    if (sticker == null || !mounted) return;
    await widget.backend.sendSticker(
      sticker,
      roomId: widget.backend.selectedRoom?.id,
    );
    _composerFocus.requestFocus();
  }

  Future<void> _scheduleCurrentMessage() async {
    if (_sending) return;
    final text = serializeRichMessage(_message.document).plainText.trim();
    if (text.isEmpty) return;
    if (_pendingAttachments.isNotEmpty || _editingMessage != null) {
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
    await widget.backend.scheduleMessage(
      text,
      sendAt,
      roomId: widget.backend.selectedRoom?.id,
      replyToMessageId: _replyingTo?.id,
    );
    _restoringDraft = true;
    try {
      _message.clear();
    } finally {
      _restoringDraft = false;
    }
    setState(() => _replyingTo = null);
    final roomId = widget.backend.selectedRoom?.id;
    if (roomId != null) {
      _memoryDrafts.remove(roomId);
      _draftStore.remove(roomId);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message scheduled for ${sendAt.toLocal()}')),
      );
      _composerFocus.requestFocus();
    }
  }

  void _replyTo(ChatMessage message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  void _edit(ChatMessage message) {
    _message.document = Document()..insert(0, message.body);
    _message.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: message.body.length),
      ChangeSource.local,
    );
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
    });
    _composerFocus.requestFocus();
  }

  void _cancelComposerAction() {
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  Future<void> _attachFile() async {
    if (_sending) return;
    final result = await FilePicker.pickFiles(
      withData: false,
      allowMultiple: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    for (var index = 0; index < result.files.length; index++) {
      final picked = result.files[index];
      final bytes = picked.bytes ?? await result.xFiles[index].readAsBytes();
      if (!mounted) return;
      _queueAttachment(
        bytes: bytes,
        name: picked.name,
        mimeType:
            lookupMimeType(picked.name, headerBytes: bytes) ??
            'application/octet-stream',
      );
    }
  }

  Future<void> _showGifPicker() async {
    final gif = await showDialog<GifSearchResult>(
      context: context,
      builder: (context) => GiphyDialog(service: _giphy),
    );
    if (gif == null || !mounted) {
      _composerFocus.requestFocus();
      return;
    }
    final sendingRoomId = widget.backend.selectedRoom?.id;
    setState(() => _sending = true);
    try {
      final bytes = await _giphy.download(gif);
      await widget.backend.sendAttachment(
        AttachmentDraft(
          bytes: bytes,
          name: 'giphy-${DateTime.now().millisecondsSinceEpoch}.gif',
          mimeType: 'image/gif',
          spoiler: false,
        ),
        roomId: sendingRoomId,
        replyToMessageId: _replyingTo?.id,
      );
      if (mounted) setState(() => _replyingTo = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _composerFocus.requestFocus();
  }

  void _queueClipboardImage(Uint8List bytes) {
    final mimeType = lookupMimeType('', headerBytes: bytes) ?? 'image/png';
    final extension = switch (mimeType) {
      'image/gif' => 'gif',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
    _queueAttachment(
      bytes: bytes,
      name: 'clipboard-${DateTime.now().millisecondsSinceEpoch}.$extension',
      mimeType: mimeType,
    );
  }

  void _queueAttachment({
    required Uint8List bytes,
    required String name,
    required String mimeType,
  }) async {
    if (!mounted) return;
    setState(
      () => _pendingAttachments.add(
        AttachmentDraft(
          bytes: bytes,
          name: name,
          mimeType: mimeType,
          spoiler: false,
        ),
      ),
    );
    _composerFocus.requestFocus();
  }

  void _queueAttachments(List<AttachmentDraft> attachments) {
    if (!mounted || attachments.isEmpty) return;
    setState(() => _pendingAttachments.addAll(attachments));
    _composerFocus.requestFocus();
  }

  Future<bool> _pasteClipboardImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;
    final reader = await clipboard.read();
    if (!reader.canProvide(Formats.png)) return false;
    final completed = Completer<Uint8List?>();
    final progress = reader.getFile(
      Formats.png,
      (file) async => completed.complete(await file.readAll()),
      onError: (_) => completed.complete(null),
    );
    if (progress == null) return false;
    final bytes = await completed.future;
    if (bytes == null || bytes.isEmpty) return false;
    _queueClipboardImage(bytes);
    return true;
  }

  void _removePendingAttachment(int index) {
    setState(() => _pendingAttachments.removeAt(index));
  }

  void _togglePendingSpoiler(int index) {
    final attachment = _pendingAttachments[index];
    setState(() {
      _pendingAttachments[index] = AttachmentDraft(
        bytes: attachment.bytes,
        name: attachment.name,
        mimeType: attachment.mimeType,
        spoiler: !attachment.spoiler,
      );
    });
  }

  @override
  void dispose() {
    widget.backend.setConversationVisible(false);
    _storeCurrentDraft();
    widget.backend.removeListener(_handleBackendRoomChange);
    _message.removeListener(_updateMentionQuery);
    _message.removeListener(_saveActiveDraft);
    _message.dispose();
    _composerFocus.dispose();
    _giphy.dispose();
    unawaited(_draftStore.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callbacks = <AppShortcutAction, VoidCallback>{
      for (final action in AppShortcutAction.values)
        action: () => _invokeShortcut(action),
    };
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final entry in widget.backend.preferences.shortcutBindings.entries) {
      final activator = decodeShortcut(entry.value);
      final callback = callbacks[entry.key];
      if (activator != null && callback != null) bindings[activator] = callback;
    }
    bindings[const SingleActivator(LogicalKeyboardKey.escape)] = () {
      if (_conversationKey.currentState?.dismissTemporaryUi() == true) {
        _composerFocus.requestFocus();
      } else if (_replyingTo != null || _editingMessage != null) {
        _cancelComposerAction();
      } else {
        _composerFocus.requestFocus();
      }
    };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              if (widget.backend.connectionStatus != ConnectionStatus.online)
                _ConnectionBanner(status: widget.backend.connectionStatus),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showSpaceRail = constraints.maxWidth >= 760;
                    final selectedRoom = widget.backend.selectedRoom;
                    _reportConversationVisibility(
                      selectedRoom != null && !selectedRoom.isVoice,
                    );
                    final roomMembers = widget.backend.selectedRoomMembers;
                    final otherRoomMembers = roomMembers
                        .where(
                          (member) => member.userId != widget.backend.userId,
                        )
                        .toList(growable: false);
                    RoomMemberSummary? directRecipient;
                    if (selectedRoom?.isDirect == true &&
                        otherRoomMembers.length == 1) {
                      directRecipient = otherRoomMembers.single;
                    }
                    final showMemberSidebar =
                        selectedRoom != null &&
                        (widget.backend.selectedSpaceId != null ||
                            otherRoomMembers.length > 1);
                    final hasSidePanel =
                        constraints.maxWidth >= 1100 &&
                        (directRecipient != null || showMemberSidebar);
                    _sidePanelAvailable = hasSidePanel;
                    final preferredPanel =
                        widget.backend.preferences.roomPanelWidth;
                    final maximumRoomPanelWidth = max(
                      0.0,
                      constraints.maxWidth * 0.46,
                    );
                    final minimumRoomPanelWidth = min(
                      220.0,
                      maximumRoomPanelWidth,
                    );
                    final panelWidth = preferredPanel.clamp(
                      minimumRoomPanelWidth,
                      maximumRoomPanelWidth,
                    );
                    // Include the resize gutter so the lower controls form one
                    // uninterrupted strip across rail, room list, and composer.
                    final navigationWidth =
                        panelWidth + (showSpaceRail ? 69 : 0) + 5;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Row(
                            children: [
                              if (showSpaceRail) ...[
                                SizedBox(
                                  width: 68,
                                  child: _SpaceBar(backend: widget.backend),
                                ),
                                const VerticalDivider(
                                  width: 1,
                                  color: Colors.transparent,
                                ),
                              ],
                              SizedBox(
                                width: panelWidth,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: DeltiecordCorners.corner,
                                  ),
                                  child: _RoomPanel(backend: widget.backend),
                                ),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.resizeColumn,
                                child: GestureDetector(
                                  key: const Key('room-panel-resize-handle'),
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (details) {
                                    final width =
                                        (widget
                                                    .backend
                                                    .preferences
                                                    .roomPanelWidth +
                                                details.delta.dx)
                                            .clamp(
                                              minimumRoomPanelWidth,
                                              maximumRoomPanelWidth,
                                            );
                                    widget.backend.updatePreferences(
                                      widget.backend.preferences.copyWith(
                                        roomPanelWidth: width,
                                      ),
                                    );
                                  },
                                  child: const SizedBox(
                                    width: 5,
                                    child: VerticalDivider(
                                      width: 1,
                                      color: Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: selectedRoom == null
                                    ? const _EmptyConversation()
                                    : selectedRoom.isVoice ||
                                          widget.backend.activeVoiceRoomId ==
                                              selectedRoom.id
                                    ? VoiceRoomView(
                                        backend: widget.backend,
                                        room: selectedRoom,
                                      )
                                    : _Conversation(
                                        key: _conversationKey,
                                        composerKey: _composerKey,
                                        backend: widget.backend,
                                        controller: _message,
                                        composerFocus: _composerFocus,
                                        sending: _sending,
                                        replyingTo: _replyingTo,
                                        editingMessage: _editingMessage,
                                        onSend: _send,
                                        onSchedule: _scheduleCurrentMessage,
                                        onPoll: _createPoll,
                                        onSticker: _sendSticker,
                                        onReply: _replyTo,
                                        onEdit: _edit,
                                        onCancelComposerAction:
                                            _cancelComposerAction,
                                        onAttach: _attachFile,
                                        onGif: _showGifPicker,
                                        onPasteImage: _pasteClipboardImage,
                                        onDropAttachments: _queueAttachments,
                                        pendingAttachments: _pendingAttachments,
                                        onRemoveAttachment:
                                            _removePendingAttachment,
                                        onToggleAttachmentSpoiler:
                                            _togglePendingSpoiler,
                                        mentionSuggestions: _mentionSuggestions,
                                        mentionSelectionIndex:
                                            _mentionSelectionIndex,
                                        onMentionSelected: _insertMention,
                                        onMentionSelectionChanged: (index) =>
                                            setState(
                                              () => _mentionSelectionIndex =
                                                  index,
                                            ),
                                        onShowMembers: _showMembersPanel,
                                        onShowProfile: (request) =>
                                            _showProfilePopover(
                                              request.$1,
                                              request.$2,
                                            ),
                                      ),
                              ),
                              if (hasSidePanel)
                                _SidePanelRegion(
                                  visible: _sidePanelVisible,
                                  width: widget
                                      .backend
                                      .preferences
                                      .sidePanelWidth
                                      .clamp(
                                        260,
                                        min(460, constraints.maxWidth * 0.4),
                                      ),
                                  onToggle: () => setState(
                                    () =>
                                        _sidePanelVisible = !_sidePanelVisible,
                                  ),
                                  onResize: (delta) {
                                    final width =
                                        (widget
                                                    .backend
                                                    .preferences
                                                    .sidePanelWidth -
                                                delta)
                                            .clamp(260.0, 460.0);
                                    widget.backend.updatePreferences(
                                      widget.backend.preferences.copyWith(
                                        sidePanelWidth: width,
                                      ),
                                    );
                                  },
                                  child:
                                      _sidePanelView ==
                                              _SidePanelView.profile &&
                                          (_sidePanelMember ??
                                                  directRecipient) !=
                                              null
                                      ? _RecipientProfilePanel(
                                          backend: widget.backend,
                                          member:
                                              _sidePanelMember ??
                                              directRecipient!,
                                        )
                                      : _MemberSidebar(
                                          backend: widget.backend,
                                          members: roomMembers,
                                          onMemberSelected: (member) =>
                                              _showProfilePanel(member),
                                        ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          width: navigationWidth,
                          child: _CurrentUserPanel(backend: widget.backend),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reportConversationVisibility(bool visible) {
    if (_reportedConversationVisible == visible) return;
    _reportedConversationVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedConversationVisible != visible) return;
      widget.backend.setConversationVisible(visible);
    });
  }

  List<MentionSuggestion> get _mentionSuggestions {
    final query = _mentionQuery?.toLowerCase();
    if (query == null) return const [];
    return widget.backend.mentionSuggestions
        .where(
          (suggestion) =>
              suggestion.displayName.toLowerCase().contains(query) ||
              suggestion.matrixId.toLowerCase().contains(query),
        )
        .take(6)
        .toList(growable: false);
  }
}

class _RoomDraft {
  const _RoomDraft({
    required this.delta,
    required this.attachments,
    this.replyingTo,
    this.editingMessage,
  });

  final List<dynamic> delta;
  final List<AttachmentDraft> attachments;
  final ChatMessage? replyingTo;
  final ChatMessage? editingMessage;
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (status) {
      ConnectionStatus.connecting => (
        Icons.sync,
        'Connecting to the homeserver…',
      ),
      ConnectionStatus.reconnecting => (
        Icons.sync_problem,
        'Connection interrupted — reconnecting…',
      ),
      ConnectionStatus.offline => (
        Icons.cloud_off_outlined,
        'Offline — messages will send after reconnecting.',
      ),
      ConnectionStatus.online => (Icons.cloud_done_outlined, ''),
    };
    return Material(
      color: const Color(0xff493a1f),
      child: SizedBox(
        height: 34,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(fontSize: DeltiecordTypeScale.normal),
            ),
          ],
        ),
      ),
    );
  }
}
