import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';
import 'profile_card.dart';
import 'profile_editor_dialog.dart';

enum _SpaceSettingsPage { basic, channels, roles, pages, serverProfile }

Future<void> showSpaceSettings(
  BuildContext context,
  ChatBackend backend,
  SpaceSummary space, {
  bool mobile = false,
  bool openServerProfile = false,
}) async {
  backend.selectSpace(space.id);
  final content = _SpaceSettingsView(
    backend: backend,
    space: space,
    mobile: mobile,
    initialPage: openServerProfile
        ? _SpaceSettingsPage.serverProfile
        : _SpaceSettingsPage.basic,
  );
  if (mobile) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: content)));
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          Dialog(child: SizedBox(width: 920, height: 700, child: content)),
    );
  }
}

Future<bool> showSpacePages(
  BuildContext context,
  ChatBackend backend,
  String spaceId, {
  bool skipWhenEmpty = false,
}) async {
  final pages = await backend.getSpacePages(spaceId);
  if (skipWhenEmpty &&
      pages.welcome.trim().isEmpty &&
      pages.rules.trim().isEmpty) {
    return false;
  }
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 650,
        height: 620,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Welcome'),
                  Tab(text: 'Rules'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _SpacePageText(
                      text: pages.welcome,
                      empty: 'This Space has no welcome page yet.',
                    ),
                    _SpacePageText(
                      text: pages.rules,
                      empty: 'This Space has no rules page yet.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return true;
}

class _SpacePageText extends StatelessWidget {
  const _SpacePageText({required this.text, required this.empty});

  final String text;
  final String empty;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: SelectableText(text.trim().isEmpty ? empty : text),
  );
}

class _SpaceSettingsView extends StatefulWidget {
  const _SpaceSettingsView({
    required this.backend,
    required this.space,
    required this.mobile,
    required this.initialPage,
  });

  final ChatBackend backend;
  final SpaceSummary space;
  final bool mobile;
  final _SpaceSettingsPage initialPage;

  @override
  State<_SpaceSettingsView> createState() => _SpaceSettingsViewState();
}

class _SpaceSettingsViewState extends State<_SpaceSettingsView> {
  late _SpaceSettingsPage _page = widget.initialPage;
  late final TextEditingController _name = TextEditingController(
    text: widget.space.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.space.topic,
  );
  final _welcome = TextEditingController();
  final _rules = TextEditingController();
  Uint8List? _spaceAvatar;
  UserProfileSummary? _globalProfile;
  SpaceProfileOverride? _spaceProfileOverride;
  RoomNotificationMode _suggested = RoomNotificationMode.mentionsOnly;
  late bool _spaceMuted = widget.space.muted;
  late int _layoutPowerLevel = backend.spaceChannelLayoutPowerLevel(
    widget.space.id,
  );
  bool _loading = true;
  late bool _mobileMenu = widget.initialPage == _SpaceSettingsPage.basic;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pages = await backend.getSpacePages(widget.space.id);
    final profile = await backend.getSpaceProfileOverride(widget.space.id);
    final userId = backend.userId;
    final global = userId == null ? null : await backend.getUserProfile(userId);
    if (!mounted) return;
    setState(() {
      _welcome.text = pages.welcome;
      _rules.text = pages.rules;
      _suggested = pages.suggestedNotificationMode;
      _spaceProfileOverride = profile;
      _globalProfile = global;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _welcome.dispose();
    _rules.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigation = ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            widget.space.name,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        for (final page in _SpaceSettingsPage.values)
          ListTile(
            selected: _page == page,
            leading: Icon(_pageIcon(page)),
            title: Text(_pageLabel(page)),
            onTap: () => setState(() {
              _page = page;
              _mobileMenu = false;
            }),
          ),
      ],
    );
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(key: ValueKey(_page), child: _pageBody()),
          );
    if (widget.mobile) {
      return PopScope(
        canPop: _mobileMenu,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_mobileMenu) {
            setState(() => _mobileMenu = true);
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                leading: IconButton(
                  onPressed: () {
                    if (_mobileMenu) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _mobileMenu = true);
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Text(_mobileMenu ? 'Space settings' : _pageLabel(_page)),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(_mobileMenu ? -0.08 : 0.08, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                  child: _mobileMenu
                      ? KeyedSubtree(
                          key: const ValueKey('space-settings-menu'),
                          child: navigation,
                        )
                      : KeyedSubtree(
                          key: ValueKey('space-settings-${_page.name}'),
                          child: body,
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        SizedBox(width: 230, child: navigation),
        VerticalDivider(width: 1, color: context.deltiecord.divider),
        Expanded(child: body),
      ],
    );
  }

  Widget _pageBody() => switch (_page) {
    _SpaceSettingsPage.basic => _basic(),
    _SpaceSettingsPage.channels => _channels(),
    _SpaceSettingsPage.roles => _roles(),
    _SpaceSettingsPage.pages => _pages(),
    _SpaceSettingsPage.serverProfile => _serverProfile(),
  };

  Widget _section(String title, List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        ...children,
      ],
    ),
  );

  Widget _basic() => _section('Basic', [
    Center(
      child: CircleAvatar(
        key: const Key('space-settings-avatar-preview'),
        radius: 46,
        backgroundImage: (_spaceAvatar ?? widget.space.avatarBytes) == null
            ? null
            : MemoryImage(_spaceAvatar ?? widget.space.avatarBytes!),
        child: (_spaceAvatar ?? widget.space.avatarBytes) == null
            ? const Icon(Icons.hub_outlined, size: 36)
            : null,
      ),
    ),
    TextButton.icon(
      onPressed: () => _pickImage((bytes) => _spaceAvatar = bytes),
      icon: const Icon(Icons.image_outlined),
      label: const Text('Choose picture'),
    ),
    TextField(
      key: const Key('space-settings-name'),
      controller: _name,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    const SizedBox(height: 12),
    TextField(
      key: const Key('space-settings-topic'),
      controller: _description,
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Description'),
    ),
    const SizedBox(height: 12),
    Text(
      '${backend.rooms.where((room) => !room.isVoice).length} text rooms  •  '
      '${backend.rooms.where((room) => room.isVoice).length} voice rooms  •  '
      '${backend.selectedSpaceCategories.length} categories',
      key: const Key('space-settings-room-summary'),
      style: TextStyle(color: context.deltiecord.muted),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Clipboard.setData(
          ClipboardData(text: 'https://matrix.to/#/${widget.space.id}'),
        ),
        icon: const Icon(Icons.link),
        label: const Text('Copy Space link'),
      ),
    ),
    SwitchListTile(
      key: const Key('space-settings-muted'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Mute Space'),
      subtitle: const Text('Suppress notifications from this Space.'),
      value: _spaceMuted,
      onChanged: (value) => setState(() => _spaceMuted = value),
    ),
    Row(
      children: [
        const Expanded(
          child: Text(
            'Channel and category management',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text('Power level $_layoutPowerLevel'),
      ],
    ),
    Slider(
      key: const Key('space-settings-layout-slider'),
      value: _layoutPowerLevel.toDouble(),
      min: 0,
      max: 100,
      divisions: 100,
      label: '$_layoutPowerLevel',
      onChanged: backend.canSetSpaceChannelLayoutPowerLevel(widget.space.id)
          ? (value) => setState(() => _layoutPowerLevel = value.round())
          : null,
    ),
    const SizedBox(height: 18),
    FilledButton(onPressed: _saveBasic, child: const Text('Save changes')),
  ]);

  Widget _channels() {
    final rooms = {for (final room in backend.rooms) room.id: room};
    final categories = backend.selectedSpaceCategories;
    final canManage = backend.canManageSpaceChannelLayout(widget.space.id);
    return _section('Channels', [
      Text(
        'This uses the same interoperable Space order as the normal channel '
        'panel. ${canManage ? 'Drag the grips to move channels or categories. ' : ''}'
        'Arrow buttons remain available for keyboard and touch users.',
      ),
      const SizedBox(height: 12),
      for (
        var categoryIndex = 0;
        categoryIndex < categories.length;
        categoryIndex++
      ) ...[
        DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              canManage && details.data.startsWith('category:'),
          onAcceptWithDetails: (details) => backend.reorderChannelCategory(
            details.data.substring('category:'.length),
            categoryIndex,
          ),
          builder: (context, categoryCandidates, _) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: categoryCandidates.isEmpty
                  ? context.deltiecord.panel
                  : context.deltiecord.hover,
              borderRadius: DeltiecordCorners.borderRadius,
            ),
            child: DragTarget<String>(
              onWillAcceptWithDetails: (details) =>
                  canManage && details.data.startsWith('room:'),
              onAcceptWithDetails: (details) => backend.moveRoomInSpace(
                details.data.substring('room:'.length),
                categoryId: categories[categoryIndex].id,
              ),
              builder: (context, roomCandidates, _) => Column(
                children: [
                  _draggableCategoryHeader(
                    categories,
                    categoryIndex,
                    canManage,
                  ),
                  for (
                    var roomIndex = 0;
                    roomIndex < categories[categoryIndex].roomIds.length;
                    roomIndex++
                  )
                    if (rooms[categories[categoryIndex].roomIds[roomIndex]]
                        case final room?)
                      _draggableRoomTile(
                        room,
                        categories[categoryIndex],
                        roomIndex,
                        canManage,
                      ),
                  if (roomCandidates.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Move to ${categories[categoryIndex].name}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _draggableCategoryHeader(
    List<ChannelCategorySummary> categories,
    int index,
    bool canManage,
  ) {
    final category = categories[index];
    final tile = ListTile(
      dense: true,
      leading: canManage ? const Icon(Icons.drag_indicator) : null,
      title: Text(
        category.name.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: 'Move category up',
            onPressed: canManage && index > 0
                ? () => backend.reorderChannelCategory(category.id, index - 1)
                : null,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            tooltip: 'Move category down',
            onPressed: canManage && index < categories.length - 1
                ? () => backend.reorderChannelCategory(category.id, index + 1)
                : null,
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
        ],
      ),
    );
    if (!canManage) return tile;
    return LongPressDraggable<String>(
      data: 'category:${category.id}',
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(color: context.deltiecord.elevated),
            child: tile,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }

  Widget _draggableRoomTile(
    RoomSummary room,
    ChannelCategorySummary category,
    int index,
    bool canManage,
  ) {
    final tile = ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canManage) const Icon(Icons.drag_indicator, size: 18),
          Icon(room.isVoice ? Icons.volume_up : Icons.tag, size: 18),
        ],
      ),
      title: Text(room.name),
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: 'Move up',
            onPressed: canManage && index > 0
                ? () => backend.moveRoomInSpace(
                    room.id,
                    categoryId: category.id,
                    beforeRoomId: category.roomIds[index - 1],
                  )
                : null,
            icon: const Icon(Icons.arrow_upward, size: 17),
          ),
          IconButton(
            tooltip: 'Move down',
            onPressed: canManage && index < category.roomIds.length - 1
                ? () => backend.moveRoomInSpace(
                    room.id,
                    categoryId: category.id,
                    beforeRoomId: index + 2 < category.roomIds.length
                        ? category.roomIds[index + 2]
                        : null,
                  )
                : null,
            icon: const Icon(Icons.arrow_downward, size: 17),
          ),
        ],
      ),
    );
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          canManage &&
          details.data.startsWith('room:') &&
          details.data != 'room:${room.id}',
      onAcceptWithDetails: (details) => backend.moveRoomInSpace(
        details.data.substring('room:'.length),
        categoryId: category.id,
        beforeRoomId: room.id,
      ),
      builder: (context, candidates, _) => ColoredBox(
        color: candidates.isEmpty
            ? Colors.transparent
            : context.deltiecord.hover,
        child: tile,
      ),
    );
    if (!canManage) return target;
    return LongPressDraggable<String>(
      data: 'room:${room.id}',
      feedback: Material(
        color: context.deltiecord.elevated,
        child: SizedBox(width: 360, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: target),
      child: target,
    );
  }

  Widget _roles() => _section('Roles', const [
    Text(
      'Matrix power levels currently provide moderation permissions. Named '
      'Deltiecord roles are reserved for a future interoperable extension.',
    ),
  ]);

  Widget _pages() => _section('Pages', [
    TextField(
      controller: _welcome,
      minLines: 4,
      maxLines: 10,
      decoration: const InputDecoration(labelText: 'Welcome page'),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _rules,
      minLines: 4,
      maxLines: 10,
      decoration: const InputDecoration(labelText: 'Rules page'),
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<RoomNotificationMode>(
      initialValue: _suggested,
      decoration: const InputDecoration(labelText: 'Suggested notifications'),
      items: [
        for (final mode in RoomNotificationMode.values)
          DropdownMenuItem(value: mode, child: Text(_notificationLabel(mode))),
      ],
      onChanged: (value) => setState(() => _suggested = value ?? _suggested),
    ),
    const SizedBox(height: 18),
    FilledButton(onPressed: _savePages, child: const Text('Save pages')),
  ]);

  Widget _serverProfile() => _section('Server profile', [
    if (_globalProfile case final profile?) ...[
      DeltiecordProfileCard(profile: _effectiveServerProfile(profile)),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: () => _editServerProfile(profile),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit server profile'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _spaceProfileOverride == null
            ? null
            : () async {
                await backend.setSpaceProfileOverride(
                  SpaceProfileOverride(spaceId: widget.space.id),
                );
                await _reloadServerProfile();
              },
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset every field to general profile'),
      ),
    ] else
      const Center(child: CircularProgressIndicator()),
  ]);

  UserProfileSummary _effectiveServerProfile(UserProfileSummary global) {
    final override = _spaceProfileOverride;
    return UserProfileSummary(
      userId: global.userId,
      displayName: override?.nickname ?? global.displayName,
      avatarBytes: override?.avatarBytes ?? global.avatarBytes,
      bannerBytes: override?.bannerBytes ?? global.bannerBytes,
      presence: global.presence,
      bio: override?.bio ?? global.bio,
      pronouns: override?.pronouns ?? global.pronouns,
      timezone: override?.timezone ?? global.timezone,
      statusMessage: override?.statusMessage ?? global.statusMessage,
      profileColor: override?.accentColor ?? global.profileColor,
      profileColorSecondary:
          override?.accentColorSecondary ?? global.profileColorSecondary,
      voiceColor: override?.voiceColor ?? global.voiceColor,
      voiceBackgroundBytes:
          override?.voiceBackgroundBytes ?? global.voiceBackgroundBytes,
      extensibleFieldsSupported: global.extensibleFieldsSupported,
    );
  }

  Future<void> _editServerProfile(UserProfileSummary profile) async {
    final changed = await showSpaceProfileEditor(
      context,
      backend,
      profile,
      _spaceProfileOverride,
      widget.space.id,
    );
    if (changed) await _reloadServerProfile();
  }

  Future<void> _reloadServerProfile() async {
    final override = await backend.getSpaceProfileOverride(widget.space.id);
    if (mounted) setState(() => _spaceProfileOverride = override);
  }

  Future<void> _pickImage(ValueChanged<Uint8List> onPicked) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes != null && mounted) setState(() => onPicked(bytes));
  }

  Future<void> _saveBasic() async {
    final name = _name.text.trim();
    if (name.isNotEmpty && name != widget.space.name) {
      await backend.renameRoom(widget.space.id, name);
    }
    if (_description.text.trim() != widget.space.topic) {
      await backend.setRoomTopic(widget.space.id, _description.text.trim());
    }
    if (_spaceAvatar != null) {
      await backend.setRoomAvatar(widget.space.id, _spaceAvatar);
    }
    if (_spaceMuted != widget.space.muted) {
      await backend.setRoomMuted(widget.space.id, _spaceMuted);
    }
    if (_layoutPowerLevel !=
        backend.spaceChannelLayoutPowerLevel(widget.space.id)) {
      await backend.setSpaceChannelLayoutPowerLevel(
        widget.space.id,
        _layoutPowerLevel,
      );
    }
    _saved();
  }

  Future<void> _savePages() async {
    await backend.setSpacePages(
      widget.space.id,
      SpacePagesSummary(
        welcome: _welcome.text.trim(),
        rules: _rules.text.trim(),
        suggestedNotificationMode: _suggested,
      ),
    );
    _saved();
  }

  void _saved() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Space settings saved')));
  }
}

String _pageLabel(_SpaceSettingsPage page) => switch (page) {
  _SpaceSettingsPage.basic => 'Basic',
  _SpaceSettingsPage.channels => 'Channels',
  _SpaceSettingsPage.roles => 'Roles',
  _SpaceSettingsPage.pages => 'Pages',
  _SpaceSettingsPage.serverProfile => 'Server profile',
};

IconData _pageIcon(_SpaceSettingsPage page) => switch (page) {
  _SpaceSettingsPage.basic => Icons.tune,
  _SpaceSettingsPage.channels => Icons.format_list_bulleted,
  _SpaceSettingsPage.roles => Icons.badge_outlined,
  _SpaceSettingsPage.pages => Icons.article_outlined,
  _SpaceSettingsPage.serverProfile => Icons.person_outline,
};

String _notificationLabel(RoomNotificationMode mode) => switch (mode) {
  RoomNotificationMode.allMessages => 'All messages',
  RoomNotificationMode.mentionsOnly => 'Mentions only',
  RoomNotificationMode.muted => 'Muted',
};
