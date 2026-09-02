part of 'matrix_backend.dart';

enum _MemberModerationAction { kick, ban, unban }

extension _MatrixAdvancedFeatures on MatrixBackend {
  RoomNotificationMode _notificationModeFor(Room? room) =>
      switch (room?.pushRuleState) {
        PushRuleState.mentionsOnly => RoomNotificationMode.mentionsOnly,
        PushRuleState.dontNotify => RoomNotificationMode.muted,
        _ => RoomNotificationMode.allMessages,
      };

  void _loadAdvancedAccountData() {
    final bookmarkContent =
        _matrix.accountData[MatrixBackend._bookmarksAccountDataType]?.content;
    _bookmarkedEventIds
      ..clear()
      ..addAll(
        (bookmarkContent?.tryGetList('event_ids') ?? const [])
            .whereType<String>(),
      );
    final settings =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    _presenceMode =
        PresenceMode.values
            .where((mode) => mode.name == settings?['presence_mode'])
            .firstOrNull ??
        PresenceMode.online;
    _temporaryRoomMutes.clear();
    _temporaryRoomMuteRestoreModes.clear();
    for (final entry
        in (settings?.tryGetMap<String, Object?>('temporary_room_mutes') ??
                const {})
            .entries) {
      final value = entry.value;
      final map = value is Map ? Map<String, Object?>.from(value) : null;
      final until = DateTime.tryParse('${map?['until'] ?? value}')?.toUtc();
      if (until == null) continue;
      _temporaryRoomMutes[entry.key] = until;
      _temporaryRoomMuteRestoreModes[entry.key] =
          RoomNotificationMode.values
              .where((mode) => mode.name == map?['restore_mode'])
              .firstOrNull ??
          RoomNotificationMode.allMessages;
    }
    _expireTemporaryRoomMutes();
  }

  Future<void> _initializeScheduledMessages() async {
    await _scheduledMessageStore.initialize();
    _scheduleNextQueuedMessage();
    unawaited(_sendDueScheduledMessages());
  }

