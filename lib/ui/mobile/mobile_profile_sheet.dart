import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../profile_card.dart';

Future<void> showMobileProfileSheet(
  BuildContext context,
  ChatBackend backend,
  String userId, {
  VoidCallback? onEditOwnProfile,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.transparent,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: _MobileProfileCard(
      backend: backend,
      userId: userId,
      onEditOwnProfile: onEditOwnProfile,
    ),
  ),
);

/// Mobile host for the same profile card rendered on desktop.
///
/// A raw downward gesture is observed outside Flutter's scroll gesture arena,
/// so the sheet remains dismissible from anywhere without sacrificing its
/// scrollable profile content.
class _MobileProfileCard extends StatefulWidget {
  const _MobileProfileCard({
    required this.backend,
    required this.userId,
    this.onEditOwnProfile,
  });

  final ChatBackend backend;
  final String userId;
  final VoidCallback? onEditOwnProfile;

  @override
  State<_MobileProfileCard> createState() => _MobileProfileCardState();
}

class _MobileProfileCardState extends State<_MobileProfileCard> {
  late Future<UserProfileSummary> _profile;
  final Map<int, Offset> _pointerStarts = {};

  @override
  void initState() {
    super.initState();
    _profile = widget.backend.getUserProfile(widget.userId);
  }

  void _refresh() => setState(() {
    _profile = widget.backend.getUserProfile(widget.userId, refresh: true);
  });

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => _pointerStarts[event.pointer] = event.position,
    onPointerCancel: (event) => _pointerStarts.remove(event.pointer),
    onPointerUp: (event) {
      final start = _pointerStarts.remove(event.pointer);
      if (start == null) return;
      final delta = event.position - start;
      if (delta.dy > 82 && delta.dy > delta.dx.abs() * 1.2) {
        Navigator.of(context).maybePop();
      }
    },
    child: FutureBuilder<UserProfileSummary>(
      future: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) {
          return const Material(
            color: Colors.transparent,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final own = profile.userId == widget.backend.userId;
        return Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                child: DeltiecordProfileCard(
                  profile: profile,
                  onClose: () => Navigator.pop(context),
                  onEdit: own && widget.onEditOwnProfile != null
                      ? () {
                          Navigator.pop(context);
                          widget.onEditOwnProfile!();
                        }
                      : null,
                  onMessage: own
                      ? null
                      : () async {
                          await widget.backend.startDirectChat(profile.userId);
                          if (context.mounted) Navigator.pop(context);
                        },
                  onBlock: own
                      ? null
                      : () async {
                          await widget.backend.setUserBlocked(
                            profile.userId,
                            !profile.blocked,
                          );
                          _refresh();
                        },
                  blocked: profile.blocked,
                ),
              ),
            ),
            Positioned(
              right: 112,
              top: 14,
              child: IconButton.filledTonal(
                tooltip: 'Refresh profile',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ],
        );
      },
    ),
  );
}
