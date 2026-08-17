import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../../services/draft_store.dart';
import '../settings_screen.dart';
import 'mobile_details_panel.dart';
import 'mobile_navigation.dart';
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

class _MobileChatShellState extends State<MobileChatShell> {
  bool _navigationVisible = true;
  bool _detailsVisible = false;
  final Map<String, String> _drafts = {};
  final DraftStore _draftStore = DraftStore();
  String? _lastRoomId;
  bool _openingRoom = false;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _lastRoomId = backend.selectedRoom?.id;
    backend.addListener(_backendChanged);
    unawaited(_restoreDrafts());
  }

  Future<void> _restoreDrafts() async {
    await _draftStore.initialize();
    for (final room in [...backend.rooms]) {
      final stored = _draftStore.read(room.id);
      if (stored == null) continue;
      final text = stored.delta
          .whereType<Map>()
          .map((operation) => operation['insert'])
          .whereType<String>()
          .join()
          .replaceFirst(RegExp(r'\n$'), '');
      if (text.isNotEmpty) _drafts[room.id] = text;
    }
    if (mounted) setState(() {});
  }

  void _backendChanged() {
    if (!mounted || _openingRoom) return;
    final roomId = backend.selectedRoom?.id;
    if (roomId != null && roomId != _lastRoomId) {
      _lastRoomId = roomId;
      setState(() {
        _navigationVisible = false;
        _detailsVisible = false;
      });
    }
  }

  @override
  void dispose() {
    backend.removeListener(_backendChanged);
    unawaited(_draftStore.dispose());
    super.dispose();
  }

  Future<void> _openRoom(RoomSummary room) async {
    _openingRoom = true;
    try {
      await backend.selectRoom(room.id);
      if (room.isVoice && backend.activeVoiceRoomId != room.id) {
        await backend.joinVoiceRoom(room.id);
      }
      if (!mounted) return;
      setState(() {
        _lastRoomId = room.id;
        _navigationVisible = false;
        _detailsVisible = false;
      });
    } finally {
      _openingRoom = false;
    }
  }

  void _showSettings() => showDeltiecordSettings(context, backend);

  @override
  Widget build(BuildContext context) {
    final room = backend.selectedRoom;
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
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (!_detailsVisible && !_navigationVisible && velocity > 450) {
              setState(() => _navigationVisible = true);
            } else if (_navigationVisible && room != null && velocity < -450) {
              setState(() => _navigationVisible = false);
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSlide(
                  offset: _navigationVisible && room != null
                      ? const Offset(0.12, 0)
                      : Offset.zero,
                  duration: _duration,
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
                          initialDraft: _drafts[room.id] ?? '',
                          onDraftChanged: (value) {
                            if (value.isEmpty) {
                              _drafts.remove(room.id);
                              _draftStore.remove(room.id);
                            } else {
                              _drafts[room.id] = value;
                              _draftStore.write(room.id, [
                                {'insert': '$value\n'},
                              ]);
                            }
                          },
                        ),
                ),
              ),
              Positioned.fill(
                child: AnimatedSlide(
                  offset: _navigationVisible
                      ? Offset.zero
                      : const Offset(-1, 0),
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !_navigationVisible,
                    child: Material(
                      elevation: 12,
                      child: MobileNavigationPanel(
                        backend: backend,
                        onOpenRoom: _openRoom,
                        onOpenSettings: _showSettings,
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
