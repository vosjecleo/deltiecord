part of 'matrix_backend.dart';

const _profileBioField = 'net.deltiecord.bio';
const _profilePronounsField = 'net.deltiecord.pronouns';
const _profileBannerField = 'net.deltiecord.banner';
const _profileColorField = 'net.deltiecord.profile_color';
const _profileColorSecondaryField = 'net.deltiecord.profile_color_secondary';
const _profileVoiceColorField = 'net.deltiecord.voice_color';
const _profileVoiceBackgroundField = 'net.deltiecord.voice_background';

class _ProfileCacheEntry {
  _ProfileCacheEntry({
    required this.profile,
    required this.avatarUri,
    required this.metadataFetchedAt,
    required this.statusFetchedAt,
    required this.lastAccessedAt,
  });

  UserProfileSummary profile;
  Uri? avatarUri;
  DateTime metadataFetchedAt;
  DateTime statusFetchedAt;
  DateTime lastAccessedAt;
}

/// Reads and writes standard and namespaced extensible Matrix profile fields.
///
/// Custom fields are written only when advertised by `m.profile_fields`; a
/// server without that capability continues to expose an ordinary profile.
extension _MatrixProfiles on MatrixBackend {
  Future<UserProfileSummary> _getUserProfile(
    String userId, {
    bool refresh = false,
  }) {
    final now = DateTime.now();
    final cached = _profileCache[userId];
    if (!refresh && cached != null) {
      cached.lastAccessedAt = now;
      cached.profile = _profileWithSyncedPresence(cached.profile);
      // Reinsert to maintain least-recently-used order.
      _profileCache.remove(userId);
      _profileCache[userId] = cached;

      final refreshMetadata = ProfileRefreshPolicy.metadataIsStale(
        cached.metadataFetchedAt,
        now,
      );
      final refreshStatus = ProfileRefreshPolicy.statusIsStale(
        cached.statusFetchedAt,
        now,
      );
      if (refreshMetadata || refreshStatus) {
        // Cached content is returned immediately. Optional metadata hydrates
        // behind it and is available to every subsequent profile reference.
        unawaited(
          _refreshProfileCache(
            userId,
            refreshMetadata: refreshMetadata,
            refreshStatus: refreshStatus,
            refreshMedia: false,
          ).then((_) => _notifyBackendListeners()),
        );
      }
      return Future.value(_profileWithSpaceOverride(cached.profile));
    }

    return _refreshProfileCache(
      userId,
      refreshMetadata: true,
      refreshStatus: true,
      refreshMedia: refresh || cached == null,
    ).then(_profileWithSpaceOverride);
  }

  UserProfileSummary _profileWithSpaceOverride(UserProfileSummary profile) {
    final spaceId = _selectedSpaceId;
    if (spaceId == null) return profile;
    final content = _matrix
        .getRoomById(spaceId)
        ?.getState(EventTypes.RoomMember, profile.userId)
        ?.content;
    if (content == null) return profile;
    final displayName = content.tryGet<String>('displayname');
    final pronouns = content.tryGet<String>('net.deltiecord.pronouns');
    final accent = content.tryGet<int>('net.deltiecord.accent_color');
    final key = '$spaceId|${profile.userId}';
    return UserProfileSummary(
      userId: profile.userId,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!
          : profile.displayName,
      avatarBytes: _spaceProfileAvatarBytes[key] ?? profile.avatarBytes,
      bannerBytes: _spaceProfileBannerBytes[key] ?? profile.bannerBytes,
      presence: profile.presence,
      bio: content.tryGet<String>('net.deltiecord.bio') ?? profile.bio,
      pronouns: pronouns?.trim().isNotEmpty == true
          ? pronouns
          : profile.pronouns,
      timezone:
          content.tryGet<String>('net.deltiecord.timezone') ?? profile.timezone,
      statusMessage:
          content.tryGet<String>('net.deltiecord.status') ??
          profile.statusMessage,
      profileColor: accent ?? profile.profileColor,
      profileColorSecondary:
          content.tryGet<int>('net.deltiecord.accent_color_secondary') ??
          profile.profileColorSecondary,
      voiceColor:
          content.tryGet<int>('net.deltiecord.voice_color') ??
          profile.voiceColor,
      voiceBackgroundBytes:
          _spaceProfileVoiceBackgroundBytes[key] ??
          profile.voiceBackgroundBytes,
      extensibleFieldsSupported: profile.extensibleFieldsSupported,
      blocked: profile.blocked,
    );
  }

