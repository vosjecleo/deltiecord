part of 'matrix_backend.dart';

/// Owns the Matrix client session, sync listeners, preferences, and shutdown.
///
/// Every listener and RTC resource created here has a matching logout/dispose
/// path. Room-specific asynchronous work is guarded elsewhere by the timeline
/// generation established by this lifecycle.
extension _MatrixSession on MatrixBackend {
  Future<void> _initializeSession() async {
    try {
      await _syncSubscription?.cancel();
      await _loginSubscription?.cancel();
      await _syncStatusSubscription?.cancel();
      _stopProfileRefreshTimer();
      _desktopActivityLeaseTimer?.cancel();
      _desktopActivityLeaseTimer = null;
      _desktopIdle = true;
      await _disposeVoice();
      _client?.dispose();
      _client = await createMatrixClient();
      _roomHeroUsersLoaded.clear();
      _profileFieldsCapability = null;
      _profileFieldsCapabilityLoaded = false;
      _syncSubscription = _matrix.onSync.stream.listen((_) {
        // Successful local state writes are mirrored until this authoritative
        // sync makes the SDK's room-state cache current.
        _spaceChannelLayoutOverrides.clear();
        _spaceRoomOrderOverrides.clear();
        _applySyncedProfilePresence();
        _loadSettings();
        if (_stickerPackSourcesChanged()) unawaited(_refreshStickerPacks());
        unawaited(_enforceCallDeviceHandoff());
        unawaited(_restoreExpiredMemberTimeouts());
        _notifyBackendListeners();
        unawaited(_refreshRoomMetadata());
        unawaited(_notifyNewMessages());
      });
      _loginSubscription = _matrix.onLoginStateChanged.stream.listen((_) {
        _status = _matrix.isLogged()
            ? SessionStatus.signedIn
            : SessionStatus.signedOut;
        _notifyBackendListeners();
      });
      _syncStatusSubscription = _matrix.onSyncStatus.stream.listen((update) {
        final previousStatus = _connectionStatus;
        _connectionStatus = switch (update.status) {
          SyncStatus.finished ||
          SyncStatus.waitingForResponse => ConnectionStatus.online,
          SyncStatus.processing || SyncStatus.cleaningUp =>
            _connectionStatus == ConnectionStatus.offline
                ? ConnectionStatus.reconnecting
                : ConnectionStatus.online,
          SyncStatus.error => ConnectionStatus.offline,
        };
        _notifyBackendListeners();
        if (_connectionStatus == ConnectionStatus.online &&
            previousStatus != ConnectionStatus.online) {
          unawaited(_retryOfflineSends());
          unawaited(_sendDueScheduledMessages());
          if (Platform.isAndroid) unawaited(_restoreUnifiedPushPusher());
        }
      });
      await _matrix.init();
      await _initializeScheduledMessages();
      _initializeVoice();
      _loadSettings();
      _notificationSubscription ??= _notifications.activations.listen(
        (target) => unawaited(_openNotificationTarget(target)),
      );
      _unifiedPushSubscription ??= UnifiedPushPlatform.instance.stateChanges
          .listen((instance) {
            if (instance == _matrix.userID) {
              unawaited(_reconcileUnifiedPushState(instance));
            }
          });
      try {
        await _notifications.initialize();
      } catch (_) {
        // A missing desktop notification service must not prevent Matrix from
        // restoring the session. Messaging remains usable without alerts.
      }
      _status = _matrix.isLogged()
          ? SessionStatus.signedIn
          : SessionStatus.signedOut;
      _error = null;
      if (_matrix.isLogged()) {
        _startProfileRefreshTimer();
        unawaited(refreshEncryptionSetup());
        unawaited(_refreshProfile());
        unawaited(_refreshRoomMetadata());
        unawaited(_refreshMediaConfig());
        unawaited(_restoreUnifiedPushPusher());
      }
    } catch (exception) {
      _status = SessionStatus.failed;
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  Future<void> _loginSession({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    _status = SessionStatus.signingIn;
    _connectionStatus = ConnectionStatus.connecting;
    _error = null;
    _notifyBackendListeners();
    try {
      await _matrix.checkHomeserver(homeserver);
      await _matrix.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: Platform.isAndroid
            ? 'Deltiecord Android'
            : 'Deltiecord Desktop',
      );
      _initializeVoice();
      _status = SessionStatus.signedIn;
      _connectionStatus = ConnectionStatus.online;
      _startProfileRefreshTimer();
      // Login does not recreate the Matrix client, so it does not pass through
      // the session-restoration hydration path above. Hydrate the same profile
      // and room metadata here before the first sync-dependent UI settles.
      unawaited(_refreshProfile());
      unawaited(_refreshRoomMetadata());
      unawaited(_refreshMediaConfig());
      unawaited(_restoreUnifiedPushPusher());
      await refreshEncryptionSetup();
    } catch (exception) {
      _status = SessionStatus.signedOut;
      _connectionStatus = ConnectionStatus.offline;
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  Future<void> _logoutSession() async {
    _error = null;
    try {
      _stopProfileRefreshTimer();
      await _disposeVoice();
      await _closeTimeline();
      await _matrix.logout();
      _selectedRoomId = null;
      _selectedSpaceId = null;
      _loadedBackupRoomIds.clear();
      _roomHeroUsersLoaded.clear();
      _avatarBytes.clear();
      _avatarUris.clear();
      _notificationAvatarBytes.clear();
      _senderAvatarBytes.clear();
      _spaceProfileAvatarBytes.clear();
      _spaceProfileBannerBytes.clear();
      _spaceProfileVoiceBackgroundBytes.clear();
      _senderAvatarUris.clear();
      await _avatarMediaPool.clear();
      _decryptedPreviews.clear();
      _replyPreviews.clear();
      _linkPreviews.clear();
      _linkPreviewUrlCache.clear();
      _outboundSessionsReset.clear();
      _roomsMarkingRead.clear();
      _lastMarkedReadEventIds.clear();
      _firstUnreadEventIds.clear();
      _lastNotificationEventIds.clear();
      _roomPresentationOverrides.clear();
      _spaceChannelLayoutOverrides.clear();
      _spaceRoomOrderOverrides.clear();
      _collapsedChannelCategories.clear();
      _roomMessageCache.clear();
      _offlineSendRooms.clear();
      _dismissedLocalEchoIds.clear();
      _scheduledMessageTimer?.cancel();
      _scheduledMessageTimer = null;
      _temporaryRoomMuteTimer?.cancel();
      _temporaryRoomMuteTimer = null;
      for (final timer in _memberTimeoutTimers.values) {
        timer.cancel();
      }
      _memberTimeoutTimers.clear();
      await _scheduledMessageStore.clear();
      await _notifications.clearPrivateState();
      _bookmarkedEventIds.clear();
      _temporaryRoomMutes.clear();
      _temporaryRoomMuteRestoreModes.clear();
      _stickerPacks = const [];
      _stickerPackSourceSignature = null;
      _notificationsPrimed = false;
      _maximumUploadBytes = null;
      _mediaPlaybackSources.clear();
      _mediaPlaybackReferences.clear();
      _attachmentBytesCache.clear();
      _attachmentDownloads.clear();
      _attachmentBytesCacheSize = 0;
      _attachmentCacheGeneration++;
      _deviceSessions = const [];
      _profileDisplayName = null;
      _profileAvatarBytes = null;
      _profilePresence = UserPresence.offline;
      _profileStatusMessage = null;
      _ownProfileHydrated = false;
      _lastUnifiedPushRestore = null;
      _unifiedPushRestoreRunning = false;
      _profileColor = null;
      _profileCache.clear();
      _profileRequests.clear();
      _profileFieldsCapability = null;
      _profileFieldsCapabilityLoaded = false;
      _mediaRangeProxy.clear();
      _encryptionSetup = const EncryptionSetupState(
        status: EncryptionSetupStatus.loading,
      );
      _status = SessionStatus.signedOut;
      _connectionStatus = ConnectionStatus.offline;
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  void _initializeVoice() {
    if (!_matrix.isLogged() || _voice != null) return;
    _voice = MatrixVoiceController(_matrix, friendlyError: _friendlyError)
      ..addListener(_notifyBackendListeners)
      ..initialize();
  }

  Future<void> _disposeVoice() async {
    final voice = _voice;
    if (voice == null) return;
    _voice = null;
    voice.removeListener(_notifyBackendListeners);
    await voice.leave();
    voice.dispose();
  }

  Future<void> _refreshAudioInputs() async => _voice?.refreshAudioInputs();

  Future<void> _selectAudioInput(String? deviceId) async {
    await _voice?.selectAudioInput(deviceId);
    await _updatePreferences(
      _preferences.copyWith(preferredAudioInputId: deviceId ?? ''),
    );
  }

  Future<void> _selectAudioOutputAndRemember(String? deviceId) async {
    await _voice?.selectAudioOutput(deviceId);
    await _updatePreferences(
      _preferences.copyWith(preferredAudioOutputId: deviceId ?? ''),
    );
  }

  Future<void> _selectCameraAndRemember(String? deviceId) async {
    await _voice?.selectCamera(deviceId);
    await _updatePreferences(
      _preferences.copyWith(preferredCameraId: deviceId ?? ''),
    );
  }

  Future<void> _setParticipantVolumeAndRemember(
    String userId,
    double volume,
  ) async {
    final normalized = volume.clamp(0.0, 1.0).toDouble();
    await _voice?.setParticipantVolume(userId, normalized);
    await _updatePreferences(
      _preferences.copyWith(
        participantVolumes: {
          ..._preferences.participantVolumes,
          userId: normalized,
        },
      ),
    );
  }

  Future<void> _refreshDevices() async {
    if (!_matrix.isLogged() || _devicesLoading) return;
    _devicesLoading = true;
    _notifyBackendListeners();
    try {
      final devices = await _matrix.getDevices() ?? const [];
      await _matrix.userDeviceKeysLoading;
      final ownKeys = _matrix.userDeviceKeys[_matrix.userID]?.deviceKeys;
      _deviceSessions =
          devices
              .map((device) {
                final keys = ownKeys?[device.deviceId];
                return DeviceSessionSummary(
                  id: device.deviceId,
                  displayName: device.displayName?.trim().isNotEmpty == true
                      ? device.displayName!.trim()
                      : 'Unnamed Matrix device',
                  current: device.deviceId == _matrix.deviceID,
                  lastSeenAt: device.lastSeenTs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!),
                  lastSeenIp: device.lastSeenIp,
                  verified: keys?.verified ?? false,
                  crossSigned: keys?.crossVerified ?? false,
                );
              })
              .toList(growable: false)
            ..sort((a, b) {
              if (a.current != b.current) return a.current ? -1 : 1;
              return (b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  );
            });
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _devicesLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _refreshProfile() async {
    final userId = _matrix.userID;
    if (userId == null || _profileLoading) return;
    _profileLoading = true;
    _notifyBackendListeners();
    try {
      final profile = await _getUserProfile(userId, refresh: true);
      _applyOwnProfileSummary(profile);
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _profileLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _setProfileDisplayName(String displayName) async {
    final userId = _matrix.userID;
    if (userId == null || displayName.trim().isEmpty) return;
    try {
      await _matrix.setProfileField(userId, 'displayname', {
        'displayname': displayName.trim(),
      });
      _profileDisplayName = displayName.trim();
      _profileCache.remove(userId);
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _setProfileAvatar(
    Uint8List? bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    try {
      await _matrix.setAvatar(
        bytes == null
            ? null
            : MatrixFile(bytes: bytes, name: fileName, mimeType: mimeType),
      );
      _profileAvatarBytes = bytes;
      final userId = _matrix.userID;
      if (userId != null) _profileCache.remove(userId);
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _removeDevice(String targetDeviceId, String password) async {
    if (targetDeviceId == _matrix.deviceID) {
      throw StateError('Log out to remove the device currently in use.');
    }
    await _runPasswordUia(
      password,
      (auth) => _matrix.deleteDevice(targetDeviceId, auth: auth),
    );
    await _refreshDevices();
  }

  Future<void> _deleteAccount(String password) async {
    await _runPasswordUia(
      password,
      (auth) => _matrix.deactivateAccount(auth: auth, erase: true),
    );
    try {
      await _matrix.logout();
    } catch (_) {
      // Deactivation commonly invalidates the token before logout can run.
    }
    _status = SessionStatus.signedOut;
    _connectionStatus = ConnectionStatus.offline;
    _notifyBackendListeners();
  }

  Future<T> _runPasswordUia<T>(
    String password,
    Future<T> Function(AuthenticationData? auth) request,
  ) async {
    if (password.isEmpty) throw ArgumentError('Enter your account password.');
    try {
      return await request(null);
    } on MatrixException catch (exception) {
      if (!exception.requireAdditionalAuthentication) rethrow;
      return request(
        AuthenticationPassword(
          session: exception.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: _matrix.userID!),
        ),
      );
    }
  }

  Future<void> _joinVoiceRoom(String roomId) async {
    _initializeVoice();
    await _voice?.join(roomId);
    await _publishActiveCallDevice(roomId);
  }

  Future<void> _setVoiceMuted(bool muted) async => _voice?.setMuted(muted);

  Future<void> _leaveVoiceRoom() async {
    await _voice?.leave();
    await _clearActiveCallDevice();
  }

  Future<void> _publishActiveCallDevice(String roomId) async {
    final userId = _matrix.userID;
    final deviceId = _matrix.deviceID;
    if (userId == null || deviceId == null) return;
    await _matrix.setAccountData(
      userId,
      MatrixBackend._activeCallDeviceAccountDataType,
      {
        'device_id': deviceId,
        'room_id': roomId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> _clearActiveCallDevice() async {
    final userId = _matrix.userID;
    final deviceId = _matrix.deviceID;
    final content = _matrix
        .accountData[MatrixBackend._activeCallDeviceAccountDataType]
        ?.content;
    if (userId == null || content?['device_id'] != deviceId) return;
    await _matrix.setAccountData(
      userId,
      MatrixBackend._activeCallDeviceAccountDataType,
      const {},
    );
  }

  Future<void> _enforceCallDeviceHandoff() async {
    final voice = _voice;
    if (voice?.activeRoomId == null) return;
    final content = _matrix
        .accountData[MatrixBackend._activeCallDeviceAccountDataType]
        ?.content;
    final owner = content?.tryGet<String>('device_id');
    final updatedAt = content?.tryGet<int>('updated_at');
    if (owner == null ||
        owner == _matrix.deviceID ||
        updatedAt == null ||
        DateTime.now().millisecondsSinceEpoch - updatedAt >
            const Duration(minutes: 10).inMilliseconds) {
      return;
    }
    await voice!.leave();
  }

  Future<void> _setComposerTyping(bool typing) async {
    if (!_preferences.sendTypingNotifications) return;
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null || room.isSpace) return;
    _typingStopTimer?.cancel();
    if (typing) {
      if (_typingRoomId != room.id) {
        final oldRoom = _matrix.getRoomById(_typingRoomId ?? '');
        if (oldRoom != null) unawaited(oldRoom.setTyping(false));
      }
      _typingRoomId = room.id;
      await room.setTyping(true, timeout: 5000);
      _typingStopTimer = Timer(const Duration(seconds: 4), () {
        unawaited(setComposerTyping(false));
      });
    } else {
      if (_typingRoomId == room.id) await room.setTyping(false);
      _typingRoomId = null;
    }
  }

  Future<void> _notifyNewMessages() async {
    if (!_matrix.isLogged() ||
        !_preferences.notificationsEnabled ||
        _presenceMode == PresenceMode.doNotDisturb) {
      return;
    }
    final rooms = _joinedRooms.where((room) => !room.isSpace);
    final activeDesktopOwnsExternalNotifications =
        Platform.isAndroid &&
        !_applicationForeground &&
        hasActiveDesktopLease(
          _matrix
              .accountData[MatrixBackend._deviceActivityAccountDataType]
              ?.content,
          currentDeviceId: _matrix.deviceID,
        );
    if (!_notificationsPrimed) {
      for (final room in rooms) {
        final eventId = room.lastEvent?.eventId;
        if (eventId != null) _lastNotificationEventIds[room.id] = eventId;
      }
      _notificationsPrimed = true;
      return;
    }
    for (final room in rooms) {
      final event = room.lastEvent;
      if (event == null ||
          _lastNotificationEventIds[room.id] == event.eventId) {
        continue;
      }
      _lastNotificationEventIds[room.id] = event.eventId;
      if (activeDesktopOwnsExternalNotifications ||
          (room.id == _selectedRoomId && _conversationVisible) ||
          event.senderId == _matrix.userID ||
          room.pushRuleState == PushRuleState.dontNotify ||
          (room.pushRuleState == PushRuleState.mentionsOnly &&
              room.highlightCount == 0)) {
        continue;
      }
      var displayEvent = event;
      if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
        try {
          displayEvent = await _matrix.encryption!.decryptRoomEvent(event);
        } catch (_) {
          // A key arriving later will still update the room preview. The
          // notification must remain useful without delaying sync forever.
        }
      }
      final sender = event.senderFromMemoryOrFallback.calcDisplayname();
      final notificationBody = !_notificationPreviewsEnabled
          ? 'New message'
          : displayEvent.type == EventTypes.Message
          ? displayEvent.calcUnlocalizedBody(
              hideReply: true,
              hideEdit: true,
              plaintextBody: true,
            )
          : 'New room activity';
      final notificationAvatar = await _notificationAvatarFor(room, event);
      final notificationImage = await _notificationImageFor(displayEvent);
      // Avatar/media enrichment is asynchronous. The user may open this room
      // while those bytes are loading; re-check immediately before posting so
      // a stale task cannot resurrect a notification that room-open cleared.
      if (activeDesktopOwnsExternalNotifications ||
          (room.id == _selectedRoomId && _conversationVisible) ||
          event.senderId == _matrix.userID) {
        InAppNotificationCenter.dismissRoom(room.id);
        unawaited(_notifications.clearRoom(room.id));
        continue;
      }
      if (notificationAvatar != null) {
        _cacheNotificationAvatar(room.id, notificationAvatar);
      }
      if (_applicationForeground && Platform.isAndroid) {
        InAppNotificationCenter.show(
          InAppChatNotification(
            roomId: room.id,
            title: room.isDirectChat
                ? sender
                : '$sender in ${room.getLocalizedDisplayname()}',
            body: notificationBody,
            avatar: notificationAvatar,
            onTap: () {
              InAppNotificationCenter.dismiss();
              unawaited(
                _openNotificationTarget(
                  NotificationTarget(roomId: room.id, eventId: event.eventId),
                ),
              );
            },
          ),
        );
        final cadence = _preferences.notificationAlertCadence;
        final now = DateTime.now();
        final previous = _lastForegroundAlertAt[room.id];
        final shouldAlert =
            cadence == NotificationAlertCadence.everyMessage ||
            (cadence == NotificationAlertCadence.fiveMinuteCooldown &&
                (previous == null ||
                    now.difference(previous) >= const Duration(minutes: 5)));
        if (shouldAlert && !Platform.isAndroid) {
          _lastForegroundAlertAt[room.id] = now;
          if (_preferences.notificationSound) {
            unawaited(AppSounds.notification());
          }
        }
        continue;
      }
      await _notifications.show(
        title: '$sender in ${room.getLocalizedDisplayname()}',
        body: notificationBody,
        roomId: room.id,
        eventId: event.eventId,
        senderName: sender,
        roomName: room.getLocalizedDisplayname(),
        groupConversation: !room.isDirectChat,
        senderAvatar: notificationAvatar,
        image: notificationImage?.$1,
        imageMimeType: notificationImage?.$2,
        timestamp: event.originServerTs,
        sound: _preferences.notificationSound,
        vibrate: _preferences.notificationVibration,
        alertCadence: _preferences.notificationAlertCadence,
        unreadCount: room.isDirectChat
            ? room.notificationCount
            : room.highlightCount,
      );
    }
  }

  Future<Uint8List?> _notificationAvatarFor(Room room, Event event) async {
    final cached = _senderAvatarBytes[event.senderId];
    if (cached != null) return cached;
    final avatar = event.senderFromMemoryOrFallback.avatarUrl;
    if (avatar == null || !avatar.isScheme('mxc')) return null;
    try {
      final bytes = await _avatarMedia(avatar, AvatarMediaPool.rowDimension);
      if (bytes == null) return null;
      _senderAvatarUris[event.senderId] = avatar;
      _senderAvatarBytes[event.senderId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<(Uint8List, String)?> _notificationImageFor(Event event) async {
    if (!_notificationPreviewsEnabled ||
        !event.hasAttachment ||
        !event.attachmentMimetype.startsWith('image/')) {
      return null;
    }
    final useThumbnail = event.hasThumbnail;
    final declaredSize = useThumbnail
        ? event.thumbnailInfoMap.tryGet<int>('size')
        : event.infoMap.tryGet<int>('size');
    // Background rich notifications never fetch media with unknown bounds.
    // A small compressed file can otherwise expand into an enormous bitmap.
    if (declaredSize == null ||
        declaredSize <= 0 ||
        declaredSize > 3 * 1024 * 1024) {
      return null;
    }
    final info = useThumbnail ? event.thumbnailInfoMap : event.infoMap;
    final width = info.tryGet<int>('w');
    final height = info.tryGet<int>('h');
    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        width > 4096 ||
        height > 4096 ||
        width * height > 8000000) {
      return null;
    }
    try {
      final file = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (file.bytes.length > 3 * 1024 * 1024) return null;
      return (file.bytes, file.mimeType);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openNotificationTarget(NotificationTarget target) async {
    if (!_matrix.isLogged()) return;
    final room = _matrix.getRoomById(target.roomId);
    if (room == null || room.membership != Membership.join) return;
    try {
      await _selectRoom(target.roomId);
      await _jumpToEvent(target.eventId);
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  void _loadSettings() {
    final content =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    _notificationPreviewsEnabled =
        content?.tryGet<bool>('notification_previews') ?? true;
    _loadAdvancedAccountData();
    _collapsedChannelCategories
      ..clear()
      ..addEntries(
        (content?.tryGetMap<String, Object?>('collapsed_channel_categories') ??
                const {})
            .entries
            .map(
              (entry) => MapEntry(
                entry.key,
                (entry.value as List? ?? const []).whereType<String>().toSet(),
              ),
            ),
      );
    if (_pendingPreferences != null) return;
    _preferences = AppPreferences(
      density: content?.tryGet<String>('density') == 'cozy'
          ? InterfaceDensity.cozy
          : InterfaceDensity.compact,
      compactness:
          (content?['compactness'] as num?)?.toDouble().clamp(0, 1) ??
          (content?.tryGet<String>('density') == 'cozy' ? 0.15 : 0.5),
      themeMode:
          DeltiecordThemeMode.values
              .where(
                (mode) => mode.name == content?.tryGet<String>('theme_mode'),
              )
              .firstOrNull ??
          DeltiecordThemeMode.dark,
      interfaceScale:
          (content?['interface_scale'] as num?)?.toDouble().clamp(0.8, 1.4) ??
          1,
      fontScale: _readPlatformFontScale(content),
      use24HourTime: content?.tryGet<bool>('use_24_hour_time') ?? true,
      roomPanelWidth:
          (content?['room_panel_width'] as num?)?.toDouble().clamp(220, 420) ??
          280,
      sidePanelWidth:
          (content?['side_panel_width'] as num?)?.toDouble().clamp(260, 460) ??
          310,
      reducedMotion: content?.tryGet<bool>('reduced_motion') ?? false,
      highContrast: content?.tryGet<bool>('high_contrast') ?? false,
      autoplayGifs: content?.tryGet<bool>('autoplay_gifs') ?? true,
      notificationsEnabled:
          content?.tryGet<bool>('notifications_enabled') ?? true,
      notificationSound: content?.tryGet<bool>('notification_sound') ?? true,
      notificationVibration:
          content?.tryGet<bool>('notification_vibration') ?? true,
      notificationAlertCadence:
          NotificationAlertCadence.values
              .where(
                (value) =>
                    value.name ==
                    content?.tryGet<String>('notification_alert_cadence'),
              )
              .firstOrNull ??
          NotificationAlertCadence.fiveMinuteCooldown,
      sendReadReceipts: content?.tryGet<bool>('send_read_receipts') ?? true,
      sendTypingNotifications:
          content?.tryGet<bool>('send_typing_notifications') ?? true,
      sharePresence: content?.tryGet<bool>('share_presence') ?? true,
      desktopIdleMinutes: (content?.tryGet<int>('desktop_idle_minutes') ?? 5)
          .clamp(1, 120),
      directLinkPreviewMode:
          DirectLinkPreviewMode.values
              .where(
                (value) =>
                    value.name ==
                    content?.tryGet<String>('direct_link_preview_mode'),
              )
              .firstOrNull ??
          ((content?.tryGet<bool>('fetch_direct_link_previews') ?? false)
              ? DirectLinkPreviewMode.allPublicSites
              : DirectLinkPreviewMode.none),
      improveTwitterLinks:
          content?.tryGet<bool>('improve_twitter_links') ?? true,
      accentColor: content?.tryGet<int>('accent_color') ?? 0xff6975d9,
      fontFamily: _supportedInterfaceFont(
        content?.tryGet<String>('font_family'),
      ),
      emojiFontFamily: normalizeEmojiFontFamily(
        content?.tryGet<String>('emoji_font_family'),
      ),
      showNativeTitleBar:
          content?.tryGet<bool>('show_native_title_bar') ?? true,
      rememberWindowState:
          content?.tryGet<bool>('remember_window_state') ?? true,
      shortcutBindings: _shortcutBindingsFrom(content),
      sendWithCtrlEnter: content?.tryGet<bool>('send_with_ctrl_enter') ?? false,
      readReceiptMemberThreshold:
          content?.tryGet<int>('receipt_member_threshold') ?? 10,
      timelineChunkSize: content?.tryGet<int>('timeline_chunk_size') ?? 30,
      timelineChunkCap: content?.tryGet<int>('timeline_chunk_cap') ?? 3,
      preferredAudioInputId:
          content?.tryGet<String>('preferred_audio_input') ?? '',
      preferredAudioOutputId:
          content?.tryGet<String>('preferred_audio_output') ?? '',
      preferredCameraId: content?.tryGet<String>('preferred_camera') ?? '',
      echoCancellation: content?.tryGet<bool>('echo_cancellation') ?? true,
      noiseSuppression: content?.tryGet<bool>('noise_suppression') ?? true,
      autoGainControl: content?.tryGet<bool>('auto_gain_control') ?? true,
      microphoneVolume:
          (content?['microphone_volume'] as num?)?.toDouble().clamp(0, 1) ?? 1,
      outputVolume:
          (content?['output_volume'] as num?)?.toDouble().clamp(0, 1) ?? 1,
      callSound: content?.tryGet<bool>('call_sound') ?? true,
      shareDesktopAudio: content?.tryGet<bool>('share_desktop_audio') ?? false,
      enableChannelDragAndDrop:
          content?.tryGet<bool>('enable_channel_drag_and_drop') ?? false,
      participantVolumes:
          content
              ?.tryGetMap<String, Object?>('participant_volumes')
              ?.map(
                (userId, volume) => MapEntry(
                  userId,
                  volume is num ? volume.toDouble().clamp(0, 1) : 1,
                ),
              ) ??
          const {},
    );
    _voice?.applyPreferences(_preferences);
  }

  String _supportedInterfaceFont(String? stored) =>
      const {'System', 'Noto Sans', 'DejaVu Sans', 'monospace'}.contains(stored)
      ? stored!
      : 'System';

  Map<AppShortcutAction, String> _shortcutBindingsFrom(
    Map<String, Object?>? content,
  ) {
    final result = <AppShortcutAction, String>{...defaultShortcutBindings};
    final stored = content?['shortcut_bindings'];
    if (stored is! Map) return result;
    for (final entry in stored.entries) {
      final action = AppShortcutAction.values
          .where((candidate) => candidate.name == entry.key)
          .firstOrNull;
      if (action != null) result[action] = entry.value.toString();
    }
    return result;
  }

  Future<void> _updatePreferences(AppPreferences preferences) async {
    if (_matrix.userID == null) return;
    final previewPolicyChanged =
        preferences.directLinkPreviewMode !=
            _preferences.directLinkPreviewMode ||
        preferences.improveTwitterLinks != _preferences.improveTwitterLinks;
    if (previewPolicyChanged) {
      // A previous homeserver-only miss must not suppress a newly opted-in
      // direct fallback (and vice versa). Event previews hydrate again lazily.
      _linkPreviews.clear();
      _linkPreviewUrlCache.clear();
    }
    if (preferences.sharePresence != _preferences.sharePresence) {
      unawaited(
        _matrix
            .setPresence(
              _matrix.userID!,
              preferences.sharePresence
                  ? PresenceType.online
                  : PresenceType.offline,
              statusMsg: _profileStatusMessage,
            )
            .catchError((_) {}),
      );
    }
    _preferences = preferences;
    _voice?.applyPreferences(preferences);
    _pendingPreferences = preferences;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(const Duration(milliseconds: 300), () {
      final pending = _pendingPreferences;
      if (pending != null) unawaited(_persistPreferences(pending));
    });
    _notifyBackendListeners();
    final timeline = _timeline;
    if (previewPolicyChanged && timeline != null) {
      // Rehydrate the current room immediately. Waiting for another Matrix
      // timeline event made this privacy toggle appear broken until the user
      // switched rooms or received a message.
      unawaited(_hydrateCurrentTimeline(timeline, _timelineGeneration));
    }
  }

  Future<void> _persistPreferences(AppPreferences preferences) async {
    if (_matrix.userID == null) return;
    final existing =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    try {
      await _matrix.setAccountData(
        _matrix.userID!,
        MatrixBackend._settingsAccountDataType,
        {
          ...?existing,
          'density': preferences.density.name,
          'compactness': preferences.compactness,
          'theme_mode': preferences.themeMode.name,
          'interface_scale': preferences.interfaceScale,
          _platformFontScaleKey: preferences.fontScale,
          'use_24_hour_time': preferences.use24HourTime,
          'room_panel_width': preferences.roomPanelWidth,
          'side_panel_width': preferences.sidePanelWidth,
          'reduced_motion': preferences.reducedMotion,
          'high_contrast': preferences.highContrast,
          'autoplay_gifs': preferences.autoplayGifs,
          'notifications_enabled': preferences.notificationsEnabled,
          'notification_sound': preferences.notificationSound,
          'notification_vibration': preferences.notificationVibration,
          'notification_alert_cadence':
              preferences.notificationAlertCadence.name,
          'send_read_receipts': preferences.sendReadReceipts,
          'send_typing_notifications': preferences.sendTypingNotifications,
          'share_presence': preferences.sharePresence,
          'desktop_idle_minutes': preferences.desktopIdleMinutes,
          'fetch_direct_link_previews': preferences.fetchDirectLinkPreviews,
          'direct_link_preview_mode': preferences.directLinkPreviewMode.name,
          'improve_twitter_links': preferences.improveTwitterLinks,
          'accent_color': preferences.accentColor,
          'font_family': preferences.fontFamily,
          'emoji_font_family': preferences.emojiFontFamily,
          'show_native_title_bar': preferences.showNativeTitleBar,
          'remember_window_state': preferences.rememberWindowState,
          'shortcut_bindings': {
            for (final entry in preferences.shortcutBindings.entries)
              entry.key.name: entry.value,
          },
          'send_with_ctrl_enter': preferences.sendWithCtrlEnter,
          'receipt_member_threshold': preferences.readReceiptMemberThreshold,
          'timeline_chunk_size': preferences.timelineChunkSize,
          'timeline_chunk_cap': preferences.timelineChunkCap,
          'preferred_audio_input': preferences.preferredAudioInputId,
          'preferred_audio_output': preferences.preferredAudioOutputId,
          'preferred_camera': preferences.preferredCameraId,
          'echo_cancellation': preferences.echoCancellation,
          'noise_suppression': preferences.noiseSuppression,
          'auto_gain_control': preferences.autoGainControl,
          'microphone_volume': preferences.microphoneVolume,
          'output_volume': preferences.outputVolume,
          'call_sound': preferences.callSound,
          'share_desktop_audio': preferences.shareDesktopAudio,
          'enable_channel_drag_and_drop': preferences.enableChannelDragAndDrop,
          'participant_volumes': preferences.participantVolumes,
        },
      );
      if (identical(_pendingPreferences, preferences)) {
        _pendingPreferences = null;
      }
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  void _setDesktopIdle(bool idle) {
    if (Platform.isAndroid || _desktopIdle == idle) return;
    _desktopIdle = idle;
    _desktopActivityLeaseTimer?.cancel();
    unawaited(_publishDesktopActivityLease(idle));
    final userId = _matrix.userID;
    // The activity watcher can fire before the own profile has restored the
    // existing status. Publishing presence before then would erase it.
    if (userId != null && _ownProfileHydrated) {
      final presence = !_preferences.sharePresence
          ? PresenceType.offline
          : switch (_presenceMode) {
              PresenceMode.online =>
                idle ? PresenceType.unavailable : PresenceType.online,
              PresenceMode.idle => PresenceType.unavailable,
              PresenceMode.doNotDisturb => PresenceType.online,
              PresenceMode.invisible => PresenceType.offline,
            };
      unawaited(
        _matrix.setPresence(userId, presence, statusMsg: _profileStatusMessage),
      );
    }
    if (!idle) {
      _desktopActivityLeaseTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_publishDesktopActivityLease(false)),
      );
    }
  }

  Future<void> _publishDesktopActivityLease(bool idle) async {
    final userId = _matrix.userID;
    final deviceId = _matrix.deviceID;
    if (userId == null || deviceId == null) return;
    final existing = _matrix
        .accountData[MatrixBackend._deviceActivityAccountDataType]
        ?.content;
    final devices = <String, Object?>{
      ...?existing?.tryGetMap<String, Object?>('devices'),
    };
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .millisecondsSinceEpoch;
    devices.removeWhere((_, value) {
      if (value is! Map) return true;
      final updatedAt = value['updated_at'] as int?;
      return updatedAt == null || updatedAt < cutoff;
    });
    devices[deviceId] = {
      'platform': Platform.operatingSystem,
      'idle': idle,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await _matrix.setAccountData(
        userId,
        MatrixBackend._deviceActivityAccountDataType,
        {'devices': devices},
      );
    } catch (_) {
      // Device activity is advisory. Failure must not interrupt the session.
    }
  }

  Future<void> _setNotificationPreviewsEnabled(bool enabled) async {
    if (_matrix.userID == null) return;
    final existing =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    try {
      await _matrix.setAccountData(
        _matrix.userID!,
        MatrixBackend._settingsAccountDataType,
        {...?existing, 'notification_previews': enabled},
      );
      _notificationPreviewsEnabled = enabled;
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  Future<void> _setUnifiedPushEndpoint(String endpoint) async {
    try {
      final result = await _reconcileUnifiedPushEndpoint(endpoint);
      await UnifiedPushPlatform.instance.recordPusherVerification(result);
    } catch (_) {
      await UnifiedPushPlatform.instance.recordPusherVerification(
        'verification_failed',
      );
      rethrow;
    }
  }

  Future<String> _reconcileUnifiedPushEndpoint(String endpoint) async =>
      (await reconcileMatrixUnifiedPushPusher(_matrix, endpoint)).name;

  Future<void> _reconcileUnifiedPushState(String instance) async {
    if (_matrix.userID != instance || !_matrix.isLogged()) return;
    final state = await UnifiedPushPlatform.instance.state(instance);
    if (state.endpoint case final endpoint?) {
      await _setUnifiedPushEndpoint(endpoint);
    }
  }

  Future<void> _restoreUnifiedPushPusher() async {
    final userId = _matrix.userID;
    final platform = UnifiedPushPlatform.instance;
    if (userId == null || !platform.supported) return;
    final lastRestore = _lastUnifiedPushRestore;
    if (_unifiedPushRestoreRunning ||
        (lastRestore != null &&
            DateTime.now().difference(lastRestore) <
                const Duration(minutes: 10))) {
      return;
    }
    _unifiedPushRestoreRunning = true;
    try {
      await platform.ensureDefaultDistributor(userId);
      var state = await platform.state(userId);
      if (state.distributor != null) await platform.register(userId);
      for (var attempt = 0; attempt < 20 && state.endpoint == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        state = await platform.state(userId);
        if (state.error != null) break;
      }
      await _reconcileUnifiedPushState(userId);
      _lastUnifiedPushRestore = DateTime.now();
    } catch (_) {
      // Push is an optional background optimization. Distributor absence or a
      // stale endpoint must never prevent an otherwise healthy Matrix login.
    } finally {
      _unifiedPushRestoreRunning = false;
    }
  }

  Future<void> _removeUnifiedPushEndpoint(String endpoint) async {
    if (_matrix.userID == null || endpoint.isEmpty) return;
    await _matrix.deletePusher(
      PusherId(appId: 'net.deltie.deltiecord', pushkey: endpoint),
    );
  }

  void _clearSessionError() {
    _error = null;
    _notifyBackendListeners();
  }
}
