import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../deltiecord_theme.dart';
import '../advanced_chat_views.dart';
import '../presence_controls.dart';
import '../relative_activity_time.dart';
import '../space_settings_screen.dart';
import 'mobile_widgets.dart';
import 'mobile_channel_manager.dart';

class MobileNavigationPanel extends StatefulWidget {
  const MobileNavigationPanel({
    required this.backend,
    required this.onOpenRoom,
    required this.onOpenSettings,
    required this.onOpenProfile,
    super.key,
  });

  final ChatBackend backend;
  final ValueChanged<RoomSummary> onOpenRoom;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenProfile;

  @override
  State<MobileNavigationPanel> createState() => _MobileNavigationPanelState();
}

class _MobileNavigationPanelState extends State<MobileNavigationPanel> {
  String _query = '';

  ChatBackend get backend => widget.backend;

  @override
  Widget build(BuildContext context) {
    final selectedSpace = backend.selectedSpaceId;
    final rooms = backend.rooms
        .where((room) {
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              room.name.toLowerCase().contains(query) ||
              room.lastMessage.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final darkSystemIcons = Theme.of(context).brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('mobile-system-bars'),
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: darkSystemIcons
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: darkSystemIcons
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ColoredBox(
        key: const ValueKey('mobile-navigation-background'),
        color: context.deltiecord.rail,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    _SpaceRail(backend: backend),
                    const SizedBox(width: 1),
                    Expanded(
                      child: CustomPaint(
                        key: const ValueKey('mobile-rail-separator'),
                        foregroundPainter: _NavigationCardEdgePainter(
                          context.deltiecord.divider.withValues(alpha: 0.65),
                        ),
                        child: ClipRRect(
                          key: const ValueKey('mobile-navigation-card'),
                          borderRadius: const BorderRadius.only(
                            topLeft: DeltiecordCorners.corner,
                          ),
                          child: Material(
                            color: context.deltiecord.panel,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    10,
                                    6,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: InkWell(
                                      borderRadius:
                                          DeltiecordCorners.borderRadius,
                                      onTap: selectedSpace == null
                                          ? null
                                          : () => showSpacePages(
                                              context,
                                              backend,
                                              selectedSpace,
                                            ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 3,
                                        ),
                                        child: Text(
                                          selectedSpace == null
                                              ? 'Home'
                                              : backend.spaces
                                                        .where(
                                                          (space) =>
                                                              space.id ==
                                                              selectedSpace,
                                                        )
                                                        .firstOrNull
                                                        ?.name ??
                                                    'Space',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    6,
                                    6,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: const ValueKey(
                                            'mobile-room-search',
                                          ),
                                          onChanged: (value) =>
                                              setState(() => _query = value),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: selectedSpace == null
                                                ? 'Search direct messages'
                                                : 'Search rooms',
                                            prefixIcon: const Icon(
                                              Icons.search,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      IconButton(
                                        key: const ValueKey('mobile-inbox'),
                                        tooltip: 'Inbox',
                                        onPressed: () => _openInbox(context),
                                        icon: const Icon(Icons.inbox_outlined),
                                      ),
                                      IconButton(
                                        key: const ValueKey(
                                          'mobile-start-chat',
                                        ),
                                        tooltip: selectedSpace == null
                                            ? 'Start a chat'
                                            : 'Create a room',
                                        onPressed: () => selectedSpace == null
                                            ? _startChat(context)
                                            : _createRoom(context),
                                        icon: const Icon(Icons.add),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: selectedSpace == null
                                      ? _RoomList(
                                          rooms: rooms,
                                          onOpenRoom: widget.onOpenRoom,
                                        )
                                      : _SpaceRoomList(
                                          backend: backend,
                                          rooms: rooms,
                                          onOpenRoom: widget.onOpenRoom,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('mobile-navigation-bottom-scrim'),
                    height: 128,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          context.deltiecord.panel.withValues(alpha: 0),
                          context.deltiecord.rail.withValues(alpha: 0.82),
                          context.deltiecord.rail,
                        ],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _MobileUserIsland(
                  backend: backend,
                  onOpenSettings: widget.onOpenSettings,
                  onOpenProfile: widget.onOpenProfile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startChat(BuildContext context) async {
    final controller = TextEditingController();
    final userId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a direct chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '@user:homeserver.tld'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (userId != null && userId.isNotEmpty) {
      await backend.startDirectChat(userId);
    }
  }

  Future<void> _openInbox(BuildContext context) => showUnifiedInbox(
    context,
    backend,
    onOpen: (item) async {
      await backend.selectRoom(item.roomId);
      final room = backend.selectedRoom;
      if (room != null) widget.onOpenRoom(room);
      if (item.eventId != null) await backend.jumpToEvent(item.eventId!);
    },
  );

  Future<void> _createRoom(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create room'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await backend.createRoom(
        name: name,
        presentation: RoomPresentation.text,
        encrypted: true,
      );
    }
  }
}

class _SpaceRail extends StatelessWidget {
  const _SpaceRail({required this.backend});
  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('mobile-space-rail'),
    width: 70,
    color: context.deltiecord.rail,
    child: Column(
      children: [
        const SizedBox(height: 8),
        _RailButton(
          selected: backend.selectedSpaceId == null,
          tooltip: 'Home',
          onTap: () => backend.selectSpace(null),
          attentionCount: backend.directUnreadCount,
          child: const Icon(Icons.home_rounded),
        ),
        const Divider(indent: 14, endIndent: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 84),
            children: [
              for (final space in backend.spaces)
                _RailButton(
                  selected: backend.selectedSpaceId == space.id,
                  tooltip: space.name,
                  onTap: () => backend.selectSpace(space.id),
                  onLongPress: () => _showSpaceActions(context, space),
                  attentionCount: backend.pingCountForSpace(space.id),
                  child: MobileAvatar(
                    bytes: space.avatarBytes,
                    fallback: space.name,
                    size: 54,
                    square: true,
                  ),
                ),
              _RailButton(
                key: const ValueKey('mobile-create-space'),
                tooltip: 'Create Space',
                onTap: () => _createSpace(context),
                child: const Icon(Icons.add),
              ),
              _RailButton(
                key: const ValueKey('mobile-discover-spaces'),
                tooltip: 'Discover Spaces',
                onTap: () => _discoverSpaces(context),
                child: const Icon(Icons.travel_explore),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _createSpace(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Space'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) await backend.createSpace(name: name);
  }

  Future<void> _showSpaceActions(
    BuildContext context,
    SpaceSummary space,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                space.muted
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(space.muted ? 'Unmute Space' : 'Mute Space'),
              onTap: () => Navigator.pop(sheetContext, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Space settings'),
              onTap: () => Navigator.pop(sheetContext, 'settings'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Server profile'),
              onTap: () => Navigator.pop(sheetContext, 'server-profile'),
            ),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Leave Space',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(sheetContext, 'leave'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'mute':
        await backend.setRoomMuted(space.id, !space.muted);
      case 'settings':
        await showSpaceSettings(context, backend, space, mobile: true);
      case 'server-profile':
        await showSpaceSettings(
          context,
          backend,
          space,
          mobile: true,
          openServerProfile: true,
        );
      case 'leave':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Leave ${space.name}?'),
            content: const Text(
              'Rooms inside the Space are not left automatically.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (confirmed == true) await backend.leaveRoom(space.id);
    }
  }

  // Retained temporarily for compatibility with older widget tests while the
  // multi-page settings surface replaces this dialog.
  // ignore: unused_element
  Future<void> _editSpace(BuildContext context, SpaceSummary space) async {
    final name = TextEditingController(text: space.name);
    final topic = TextEditingController(text: space.topic);
    var muted = space.muted;
    Uint8List? avatar;
    var removeAvatar = false;
    var openChannelManager = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Space settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Space name'),
                ),
                TextField(
                  controller: topic,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description / topic',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        final bytes = result?.files.single.bytes;
                        if (bytes != null) {
                          setDialogState(() {
                            avatar = bytes;
                            removeAvatar = false;
                          });
                        }
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose picture'),
                    ),
                    if (space.avatarBytes != null || avatar != null)
                      TextButton(
                        onPressed: () => setDialogState(() {
                          avatar = null;
                          removeAvatar = true;
                        }),
                        child: const Text('Remove picture'),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mute Space'),
                  value: muted,
                  onChanged: (value) => setDialogState(() => muted = value),
                ),
                if (backend.canManageSpaceChannelLayout(space.id))
                  ListTile(
                    key: const ValueKey('mobile-channel-management'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.reorder),
                    title: const Text('Manage channels and categories'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      openChannelManager = true;
                      Navigator.pop(dialogContext, false);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final newName = name.text.trim();
    final newTopic = topic.text.trim();
    name.dispose();
    topic.dispose();
    if (openChannelManager) {
      if (context.mounted) await showMobileChannelManager(context, backend);
      return;
    }
    if (save != true) return;
    if (newName.isNotEmpty && newName != space.name) {
      await backend.renameRoom(space.id, newName);
    }
    if (newTopic != space.topic) {
      await backend.setRoomTopic(space.id, newTopic);
    }
    if (avatar != null || removeAvatar) {
      await backend.setRoomAvatar(space.id, avatar);
    }
    if (muted != space.muted) await backend.setRoomMuted(space.id, muted);
  }

  Future<void> _discoverSpaces(BuildContext context) async {
    final controller = TextEditingController();
    var results = const <SpaceDirectoryEntry>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Discover Spaces'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: (query) async {
                    final found = await backend.searchPublicSpaces(query);
                    setState(() => results = found);
                  },
                ),
                for (final result in results)
                  ListTile(
                    title: Text(result.name),
                    subtitle: Text('${result.memberCount} members'),
                    onTap: () async {
                      await backend.joinPublicSpace(result.roomId);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
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

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.onLongPress,
    this.attentionCount = 0,
    super.key,
  });
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final VoidCallback? onLongPress;
  final int attentionCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
    child: Tooltip(
      message: tooltip,
      child: Badge.count(
        key: ValueKey('mobile-rail-badge-$tooltip'),
        count: attentionCount.clamp(0, 999),
        isLabelVisible: attentionCount > 0,
        alignment: Alignment.topRight,
        offset: const Offset(-2, 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
        textColor: Theme.of(context).colorScheme.onPrimary,
        child: Material(
          key: ValueKey('mobile-rail-button-$tooltip'),
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : context.deltiecord.elevated,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox.square(dimension: 54, child: Center(child: child)),
          ),
        ),
      ),
    ),
  );
}

class _RoomList extends StatelessWidget {
  const _RoomList({required this.rooms, required this.onOpenRoom});
  final List<RoomSummary> rooms;
  final ValueChanged<RoomSummary> onOpenRoom;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const ValueKey('mobile-room-list'),
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 84),
    itemCount: rooms.length,
    itemBuilder: (context, index) {
      final room = rooms[index];
      final age = compactActivityAge(room.lastActivityAt);
      return ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        selected: false,
        leading: MobileAvatar(
          bytes: room.avatarBytes,
          fallback: room.name,
          presence: room.isDirect ? room.presence : null,
        ),
        title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          room.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.deltiecord.muted),
        ),
        trailing: room.unreadCount == 0 && age.isEmpty
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (room.unreadCount > 0)
                    Badge(
                      largeSize: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      label: Text(
                        '${room.unreadCount}',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  if (room.unreadCount > 0 && age.isNotEmpty)
                    const SizedBox(height: 2),
                  if (age.isNotEmpty)
                    Text(
                      age,
                      style: TextStyle(
                        color: context.deltiecord.muted,
                        fontSize: DeltiecordTypeScale.small,
                        height: 1.05,
                      ),
                    ),
                ],
              ),
        onTap: () => onOpenRoom(room),
      );
    },
  );
}

class _SpaceRoomList extends StatelessWidget {
  const _SpaceRoomList({
    required this.backend,
    required this.rooms,
    required this.onOpenRoom,
  });
  final ChatBackend backend;
  final List<RoomSummary> rooms;
  final ValueChanged<RoomSummary> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final room in rooms) room.id: room};
    final categorized = backend.selectedSpaceCategories
        .expand((category) => category.roomIds)
        .toSet();
    final children = <Widget>[];
    for (final category in backend.selectedSpaceCategories) {
      children.add(
        ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -3),
          minTileHeight: 36,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.deltiecord.muted,
                    fontSize: DeltiecordTypeScale.normal - 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                category.collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: context.deltiecord.muted,
              ),
            ],
          ),
          onTap: () => backend.setChannelCategoryCollapsed(
            category.id,
            !category.collapsed,
          ),
        ),
      );
      if (!category.collapsed) {
        for (final id in category.roomIds) {
          final room = byId[id];
          if (room != null) {
            children.add(
              _SpaceRoomTile(room: room, onTap: () => onOpenRoom(room)),
            );
          }
        }
      }
    }
    for (final room in rooms.where((room) => !categorized.contains(room.id))) {
      children.add(_SpaceRoomTile(room: room, onTap: () => onOpenRoom(room)));
    }
    return ListView(
      key: const ValueKey('mobile-space-room-list'),
      padding: const EdgeInsets.only(bottom: 84),
      children: children,
    );
  }
}

class _NavigationCardEdgePainter extends CustomPainter {
  const _NavigationCardEdgePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = DeltiecordCorners.radius;
    final path = Path()
      ..moveTo(radius, 0)
      ..quadraticBezierTo(0, 0, 0, radius)
      ..lineTo(0, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _NavigationCardEdgePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SpaceRoomTile extends StatelessWidget {
  const _SpaceRoomTile({required this.room, required this.onTap});
  final RoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: const VisualDensity(vertical: -3),
    minTileHeight: 40,
    leading: Icon(
      room.isVoice ? Icons.volume_up_outlined : Icons.tag,
      size: 21,
    ),
    title: Text(room.name),
    subtitle: room.isVoice && room.voiceParticipants.isNotEmpty
        ? Text(
            room.voiceParticipants.isEmpty
                ? 'Nobody connected'
                : '${room.voiceParticipants.length} connected',
          )
        : null,
    trailing: room.unreadCount == 0
        ? null
        : Badge(label: Text('${room.unreadCount}')),
    onTap: onTap,
  );
}

class _MobileUserIsland extends StatelessWidget {
  const _MobileUserIsland({
    required this.backend,
    required this.onOpenSettings,
    required this.onOpenProfile,
  });
  final ChatBackend backend;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      key: const ValueKey('mobile-user-island'),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.deltiecord.island,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onOpenProfile,
        onLongPress: () => showPresenceControls(context, backend),
        child: Row(
          children: [
            MobileAvatar(
              bytes: backend.profileAvatarBytes,
              fallback: backend.profileDisplayName ?? backend.userId ?? '?',
              presence: backend.profilePresence,
              size: 46,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    backend.profileDisplayName ?? backend.userId ?? 'Account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    backend.profileStatusMessage ??
                        mobilePresenceLabel(backend.profilePresence),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Mute',
              color: backend.voiceMuted ? Colors.redAccent : null,
              onPressed: () => backend.setVoiceMuted(!backend.voiceMuted),
              icon: Icon(backend.voiceMuted ? Icons.mic_off : Icons.mic),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
      ),
    ),
  );
}