  Future<UserProfileSummary> _refreshProfileCache(
    String userId, {
    required bool refreshMetadata,
    required bool refreshStatus,
    required bool refreshMedia,
  }) async {
    final cached = _profileCache[userId];
    final pending = _profileRequests[userId];
    if (pending != null) {
      final pendingResult = await pending;
      final updated = _profileCache[userId];
      final now = DateTime.now();
      final stillNeedsMetadata =
          refreshMetadata &&
          (updated == null ||
              ProfileRefreshPolicy.metadataIsStale(
                updated.metadataFetchedAt,
                now,
              ));
      final stillNeedsStatus =
          refreshStatus &&
          (updated == null ||
              ProfileRefreshPolicy.statusIsStale(updated.statusFetchedAt, now));
      if (!refreshMedia && !stillNeedsMetadata && !stillNeedsStatus) {
        return pendingResult;
      }
      // An explicit full-profile refresh must not be satisfied by an older
      // metadata-only request which deliberately retained pooled media.
    }
    final request =
        _fetchUserProfile(
          userId,
          refreshMetadata: refreshMetadata,
          refreshStatus: refreshStatus,
          refreshMedia: refreshMedia,
        ).onError((error, stackTrace) {
          if (cached != null) {
            final attemptedAt = DateTime.now();
            if (refreshMetadata) cached.metadataFetchedAt = attemptedAt;
            if (refreshStatus) cached.statusFetchedAt = attemptedAt;
            return _profileWithSyncedPresence(cached.profile);
          }
          if (error != null) Error.throwWithStackTrace(error, stackTrace);
          throw StateError('Profile loading failed without an error.');
        });
    _profileRequests[userId] = request;
    return request.whenComplete(() => _profileRequests.remove(userId));
  }

