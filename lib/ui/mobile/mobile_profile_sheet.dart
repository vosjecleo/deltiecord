import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import 'mobile_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    _profile = widget.backend.getUserProfile(widget.userId);
  }

  @override
  Widget build(BuildContext context) => Material(
    clipBehavior: Clip.antiAlias,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    color: Theme.of(context).colorScheme.surface,
    child: FutureBuilder<UserProfileSummary>(
      future: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final top = Color(profile.profileColor ?? 0xff4d5275);
        final bottom = Color(profile.profileColorSecondary ?? top.toARGB32());
        final own = profile.userId == widget.backend.userId;
        return RefreshIndicator(
          onRefresh: () async {
            final refreshed = widget.backend.getUserProfile(
              profile.userId,
              refresh: true,
            );
            setState(() => _profile = refreshed);
            await refreshed;
          },
          child: ListView(
            children: [
              SizedBox(
                height: 190,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      bottom: 46,
                      child: profile.bannerBytes == null
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [top, bottom],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            )
                          : Image.memory(
                              profile.bannerBytes!,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      left: 22,
                      bottom: 0,
                      child: MobileAvatar(
                        bytes: profile.avatarBytes,
                        fallback: profile.displayName,
                        presence: profile.presence,
                        size: 112,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          profile.displayName,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (profile.pronouns?.isNotEmpty == true)
                          Chip(label: Text(profile.pronouns!)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(profile.userId),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.circle, size: 12),
                          label: Text(mobilePresenceLabel(profile.presence)),
                        ),
                        if (profile.timezone?.isNotEmpty == true)
                          Chip(
                            avatar: const Icon(Icons.schedule, size: 17),
                            label: Text(profile.timezone!),
                          ),
                        if (profile.statusMessage?.isNotEmpty == true)
                          Chip(
                            avatar: const Icon(
                              Icons.chat_bubble_outline,
                              size: 17,
                            ),
                            label: Text(profile.statusMessage!),
                          ),
                      ],
                    ),
                    if (profile.bio?.isNotEmpty == true) ...[
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.person_outline, size: 19),
                                  SizedBox(width: 8),
                                  Text(
                                    'About me',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SelectableText(profile.bio!),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (!own)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                await widget.backend.startDirectChat(
                                  profile.userId,
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                              icon: const Icon(Icons.chat_bubble_outline),
                              label: const Text('Message'),
                            ),
                          ),
                        if (!own) const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Copy Matrix ID',
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: profile.userId),
                          ),
                          icon: const Icon(Icons.copy),
                        ),
                        if (!own) ...[
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: profile.blocked ? 'Unblock' : 'Block',
                            onPressed: () async {
                              await widget.backend.setUserBlocked(
                                profile.userId,
                                !profile.blocked,
                              );
                              setState(() {
                                _profile = widget.backend.getUserProfile(
                                  profile.userId,
                                  refresh: true,
                                );
                              });
                            },
                            icon: Icon(
                              profile.blocked ? Icons.undo : Icons.block,
                            ),
                          ),
                        ],
                        if (own && widget.onEditOwnProfile != null)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onEditOwnProfile!();
                              },
                              icon: const Icon(Icons.edit),
                              label: const Text('Edit profile'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
