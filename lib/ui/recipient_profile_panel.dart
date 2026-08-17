part of 'chat_shell.dart';

/// Persistent, compact profile summary shown beside direct conversations.
///
/// This deliberately consumes only [ChatBackend] models so Matrix SDK objects
/// remain behind the application boundary.
class _RecipientProfilePanel extends StatefulWidget {
  const _RecipientProfilePanel({required this.backend, required this.member});

  final ChatBackend backend;
  final RoomMemberSummary member;

  @override
  State<_RecipientProfilePanel> createState() => _RecipientProfilePanelState();
}

class _RecipientProfilePanelState extends State<_RecipientProfilePanel> {
  late Future<UserProfileSummary> _profile = _load();
  late int _profileRevision = widget.backend.profileRevision;

  Future<UserProfileSummary> _load() =>
      widget.backend.getUserProfile(widget.member.userId);

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_backendChanged);
  }

  void _backendChanged() {
    final revision = widget.backend.profileRevision;
    if (!mounted || revision == _profileRevision) return;
    _profileRevision = revision;
    setState(() => _profile = _load());
  }

  @override
  void didUpdateWidget(covariant _RecipientProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.userId != widget.member.userId) {
      _profile = _load();
    }
    if (oldWidget.backend != widget.backend) {
      oldWidget.backend.removeListener(_backendChanged);
      widget.backend.addListener(_backendChanged);
      _profileRevision = widget.backend.profileRevision;
      _profile = _load();
    }
  }

  @override
  void dispose() {
    widget.backend.removeListener(_backendChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('recipient-profile-panel'),
    decoration: BoxDecoration(color: context.deltiecord.panel),
    child: FutureBuilder<UserProfileSummary>(
      future: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading profile…'),
              ],
            ),
          );
        }
        return _RecipientProfileContents(
          backend: widget.backend,
          member: widget.member,
          profile: profile,
          loading: false,
        );
      },
    ),
  );
}

class _RecipientProfileContents extends StatelessWidget {
  const _RecipientProfileContents({
    required this.backend,
    required this.member,
    required this.profile,
    required this.loading,
  });

  final ChatBackend backend;
  final RoomMemberSummary member;
  final UserProfileSummary profile;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.deltiecord;
    final accent = Color(
      profile.profileColor ?? Theme.of(context).colorScheme.primary.toARGB32(),
    );
    final secondary = Color(
      profile.profileColorSecondary ??
          Color.lerp(accent, palette.rail, 0.58)!.toARGB32(),
    );
    final gradientTop = Color.alphaBlend(
      accent.withValues(alpha: 0.25),
      palette.panel,
    );
    final gradientBottom = Color.alphaBlend(
      secondary.withValues(alpha: 0.3),
      palette.panel,
    );
    return DecoratedBox(
      key: const Key('recipient-profile-gradient'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gradientTop, gradientBottom],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.72), width: 2),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 204,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          bottom: 58,
                          child: profile.bannerBytes == null
                              ? DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [accent, secondary],
                                    ),
                                  ),
                                )
                              : Image.memory(
                                  profile.bannerBytes!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 720,
                                  filterQuality: FilterQuality.medium,
                                ),
                        ),
                        Positioned(
                          left: 20,
                          bottom: 18,
                          child: _RecipientAvatar(
                            profile: profile,
                            fallback: member,
                            panelColor: palette.panel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: DeltiecordTypeScale.bigUi,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (profile.statusMessage?.trim().isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 5),
                          ProfileStatusBubble(
                            status: profile.statusMessage!,
                            accent: accent,
                            expanded: true,
                          ),
                        ],
                        const SizedBox(height: 5),
                        SelectableText(
                          profile.userId,
                          style: TextStyle(color: palette.muted),
                        ),
                        if (profile.pronouns?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 7),
                          Text(
                            profile.pronouns!,
                            style: TextStyle(color: palette.muted),
                          ),
                        ],
                        if (profile.timezone?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 16, color: accent),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${TimezoneCatalog.offsetLabel(profile.timezone)}'
                                  '  •  ${TimezoneCatalog.localTimeLabel(profile.timezone)} local time',
                                  style: TextStyle(color: palette.muted),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (profile.bio?.trim().isNotEmpty == true)
                          SizedBox(
                            key: const Key('recipient-about-island'),
                            width: double.infinity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.surface,
                                border: Border.all(color: palette.divider),
                                borderRadius: DeltiecordCorners.borderRadius,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ABOUT ME',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: DeltiecordTypeScale.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(profile.bio!),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (loading) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: _bottomPanelHeightFor(context),
            child: ColoredBox(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: _bottomPanelVerticalInset,
                ),
                child: SizedBox(
                  key: const Key('view-full-profile-island'),
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.island,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: DeltiecordCorners.borderRadius,
                      ),
                    ),
                    onPressed: () =>
                        showFullMemberProfile(context, backend, member),
                    child: const Text('View full profile'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar({
    required this.profile,
    required this.fallback,
    required this.panelColor,
  });

  final UserProfileSummary profile;
  final RoomMemberSummary fallback;
  final Color panelColor;

  @override
  Widget build(BuildContext context) {
    final bytes = profile.avatarBytes ?? fallback.avatarBytes;
    final presence = profile.presence;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 88,
          height: 88,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: panelColor, shape: BoxShape.circle),
          child: CircleAvatar(
            backgroundImage: bytes == null
                ? null
                : ResizeImage(MemoryImage(bytes), width: 192, height: 192),
            child: bytes == null
                ? Text(
                    profile.displayName.trim().isEmpty
                        ? '?'
                        : profile.displayName.characters.first,
                    style: const TextStyle(fontSize: 30),
                  )
                : null,
          ),
        ),
        Positioned(
          right: 2,
          bottom: 3,
          child: Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: switch (presence) {
                UserPresence.online => const Color(0xff23d18b),
                UserPresence.away => const Color(0xffffc857),
                UserPresence.offline => const Color(0xff686a73),
              },
              shape: BoxShape.circle,
              border: Border.all(color: panelColor, width: 4),
            ),
          ),
        ),
      ],
    );
  }
}