  Future<UserProfileSummary> _fetchUserProfile(
    String userId, {
    required bool refreshMetadata,
    required bool refreshStatus,
    required bool refreshMedia,
  }) async {
    final previous = _profileCache[userId];
    final needsProfileResponse =
        previous == null || refreshMetadata || refreshMedia;
    final remoteProfile = needsProfileResponse
        ? await _matrix.getUserProfile(userId, maxCacheAge: Duration.zero)
        : null;

    CachedPresence? presence;
    if (previous == null || refreshStatus) {
      try {
        presence = await _matrix.fetchCurrentPresence(userId);
      } catch (_) {
        // Profiles remain useful on homeservers with presence disabled.
      }
    }

    final old = previous?.profile;
    final avatarUri = remoteProfile?.avatarUrl ?? previous?.avatarUri;
    final bannerUri = Uri.tryParse(
      remoteProfile?.additionalProperties[_profileBannerField] as String? ?? '',
    );
    final voiceBackgroundUri = Uri.tryParse(
      remoteProfile?.additionalProperties[_profileVoiceBackgroundField]
              as String? ??
          '',
    );
    final avatarBytes = refreshMedia || old == null
        ? avatarUri == null
              ? null
              : await _avatarMedia(
                      avatarUri,
                      AvatarMediaPool.profileDimension,
                    ) ??
                    old?.avatarBytes
        : old.avatarBytes;
    final bannerBytes = refreshMedia || old == null
        ? bannerUri == null
              ? null
              : await _profileOriginalMedia(bannerUri) ?? old?.bannerBytes
        : old.bannerBytes;
    final voiceBackgroundBytes = refreshMedia || old == null
        ? voiceBackgroundUri == null
              ? null
              : await _profileOriginalMedia(voiceBackgroundUri) ??
                    old?.voiceBackgroundBytes
        : old.voiceBackgroundBytes;
    final capability = needsProfileResponse ? await _profileCapability() : null;
    final properties = remoteProfile?.additionalProperties;
    final colorValue = properties?[_profileColorField];
    final now = DateTime.now();
    final result = UserProfileSummary(
      userId: userId,
      displayName:
          remoteProfile?.displayname ??
          old?.displayName ??
          userId.split(':').first.replaceFirst('@', ''),
      avatarBytes: avatarBytes,
      bannerBytes: bannerBytes,
      presence: switch (presence?.presence) {
        PresenceType.online => UserPresence.online,
        PresenceType.unavailable => UserPresence.away,
        PresenceType.offline => UserPresence.offline,
        _ => old?.presence ?? UserPresence.offline,
      },
      bio: properties?[_profileBioField] as String? ?? old?.bio,
      pronouns: properties?[_profilePronounsField] as String? ?? old?.pronouns,
      timezone: remoteProfile?.mTz ?? old?.timezone,
      statusMessage: presence == null
          ? old?.statusMessage
          : _normalizedProfileStatus(presence.statusMsg),
      profileColor: remoteProfile == null
          ? old?.profileColor
          : _parseProfileColor(colorValue),
      profileColorSecondary: remoteProfile == null
          ? old?.profileColorSecondary
          : _parseProfileColor(properties?[_profileColorSecondaryField]),
      voiceColor: remoteProfile == null
          ? old?.voiceColor
          : _parseProfileColor(properties?[_profileVoiceColorField]),
      voiceBackgroundBytes: voiceBackgroundBytes,
      extensibleFieldsSupported: remoteProfile == null
          ? old?.extensibleFieldsSupported ?? false
          : capability?.enabled == true,
      blocked: _matrix.ignoredUsers.contains(userId),
    );
    final withSyncedPresence = _profileWithSyncedPresence(result);
    _profileCache.remove(userId);
    _profileCache[userId] = _ProfileCacheEntry(
      profile: withSyncedPresence,
      avatarUri: avatarUri,
      metadataFetchedAt: needsProfileResponse
          ? now
          : previous.metadataFetchedAt,
      statusFetchedAt: presence != null
          ? now
          : refreshStatus
          ? now
          : previous?.statusFetchedAt ?? now,
      lastAccessedAt: now,
    );
    _profileRevision++;
    var mediaBytes = _profileCache.values.fold<int>(
      0,
      (total, entry) =>
          total +
          (entry.profile.avatarBytes?.length ?? 0) +
          (entry.profile.bannerBytes?.length ?? 0) +
          (entry.profile.voiceBackgroundBytes?.length ?? 0),
    );
    while (_profileCache.length > MatrixBackend._maximumCachedProfiles ||
        (mediaBytes > MatrixBackend._maximumCachedProfileMediaBytes &&
            _profileCache.length > 1)) {
      final removed = _profileCache.remove(_profileCache.keys.first);
      mediaBytes -=
          (removed?.profile.avatarBytes?.length ?? 0) +
          (removed?.profile.bannerBytes?.length ?? 0) +
          (removed?.profile.voiceBackgroundBytes?.length ?? 0);
    }
    return withSyncedPresence;
  }

  String? _normalizedProfileStatus(String? status) =>
      status?.trim().isEmpty == true ? null : status?.trim();

  UserPresence _matrixPresenceFor(String userId, UserPresence fallback) {
    // ignore: deprecated_member_use
    return switch (_matrix.presences[userId]?.presence) {
      PresenceType.online => UserPresence.online,
      PresenceType.unavailable => UserPresence.away,
      PresenceType.offline => UserPresence.offline,
      _ => fallback,
    };
  }

