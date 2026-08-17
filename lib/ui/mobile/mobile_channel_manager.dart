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
  late Map<String, String?> _roomCategories;
  bool _saving = false;
  bool _dirty = false;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _rooms = List.of(backend.rooms);
    _categories = List.of(backend.selectedSpaceCategories);
    _roomCategories = {
      for (final room in _rooms) room.id: _initialCategoryFor(room.id),
    };
  }

  String? _initialCategoryFor(String roomId) {
    for (final category in _categories) {
      if (category.roomIds.contains(roomId)) return category.id;
    }
    return null;
  }

  String? _categoryFor(String roomId) {
    return _roomCategories[roomId];
  }

  void _reorderRoom(int oldIndex, int newIndex) {
    if (_saving) return;
    final next = List<RoomSummary>.of(_rooms);
    final room = next.removeAt(oldIndex);
    next.insert(newIndex, room);
    setState(() {
      _rooms = next;
      _dirty = true;
    });
  }

  void _reorderCategory(int oldIndex, int newIndex) {
    if (_saving) return;
    final next = List<ChannelCategorySummary>.of(_categories);
    final category = next.removeAt(oldIndex);
    next.insert(newIndex, category);
    setState(() {
      _categories = next;
      _dirty = true;
    });
  }

  void _moveToCategory(RoomSummary room, String? categoryId) {
    if (_saving) return;
    setState(() {
      _roomCategories[room.id] = categoryId;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    try {
      for (var index = 0; index < _categories.length; index++) {
        await backend.reorderChannelCategory(_categories[index].id, index);
      }
      // Work backwards so each room can be placed immediately before an
      // already-positioned successor without transiently disturbing it.
      for (var index = _rooms.length - 1; index >= 0; index--) {
        await backend.moveRoomInSpace(
          _rooms[index].id,
          categoryId: _categoryFor(_rooms[index].id),
          beforeRoomId: index + 1 < _rooms.length ? _rooms[index + 1].id : null,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save channel order: $error')),
      );
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
            )
          else
            IconButton(
              key: const ValueKey('confirm-mobile-channel-order'),
              tooltip: _dirty ? 'Save channel order' : 'No changes to save',
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.check),
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
                  buildDefaultDragHandles: false,
                  itemCount: _categories.length,
                  onReorderItem: _reorderCategory,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return ListTile(
                      key: ValueKey('category-${category.id}'),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator),
                      ),
                      title: Text(category.name),
                      subtitle: Text('${category.roomIds.length} rooms'),
                    );
                  },
                ),
                const Divider(height: 28),
                Text('Rooms', style: Theme.of(context).textTheme.titleMedium),
                const Text(
                  'Drag the handles to reorder, then tap the checkmark to '
                  'save. Assign a category below.',
                ),
                const SizedBox(height: 6),
                ReorderableListView.builder(
                  key: const ValueKey('mobile-room-order'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _rooms.length,
                  onReorderItem: _reorderRoom,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return ListTile(
                      key: ValueKey('room-${room.id}'),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator),
                      ),
                      title: Row(
                        children: [
                          Icon(
                            room.isVoice ? Icons.volume_up_outlined : Icons.tag,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(room.name)),
                        ],
                      ),
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
