part of 'matrix_backend.dart';

extension _MatrixRoomOperations on MatrixBackend {
  Map<String, dynamic> _spaceChannelLayout(String spaceId) {
    final override = _spaceChannelLayoutOverrides[spaceId];
    if (override != null) return Map.of(override);
    final content = _matrix
        .getRoomById(spaceId)
        ?.getState(MatrixBackend._spaceChannelsEventType)
        ?.content;
    return content == null ? <String, dynamic>{} : Map.of(content);
  }

  List<ChannelCategorySummary> _channelCategoriesFor(String? spaceId) {
    if (spaceId == null) return const [];
    final layout = _spaceChannelLayout(spaceId);
    final roomCategories = layout.tryGetMap<String, dynamic>('rooms') ?? {};
    final collapsed = _collapsedChannelCategories[spaceId] ?? const <String>{};
    return (layout.tryGetList('categories') ?? const [])
        .whereType<Map>()
        .map((raw) {
          final category = Map<String, dynamic>.from(raw);
          final id = category.tryGet<String>('id') ?? '';
          return ChannelCategorySummary(
            id: id,
            name: category.tryGet<String>('name') ?? 'Category',
            collapsed: collapsed.contains(id),
            roomIds: roomCategories.entries
                .where((entry) => entry.value == id)
                .map((entry) => entry.key)
                .toList(growable: false),
          );
        })
        .where((category) => category.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _writeSpaceChannelLayout(
    String spaceId,
    Map<String, dynamic> content,
  ) async {
    await _matrix.setRoomStateWithKey(
      spaceId,
      MatrixBackend._spaceChannelsEventType,
      '',
      {'version': 1, ...content},
    );
    // The SDK exposes newly-written state only after the next sync. Keep the
    // successful write visible immediately, then drop the override on sync.
    _spaceChannelLayoutOverrides[spaceId] = {'version': 1, ...content};
    _notifyBackendListeners();
  }

  Future<void> _createChannelCategory(String name) async {
    final spaceId = _selectedSpaceId;
    if (spaceId == null || name.trim().isEmpty) return;
    final layout = _spaceChannelLayout(spaceId);
    final categories = List<Map<String, dynamic>>.from(
      (layout.tryGetList('categories') ?? const []).map(
        (value) => Map<String, dynamic>.from(value as Map),
      ),
    );
    categories.add({
      'id': 'category-${DateTime.now().microsecondsSinceEpoch}',
      'name': name.trim(),
    });
    await _writeSpaceChannelLayout(spaceId, {
      ...layout,
      'categories': categories,
    });
  }

  Future<void> _renameChannelCategory(String categoryId, String name) async {
    final spaceId = _selectedSpaceId;
    if (spaceId == null || name.trim().isEmpty) return;
    final layout = _spaceChannelLayout(spaceId);
    final categories = (layout.tryGetList('categories') ?? const [])
        .map((raw) {
          final category = Map<String, dynamic>.from(raw as Map);
          if (category['id'] == categoryId) category['name'] = name.trim();
          return category;
        })
        .toList(growable: false);
    await _writeSpaceChannelLayout(spaceId, {
      ...layout,
      'categories': categories,
    });
  }

  Future<void> _deleteChannelCategory(String categoryId) async {
    final spaceId = _selectedSpaceId;
    if (spaceId == null) return;
    final layout = _spaceChannelLayout(spaceId);
    final categories = (layout.tryGetList('categories') ?? const [])
        .where((raw) => (raw as Map)['id'] != categoryId)
        .toList(growable: false);
    final rooms = Map<String, dynamic>.from(
      layout.tryGetMap<String, dynamic>('rooms') ?? const {},
    )..removeWhere((_, value) => value == categoryId);
    await _writeSpaceChannelLayout(spaceId, {
      ...layout,
      'categories': categories,
      'rooms': rooms,
    });
  }

  Future<void> _reorderChannelCategory(String categoryId, int newIndex) async {
    final spaceId = _selectedSpaceId;
    if (spaceId == null) return;
    final layout = _spaceChannelLayout(spaceId);
    final categories = List<dynamic>.from(
      layout.tryGetList('categories') ?? const [],
    );
    final oldIndex = categories.indexWhere(
      (raw) => (raw as Map)['id'] == categoryId,
    );
    if (oldIndex < 0) return;
    final category = categories.removeAt(oldIndex);
    categories.insert(newIndex.clamp(0, categories.length), category);
    await _writeSpaceChannelLayout(spaceId, {
      ...layout,
      'categories': categories,
    });
  }

  Future<void> _setChannelCategoryCollapsed(
    String categoryId,
    bool collapsed,
  ) async {
    final spaceId = _selectedSpaceId;
    if (spaceId == null) return;
    final values = _collapsedChannelCategories.putIfAbsent(spaceId, () => {});
    collapsed ? values.add(categoryId) : values.remove(categoryId);
    final existing =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    await _matrix.setAccountData(
      _matrix.userID!,
      MatrixBackend._settingsAccountDataType,
      {
        ...?existing,
        'collapsed_channel_categories': {
          for (final entry in _collapsedChannelCategories.entries)
            entry.key: entry.value.toList(growable: false),
        },
      },
    );
    _notifyBackendListeners();
  }

  Future<void> _moveRoomInSpace(
    String roomId, {
    String? categoryId,
    String? beforeRoomId,
  }) async {
    final spaceId = _selectedSpaceId;
    final space = spaceId == null ? null : _matrix.getRoomById(spaceId);
    if (spaceId == null || space == null) return;
    final ids = space.spaceChildren
        .map((child) => child.roomId)
        .whereType<String>()
        .where((id) => id != roomId)
        .toList();
    final insertion = beforeRoomId == null ? -1 : ids.indexOf(beforeRoomId);
    ids.insert(insertion < 0 ? ids.length : insertion, roomId);
    for (var index = 0; index < ids.length; index++) {
      await space.setSpaceChild(
        ids[index],
        order: index.toString().padLeft(6, '0'),
      );
    }
    _spaceRoomOrderOverrides[spaceId] = List.unmodifiable(ids);
    final layout = _spaceChannelLayout(spaceId);
    final rooms = Map<String, dynamic>.from(
      layout.tryGetMap<String, dynamic>('rooms') ?? const {},
    );
    if (categoryId == null) {
      rooms.remove(roomId);
    } else {
      rooms[roomId] = categoryId;
    }
    await _writeSpaceChannelLayout(spaceId, {...layout, 'rooms': rooms});
  }

  Future<List<SpaceDirectoryEntry>> _searchPublicSpaces(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty || !_matrix.isLogged()) return const [];
    try {
      String? directoryServer;
      var searchTerm = normalized;
      final alias = RegExp(r'^#[^:]*:([^\s]+)$').firstMatch(normalized);
      if (alias != null) {
        directoryServer = alias.group(1);
        searchTerm = normalized.substring(1, normalized.indexOf(':'));
      } else if (!normalized.contains(RegExp(r'\s')) &&
          normalized.contains('.') &&
          !normalized.startsWith('#')) {
        directoryServer = normalized;
        searchTerm = '';
      }

      Future<QueryPublicRoomsResponse> queryDirectory({
        required bool filterByType,
      }) => _matrix.queryPublicRooms(
        server: directoryServer,
        filter: PublicRoomQueryFilter(
          genericSearchTerm: searchTerm.isEmpty ? null : searchTerm,
          roomTypes: filterByType ? const ['m.space'] : null,
        ),
        limit: 30,
      );

      QueryPublicRoomsResponse response;
      try {
        try {
          response = await queryDirectory(filterByType: true);
        } catch (_) {
          // The room-type directory filter is newer than public-room search
          // and older Synapse deployments may reject it altogether.
          response = await queryDirectory(filterByType: false);
        }
      } catch (_) {
        if (alias == null) rethrow;
        response = QueryPublicRoomsResponse(chunk: const []);
      }
      if (response.chunk.isEmpty) {
        try {
          response = await queryDirectory(filterByType: false);
        } catch (_) {
          if (alias == null) rethrow;
        }
      }
      final entries = <SpaceDirectoryEntry>[];
      for (final room in response.chunk) {
        var isSpace = room.roomType == 'm.space';
        if (!isSpace && room.roomType == null) {
          try {
            await _matrix.getSpaceHierarchy(room.roomId, limit: 1, maxDepth: 0);
            isSpace = true;
          } catch (_) {
            // Ordinary public rooms do not belong in the Space picker.
          }
        }
        if (!isSpace) continue;
        entries.add(
          SpaceDirectoryEntry(
            roomId: room.roomId,
            name: room.name?.trim().isNotEmpty == true
                ? room.name!.trim()
                : room.canonicalAlias ?? room.roomId,
            memberCount: room.numJoinedMembers,
            topic: room.topic ?? '',
            avatarBytes: await _profileMedia(room.avatarUrl, 96, 96),
          ),
        );
      }
      if (entries.isEmpty && alias != null) {
        // Exact aliases can still be resolved when a Space is joinable but its
        // owner has not published it in the server's room directory.
        try {
          final resolved = await _matrix.getRoomIdByAlias(normalized);
          final roomId = resolved.roomId;
          if (roomId == null) return entries;
          final hierarchy = await _matrix.getSpaceHierarchy(
            roomId,
            limit: 1,
            maxDepth: 0,
          );
          final root = hierarchy.rooms
              .where((room) => room.roomId == roomId)
              .firstOrNull;
          if (root != null && root.roomType == 'm.space') {
            entries.add(
              SpaceDirectoryEntry(
                roomId: root.roomId,
                name: root.name?.trim().isNotEmpty == true
                    ? root.name!.trim()
                    : normalized,
                memberCount: root.numJoinedMembers,
                topic: root.topic ?? '',
                avatarBytes: await _profileMedia(root.avatarUrl, 96, 96),
              ),
            );
          }
        } catch (_) {
          // The no-results explanation in the picker covers unpublished or
          // inaccessible aliases without turning it into an application error.
        }
      }
      return entries;
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _joinPublicSpace(String roomId) async {
    try {
      final joinedRoomId = await _matrix.joinRoom(roomId);
      _selectSpace(joinedRoomId);
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  void _selectSpace(String? spaceId) {
    if (_selectedSpaceId == spaceId) return;
    _selectedSpaceId = spaceId;
    _selectedRoomId = null;
    _closeTimeline();
    _notifyBackendListeners();
  }

  Future<void> _selectRoom(String roomId) async {
    if (_selectedRoomId == roomId && _timeline != null) return;
    _cacheCurrentRoomMessages();
    await _closeTimeline();
    final generation = _timelineGeneration;
    _selectedRoomId = roomId;
    _timelineLoading = true;
    _error = null;
    _notifyBackendListeners();
    try {
      final room = _matrix.getRoomById(roomId);
      if (room == null) throw StateError('That room is no longer available.');
      await room.postLoad();
      if (_presentationFor(room) == RoomPresentation.voice) {
        _timelineLoading = false;
        _notifyBackendListeners();
        return;
      }
      await _loadRoomBackupKeys(room);
      if (!_isCurrentSelection(roomId, generation)) return;
      final timeline = await room.getTimeline(
        onUpdate: () => _onTimelineUpdate(generation),
        limit: _preferences.timelineChunkSize,
      );
      if (!_isCurrentSelection(roomId, generation)) {
        timeline.cancelSubscriptions();
        return;
      }
      _timeline = timeline;
      _timelineDatabaseOffset = timeline.events.length;
      _captureFirstUnread(room, timeline);
      await _decryptTimelineEvents(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
      _roomMessageCache[roomId] = List.unmodifiable(_mappedMessages);
      _timelineLoading = false;
      _notifyBackendListeners();
      unawaited(_hydrateCurrentTimeline(timeline, generation));
      timeline.requestKeys(tryOnlineBackup: true, onlineKeyBackupOnly: false);
      unawaited(_markSelectedRoomRead());
    } catch (exception) {
      if (_isCurrentSelection(roomId, generation)) {
        _error = _friendlyError(exception);
      }
    } finally {
      if (_isCurrentSelection(roomId, generation)) {
        _timelineLoading = false;
        _notifyBackendListeners();
      }
    }
  }

  Future<void> _jumpToPresent() async {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    await _closeTimeline();
    await _selectRoom(roomId);
  }

  Future<void> _jumpToEvent(String eventId) async {
    final roomId = _selectedRoomId;
    final room = _matrix.getRoomById(roomId ?? '');
    if (room == null) return;
    await _closeTimeline();
    final generation = _timelineGeneration;
    _timelineLoading = true;
    _notifyBackendListeners();
    try {
      final timeline = await room.getTimeline(
        eventContextId: eventId,
        limit: _preferences.timelineChunkSize,
        onUpdate: () => _onTimelineUpdate(generation),
      );
      if (!_isCurrentSelection(room.id, generation)) {
        timeline.cancelSubscriptions();
        return;
      }
      _timeline = timeline;
      _timelineDatabaseOffset = timeline.events.length;
      _timelineDatabaseExhausted = true;
      await _decryptTimelineEvents(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
      await _hydrateTimelineMetadata(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
    } catch (exception) {
      if (_isCurrentSelection(room.id, generation)) {
        _error = _friendlyError(exception);
      }
    } finally {
      if (_isCurrentSelection(room.id, generation)) {
        _timelineLoading = false;
        _notifyBackendListeners();
      }
    }
  }

  Future<void> _setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await _matrix.setRoomStateWithKey(
        room.id,
        MatrixBackend._roomPresentationEventType,
        '',
        {'kind': presentation.name},
      );
      _roomPresentationOverrides[roomId] = presentation;
      if (roomId == _selectedRoomId) {
        await _closeTimeline();
        _selectedRoomId = null;
        await selectRoom(roomId);
      }
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _createRoom({
    required String name,
    required RoomPresentation presentation,
    required String topic,
    required bool encrypted,
  }) async {
    _error = null;
    try {
      final roomId = await _matrix.createRoom(
        name: name.trim(),
        preset: CreateRoomPreset.privateChat,
        visibility: Visibility.private,
        topic: topic.trim().isEmpty ? null : topic.trim(),
        initialState: encrypted
            ? [
                StateEvent(
                  type: EventTypes.Encryption,
                  stateKey: '',
                  content: {'algorithm': 'm.megolm.v1.aes-sha2'},
                ),
              ]
            : null,
      );
      await _matrix.waitForRoomInSync(roomId, join: true);
      final room = _matrix.getRoomById(roomId);
      if (room == null) {
        throw StateError('The new room did not arrive in sync.');
      }
      if (_selectedSpaceId case final spaceId?) {
        await _matrix.getRoomById(spaceId)?.setSpaceChild(roomId);
      }
      await setRoomPresentation(roomId, presentation);
      await selectRoom(roomId);
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  Future<void> _createSpace({
    required String name,
    required String topic,
  }) async {
    try {
      final roomId = await _matrix.createSpace(
        name: name.trim(),
        topic: topic.trim().isEmpty ? null : topic.trim(),
        visibility: Visibility.private,
        waitForSync: true,
      );
      _selectSpace(roomId);
      unawaited(_refreshRoomMetadata());
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _renameRoom(String roomId, String name) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null || name.trim().isEmpty) return;
    try {
      await room.setName(name.trim());
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  Future<void> _setRoomTopic(String roomId, String topic) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await room.setDescription(topic.trim());
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _setRoomAvatar(String roomId, Uint8List? bytes) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await room.setAvatar(
        bytes == null
            ? null
            : MatrixFile(bytes: bytes, name: 'room-avatar.png'),
      );
      _avatarUris.remove(roomId);
      await _refreshAvatar(room);
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _leaveRoom(String roomId) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      if (_voice?.activeRoomId == roomId) await _leaveVoiceRoom();
      await room.leave();
      if (_selectedRoomId == roomId) {
        _selectedRoomId = null;
        await _closeTimeline();
      }
      unawaited(_refreshRoomMetadata());
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _setMemberPowerLevel(String userId, int powerLevel) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) throw StateError('No room is selected.');
    final member = room.unsafeGetUserFromMemoryOrFallback(userId);
    if (!room.canChangePowerLevel || member.powerLevel >= room.ownPowerLevel) {
      throw StateError('You do not have permission to change this member.');
    }
    if (powerLevel > room.ownPowerLevel.level) {
      throw StateError('You cannot grant a power level above your own.');
    }
    try {
      await room.setPower(userId, powerLevel.clamp(0, 100));
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _setSelectedRoomMuted(bool muted) async {
    await _setRoomMuted(_selectedRoomId ?? '', muted);
  }

  Future<void> _setRoomMuted(String roomId, bool muted) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) return;
    try {
      await room.setPushRuleState(
        muted ? PushRuleState.dontNotify : PushRuleState.notify,
      );
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  void _captureFirstUnread(Room room, Timeline timeline) {
    if (!room.hasNewMessages) {
      _firstUnreadEventIds[room.id] = null;
      return;
    }
    final markerId =
        room.receiptState.global.latestOwnReceipt?.eventId ??
        (room.fullyRead.isEmpty ? null : room.fullyRead);
    final markerIndex = markerId == null
        ? timeline.events.length
        : timeline.events.indexWhere((event) => event.eventId == markerId);
    final oldestUnreadIndex = markerIndex <= 0
        ? null
        : markerIndex > timeline.events.length
        ? timeline.events.length - 1
        : markerIndex - 1;
    _firstUnreadEventIds[room.id] = oldestUnreadIndex == null
        ? null
        : timeline.events[oldestUnreadIndex].eventId;
  }
}