  UserProfileSummary _profileWithSyncedPresence(UserProfileSummary profile) {
    // Presence events arrive in `/sync` and update this SDK cache. That makes
    // online state live without polling or re-downloading the whole profile.
    // ignore: deprecated_member_use
    final synced = _matrix.presences[profile.userId];
    if (synced == null) return profile;
    return _copyProfile(
      profile,
      presence: _matrixPresenceFor(profile.userId, profile.presence),
      statusMessage: _normalizedProfileStatus(synced.statusMsg),
    );
  }

  UserProfileSummary _copyProfile(
    UserProfileSummary profile, {
    UserPresence? presence,
    String? statusMessage,
  }) => UserProfileSummary(
    userId: profile.userId,
    displayName: profile.displayName,
    avatarBytes: profile.avatarBytes,
    bannerBytes: profile.bannerBytes,
    presence: presence ?? profile.presence,
    bio: profile.bio,
    pronouns: profile.pronouns,
    timezone: profile.timezone,
    statusMessage: statusMessage,
    profileColor: profile.profileColor,
    profileColorSecondary: profile.profileColorSecondary,
    voiceColor: profile.voiceColor,
    voiceBackgroundBytes: profile.voiceBackgroundBytes,
    extensibleFieldsSupported: profile.extensibleFieldsSupported,
    blocked: profile.blocked,
  );

  void _startProfileRefreshTimer() {
    _profileRefreshTimer?.cancel();
    _profileRefreshTimer = Timer.periodic(
      ProfileRefreshPolicy.statusInterval,
      (_) => unawaited(_refreshActiveProfileCache()),
    );
  }

  void _stopProfileRefreshTimer() {
    _profileRefreshTimer?.cancel();
    _profileRefreshTimer = null;
  }

  Future<void> _refreshActiveProfileCache() async {
    if (_profileRefreshRunning ||
        !_matrix.isLogged() ||
        _connectionStatus != ConnectionStatus.online) {
      return;
    }
    _profileRefreshRunning = true;
    try {
      final now = DateTime.now();
      final ownUserId = _matrix.userID;
      final activeUserIds = _profileCache.entries
          .where(
            (entry) =>
                entry.key == ownUserId ||
                ProfileRefreshPolicy.wasRecentlyAccessed(
                  entry.value.lastAccessedAt,
                  now,
                ),
          )
          .map((entry) => entry.key)
          .toList(growable: false);
      var refreshed = false;
      for (final userId in activeUserIds) {
        final cached = _profileCache[userId];
        if (cached == null) continue;
        final refreshMetadata = ProfileRefreshPolicy.metadataIsStale(
          cached.metadataFetchedAt,
          now,
        );
        final refreshStatus = ProfileRefreshPolicy.statusIsStale(
          cached.statusFetchedAt,
          now,
        );
        if (!refreshMetadata && !refreshStatus) continue;
        final profile = await _refreshProfileCache(
          userId,
          refreshMetadata: refreshMetadata,
          refreshStatus: refreshStatus,
          refreshMedia: false,
        );
        if (userId == ownUserId) _applyOwnProfileSummary(profile);
        refreshed = true;
      }
      if (refreshed) _notifyBackendListeners();
    } finally {
      _profileRefreshRunning = false;
    }
  }

  void _applySyncedProfilePresence() {
    final now = DateTime.now();
    var changed = false;
    for (final entry in _profileCache.values) {
      final old = entry.profile;
      final updated = _profileWithSyncedPresence(old);
      if (updated.presence == old.presence &&
          updated.statusMessage == old.statusMessage) {
        continue;
      }
      entry.profile = updated;
      changed = true;
      // A status carried by Matrix sync is authoritative and replaces the
      // one-minute fallback poll immediately.
      if (updated.statusMessage != old.statusMessage) {
        entry.statusFetchedAt = now;
      }
      if (updated.userId == _matrix.userID) _applyOwnProfileSummary(updated);
    }
    if (changed) _profileRevision++;
  }

