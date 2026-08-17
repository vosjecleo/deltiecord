import 'package:flutter/material.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';

Future<void> showMobileChannelManager(
  BuildContext context,
  ChatBackend backend,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _MobileChannelManager(backend: backend),
  ),
);

/// Touch-oriented editor for Deltiecord's interoperable Space ordering state.
///
/// The backend remains responsible for power-level enforcement and for writing
/// both Matrix Space child order and the namespaced category assignment state.
class _MobileChannelManager extends StatefulWidget {
  const _MobileChannelManager({required this.backend});

  final ChatBackend backend;

  @override
  State<_MobileChannelManager> createState() => _MobileChannelManagerState();
}

class _MobileChannelManagerState extends State<_MobileChannelManager> {
  late List<RoomSummary> _rooms;
  late List<ChannelCategorySummary> _categories;
  bool _saving = false;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _rooms = List.of(backend.rooms);
    _categories = List.of(backend.selectedSpaceCategories);
  }

  String? _categoryFor(String roomId) {
    for (final category in _categories) {
      if (category.roomIds.contains(roomId)) return category.id;
    }
    return null;
  }

  Future<void> _reorderRoom(int oldIndex, int newIndex) async {
    if (_saving) return;
    final next = List<RoomSummary>.of(_rooms);
    final room = next.removeAt(oldIndex);
    next.insert(newIndex, room);
    setState(() {
      _rooms = next;
      _saving = true;
    });
    try {
      final before = newIndex + 1 < next.length ? next[newIndex + 1].id : null;
      await backend.moveRoomInSpace(
        room.id,
        categoryId: _categoryFor(room.id),
        beforeRoomId: before,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reorderCategory(int oldIndex, int newIndex) async {
    if (_saving) return;
    final next = List<ChannelCategorySummary>.of(_categories);
    final category = next.removeAt(oldIndex);
    next.insert(newIndex, category);
    setState(() {
      _categories = next;
      _saving = true;
    });
    try {
      await backend.reorderChannelCategory(category.id, newIndex);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _moveToCategory(RoomSummary room, String? categoryId) async {
    setState(() => _saving = true);
    try {
      final index = _rooms.indexWhere((entry) => entry.id == room.id);
      final before = index >= 0 && index + 1 < _rooms.length
          ? _rooms[index + 1].id
          : null;
      await backend.moveRoomInSpace(
        room.id,
        categoryId: categoryId,
        beforeRoomId: before,
      );
      if (!mounted) return;
      setState(() {
        _categories = [
          for (final category in _categories)
            ChannelCategorySummary(
              id: category.id,
              name: category.name,
              collapsed: category.collapsed,
              roomIds: [
                for (final id in category.roomIds)
                  if (id != room.id) id,
                if (category.id == categoryId) room.id,
              ],
            ),
        ];
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spaceId = backend.selectedSpaceId;
    final permitted =
        spaceId != null && backend.canManageSpaceChannelLayout(spaceId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel management'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: !permitted
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your power level does not permit changing this Space layout.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                Text(
                  'Categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                ReorderableListView.builder(
                  key: const ValueKey('mobile-category-order'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  itemCount: _categories.length,
                  onReorderItem: _reorderCategory,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return ListTile(
                      key: ValueKey('category-${category.id}'),
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(category.name),
                      subtitle: Text('${category.roomIds.length} rooms'),
                    );
                  },
                ),
                const Divider(height: 28),
                Text('Rooms', style: Theme.of(context).textTheme.titleMedium),
                const Text(
                  'Hold the handle to reorder. Assign a category below.',
                ),
                const SizedBox(height: 6),
                ReorderableListView.builder(
                  key: const ValueKey('mobile-room-order'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  itemCount: _rooms.length,
                  onReorderItem: _reorderRoom,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return ListTile(
                      key: ValueKey('room-${room.id}'),
                      leading: Icon(
                        room.isVoice ? Icons.volume_up_outlined : Icons.tag,
                      ),
                      title: Text(room.name),
                      subtitle: DropdownButton<String?>(
                        value: _categoryFor(room.id),
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          for (final category in _categories)
                            DropdownMenuItem<String?>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => _moveToCategory(room, value),
                      ),
                    );
                  },
                ),
                const Divider(height: 28),
                Text(
                  'Required power level: '
                  '${backend.spaceChannelLayoutPowerLevel(spaceId)}',
                ),
                const Text(
                  'The default is Administrator (100). Space admins can '
                  'change this from the desktop Space settings.',
                ),
              ],
            ),
    );
  }
}
