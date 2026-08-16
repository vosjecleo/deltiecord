import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../services/timezone_catalog.dart';
import 'deltiecord_theme.dart';

class DeltiecordProfileCard extends StatelessWidget {
  const DeltiecordProfileCard({
    required this.profile,
    this.onEdit,
    this.onClose,
    this.onMessage,
    this.onBlock,
    this.blocked = false,
    this.preview = false,
    super.key,
  });

  final UserProfileSummary profile;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final VoidCallback? onMessage;
  final VoidCallback? onBlock;
  final bool blocked;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    final accent = Color(
      profile.profileColor ?? Theme.of(context).colorScheme.primary.toARGB32(),
    );
    final secondaryAccent = Color(
      profile.profileColorSecondary ??
          Color.lerp(accent, palette.rail, 0.62)!.toARGB32(),
    );
    final gradientTop = Color.alphaBlend(
      accent.withValues(alpha: 0.28),
      palette.surface,
    );
    final gradientBottom = Color.alphaBlend(
      secondaryAccent.withValues(alpha: 0.3),
      palette.surface,
    );
    final timezone = profile.timezone;
    return Container(
      key: const Key('profile-card'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gradientTop, gradientBottom],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.75), width: 2),
        borderRadius: DeltiecordCorners.borderRadius,
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeader(
            profile: profile,
            accent: accent,
            secondaryAccent: secondaryAccent,
            onEdit: onEdit,
            onClose: onClose,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 4, 30, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      profile.displayName,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (profile.pronouns?.trim().isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.32),
                          borderRadius: DeltiecordCorners.borderRadius,
                        ),
                        child: Text(profile.pronouns!),
                      ),
                    if (profile.statusMessage?.trim().isNotEmpty == true)
                      ProfileStatusBubble(
                        status: profile.statusMessage!,
                        accent: accent,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        profile.userId,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: DeltiecordTypeScale.normal,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy Matrix ID',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: profile.userId),
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                    ),
                  ],
                ),
                if (timezone?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${TimezoneCatalog.offsetLabel(timezone)}  •  '
                        '${TimezoneCatalog.localTimeLabel(timezone)}',
                        style: TextStyle(color: palette.muted),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.background,
                    border: Border.all(color: palette.divider),
                    borderRadius: DeltiecordCorners.borderRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_outline, size: 19),
                          SizedBox(width: 8),
                          Text(
                            'About me',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        profile.bio?.trim().isNotEmpty == true
                            ? profile.bio!
                            : preview
                            ? 'Your bio preview will appear here.'
                            : 'No bio provided.',
                      ),
                    ],
                  ),
                ),
                if (onMessage != null || onBlock != null) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (onMessage != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onMessage,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Message'),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: deltiecordContrastingForeground(
                                accent,
                              ),
                            ),
                          ),
                        ),
                      if (onMessage != null && onBlock != null)
                        const SizedBox(width: 10),
                      if (onBlock != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onBlock,
                            icon: Icon(blocked ? Icons.undo : Icons.block),
                            label: Text(blocked ? 'Unblock' : 'Block'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileStatusBubble extends StatelessWidget {
  const ProfileStatusBubble({
    required this.status,
    required this.accent,
    this.expanded = false,
    super.key,
  });

  final String status;
  final Color accent;
  final bool expanded;

  @override
  Widget build(BuildContext context) => Container(
    width: expanded ? double.infinity : null,
    constraints: const BoxConstraints(maxWidth: 360),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        accent.withValues(alpha: 0.18),
        context.deltiecord.elevated,
      ),
      border: Border.all(color: accent.withValues(alpha: 0.58)),
      borderRadius: DeltiecordCorners.borderRadius,
    ),
    child: Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(Icons.chat_bubble_outline, size: 15, color: accent),
        const SizedBox(width: 7),
        Flexible(
          child: Text(status, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.accent,
    required this.secondaryAccent,
    required this.onEdit,
    required this.onClose,
  });

  final UserProfileSummary profile;
  final Color accent;
  final Color secondaryAccent;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerHeight = (constraints.maxWidth / 3).clamp(180.0, 260.0);
        return SizedBox(
          height: bannerHeight + 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: bannerHeight,
                child: profile.bannerBytes == null
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.72),
                              secondaryAccent.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      )
                    : Image.memory(
                        profile.bannerBytes!,
                        fit: BoxFit.cover,
                        cacheWidth: 1440,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.high,
                      ),
              ),
              Positioned(
                left: 30,
                bottom: 0,
                child: Container(
                  width: 124,
                  height: 124,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surface,
                  ),
                  child: ClipOval(
                    clipBehavior: Clip.antiAlias,
                    child: ColoredBox(
                      color: palette.elevated,
                      child: profile.avatarBytes == null
                          ? Center(
                              child: Text(
                                profile.displayName.characters.firstOrNull
                                        ?.toUpperCase() ??
                                    '?',
                                style: const TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Image.memory(
                              profile.avatarBytes!,
                              fit: BoxFit.cover,
                              cacheWidth: 256,
                              cacheHeight: 256,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.high,
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 132,
                bottom: 12,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _profilePresenceColour(profile.presence),
                    border: Border.all(color: palette.surface, width: 4),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: palette.elevated,
                    border: Border.all(color: palette.divider),
                    borderRadius: DeltiecordCorners.borderRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _profilePresenceColour(profile.presence),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_profilePresenceLabel(profile.presence)),
                    ],
                  ),
                ),
              ),
              if (onEdit != null)
                Positioned(
                  right: onClose == null ? 16 : 68,
                  top: 14,
                  child: IconButton.filledTonal(
                    tooltip: 'Edit profile',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              if (onClose != null)
                Positioned(
                  right: 16,
                  top: 14,
                  child: IconButton.filledTonal(
                    key: const Key('profile-close-button'),
                    tooltip: 'Close profile',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Color _profilePresenceColour(UserPresence presence) => switch (presence) {
  UserPresence.online => const Color(0xff23d887),
  UserPresence.away => const Color(0xffffc857),
  UserPresence.offline => const Color(0xff747680),
};

String _profilePresenceLabel(UserPresence presence) => switch (presence) {
  UserPresence.online => 'Online',
  UserPresence.away => 'Away',
  UserPresence.offline => 'Offline',
};
