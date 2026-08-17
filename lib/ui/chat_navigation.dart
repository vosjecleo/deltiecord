part of 'chat_shell.dart';

class _SpaceBar extends StatelessWidget {
  const _SpaceBar({required this.backend});

  final ChatBackend backend;

  Future<void> _createSpace(BuildContext context) async {
    final name = TextEditingController();
    final topic = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Space'),
        content: SizedBox(
          width: 400,
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
                decoration: const InputDecoration(
                  labelText: 'Topic (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final spaceName = name.text.trim();
    final spaceTopic = topic.text.trim();
    name.dispose();
    topic.dispose();
    if (create == true && spaceName.isNotEmpty) {
      await backend.createSpace(name: spaceName, topic: spaceTopic);
    }
  }

  Future<void> _searchSpaces(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => _SpaceSearchDialog(backend: backend),
  );

  Future<void> _editSpace(BuildContext context, SpaceSummary space) async {
    final name = TextEditingController(text: space.name);
    final topic = TextEditingController(text: space.topic);
    Uint8List? avatar;
    var removeAvatar = false;
    final originalLayoutPowerLevel = backend.spaceChannelLayoutPowerLevel(
      space.id,
    );
    var layoutPowerLevel = originalLayoutPowerLevel;
    var muted = space.muted;
    final selectedSpace = backend.selectedSpaceId == space.id;
    final textRoomCount = selectedSpace
        ? backend.rooms.where((room) => !room.isVoice).length
        : null;
    final voiceRoomCount = selectedSpace
        ? backend.rooms.where((room) => room.isVoice).length
        : null;
    final categoryCount = selectedSpace
        ? backend.selectedSpaceCategories.length
        : null;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final previewAvatar = removeAvatar
              ? null
              : avatar ?? space.avatarBytes;
          final canSetLayoutPower = backend.canSetSpaceChannelLayoutPowerLevel(
            space.id,
          );
          return AlertDialog(
            title: Text('${space.name} settings'),
            content: SizedBox(
              width: 500,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: min(MediaQuery.sizeOf(context).height * 0.72, 650),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            key: const Key('space-settings-avatar-preview'),
                            radius: 34,
                            backgroundColor: context.deltiecord.elevated,
                            backgroundImage: previewAvatar == null
                                ? null
                                : MemoryImage(previewAvatar),
                            child: previewAvatar == null
                                ? Text(
                                    _initials(name.text),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                if (previewAvatar != null)
                                  TextButton(
                                    onPressed: () => setDialogState(() {
                                      avatar = null;
                                      removeAvatar = true;
                                    }),
                                    child: const Text('Remove picture'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('space-settings-name'),
                        controller: name,
                        autofocus: true,
                        maxLength: 255,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Space name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('space-settings-topic'),
                        controller: topic,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Description / topic',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'SPACE INFORMATION',
                        style: TextStyle(
                          color: context.deltiecord.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: DeltiecordTypeScale.small,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        space.id,
                        style: TextStyle(color: context.deltiecord.muted),
                      ),
                      if (textRoomCount != null &&
                          voiceRoomCount != null &&
                          categoryCount != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '$textRoomCount text rooms  •  '
                          '$voiceRoomCount voice rooms  •  '
                          '$categoryCount categories',
                          key: const Key('space-settings-room-summary'),
                          style: TextStyle(color: context.deltiecord.muted),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(
                              text: 'https://matrix.to/#/${space.id}',
                            ),
                          ),
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Copy Space link'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(),
                      SwitchListTile(
                        key: const Key('space-settings-muted'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mute Space'),
                        subtitle: const Text(
                          'Suppress desktop notifications from this Space.',
                        ),
                        value: muted,
                        onChanged: (value) =>
                            setDialogState(() => muted = value),
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Channel and category management',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            'Power level $layoutPowerLevel',
                            key: const Key('space-settings-layout-level'),
                            style: TextStyle(color: context.deltiecord.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Controls who may reorder rooms and manage '
                        'Deltiecord categories. The permission is synced '
                        'through Matrix room power levels.',
                        style: TextStyle(color: context.deltiecord.muted),
                      ),
                      Slider(
                        key: const Key('space-settings-layout-slider'),
                        value: layoutPowerLevel.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '$layoutPowerLevel',
                        onChanged: canSetLayoutPower
                            ? (value) => setDialogState(
                                () => layoutPowerLevel = value.round(),
                              )
                            : null,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Members (0)',
                              style: TextStyle(color: context.deltiecord.muted),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Moderators (50)',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: context.deltiecord.muted),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Admins (100)',
                              textAlign: TextAlign.end,
                              style: TextStyle(color: context.deltiecord.muted),
                            ),
                          ),
                        ],
                      ),
                      if (!canSetLayoutPower) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Your current power level cannot change this '
                          'permission.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: Navigator.of(context).pop,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save changes'),
              ),
            ],
          );
        },
      ),
    );
    final newName = name.text.trim();
    final newTopic = topic.text.trim();
    name.dispose();
    topic.dispose();
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
    if (layoutPowerLevel != originalLayoutPowerLevel) {
      await backend.setSpaceChannelLayoutPowerLevel(space.id, layoutPowerLevel);
    }
    if (muted != space.muted) {
      await backend.setRoomMuted(space.id, muted);
    }
  }

  Future<void> _confirmLeaveSpace(
    BuildContext context,
    SpaceSummary space,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave ${space.name}?'),
        content: const Text(
          'Rooms in the Space are not left automatically. You may need '
          'another invitation to rejoin the Space itself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave Space'),
          ),
        ],
      ),
    );
    if (confirmed == true) await backend.leaveRoom(space.id);
  }

  Future<void> _showSpaceNotificationSettings(
    BuildContext context,
    SpaceSummary space,
  ) async {
    final muted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${space.name} notifications'),
        content: RadioGroup<bool>(
          groupValue: space.muted,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(value: false, title: Text('Notify normally')),
              RadioListTile<bool>(value: true, title: Text('Mute Space')),
            ],
          ),
        ),
      ),
    );
    if (muted != null) await backend.setRoomMuted(space.id, muted);
  }

  Future<void> _showSpaceMenu(
    BuildContext context,
    SpaceSummary space,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & MediaQuery.sizeOf(context),
      ),
      items: [
        PopupMenuItem(
          value: 'mute',
          child: _RoomContextMenuEntry(
            icon: space.muted
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
            label: space.muted ? 'Unmute Space' : 'Mute Space',
          ),
        ),
        const PopupMenuItem(
          value: 'notifications',
          child: _RoomContextMenuEntry(
            icon: Icons.tune,
            label: 'Notification settings',
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: _RoomContextMenuEntry(
            icon: Icons.settings_outlined,
            label: 'Space settings',
          ),
        ),
        const PopupMenuItem(
          value: 'copy-link',
          child: _RoomContextMenuEntry(
            icon: Icons.link,
            label: 'Copy Space link',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: _RoomContextMenuEntry(
            icon: Icons.logout,
            label: 'Leave Space',
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'mute':
        await backend.setRoomMuted(space.id, !space.muted);
      case 'notifications':
        await _showSpaceNotificationSettings(context, space);
      case 'settings':
        await _editSpace(context, space);
      case 'copy-link':
        await Clipboard.setData(
          ClipboardData(text: 'https://matrix.to/#/${space.id}'),
        );
      case 'leave':
        await _confirmLeaveSpace(context, space);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.deltiecord.rail,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                vertical: _densityBetween(
                  backend.preferences.compactness,
                  roomy: 9,
                  compact: 5,
                ),
                horizontal: 8,
              ),
              children: [
                _SpaceButton(
                  tooltip: 'Home',
                  selected: backend.selectedSpaceId == null,
                  onTap: () => backend.selectSpace(null),
                  child: const Icon(Icons.home_filled, size: 21),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  child: Divider(height: 1),
                ),
                for (final space in backend.spaces)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: _densityBetween(
                        backend.preferences.compactness,
                        roomy: 8,
                        compact: 4,
                      ),
                    ),
                    child: _SpaceButton(
                      tooltip: space.name,
                      selected: backend.selectedSpaceId == space.id,
                      onTap: () => backend.selectSpace(space.id),
                      onSecondaryTapDown: (details) => _showSpaceMenu(
                        context,
                        space,
                        details.globalPosition,
                      ),
                      child: space.avatarBytes == null
                          ? Text(
                              _initials(space.name),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                fontSize: DeltiecordTypeScale.normal,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Image.memory(
                              space.avatarBytes!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                    ),
                  ),
                Padding(
                  key: const Key('create-space-panel'),
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: _SpaceButton(
                    tooltip: 'Create Space',
                    selected: false,
                    onTap: () => _createSpace(context),
                    child: const Icon(Icons.add, size: 25),
                  ),
                ),
                _SpaceButton(
                  tooltip: 'Search for Spaces',
                  selected: false,
                  onTap: () => _searchSpaces(context),
                  child: const Icon(Icons.travel_explore_outlined, size: 23),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

class _SpaceSearchDialog extends StatefulWidget {
  const _SpaceSearchDialog({required this.backend});

  final ChatBackend backend;

  @override
  State<_SpaceSearchDialog> createState() => _SpaceSearchDialogState();
}

class _SpaceSearchDialogState extends State<_SpaceSearchDialog> {
  final _query = TextEditingController();
  List<SpaceDirectoryEntry> _results = const [];
  bool _searching = false;
  String? _error;
  int _generation = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.backend.searchPublicSpaces(query);
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'The Space directory search failed.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _join(String roomId) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      await widget.backend.joinPublicSpace(roomId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = 'Deltiecord could not join that Space.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search for Spaces'),
    content: SizedBox(
      width: 520,
      height: 430,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Space name, #alias:server, or Matrix server',
              prefixIcon: const Icon(Icons.travel_explore_outlined),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _searching ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_error case final error?)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(error)),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty && !_searching
                ? const Center(
                    child: Text(
                      'No published Spaces found. Try #alias:server or a '
                      'Matrix server name; unpublished Spaces cannot be '
                      'discovered through Matrix directories.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final space = _results[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundImage: space.avatarBytes == null
                              ? null
                              : MemoryImage(space.avatarBytes!),
                          child: space.avatarBytes == null
                              ? const Icon(Icons.workspaces_outline, size: 18)
                              : null,
                        ),
                        title: Text(space.name),
                        subtitle: Text(
                          [
                            '${space.memberCount} members',
                            if (space.topic.trim().isNotEmpty) space.topic,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: _searching
                              ? null
                              : () => _join(space.roomId),
                          child: const Text('Join'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Close'),
      ),
    ],
  );
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
    this.onSecondaryTapDown,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Align(
        child: SizedBox.square(
          key: ValueKey('space-button-$tooltip'),
          dimension: 48,
          child: Material(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : context.deltiecord.elevated,
            borderRadius: DeltiecordCorners.borderRadius,
            clipBehavior: Clip.hardEdge,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: onSecondaryTapDown,
              child: InkWell(
                onTap: onTap,
                borderRadius: DeltiecordCorners.borderRadius,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomPanel extends StatefulWidget {
  const _RoomPanel({required this.backend});

  final ChatBackend backend;

  @override
  State<_RoomPanel> createState() => _RoomPanelState();
}

class _RoomPanelState extends State<_RoomPanel> {
  final _roomSearchController = TextEditingController();
  final _roomSearchTapGroup = Object();
  String _roomQuery = '';
  bool _roomSearchVisible = false;

  ChatBackend get backend => widget.backend;

  @override
  void dispose() {
    _roomSearchController.dispose();
    super.dispose();
  }

  Future<void> _createRoom(BuildContext context) async {
    final name = TextEditingController();
    final topic = TextEditingController();
    var presentation = RoomPresentation.text;
    var encrypted = true;
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            backend.selectedSpaceId == null
                ? 'Create chat room'
                : 'Create channel',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Room name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: topic,
                decoration: const InputDecoration(
                  labelText: 'Topic (optional)',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<RoomPresentation>(
                segments: const [
                  ButtonSegment(
                    value: RoomPresentation.text,
                    icon: Icon(Icons.tag),
                    label: Text('Text'),
                  ),
                  ButtonSegment(
                    value: RoomPresentation.voice,
                    icon: Icon(Icons.volume_up_outlined),
                    label: Text('Voice'),
                  ),
                ],
                selected: {presentation},
                onSelectionChanged: (selection) =>
                    setDialogState(() => presentation = selection.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End-to-end encryption'),
                subtitle: const Text('Cannot be disabled after creation.'),
                value: encrypted,
                onChanged: (value) => setDialogState(() => encrypted = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final roomName = name.text.trim();
    final roomTopic = topic.text.trim();
    name.dispose();
    topic.dispose();
    if (create == true && roomName.isNotEmpty) {
      await backend.createRoom(
        name: roomName,
        presentation: presentation,
        topic: roomTopic,
        encrypted: encrypted,
      );
    }
  }

  Future<void> _startDirectMessage(BuildContext context) async {
    final matrixId = await showDialog<String>(
      context: context,
      builder: (context) => const _StartDirectMessageDialog(),
    );
    if (matrixId != null && RegExp(r'^@[^:]+:.+$').hasMatch(matrixId)) {
      await backend.startDirectChat(matrixId);
    }
  }

  Future<void> _createCategory(BuildContext context) async {
    final controller = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (create == true && name.isNotEmpty) {
      await backend.createChannelCategory(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _roomQuery.trim().toLowerCase();
    final visibleRooms = query.isEmpty
        ? backend.rooms
        : backend.rooms
              .where(
                (room) =>
                    room.name.toLowerCase().contains(query) ||
                    room.topic.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final textRooms = visibleRooms.where((room) => !room.isVoice).toList();
    final voiceRooms = visibleRooms.where((room) => room.isVoice).toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_roomSearchVisible) {
            setState(() => _roomSearchVisible = false);
          }
        },
      },
      child: Focus(
        child: Material(
          color: context.deltiecord.panel,
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: context.deltiecord.surface,
                      border: Border(
                        bottom: BorderSide(color: context.deltiecord.divider),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            backend.selectedSpaceId == null
                                ? 'Home'
                                : backend.spaces
                                          .where(
                                            (space) =>
                                                space.id ==
                                                backend.selectedSpaceId,
                                          )
                                          .map((space) => space.name)
                                          .firstOrNull ??
                                      'Space',
                            style: const TextStyle(
                              fontSize: DeltiecordTypeScale.bigUi,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TapRegion(
                          groupId: _roomSearchTapGroup,
                          child: IconButton(
                            tooltip: backend.selectedSpaceId == null
                                ? 'Search direct messages and groups'
                                : 'Search rooms',
                            onPressed: () => setState(
                              () => _roomSearchVisible = !_roomSearchVisible,
                            ),
                            icon: Icon(
                              _roomSearchVisible ? Icons.close : Icons.search,
                              size: 19,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: backend.selectedSpaceId == null
                              ? 'Start chat or create room'
                              : 'Create room',
                          icon: const Icon(Icons.add, size: 20),
                          onSelected: (value) {
                            if (value == 'direct') _startDirectMessage(context);
                            if (value == 'room') _createRoom(context);
                            if (value == 'category') _createCategory(context);
                          },
                          itemBuilder: (context) => [
                            if (backend.selectedSpaceId == null)
                              const PopupMenuItem(
                                value: 'direct',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  title: Text('Start direct message'),
                                ),
                              ),
                            PopupMenuItem(
                              value: 'room',
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.add_comment_outlined),
                                title: Text(
                                  backend.selectedSpaceId == null
                                      ? 'Create group chat'
                                      : 'Create room',
                                ),
                              ),
                            ),
                            if (backend.selectedSpaceId case final spaceId?
                                when backend.canManageSpaceChannelLayout(
                                  spaceId,
                                ))
                              const PopupMenuItem(
                                value: 'category',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.create_new_folder_outlined,
                                  ),
                                  title: Text('Create category'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: visibleRooms.isEmpty
                        ? Center(
                            child: Text(
                              query.isEmpty
                                  ? 'No joined rooms'
                                  : 'No matching rooms',
                            ),
                          )
                        : backend.selectedSpaceId != null &&
                              backend.selectedSpaceCategories.isNotEmpty &&
                              query.isEmpty
                        ? _CategorizedRoomList(
                            backend: backend,
                            rooms: visibleRooms,
                          )
                        : ListView(
                            padding: EdgeInsets.symmetric(
                              vertical: _densityBetween(
                                backend.preferences.compactness,
                                roomy: 8,
                                compact: 3,
                              ),
                            ),
                            children: [
                              if (backend.selectedSpaceId != null &&
                                  textRooms.isNotEmpty)
                                const _RoomSectionLabel('TEXT ROOMS'),
                              for (final room in textRooms)
                                _RoomListTile(backend: backend, room: room),
                              if (voiceRooms.isNotEmpty)
                                const _RoomSectionLabel('VOICE ROOMS'),
                              for (final room in voiceRooms)
                                _RoomListTile(backend: backend, room: room),
                            ],
                          ),
                  ),
                  SizedBox(height: _bottomPanelHeightFor(context)),
                ],
              ),
              if (_roomSearchVisible)
                Positioned(
                  key: const Key('room-search-popup'),
                  top: 50,
                  left: 8,
                  right: 8,
                  child: TapRegion(
                    groupId: _roomSearchTapGroup,
                    onTapOutside: (_) =>
                        setState(() => _roomSearchVisible = false),
                    child: Material(
                      elevation: 12,
                      color: context.deltiecord.elevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: DeltiecordCorners.borderRadius,
                        side: BorderSide(color: context.deltiecord.divider),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            key: const Key('room-list-search'),
                            controller: _roomSearchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: backend.selectedSpaceId == null
                                  ? 'Search direct messages and groups'
                                  : 'Search rooms',
                              prefixIcon: const Icon(Icons.search, size: 17),
                              suffixIcon: _roomQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear room search',
                                      onPressed: () {
                                        _roomSearchController.clear();
                                        setState(() => _roomQuery = '');
                                      },
                                      icon: const Icon(Icons.close, size: 15),
                                    ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 6,
                              ),
                            ),
                            onChanged: (value) =>
                                setState(() => _roomQuery = value),
                            onSubmitted: (_) =>
                                setState(() => _roomSearchVisible = false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentUserPanel extends StatelessWidget {
  const _CurrentUserPanel({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('current-user-panel'),
    height: _bottomPanelHeightFor(context),
    child: ColoredBox(
      color: context.deltiecord.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: _bottomPanelVerticalInset,
        ),
        child: Material(
          key: const Key('current-user-island'),
          color: context.deltiecord.island,
          shape: RoundedRectangleBorder(
            borderRadius: DeltiecordCorners.borderRadius,
            side: const BorderSide(color: Colors.black, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showOwnProfile(context, backend),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: ClipOval(
                            child: backend.profileAvatarBytes == null
                                ? ColoredBox(
                                    color: context.deltiecord.elevated,
                                    child: const Icon(Icons.person, size: 19),
                                  )
                                : Image.memory(
                                    backend.profileAvatarBytes!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        Positioned(
                          left: -1,
                          bottom: -1,
                          child: Container(
                            key: ValueKey(
                              'current-user-presence-'
                              '${backend.profilePresence.name}',
                            ),
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: switch (backend.profilePresence) {
                                UserPresence.online => const Color(0xff43b581),
                                UserPresence.away => const Color(0xffffc857),
                                UserPresence.offline => const Color(0xff747680),
                              },
                              border: Border.all(
                                color: context.deltiecord.island,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          backend.profileDisplayName ??
                              backend.userId
                                  ?.split(':')
                                  .first
                                  .replaceFirst('@', '') ??
                              'Matrix account',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (backend.profileStatusMessage case final status?)
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.deltiecord.muted),
                          ),
                      ],
                    ),
                  ),
                  _UserControlButton(
                    tooltip: backend.voiceMuted ? 'Unmute' : 'Mute',
                    onPressed: () => backend.setVoiceMuted(!backend.voiceMuted),
                    icon: backend.voiceMuted ? Icons.mic_off : Icons.mic,
                    disabled: backend.voiceMuted,
                  ),
                  _UserControlButton(
                    tooltip: backend.voiceDeafened ? 'Undeafen' : 'Deafen',
                    onPressed: () =>
                        backend.setVoiceDeafened(!backend.voiceDeafened),
                    icon: backend.voiceDeafened
                        ? Icons.headset_off
                        : Icons.headphones,
                    disabled: backend.voiceDeafened,
                  ),
                  _UserControlButton(
                    tooltip: 'Settings',
                    onPressed: () => showDeltiecordSettings(context, backend),
                    icon: Icons.settings_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _UserControlButton extends StatelessWidget {
  const _UserControlButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.disabled = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final bool disabled;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 34,
    child: IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: disabled
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        backgroundColor: disabled
            ? Theme.of(context).colorScheme.error.withValues(alpha: 0.14)
            : Colors.transparent,
      ),
      icon: Icon(icon, size: 18),
    ),
  );
}

class _StartDirectMessageDialog extends StatefulWidget {
  const _StartDirectMessageDialog();

  @override
  State<_StartDirectMessageDialog> createState() =>
      _StartDirectMessageDialogState();
}

class _StartDirectMessageDialogState extends State<_StartDirectMessageDialog> {
  final _userIdController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_userIdController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start direct message'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('new-direct-message-id'),
          controller: _userIdController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Matrix ID',
            hintText: '@person:example.org',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Message')),
      ],
    );
  }
}

class _RoomSectionLabel extends StatelessWidget {
  const _RoomSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 9, 10, 3),
    child: Text(
      label,
      style: TextStyle(
        color: context.deltiecord.muted,
        fontSize: DeltiecordTypeScale.normal,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _CategorizedRoomList extends StatelessWidget {
  const _CategorizedRoomList({required this.backend, required this.rooms});

  final ChatBackend backend;
  final List<RoomSummary> rooms;

  @override
  Widget build(BuildContext context) {
    final categories = backend.selectedSpaceCategories;
    final selectedSpaceId = backend.selectedSpaceId;
    final canArrange =
        backend.preferences.enableChannelDragAndDrop &&
        selectedSpaceId != null &&
        backend.canManageSpaceChannelLayout(selectedSpaceId);
    final categorizedIds = categories
        .expand((category) => category.roomIds)
        .toSet();
    final ungrouped = rooms
        .where((room) => !categorizedIds.contains(room.id))
        .toList(growable: false);
    final sections = <Widget>[
      if (ungrouped.isNotEmpty)
        _ChannelCategorySection(
          key: const ValueKey('uncategorized-rooms'),
          backend: backend,
          name: 'CHANNELS',
          rooms: ungrouped,
          canArrange: canArrange,
        ),
      for (var index = 0; index < categories.length; index++)
        _ChannelCategorySection(
          key: ValueKey(categories[index].id),
          backend: backend,
          category: categories[index],
          name: categories[index].name,
          rooms: categories[index].roomIds
              .map((id) => rooms.where((room) => room.id == id).firstOrNull)
              .whereType<RoomSummary>()
              .toList(growable: false),
          canArrange: canArrange,
          categoryIndex: index,
          dragIndex: index + (ungrouped.isEmpty ? 0 : 1),
        ),
    ];
    return ReorderableListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        if (!canArrange) return;
        if (ungrouped.isNotEmpty) {
          if (oldIndex == 0 || newIndex == 0) return;
          oldIndex--;
          newIndex--;
        }
        if (oldIndex < 0 || oldIndex >= categories.length) return;
        backend.reorderChannelCategory(categories[oldIndex].id, newIndex);
      },
      children: sections,
    );
  }
}

class _ChannelCategorySection extends StatelessWidget {
  const _ChannelCategorySection({
    required super.key,
    required this.backend,
    required this.name,
    required this.rooms,
    required this.canArrange,
    this.category,
    this.categoryIndex,
    this.dragIndex,
  });

  final ChatBackend backend;
  final String name;
  final List<RoomSummary> rooms;
  final bool canArrange;
  final ChannelCategorySummary? category;
  final int? categoryIndex;
  final int? dragIndex;

  static const double _gripColumnWidth = 26;

  Future<void> _rename(BuildContext context) async {
    final current = category;
    if (current == null) return;
    final controller = TextEditingController(text: current.name);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = controller.text.trim();
    controller.dispose();
    if (save == true && value.isNotEmpty) {
      await backend.renameChannelCategory(current.id, value);
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final current = category;
    if (current == null || !canArrange) return;
    final screen = MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & screen,
      ),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: _RoomContextMenuEntry(
            icon: Icons.edit_outlined,
            label: 'Rename category',
          ),
        ),
        PopupMenuItem(
          value: 'up',
          enabled: (categoryIndex ?? 0) > 0,
          child: const _RoomContextMenuEntry(
            icon: Icons.arrow_upward,
            label: 'Move up',
          ),
        ),
        const PopupMenuItem(
          value: 'down',
          child: _RoomContextMenuEntry(
            icon: Icons.arrow_downward,
            label: 'Move down',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: _RoomContextMenuEntry(
            icon: Icons.delete_outline,
            label: 'Delete category',
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _rename(context);
      case 'up':
        await backend.reorderChannelCategory(
          current.id,
          max(0, (categoryIndex ?? 0) - 1),
        );
      case 'down':
        await backend.reorderChannelCategory(
          current.id,
          (categoryIndex ?? 0) + 1,
        );
      case 'delete':
        await backend.deleteChannelCategory(current.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = category;
    final collapsed = current?.collapsed ?? false;
    return DragTarget<RoomSummary>(
      onWillAcceptWithDetails: canArrange ? (_) => true : null,
      onAcceptWithDetails: canArrange
          ? (details) => backend.moveRoomInSpace(
              details.data.id,
              categoryId: current?.id,
            )
          : null,
      builder: (context, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: current == null ? 2 : 5, bottom: 1),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: current == null
                    ? null
                    : (details) =>
                          _showContextMenu(context, details.globalPosition),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      if (current != null && canArrange)
                        ReorderableDragStartListener(
                          index: dragIndex!,
                          child: SizedBox(
                            key: ValueKey('category-drag-grip-${current.id}'),
                            width: _gripColumnWidth,
                            height: 32,
                            child: Center(
                              child: Transform.translate(
                                offset: const Offset(0, 1),
                                child: const Icon(
                                  Icons.drag_indicator,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: _gripColumnWidth),
                      Expanded(
                        child: InkWell(
                          onTap: current == null
                              ? null
                              : () => backend.setChannelCategoryCollapsed(
                                  current.id,
                                  !collapsed,
                                ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                if (current != null) ...[
                                  Icon(
                                    collapsed
                                        ? Icons.arrow_right
                                        : Icons.arrow_drop_down,
                                    size: 17,
                                    color: context.deltiecord.muted,
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.deltiecord.muted,
                                      fontSize: DeltiecordTypeScale.normal,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
              ),
            ),
            if (!collapsed)
              for (final room in rooms)
                DragTarget<RoomSummary>(
                  onWillAcceptWithDetails: canArrange ? (_) => true : null,
                  onAcceptWithDetails: canArrange
                      ? (details) => backend.moveRoomInSpace(
                          details.data.id,
                          categoryId: current?.id,
                          beforeRoomId: room.id,
                        )
                      : null,
                  builder: (context, candidates, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      border: candidates.isEmpty
                          ? null
                          : Border(
                              top: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                    ),
                    child: _RoomListTile(
                      backend: backend,
                      room: room,
                      canArrange: canArrange,
                    ),
                  ),
                ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

class _RoomListTile extends StatelessWidget {
  const _RoomListTile({
    required this.backend,
    required this.room,
    this.canArrange,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final bool? canArrange;

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: room.name);
    final topic = TextEditingController(text: room.topic);
    var presentation = room.presentation;
    Uint8List? avatar;
    var removeAvatar = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Room settings'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: topic,
                  decoration: const InputDecoration(labelText: 'Topic'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SegmentedButton<RoomPresentation>(
                  segments: const [
                    ButtonSegment(
                      value: RoomPresentation.text,
                      icon: Icon(Icons.tag),
                      label: Text('Text'),
                    ),
                    ButtonSegment(
                      value: RoomPresentation.voice,
                      icon: Icon(Icons.volume_up_outlined),
                      label: Text('Voice'),
                    ),
                  ],
                  selected: {presentation},
                  onSelectionChanged: (value) =>
                      setDialogState(() => presentation = value.first),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose picture'),
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
                    ),
                    if (room.avatarBytes != null || avatar != null)
                      TextButton(
                        onPressed: () => setDialogState(() {
                          avatar = null;
                          removeAvatar = true;
                        }),
                        child: const Text('Remove picture'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = controller.text.trim();
    final roomTopic = topic.text.trim();
    controller.dispose();
    topic.dispose();
    if (save != true) return;
    if (name.isNotEmpty && name != room.name) {
      await backend.renameRoom(room.id, name);
    }
    if (roomTopic != room.topic) {
      await backend.setRoomTopic(room.id, roomTopic);
    }
    if (presentation != room.presentation) {
      await backend.setRoomPresentation(room.id, presentation);
    }
    if (avatar != null || removeAvatar) {
      await backend.setRoomAvatar(room.id, avatar);
    }
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave ${room.name}?'),
        content: const Text(
          'You may need another invitation to return to this room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave room'),
          ),
        ],
      ),
    );
    if (confirmed == true) await backend.leaveRoom(room.id);
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final screen = MediaQuery.sizeOf(context);
    final selectedSpaceId = backend.selectedSpaceId;
    final mayArrange =
        selectedSpaceId != null &&
        backend.canManageSpaceChannelLayout(selectedSpaceId);
    final spaceRooms = backend.selectedSpaceId == null
        ? const <RoomSummary>[]
        : backend.rooms;
    final roomIndex = spaceRooms.indexWhere(
      (candidate) => candidate.id == room.id,
    );
    final currentCategoryId = backend.selectedSpaceCategories
        .where((category) => category.roomIds.contains(room.id))
        .map((category) => category.id)
        .firstOrNull;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & screen,
      ),
      items: [
        PopupMenuItem(
          value: 'settings',
          child: _RoomContextMenuEntry(
            icon: Icons.edit_outlined,
            label: room.isDirect ? 'Edit DM name' : 'Room settings',
          ),
        ),
        if (backend.selectedRoom?.id == room.id)
          PopupMenuItem(
            value: 'mute',
            child: _RoomContextMenuEntry(
              icon: backend.selectedRoomMuted
                  ? Icons.notifications_outlined
                  : Icons.notifications_off_outlined,
              label: backend.selectedRoomMuted ? 'Unmute room' : 'Mute room',
            ),
          ),
        const PopupMenuItem(
          value: 'copy-link',
          child: _RoomContextMenuEntry(
            icon: Icons.link,
            label: 'Copy room link',
          ),
        ),
        if (mayArrange) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'move-up',
            enabled: roomIndex > 0,
            child: const _RoomContextMenuEntry(
              icon: Icons.arrow_upward,
              label: 'Move up',
            ),
          ),
          PopupMenuItem(
            value: 'move-down',
            enabled: roomIndex >= 0 && roomIndex < spaceRooms.length - 1,
            child: const _RoomContextMenuEntry(
              icon: Icons.arrow_downward,
              label: 'Move down',
            ),
          ),
          const PopupMenuItem(
            value: 'uncategorized',
            child: _RoomContextMenuEntry(
              icon: Icons.folder_off_outlined,
              label: 'Move out of category',
            ),
          ),
          for (final category in backend.selectedSpaceCategories)
            PopupMenuItem(
              value: 'category:${category.id}',
              child: _RoomContextMenuEntry(
                icon: Icons.folder_outlined,
                label: 'Move to ${category.name}',
              ),
            ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: _RoomContextMenuEntry(
            icon: Icons.logout,
            label: 'Leave room',
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'settings':
        await _edit(context);
      case 'mute':
        await backend.setSelectedRoomMuted(!backend.selectedRoomMuted);
      case 'copy-link':
        await Clipboard.setData(
          ClipboardData(text: 'https://matrix.to/#/${room.id}'),
        );
      case 'leave':
        await _confirmLeave(context);
      case 'move-up':
        if (roomIndex > 0) {
          await backend.moveRoomInSpace(
            room.id,
            categoryId: currentCategoryId,
            beforeRoomId: spaceRooms[roomIndex - 1].id,
          );
        }
      case 'move-down':
        if (roomIndex >= 0 && roomIndex < spaceRooms.length - 1) {
          await backend.moveRoomInSpace(
            room.id,
            categoryId: currentCategoryId,
            beforeRoomId: roomIndex + 2 < spaceRooms.length
                ? spaceRooms[roomIndex + 2].id
                : null,
          );
        }
      case 'uncategorized':
        await backend.moveRoomInSpace(room.id);
      default:
        if (action.startsWith('category:')) {
          await backend.moveRoomInSpace(
            room.id,
            categoryId: action.substring('category:'.length),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final participantCount = room.voiceParticipants.length;
    if (backend.selectedSpaceId == null && !room.isVoice) {
      return _HomeRoomListTile(
        backend: backend,
        room: room,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
      );
    }
    final compactness = backend.preferences.compactness;
    final selectedSpaceId = backend.selectedSpaceId;
    final mayArrange =
        canArrange ??
        (backend.preferences.enableChannelDragAndDrop &&
            selectedSpaceId != null &&
            backend.canManageSpaceChannelLayout(selectedSpaceId));
    Widget dragGrip() {
      final grip = SizedBox(
        key: ValueKey('room-drag-grip-${room.id}'),
        width: _ChannelCategorySection._gripColumnWidth,
        height: 32,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, 1),
            child: const Icon(Icons.drag_indicator, size: 16),
          ),
        ),
      );
      if (!mayArrange) return const SizedBox.shrink();
      return Draggable<RoomSummary>(
        data: room,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: context.deltiecord.elevated,
          shape: RoundedRectangleBorder(
            borderRadius: DeltiecordCorners.borderRadius,
          ),
          child: SizedBox(
            width: 220,
            child: ListTile(
              dense: true,
              leading: _RoomIcon(room: room, size: 24),
              title: Text(room.name),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: grip),
        child: grip,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity(vertical: -1 - (compactness * 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9),
        minVerticalPadding: 0,
        minLeadingWidth: 0,
        horizontalTitleGap: 8,
        selected: backend.selectedRoom?.id == room.id,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mayArrange) dragGrip(),
            _RoomIcon(room: room, size: 25),
          ],
        ),
        title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: room.isVoice
            ? participantCount == 0
                  ? null
                  : Text('$participantCount connected')
            : backend.selectedSpaceId == null
            ? Text(
                room.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: backend.selectedSpaceId == null && room.unreadCount > 0
            ? Badge(label: Text('${room.unreadCount}'))
            : null,
        onTap: () => backend.selectRoom(room.id),
      ),
    );
  }
}

class _RoomContextMenuEntry extends StatelessWidget {
  const _RoomContextMenuEntry({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    ),
  );
}

class _HomeRoomListTile extends StatelessWidget {
  const _HomeRoomListTile({
    required this.backend,
    required this.room,
    required this.onSecondaryTapDown,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final selected = backend.selectedRoom?.id == room.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Material(
        color: selected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.42)
            : Colors.transparent,
        child: InkWell(
          onTap: () => backend.selectRoom(room.id),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: _densityBetween(
                backend.preferences.compactness,
                roomy: 62,
                compact: 48,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                _densityBetween(
                  backend.preferences.compactness,
                  roomy: 6,
                  compact: 3,
                ),
                10,
                _densityBetween(
                  backend.preferences.compactness,
                  roomy: 6,
                  compact: 3,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _RoomIcon(room: room, size: 40, showPresence: room.isDirect),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: DeltiecordTypeScale.bigChat,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        SizedBox(
                          height: _densityBetween(
                            backend.preferences.compactness,
                            roomy: 6,
                            compact: 3,
                          ),
                        ),
                        Text(
                          room.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.deltiecord.muted,
                            fontSize: DeltiecordTypeScale.normal,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (room.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Badge(label: Text('${room.unreadCount}')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({
    required this.room,
    required this.size,
    this.showPresence = false,
  });

  final RoomSummary room;
  final double size;
  final bool showPresence;

  @override
  Widget build(BuildContext context) {
    if (room.isVoice) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.volume_up_outlined, size: 18),
      );
    }
    if (room.usesChannelIcon) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.tag, size: 18),
      );
    }
    final avatar = room.avatarBytes;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CircleAvatar(
              backgroundColor: context.deltiecord.elevated,
              backgroundImage: avatar == null ? null : MemoryImage(avatar),
              child: avatar == null
                  ? Text(
                      room.name.trim().isEmpty
                          ? '?'
                          : room.name.trim().characters.first.toUpperCase(),
                      style: TextStyle(
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
          if (showPresence)
            Positioned(
              left: -1,
              bottom: -1,
              child: Container(
                key: ValueKey('presence-${room.id}-${room.presence.name}'),
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (room.presence) {
                    UserPresence.online => const Color(0xff43b581),
                    UserPresence.away => const Color(0xffffc857),
                    UserPresence.offline => const Color(0xff747680),
                  },
                  border: Border.all(color: context.deltiecord.panel, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
