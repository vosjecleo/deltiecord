part of 'matrix_backend.dart';

extension _MatrixRoomMetadata on MatrixBackend {
  RoomSummary _roomSummary(Room room) => RoomSummary(
    id: room.id,
    name: room.getLocalizedDisplayname(),
    lastMessage: _eventPreview(room.lastEvent),
    lastActivityAt: room.lastEvent?.originServerTs,
    unreadCount: room.notificationCount,
    highlightCount: room.highlightCount,
    usesChannelIcon: _selectedSpaceId != null,
    presentation: _presentationFor(room),
    voiceParticipants: _voiceParticipants(room),
    avatarBytes: _avatarBytes[room.id],
    topic: room.topic,
    isDirect: room.isDirectChat,
    presence: _roomPresence(room),
    notificationMode: _notificationModeFor(room),
    mutedUntil: _temporaryRoomMutes[room.id],
    markedUnread: room.markedUnread,
  );

  UserPresence _roomPresence(Room room) {
    var result = UserPresence.offline;
    for (final user in room.getParticipants()) {
      if (user.id == _matrix.userID) continue;
      // Room summaries are synchronous; sync refreshes this SDK cache and
      // notifies the backend whenever presence changes.
      // ignore: deprecated_member_use
      switch (_matrix.presences[user.id]?.presence) {
        case PresenceType.online:
          return UserPresence.online;
        case PresenceType.unavailable:
          result = UserPresence.away;
        default:
          break;
      }
    }
    return result;
  }

  RoomPresentation _presentationFor(Room room) {
    final overridden = _roomPresentationOverrides[room.id];
    if (overridden != null) return overridden;
    final kind = room
        .getState(MatrixBackend._roomPresentationEventType)
        ?.content
        .tryGet<String>('kind');
    return kind == RoomPresentation.voice.name
        ? RoomPresentation.voice
        : RoomPresentation.text;
  }