  void _applyOwnProfileSummary(UserProfileSummary profile) {
    _profileDisplayName = profile.displayName;
    _profileAvatarBytes = profile.avatarBytes;
    _profilePresence = profile.presence;
    _profileStatusMessage = profile.statusMessage;
    _profileColor = profile.profileColor;
    _ownProfileHydrated = true;
  }

  Future<Uint8List?> _profileMedia(Uri? mxc, int width, int height) async {
    if (mxc == null || !mxc.isScheme('mxc')) return null;
    try {
      final response = await _matrix.getContentThumbnail(
        mxc.host,
        mxc.pathSegments.join('/'),
        width,
        height,
        method: Method.crop,
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _avatarMedia(Uri? mxc, int dimension) {
    if (mxc == null) return Future<Uint8List?>.value();
    return _avatarMediaPool.load(mxc, dimension, () async {
      final response = await _matrix.getContentThumbnail(
        mxc.host,
        mxc.pathSegments.join('/'),
        dimension,
        dimension,
        method: Method.crop,
        animated: false,
      );
      return response.data;
    });
  }

  Future<Uint8List?> _profileOriginalMedia(Uri? mxc) async {
    if (mxc == null || !mxc.isScheme('mxc')) return null;
    try {
      final response = await _matrix.getContent(
        mxc.host,
        mxc.pathSegments.join('/'),
      );
      return response.data;
    } catch (_) {
      // Older media repositories may reject the authenticated original-media
      // endpoint. A large scale thumbnail still looks substantially better
      // than leaving the profile banner empty.
      return _profileMedia(mxc, 1920, 640);
    }
  }

  Future<void> _updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    String? statusMessage,
    int? profileColor,
    int? profileColorSecondary,
    Uint8List? bannerBytes,
    required bool removeBanner,
  }) async {
    final userId = _matrix.userID;
    if (userId == null) return;
    final capability = await _profileCapability();
    bool supports(String key) {
      if (capability?.enabled != true) return false;
      final allowed = capability?.allowed;
      if (allowed != null) return allowed.contains(key);
      return !(capability?.disallowed?.contains(key) ?? false);
    }

    Never unsupported(String key) => throw UnsupportedError(
      'This homeserver does not advertise support for the profile field $key.',
    );

    Future<void> setText(String key, String? value) async {
      if (value == null) return;
      if (!supports(key)) unsupported(key);
      try {
        if (value.trim().isEmpty) {
          await _matrix.deleteProfileField(userId, key);
        } else {
          await _matrix.setProfileField(userId, key, {key: value.trim()});
        }
      } on MatrixException catch (exception) {
        if (exception.error != MatrixError.M_UNRECOGNIZED) rethrow;
        // Extensible profiles are optional; display name/avatar still work.
      }
    }

    try {
      if (statusMessage != null) {
        final normalizedStatus = statusMessage.trim();
        await _matrix.setPresence(
          userId,
          _preferences.sharePresence
              ? PresenceType.online
              : PresenceType.offline,
          statusMsg: normalizedStatus,
        );
        _profileStatusMessage = normalizedStatus.isEmpty
            ? null
            : normalizedStatus;
      }
      await setText(_profileBioField, bio);
      await setText(_profilePronounsField, pronouns);
      await setText('m.tz', timezone);
      if (profileColor != null) {
        await setText(
          _profileColorField,
          '#${profileColor.toRadixString(16).padLeft(8, '0').substring(2)}',
        );
        _profileColor = profileColor;
      }
      if (profileColorSecondary != null &&
          supports(_profileColorSecondaryField)) {
        await setText(
          _profileColorSecondaryField,
          '#${profileColorSecondary.toRadixString(16).padLeft(8, '0').substring(2)}',
        );
      }
      if (removeBanner) {
        if (!supports(_profileBannerField)) unsupported(_profileBannerField);
        try {
          await _matrix.deleteProfileField(userId, _profileBannerField);
        } on MatrixException catch (exception) {
          if (exception.error != MatrixError.M_UNRECOGNIZED) rethrow;
        }
      } else if (bannerBytes != null) {
        if (!supports(_profileBannerField)) unsupported(_profileBannerField);
        final mxc = await _matrix.uploadContent(
          bannerBytes,
          filename: 'profile-banner.png',
          contentType: 'image/png',
        );
        try {
          await _matrix.setProfileField(userId, _profileBannerField, {
            _profileBannerField: mxc.toString(),
          });
        } on MatrixException catch (exception) {
          if (exception.error != MatrixError.M_UNRECOGNIZED) rethrow;
        }
      }
      _profileCache.remove(userId);
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _updateOwnVoicePresentation({
    int? color,
    Uint8List? backgroundBytes,
    required bool removeColor,
    required bool removeBackground,
  }) async {
    final userId = _matrix.userID;
    if (userId == null) return;
    final capability = await _profileCapability();
    bool supports(String key) {
      if (capability?.enabled != true) return false;
      final allowed = capability?.allowed;
      if (allowed != null) return allowed.contains(key);
      return !(capability?.disallowed?.contains(key) ?? false);
    }

    Never unsupported(String key) => throw UnsupportedError(
      'This homeserver does not advertise support for the profile field $key.',
    );

    try {
      if (removeColor) {
        if (!supports(_profileVoiceColorField)) {
          unsupported(_profileVoiceColorField);
        }
        await _matrix.deleteProfileField(userId, _profileVoiceColorField);
      } else if (color != null) {
        if (!supports(_profileVoiceColorField)) {
          unsupported(_profileVoiceColorField);
        }
        final value =
            '#${color.toRadixString(16).padLeft(8, '0').substring(2)}';
        await _matrix.setProfileField(userId, _profileVoiceColorField, {
          _profileVoiceColorField: value,
        });
      }
      if (removeBackground) {
        if (!supports(_profileVoiceBackgroundField)) {
          unsupported(_profileVoiceBackgroundField);
        }
        await _matrix.deleteProfileField(userId, _profileVoiceBackgroundField);
      } else if (backgroundBytes != null) {
        if (!supports(_profileVoiceBackgroundField)) {
          unsupported(_profileVoiceBackgroundField);
        }
        final mxc = await _matrix.uploadContent(
          backgroundBytes,
          filename: 'voice-background.png',
          contentType: 'image/png',
        );
        await _matrix.setProfileField(userId, _profileVoiceBackgroundField, {
          _profileVoiceBackgroundField: mxc.toString(),
        });
      }
      _profileCache.remove(userId);
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  int? _parseProfileColor(Object? value) {
    if (value is int) return value;
    if (value is! String) return null;
    final normalized = value.trim().replaceFirst('#', '');
    if (normalized.length != 6 && normalized.length != 8) return null;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return null;
    return normalized.length == 6 ? 0xff000000 | parsed : parsed;
  }

  Future<ProfileFieldsCapability?> _profileCapability() async {
    if (_profileFieldsCapabilityLoaded) return _profileFieldsCapability;
    try {
      _profileFieldsCapability =
          (await _matrix.getCapabilities()).mProfileFields;
    } catch (_) {
      _profileFieldsCapability = null;
    }
    _profileFieldsCapabilityLoaded = true;
    return _profileFieldsCapability;
  }

  Future<void> _startDirectChat(String userId) async {
    final roomId = await _matrix.startDirectChat(userId);
    _selectSpace(null);
    await _selectRoom(roomId);
  }

  Future<void> _setUserBlocked(String userId, bool blocked) async {
    if (blocked) {
      await _matrix.ignoreUser(userId);
    } else {
      await _matrix.unignoreUser(userId);
    }
    _notifyBackendListeners();
  }
}
