import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/draft_store.dart';
import '../../services/custom_emoji.dart';
import '../settings_screen.dart';
import 'mobile_details_panel.dart';
import 'mobile_navigation.dart';
import 'mobile_profile_sheet.dart';
import 'mobile_timeline.dart';
import 'mobile_voice_view.dart';

/// Phone-specific application shell.
///
/// Navigation, timeline, and details remain mounted as sliding physical layers
/// so opening a drawer never destroys a room's scroll state or draft. Matrix
/// SDK objects remain behind [ChatBackend], exactly as on desktop.
class MobileChatShell extends StatefulWidget {
  const MobileChatShell({required this.backend, super.key});
  final ChatBackend backend;

  @override
  State<MobileChatShell> createState() => _MobileChatShellState();
}

class _MobileChatShellState extends State<MobileChatShell>
    with WidgetsBindingObserver {
  bool _navigationVisible = true;
  bool _detailsVisible = false;
  final Map<String, ({String text, List<CustomEmojiTextSpan> emojis})> _drafts =
      {};
  final DraftStore _draftStore = DraftStore();
  String? _lastRoomId;
  String? _lastSpaceId;
  int _roomOpenGeneration = 0;
  final Map<int, Offset> _pointerStarts = {};
  double? _navigationDragProgress;
  bool? _dragStartedWithNavigation;
  bool? _reportedConversationVisible;
  int _resumeGeneration = 0;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _lastRoomId = backend.selectedRoom?.id;
    _lastSpaceId = backend.selectedSpaceId;
    WidgetsBinding.instance.addObserver(this);
    backend.addListener(_backendChanged);
    unawaited(_restoreDrafts());
  }

  Future<void> _restoreDrafts() async {
    await _draftStore.initialize();
    for (final room in [...backend.rooms]) {
      final stored = _draftStore.read(room.id);
      if (stored == null) continue;
      final draft = customEmojiDraftFromDelta(stored.delta);
      if (draft.text.isNotEmpty) _drafts[room.id] = draft;
    }
    if (mounted) setState(() {});
  }

  void _backendChanged() {
    if (!mounted) return;
    final roomId = backend.selectedRoom?.id;
    final spaceId = backend.selectedSpaceId;
    final roomChanged = roomId != _lastRoomId;
    final spaceChanged = spaceId != _lastSpaceId;
    if (!roomChanged && !spaceChanged) return;
    _lastRoomId = roomId;
    _lastSpaceId = spaceId;
    setState(() {
      if (roomChanged && roomId != null) {
        _navigationVisible = false;
        _detailsVisible = false;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    backend.setConversationVisible(false);
    backend.removeListener(_backendChanged);
    unawaited(_draftStore.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Pointer streams can be interrupted when Android freezes the activity.
    // Keep durable navigation state, but discard only transient gesture state
    // so an orphaned pointer cannot leave the Space rail non-interactive.
    _pointerStarts.clear();
    setState(() {
      _resumeGeneration++;
      _roomOpenGeneration++;
      // A suspended room-open future must not suppress subsequent backend
      // selection notifications after Android thaws the activity.
      _navigationDragProgress = null;
      _dragStartedWithNavigation = null;
    });
    // Rebuilding the navigation subtree reconciles the rail and room card
    // after Android recreates its surface. Do not re-select the Space through
    // the backend here: Space selection intentionally clears the active room.
  }

  Future<void> _openRoom(RoomSummary room) async {
    final generation = ++_roomOpenGeneration;
    await backend.selectRoom(room.id);
    if (generation != _roomOpenGeneration) return;
    if (room.isVoice && backend.activeVoiceRoomId != room.id) {
      await backend.joinVoiceRoom(room.id);
    }
    if (!mounted) return;
    setState(() {
      _lastRoomId = room.id;
      _navigationVisible = false;
      _detailsVisible = false;
    });
  }

  void _showSettings() => showDeltiecordSettings(context, backend);

  @override
  Widget build(BuildContext context) {
    final room = backend.selectedRoom;
    _reportConversationVisibility(
      room != null &&
          !room.isVoice &&
          !_detailsVisible &&
          _navigationProgress <= 0.001,
    );
    final canSystemPop = _navigationVisible && !_detailsVisible;
    return PopScope(
      canPop: canSystemPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_detailsVisible) {
          setState(() => _detailsVisible = false);
        } else if (!_navigationVisible) {
          setState(() => _navigationVisible = true);
        }
      },
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          // Raw pointer tracking deliberately observes (but does not win) the
          // gesture arena. Message rows may still claim a left drag for reply,
          // while a right drag anywhere on the timeline reliably opens nav.
          onPointerDown: (event) =>
              _pointerStarts[event.pointer] = event.position,
          onPointerMove: (event) {
            final start = _pointerStarts[event.pointer];
            if (start == null || _detailsVisible || room == null) return;
            final delta = event.position - start;
            if (delta.dx.abs() < 6 || delta.dx.abs() < delta.dy.abs() * 1.15) {
              return;
            }
            final startedVisible =
                _dragStartedWithNavigation ?? _navigationVisible;
            if ((startedVisible && delta.dx >= 0) ||
                (!startedVisible && delta.dx <= 0)) {
              return;
            }
            if (_navigationDragProgress == null) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
            final width = MediaQuery.sizeOf(context).width;
            final progress = startedVisible
                ? (1 + delta.dx / width).clamp(0.0, 1.0)
                : (delta.dx / width).clamp(0.0, 1.0);
            setState(() {
              _dragStartedWithNavigation = startedVisible;
              _navigationDragProgress = progress;
            });
          },
          onPointerCancel: (event) {
            _pointerStarts.remove(event.pointer);
            if (_navigationDragProgress != null) {
              setState(() {
                _navigationDragProgress = null;
                _dragStartedWithNavigation = null;
              });
            }
          },
          onPointerUp: (event) {
            final start = _pointerStarts.remove(event.pointer);
            if (start == null) return;
            final progress = _navigationDragProgress;
            final startedVisible = _dragStartedWithNavigation;
            if (progress != null && startedVisible != null) {
              setState(() {
                _navigationVisible = startedVisible
                    ? progress >= 0.78
                    : progress >= 0.18;
                _navigationDragProgress = null;
                _dragStartedWithNavigation = null;
              });
              return;
            }
            final delta = event.position - start;
            if (delta.dx.abs() < 72 || delta.dx.abs() < delta.dy.abs() * 1.25) {
              return;
            }
            if (_detailsVisible && delta.dx > 0) {
              setState(() => _detailsVisible = false);
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSlide(
                  offset: room == null
                      ? Offset.zero
                      : Offset(0.12 * _navigationProgress, 0),
                  duration: _navigationDragProgress == null
                      ? _duration
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  child: room == null
                      ? const _NoRoomSelected()
                      : room.isVoice
                      ? MobileVoiceView(
                          backend: backend,
                          room: room,
                          onOpenNavigation: () =>
                              setState(() => _navigationVisible = true),
                          onOpenDetails: () =>
                              setState(() => _detailsVisible = true),
                        )
                      : MobileTimelineView(
                          key: ValueKey('mobile-room-${room.id}'),
                          backend: backend,
                          room: room,
                          onOpenNavigation: () =>
                              setState(() => _navigationVisible = true),
                          onOpenDetails: () =>
                              setState(() => _detailsVisible = true),
                          onOpenSettings: _showSettings,
                          initialDraft: _drafts[room.id]?.text ?? '',
                          initialCustomEmojis:
                              _drafts[room.id]?.emojis ?? const [],
                          onDraftChanged: (value) {
                            if (value.text.isEmpty) {
                              _drafts.remove(room.id);
                              _draftStore.remove(room.id);
                            } else {
                              _drafts[room.id] = value;
                              _draftStore.write(
                                room.id,
                                customEmojiDraftDelta(value.text, value.emojis),
                              );
                            }
                          },
                        ),
                ),
              ),
              Positioned.fill(
                child: AnimatedSlide(
                  offset: Offset(-1 + _navigationProgress, 0),
                  duration: _navigationDragProgress == null
                      ? _duration
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: _navigationProgress < 0.02,
                    child: Material(
                      elevation: 12,
                      child: MobileNavigationPanel(
                        key: ValueKey(
                          'mobile-navigation-panel-$_resumeGeneration',
                        ),
                        backend: backend,
                        onOpenRoom: _openRoom,
                        onOpenSettings: _showSettings,
                        onOpenProfile: () {
                          final userId = backend.userId;
                          if (userId == null) return;
                          showMobileProfileSheet(
                            context,
                            backend,
                            userId,
                            onEditOwnProfile: _showSettings,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (room != null)
                Positioned.fill(
                  child: AnimatedSlide(
                    offset: _detailsVisible ? Offset.zero : const Offset(1, 0),
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      ignoring: !_detailsVisible,
                      child: Material(
                        elevation: 14,
                        child: MobileDetailsPanel(
                          backend: backend,
                          room: room,
                          onDismiss: () =>
                              setState(() => _detailsVisible = false),
                        ),
                      ),
                    ),
                  ),
                ),
              if (backend.activeVoiceRoomId != null &&
                  room?.id != backend.activeVoiceRoomId &&
                  !_navigationVisible)
                Positioned(
                  right: 12,
                  bottom: 92,
                  child: MobileCallIsland(
                    backend: backend,
                    onOpen: () async {
                      final voiceRoom = backend.rooms
                          .where((item) => item.id == backend.activeVoiceRoomId)
                          .firstOrNull;
                      if (voiceRoom != null) await _openRoom(voiceRoom);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Duration get _duration => backend.preferences.reducedMotion
      ? Duration.zero
      : const Duration(milliseconds: 220);

  double get _navigationProgress =>
      _navigationDragProgress ?? (_navigationVisible ? 1 : 0);

  void _reportConversationVisibility(bool visible) {
    if (_reportedConversationVisible == visible) return;
    _reportedConversationVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedConversationVisible != visible) return;
      backend.setConversationVisible(visible);
    });
  }
}

class _NoRoomSelected extends StatelessWidget {
  const _NoRoomSelected();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 50),
          SizedBox(height: 12),
          Text('Choose a room to start chatting'),
        ],
      ),
    ),
  );
}