  List<VoiceParticipantSummary> _voiceParticipants(Room room) {
    final memberStates = room.states[EventTypes.GroupCallMember];
    if (memberStates == null) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final participants = <String, VoiceParticipantSummary>{};
    for (final state in memberStates.values) {
      final memberships = state.content.tryGetList('memberships') ?? const [];
      final active = memberships.whereType<Map>().any((membership) {
        final expires = membership['expires_ts'];
        return expires is int && expires > now;
      });
      if (!active) continue;
      final userId = state.senderId;
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      participants[userId] = VoiceParticipantSummary(
        userId: userId,
        displayName: user.calcDisplayname(),
        avatarBytes:
            _senderAvatarBytes['${room.id}|$userId'] ??
            _senderAvatarBytes[userId],
        speaking:
            userId == _voice?.activeSpeakerUserId ||
            (userId == _matrix.userID &&
                !(_voice?.muted ?? true) &&
                (_voice?.inputLevel ?? 0) >= 0.04),
        localVolume: _voice?.participantVolume(userId) ?? 1,
        locallyMuted: _voice?.participantLocallyMuted(userId) ?? false,
      );
    }
    final result = participants.values.toList(growable: false);
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  String _eventPreview(Event? event) {
    if (event == null) return 'No messages yet';
    final decrypted = _decryptedPreviews[event.eventId];
    if (decrypted != null) return decrypted;
    if (event.type == EventTypes.Encrypted) return 'Encrypted message';
    if (event.type == PollEventContent.startType) return 'Poll';
    if (event.type == EventTypes.Sticker) return 'Sticker';
    if (event.type != EventTypes.Message) return 'Room activity';
    return _messagePreview(event);
  }

  String _messagePreview(Event event) => event.calcUnlocalizedBody(
    hideReply: true,
    hideEdit: true,
    plaintextBody: true,
  );

  Future<void> _refreshRoomMetadata() async {
    _roomMetadataRefreshRequested = true;
    if (_refreshingRoomMetadata || !_matrix.isLogged()) return;
    _refreshingRoomMetadata = true;
    var changed = false;
    try {
      do {
        _roomMetadataRefreshRequested = false;
        final joinedRooms = _joinedRooms;
        _roomHeroUsersLoaded.removeWhere(
          (roomId) => joinedRooms.every((room) => room.id != roomId),
        );
        // Prioritise the visible room so metadata work for a large account
        // cannot hold its timeline/avatar behind dozens of inactive rooms.
        final selectedRoomId = _selectedRoomId;
        final orderedRooms = selectedRoomId == null
            ? joinedRooms
            : [
                ...joinedRooms.where((room) => room.id == selectedRoomId),
                ...joinedRooms.where((room) => room.id != selectedRoomId),
              ];
        for (final room in orderedRooms) {
          try {
            await room.postLoad();
            // Matrix keeps room member state current through /sync. Loading
            // the same hero profiles from SQLite on every sync made metadata
            // refresh cost grow linearly with every room the user had opened.
            if (!room.isSpace && !_roomHeroUsersLoaded.contains(room.id)) {
              await room.loadHeroUsers();
              _roomHeroUsersLoaded.add(room.id);
            }
            changed = await _refreshAvatar(room) || changed;
            if (!room.isSpace) {
              changed = await _refreshPreview(room) || changed;
            }
          } catch (_) {
            // One unavailable avatar or key must not block the other rooms.
          }
        }
      } while (_roomMetadataRefreshRequested && _matrix.isLogged());
      // Native UnifiedPush notifications may arrive while Flutter is stopped.
      // Warm their private room-keyed avatar cache while Matrix media is
      // already available here; Space children deliberately inherit the
      // parent Space avatar for server-style notification grouping.
      final joinedRooms = _joinedRooms;
      final spaceAvatarByChildRoom = <String, Uint8List>{};
      for (final space in joinedRooms.where((room) => room.isSpace)) {
        final avatar = _avatarBytes[space.id];
        if (avatar == null) continue;
        for (final child in space.spaceChildren) {
          final roomId = child.roomId;
          if (roomId != null) {
            spaceAvatarByChildRoom.putIfAbsent(roomId, () => avatar);
          }
        }
      }
      for (final room in joinedRooms.where((room) => !room.isSpace)) {
        final notificationAvatar =
            spaceAvatarByChildRoom[room.id] ?? _avatarBytes[room.id];
        if (notificationAvatar != null) {
          _cacheNotificationAvatar(room.id, notificationAvatar);
        }
      }
    } finally {
      _refreshingRoomMetadata = false;
      if (changed) _notifyBackendListeners();
    }
  }

  void _cacheNotificationAvatar(String roomId, Uint8List avatar) {
    if (identical(_notificationAvatarBytes[roomId], avatar)) return;
    _notificationAvatarBytes[roomId] = avatar;
    unawaited(_notifications.cacheRoomAvatar(roomId, avatar));
  }

  Future<bool> _refreshAvatar(Room room) async {
    final avatar = room.avatar;
    if (_avatarUris.containsKey(room.id) &&
        _avatarUris[room.id] == avatar &&
        _avatarBytes[room.id] != null) {
      return false;
    }
    _avatarUris[room.id] = avatar;
    _avatarBytes.remove(room.id);
    if (avatar == null || !avatar.isScheme('mxc')) return true;
    final pooled = _avatarMediaPool.peek(avatar, AvatarMediaPool.rowDimension);
    final bytes =
        pooled ??
        await _avatarMedia(avatar, AvatarMediaPool.rowDimension) ??
        Uint8List(0);
    if (bytes.isNotEmpty) {
      _avatarBytes[room.id] = bytes;
      final directUserId = room.directChatMatrixID;
      if (directUserId != null) {
        final directAvatar = room
            .unsafeGetUserFromMemoryOrFallback(directUserId)
            .avatarUrl;
        if (directAvatar == avatar) {
          // The DM row and timeline use the same Matrix avatar. Seed the
          // sender cache immediately instead of decoding/downloading it again
          // when the conversation is opened.
          _senderAvatarUris[directUserId] = avatar;
          _senderAvatarBytes[directUserId] = bytes;
          _senderAvatarBytes['${room.id}|$directUserId'] = bytes;
        }
      }
    }
    return true;
  }

  Future<bool> _refreshPreview(Room room) async {
    final event = room.lastEvent;
    if (event == null) return false;
    if (event.type == EventTypes.Message) {
      final body = _messagePreview(event);
      if (_decryptedPreviews[event.eventId] == body) return false;
      _decryptedPreviews[event.eventId] = body;
      return true;
    }
    if (event.type != EventTypes.Encrypted || _matrix.encryption == null) {
      return false;
    }
    // Decryption is the expensive path and can touch the crypto database.
    // Event IDs are immutable, so a cached preview is authoritative even if
    // another sync caused a room-wide metadata pass.
    if (_decryptedPreviews.containsKey(event.eventId)) return false;
    final encrypted = event.parsedRoomEncryptedContent;
    final sessionId = encrypted.sessionId;
    final keyManager = _matrix.encryption!.keyManager;
    if (sessionId != null &&
        keyManager.enabled &&
        await keyManager.isCached()) {
      try {
        await keyManager.loadSingleKey(room.id, sessionId);
      } on MatrixException catch (exception) {
        if (exception.error != MatrixError.M_NOT_FOUND) rethrow;
      }
    }
    final decrypted = await _matrix.encryption!.decryptRoomEvent(event);
    if (decrypted.type != EventTypes.Message) return false;
    final body = _messagePreview(decrypted);
    if (_decryptedPreviews[event.eventId] == body) return false;
    _decryptedPreviews[event.eventId] = body;
    return true;
  }
}
