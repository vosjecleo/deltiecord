import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../deltiecord_theme.dart';
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
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                _SpaceRail(backend: backend),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedSpace == null
                                    ? 'Home'
                                    : backend.spaces
                                              .where(
                                                (space) =>
                                                    space.id == selectedSpace,
                                              )
                                              .firstOrNull
                                              ?.name ??
                                          'Space',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('mobile-start-chat'),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          key: const ValueKey('mobile-room-search'),
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: selectedSpace == null
                                ? 'Search direct messages'
                                : 'Search rooms',
                            prefixIcon: const Icon(Icons.search, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
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
              ],
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
                  child: MobileAvatar(
                    bytes: space.avatarBytes,
                    fallback: space.name,
                    size: 46,
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
        await _editSpace(context, space);
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
    super.key,
  });
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
    child: Tooltip(
      message: tooltip,
      child: Material(
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
      return ListTile(
        minTileHeight: 64,
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
        ),
        trailing: room.unreadCount == 0
            ? null
            : Badge(label: Text('${room.unreadCount}')),
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
          title: Text(category.name.toUpperCase()),
          leading: Icon(
            category.collapsed ? Icons.chevron_right : Icons.expand_more,
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

class _SpaceRoomTile extends StatelessWidget {
  const _SpaceRoomTile({required this.room, required this.onTap});
  final RoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minTileHeight: 50,
    leading: Icon(
      room.isVoice ? Icons.volume_up_outlined : Icons.tag,
      size: 21,
    ),
    title: Text(room.name),
    subtitle: room.isVoice
        ? Text(
            room.voiceParticipants.isEmpty
                ? 'Nobody connected'
                : '${room.voiceParticipants.length} connected',
          )
        : room.lastMessage.isEmpty
        ? null
        : Text(room.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.deltiecord.elevated,
        border: Border.all(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onOpenProfile,
        child: Row(
          children: [
            MobileAvatar(
              bytes: backend.profileAvatarBytes,
              fallback: backend.profileDisplayName ?? backend.userId ?? '?',
              presence: backend.profilePresence,
              size: 42,
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