  void _scheduleNextQueuedMessage() {
    _scheduledMessageTimer?.cancel();
    _scheduledMessageTimer = null;
    final next = _scheduledMessageStore.messages.firstOrNull;
    if (next == null) return;
    final delay = next.sendAt.difference(DateTime.now().toUtc());
    _scheduledMessageTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_sendDueScheduledMessages()),
    );
  }

  Future<void> _sendDueScheduledMessages() async {
    if (!_matrix.isLogged() || _connectionStatus != ConnectionStatus.online) {
      // Connection restoration explicitly retries the queue. Rescheduling an
      // already-due entry here would create a zero-delay timer loop offline.
      return;
    }
    final now = DateTime.now().toUtc();
    for (final message in List.of(_scheduledMessageStore.messages)) {
      if (message.sendAt.isAfter(now)) break;
      try {
        await _sendMessage(
          message.body,
          roomId: message.roomId,
          replyToMessageId: message.replyToMessageId,
        );
        await _scheduledMessageStore.remove(message.id);
      } catch (_) {
        // Retain the entry; reconnect or the next launch retries it.
        break;
      }
    }
    _scheduleNextQueuedMessage();
    _notifyBackendListeners();
  }

  Future<void> _scheduleMessage(
    String text,
    DateTime sendAt, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    final body = text.trim();
    final targetRoomId = roomId ?? _selectedRoomId;
    final instant = sendAt.toUtc();
    if (body.isEmpty || targetRoomId == null) return;
    if (!instant.isAfter(DateTime.now().toUtc())) {
      await _sendMessage(
        body,
        roomId: targetRoomId,
        replyToMessageId: replyToMessageId,
      );
      return;
    }
    final id = _matrix.generateUniqueTransactionId();
    await _scheduledMessageStore.put(
      ScheduledMessageSummary(
        id: id,
        roomId: targetRoomId,
        body: body,
        sendAt: instant,
        replyToMessageId: replyToMessageId,
      ),
    );
    _scheduleNextQueuedMessage();
    _notifyBackendListeners();
  }

  Future<void> _cancelScheduledMessage(String id) async {
    await _scheduledMessageStore.remove(id);
    _scheduleNextQueuedMessage();
    _notifyBackendListeners();
  }

  Future<void> _setRoomNotificationMode(
    String roomId,
    RoomNotificationMode mode,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) return;
    await room.setPushRuleState(switch (mode) {
      RoomNotificationMode.allMessages => PushRuleState.notify,
      RoomNotificationMode.mentionsOnly => PushRuleState.mentionsOnly,
      RoomNotificationMode.muted => PushRuleState.dontNotify,
    });
    if (_temporaryRoomMutes.remove(roomId) != null) {
      _temporaryRoomMuteRestoreModes.remove(roomId);
      await _persistAdvancedSettings();
    }
    _notifyBackendListeners();
  }

  Future<void> _muteRoomUntil(String roomId, DateTime? until) async {
    if (until == null) {
      final removed = _temporaryRoomMutes.remove(roomId) != null;
      _temporaryRoomMuteRestoreModes.remove(roomId);
      await _setRoomNotificationMode(roomId, RoomNotificationMode.allMessages);
      if (removed) await _persistAdvancedSettings();
      return;
    }
    final room = _matrix.getRoomById(roomId);
    if (room == null) return;
    _temporaryRoomMuteRestoreModes.putIfAbsent(
      roomId,
      () => _notificationModeFor(room),
    );
    _temporaryRoomMutes[roomId] = until.toUtc();
    await room.setPushRuleState(PushRuleState.dontNotify);
    await _persistAdvancedSettings();
    _scheduleTemporaryMuteExpiry();
    _notifyBackendListeners();
  }

  void _scheduleTemporaryMuteExpiry() {
    _temporaryRoomMuteTimer?.cancel();
    _temporaryRoomMuteTimer = null;
    final futureMutes =
        _temporaryRoomMutes.values
            .where((until) => until.isAfter(DateTime.now().toUtc()))
            .toList()
          ..sort();
    final next = futureMutes.firstOrNull;
    if (next == null) return;
    _temporaryRoomMuteTimer = Timer(
      next.difference(DateTime.now().toUtc()),
      _expireTemporaryRoomMutes,
    );
  }

  void _expireTemporaryRoomMutes() {
    final now = DateTime.now().toUtc();
    final expired = _temporaryRoomMutes.entries
        .where((entry) => !entry.value.isAfter(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final roomId in expired) {
      _temporaryRoomMutes.remove(roomId);
      final restoreMode =
          _temporaryRoomMuteRestoreModes.remove(roomId) ??
          RoomNotificationMode.allMessages;
      final room = _matrix.getRoomById(roomId);
      if (room != null) {
        unawaited(
          room.setPushRuleState(switch (restoreMode) {
            RoomNotificationMode.allMessages => PushRuleState.notify,
            RoomNotificationMode.mentionsOnly => PushRuleState.mentionsOnly,
            RoomNotificationMode.muted => PushRuleState.notify,
          }),
        );
      }
    }
    if (expired.isNotEmpty) unawaited(_persistAdvancedSettings());
    _scheduleTemporaryMuteExpiry();
  }

  Future<void> _markRoomUnread(String roomId, bool unread) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) return;
    await room.markUnread(unread);
    if (unread && room.lastEvent != null) {
      _firstUnreadEventIds[room.id] = room.lastEvent!.eventId;
    } else if (!unread) {
      _firstUnreadEventIds[room.id] = null;
    }
    _notifyBackendListeners();
  }

  Future<void> _toggleMessagePinned(String messageId) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) return;
    final pins = room.pinnedEventIds.toList(growable: true);
    pins.contains(messageId) ? pins.remove(messageId) : pins.add(messageId);
    await room.setPinnedEvents(pins);
    _notifyBackendListeners();
  }

  Future<void> _toggleMessageBookmarked(String messageId) async {
    _bookmarkedEventIds.contains(messageId)
        ? _bookmarkedEventIds.remove(messageId)
        : _bookmarkedEventIds.add(messageId);
    final userId = _matrix.userID;
    if (userId == null) return;
    await _matrix.setAccountData(
      userId,
      MatrixBackend._bookmarksAccountDataType,
      {'event_ids': _bookmarkedEventIds.toList(growable: false)},
    );
    _notifyBackendListeners();
  }

  Future<void> _sendPoll(PollDraft draft, {String? roomId}) async {
    final question = draft.question.trim();
    final answers = draft.answers
        .map((answer) => answer.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    final room = _matrix.getRoomById(roomId ?? _selectedRoomId ?? '');
    if (room == null || question.isEmpty || answers.length < 2) {
      throw ArgumentError('A poll needs a question and at least two answers.');
    }
    await _prepareEncryptedSend(room);
    await room.startPoll(
      question: question,
      answers: [
        for (var index = 0; index < answers.length; index++)
          PollAnswer(id: 'deltiecord-${index + 1}', mText: answers[index]),
      ],
      kind: draft.disclosed ? PollKind.disclosed : PollKind.undisclosed,
      maxSelections: draft.maxSelections.clamp(1, answers.length),
    );
  }

  Future<void> _answerPoll(String messageId, List<String> answerIds) async {
    final event = _eventById(messageId);
    if (event == null || event.type != PollEventContent.startType) {
      throw StateError('That poll is no longer available.');
    }
    await _prepareEncryptedSend(event.room);
    await event.answerPoll(answerIds);
  }

  Future<void> _endPoll(String messageId) async {
    final event = _eventById(messageId);
    if (event == null || event.type != PollEventContent.startType) {
      throw StateError('That poll is no longer available.');
    }
    await event.endPoll();
  }

  Future<void> _sendSticker(StickerSummary sticker, {String? roomId}) async {
    final room = _matrix.getRoomById(roomId ?? _selectedRoomId ?? '');
    if (room == null) return;
    await _prepareEncryptedSend(room);
    await room.sendEvent({
      'body': sticker.body ?? sticker.name,
      'url': sticker.mxcUri.toString(),
      'info': {
        'mimetype': 'image/png',
        if (sticker.width != null) 'w': sticker.width,
        if (sticker.height != null) 'h': sticker.height,
      },
    }, type: EventTypes.Sticker);
  }

  Future<void> _refreshStickerPacks() async {
    final packs = <StickerPackSummary>[];
    void parsePack(String id, Map<String, Object?> content, bool roomScoped) {
      final images = content.tryGetMap<String, Object?>('images');
      if (images == null) return;
      final stickers = <StickerSummary>[];
      for (final entry in images.entries) {
        if (entry.value is! Map) continue;
        final item = Map<String, Object?>.from(entry.value as Map);
        final uri = Uri.tryParse('${item['url'] ?? ''}');
        if (uri == null || !uri.isScheme('mxc')) continue;
        final info = item.tryGetMap<String, Object?>('info');
        stickers.add(
          StickerSummary(
            id: entry.key,
            name: '${item['body'] ?? entry.key}',
            body: item['body'] as String?,
            mxcUri: uri,
            width: info?.tryGet<int>('w'),
            height: info?.tryGet<int>('h'),
          ),
        );
      }
      if (stickers.isEmpty) return;
      final pack = content.tryGetMap<String, Object?>('pack');
      packs.add(
        StickerPackSummary(
          id: id,
          name: pack?.tryGet<String>('display_name') ?? 'Stickers',
          stickers: stickers,
          roomScoped: roomScoped,
        ),
      );
    }

    final personal = _matrix.accountData['im.ponies.user_emotes']?.content;
    if (personal != null) parsePack('personal', personal, false);
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    final roomPacks = room?.states['im.ponies.room_emotes'];
    if (roomPacks != null) {
      for (final entry in roomPacks.entries) {
        parsePack('room:${entry.key}', entry.value.content, true);
      }
    }
    final hydrated = <StickerPackSummary>[];
    for (final pack in packs) {
      final stickers = <StickerSummary>[];
      for (final sticker in pack.stickers) {
        Uint8List? bytes;
        try {
          bytes = await _avatarMedia(
            sticker.mxcUri,
            AvatarMediaPool.profileDimension,
          );
        } catch (_) {
          // A missing preview must not make an otherwise valid pack unusable.
        }
        stickers.add(
          StickerSummary(
            id: sticker.id,
            name: sticker.name,
            mxcUri: sticker.mxcUri,
            body: sticker.body,
            width: sticker.width,
            height: sticker.height,
            previewBytes: bytes,
          ),
        );
      }
      hydrated.add(
        StickerPackSummary(
          id: pack.id,
          name: pack.name,
          stickers: stickers,
          roomScoped: pack.roomScoped,
        ),
      );
    }
    _stickerPacks = List.unmodifiable(hydrated);
    _notifyBackendListeners();
  }

  Future<void> _setPresenceMode(PresenceMode mode) async {
    final userId = _matrix.userID;
    if (userId == null) return;
    _presenceMode = mode;
    _profilePresence = switch (mode) {
      PresenceMode.online || PresenceMode.doNotDisturb => UserPresence.online,
      PresenceMode.idle => UserPresence.away,
      PresenceMode.invisible => UserPresence.offline,
    };
    await _matrix.setPresence(userId, switch (mode) {
      PresenceMode.online || PresenceMode.doNotDisturb => PresenceType.online,
      PresenceMode.idle => PresenceType.unavailable,
      PresenceMode.invisible => PresenceType.offline,
    }, statusMsg: _profileStatusMessage);
    await _persistAdvancedSettings();
    _notifyBackendListeners();
  }

  Future<void> _moderateMember(
    String userId,
    _MemberModerationAction action, {
    String? reason,
  }) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) throw StateError('No room is selected.');
    switch (action) {
      case _MemberModerationAction.kick:
        await _matrix.kick(room.id, userId, reason: reason);
      case _MemberModerationAction.ban:
        await _matrix.ban(room.id, userId, reason: reason);
      case _MemberModerationAction.unban:
        await room.unban(userId);
    }
  }

  Future<void> _timeoutMember(String userId, DateTime until) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) throw StateError('No room is selected.');
    final user = room.unsafeGetUserFromMemoryOrFallback(userId);
    final previousPowerLevel = user.powerLevel.level;
    final current = room
        .getState(MatrixBackend._roomTimeoutsEventType)
        ?.content
        .tryGetMap<String, Object?>('users');
    final updatedUsers = <String, Object?>{
      ...?current,
      userId: {
        'until': until.toUtc().toIso8601String(),
        'previous_power_level': previousPowerLevel,
      },
    };
    try {
      await _matrix.setRoomStateWithKey(
        room.id,
        MatrixBackend._roomTimeoutsEventType,
        '',
        {'users': updatedUsers},
      );
    } catch (_) {
      // Standard Matrix has no timeout primitive. The power-level restriction
      // still works; without permission for the namespaced restoration state,
      // this device must remain online to restore it at the requested time.
    }
    await room.setPower(userId, -1);
    final delay = until.toUtc().difference(DateTime.now().toUtc());
    final key = '${room.id}|$userId';
    _memberTimeoutTimers.remove(key)?.cancel();
    _memberTimeoutTimers[key] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(
        _restoreTimedOutMember(room.id, userId, previousPowerLevel),
      ),
    );
  }

  Future<void> _restoreExpiredMemberTimeouts() async {
    if (_restoringMemberTimeouts) return;
    _restoringMemberTimeouts = true;
    try {
      final now = DateTime.now().toUtc();
      for (final room in _matrix.rooms.where((room) => !room.isSpace)) {
        final users = room
            .getState(MatrixBackend._roomTimeoutsEventType)
            ?.content
            .tryGetMap<String, Object?>('users');
        if (users == null) continue;
        for (final entry in users.entries) {
          if (entry.value is! Map) continue;
          final value = Map<String, Object?>.from(entry.value as Map);
          final until = DateTime.tryParse('${value['until']}')?.toUtc();
          final previous = value['previous_power_level'];
          if (until == null || previous is! int) continue;
          if (!until.isAfter(now)) {
            await _restoreTimedOutMember(room.id, entry.key, previous);
          } else {
            final key = '${room.id}|${entry.key}';
            _memberTimeoutTimers.remove(key)?.cancel();
            _memberTimeoutTimers[key] = Timer(
              until.difference(now),
              () => unawaited(
                _restoreTimedOutMember(room.id, entry.key, previous),
              ),
            );
          }
        }
      }
    } finally {
      _restoringMemberTimeouts = false;
    }
  }

  Future<void> _restoreTimedOutMember(
    String roomId,
    String userId,
    int previousPowerLevel,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null || !_matrix.isLogged()) return;
    _memberTimeoutTimers.remove('$roomId|$userId')?.cancel();
    await room.setPower(userId, previousPowerLevel);
    final current = room
        .getState(MatrixBackend._roomTimeoutsEventType)
        ?.content
        .tryGetMap<String, Object?>('users');
    if (current == null || !current.containsKey(userId)) return;
    final updated = Map<String, Object?>.from(current)..remove(userId);
    try {
      await _matrix.setRoomStateWithKey(
        room.id,
        MatrixBackend._roomTimeoutsEventType,
        '',
        {'users': updated},
      );
    } catch (_) {
      // Restoration of the standard power level is the critical operation.
    }
  }

  Future<void> _inviteMember(String userId, {String? reason}) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) throw StateError('No room is selected.');
    await room.invite(userId, reason: reason);
  }

  Future<void> _acceptRoomInvite(String roomId) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That invitation is unavailable.');
    await room.join();
    await _selectRoom(room.id);
  }

  Future<void> _rejectRoomInvite(String roomId) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) return;
    await room.leave();
    _notifyBackendListeners();
  }

  Future<List<String>> _getRoomAliases(String roomId) =>
      _matrix.getLocalAliases(roomId);

  Future<void> _setRoomCanonicalAlias(String roomId, String? alias) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is unavailable.');
    final value = alias?.trim() ?? '';
    if (value.isEmpty) {
      await _matrix.setRoomStateWithKey(
        room.id,
        EventTypes.RoomCanonicalAlias,
        '',
        {'alias': ''},
      );
    } else {
      await room.setCanonicalAlias(value);
    }
  }

  Future<void> _requestDeviceVerification(String deviceId) async {
    await _matrix.userDeviceKeysLoading;
    final device = _matrix.userDeviceKeys[_matrix.userID]?.deviceKeys[deviceId];
    if (device == null) {
      throw StateError('Encryption keys for that device are unavailable.');
    }
    await device.startVerification();
  }

  Future<SpacePagesSummary> _getSpacePages(String spaceId) async {
    final event = _matrix
        .getRoomById(spaceId)
        ?.getState(MatrixBackend._spacePagesEventType);
    return SpacePagesSummary(
      welcome: event?.content.tryGet<String>('welcome') ?? '',
      rules: event?.content.tryGet<String>('rules') ?? '',
      suggestedNotificationMode:
          RoomNotificationMode.values
              .where(
                (mode) =>
                    mode.name ==
                    event?.content.tryGet<String>('suggested_notifications'),
              )
              .firstOrNull ??
          RoomNotificationMode.mentionsOnly,
    );
  }

  Future<void> _setSpacePages(String spaceId, SpacePagesSummary pages) async {
    await _matrix
        .setRoomStateWithKey(spaceId, MatrixBackend._spacePagesEventType, '', {
          'welcome': pages.welcome,
          'rules': pages.rules,
          'suggested_notifications': pages.suggestedNotificationMode.name,
        });
  }

  Future<SpaceProfileOverride?> _getSpaceProfileOverride(String spaceId) async {
    final userId = _matrix.userID;
    if (userId == null) return null;
    final memberContent = _matrix
        .getRoomById(spaceId)
        ?.getState(EventTypes.RoomMember, userId)
        ?.content;
    final legacy = _matrix
        .accountData[MatrixBackend._spaceProfileAccountDataType]
        ?.content
        .tryGetMap<String, Object?>(spaceId);
    final value = memberContent == null
        ? legacy
        : <String, Object?>{
            'nickname': memberContent['displayname'],
            'pronouns': memberContent['net.deltiecord.pronouns'],
            'avatar_url': memberContent['avatar_url'],
            'accent_color': memberContent['net.deltiecord.accent_color'],
          };
    if (value == null) return null;
    Uint8List? avatar;
    final avatarUri = Uri.tryParse(value.tryGet<String>('avatar_url') ?? '');
    if (avatarUri != null && avatarUri.isScheme('mxc')) {
      avatar = await _avatarMedia(avatarUri, AvatarMediaPool.profileDimension);
    }
    return SpaceProfileOverride(
      spaceId: spaceId,
      nickname: value.tryGet<String>('nickname'),
      pronouns: value.tryGet<String>('pronouns'),
      avatarBytes: avatar,
      accentColor: value.tryGet<int>('accent_color'),
    );
  }

  Future<void> _setSpaceProfileOverride(SpaceProfileOverride profile) async {
    final userId = _matrix.userID;
    if (userId == null) return;
    final current = _matrix
        .accountData[MatrixBackend._spaceProfileAccountDataType]
        ?.content;
    final previous = current?.tryGetMap<String, Object?>(profile.spaceId);
    Uri? avatarUri;
    if (profile.avatarBytes != null) {
      avatarUri = await _matrix.uploadContent(
        profile.avatarBytes!,
        filename: 'space-profile-avatar.png',
        contentType: 'image/png',
      );
    }
    final globalProfile = await _matrix.getProfileFromUserId(userId);
    final effectiveAvatarUri =
        avatarUri ??
        Uri.tryParse(previous?.tryGet<String>('avatar_url') ?? '') ??
        globalProfile.avatarUrl;
    final nickname = profile.nickname?.trim();
    final pronouns = profile.pronouns?.trim();
    final space = _matrix.getRoomById(profile.spaceId);
    if (space != null) {
      final targets = <Room>[
        space,
        ...space.spaceChildren
            .map((child) => _matrix.getRoomById(child.roomId ?? ''))
            .whereType<Room>()
            .where((room) => room.membership == Membership.join),
      ];
      for (final room in targets) {
        final existing = room.getState(EventTypes.RoomMember, userId)?.content;
        try {
          await _matrix
              .setRoomStateWithKey(room.id, EventTypes.RoomMember, userId, {
                ...?existing,
                'membership': 'join',
                'displayname': nickname?.isNotEmpty == true
                    ? nickname
                    : globalProfile.displayName,
                if (effectiveAvatarUri != null)
                  'avatar_url': effectiveAvatarUri.toString(),
                if (pronouns?.isNotEmpty == true)
                  'net.deltiecord.pronouns': pronouns
                else
                  'net.deltiecord.pronouns': null,
                if (profile.accentColor != null)
                  'net.deltiecord.accent_color': profile.accentColor,
              });
        } catch (_) {
          // A child room may restrict member-profile changes independently.
          // Continue applying the override to the remaining Space rooms.
        }
      }
    }
    await _matrix.setAccountData(
      userId,
      MatrixBackend._spaceProfileAccountDataType,
      {
        ...?current,
        profile.spaceId: {
          if (nickname?.isNotEmpty == true) 'nickname': nickname,
          if (pronouns?.isNotEmpty == true) 'pronouns': pronouns,
          if (effectiveAvatarUri != null)
            'avatar_url': effectiveAvatarUri.toString(),
          if (profile.accentColor != null) 'accent_color': profile.accentColor,
        },
      },
    );
  }

  List<InboxItemSummary> _buildUnifiedInbox() {
    final userId = _client?.userID;
    final displayName = _profileDisplayName;
    if (userId == null) return const [];
    final items = <InboxItemSummary>[];
    for (final room in _client?.rooms ?? const <Room>[]) {
      if (room.membership == Membership.invite) {
        items.add(
          InboxItemSummary(
            id: 'invite:${room.id}',
            roomId: room.id,
            roomName: room.getLocalizedDisplayname(),
            kind: InboxItemKind.invite,
            timestamp: room.lastEvent?.originServerTs ?? DateTime.now().toUtc(),
            preview: 'Room invitation',
            avatarBytes: _avatarBytes[room.id],
          ),
        );
      }
    }
    for (final entry in _roomMessageCache.entries) {
      final room = _matrix.getRoomById(entry.key);
      if (room == null) continue;
      for (final message in entry.value) {
        if (message.own || message.system) continue;
        final mention =
            message.body.contains(userId) ||
            (displayName?.isNotEmpty == true &&
                message.body.contains('@$displayName'));
        final reply = message.reply?.sender == _profileDisplayName;
        if (!mention && !reply) continue;
        items.add(
          InboxItemSummary(
            id: message.id,
            roomId: room.id,
            roomName: room.getLocalizedDisplayname(),
            kind: reply ? InboxItemKind.reply : InboxItemKind.mention,
            timestamp: message.timestamp,
            preview: message.body,
            eventId: message.id,
            avatarBytes: message.avatarBytes,
          ),
        );
      }
    }
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items.take(200).toList(growable: false);
  }

  Future<void> _persistAdvancedSettings() async {
    final userId = _matrix.userID;
    if (userId == null) return;
    final existing =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    await _matrix.setAccountData(
      userId,
      MatrixBackend._settingsAccountDataType,
      {
        ...?existing,
        'presence_mode': _presenceMode.name,
        'temporary_room_mutes': {
          for (final entry in _temporaryRoomMutes.entries)
            entry.key: {
              'until': entry.value.toUtc().toIso8601String(),
              'restore_mode':
                  (_temporaryRoomMuteRestoreModes[entry.key] ??
                          RoomNotificationMode.allMessages)
                      .name,
            },
        },
      },
    );
  }
}
