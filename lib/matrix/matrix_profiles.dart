part of 'matrix_backend.dart';

const _profileBioField = 'net.deltiecord.bio';
const _profilePronounsField = 'net.deltiecord.pronouns';
const _profileBannerField = 'net.deltiecord.banner';
const _profileColorField = 'net.deltiecord.profile_color';
const _profileColorSecondaryField = 'net.deltiecord.profile_color_secondary';

/// Reads and writes standard and namespaced extensible Matrix profile fields.
///
/// Custom fields are written only when advertised by `m.profile_fields`; a
/// server without that capability continues to expose an ordinary profile.
extension _MatrixProfiles on MatrixBackend {
  Future<UserProfileSummary> _getUserProfile(
    String userId, {
    bool refresh = false,
  }) {
    final cached = _profileCache[userId];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.$2) <
            MatrixBackend._profileCacheLifetime) {
      // Reinsert to maintain least-recently-used order.
      _profileCache.remove(userId);
      _profileCache[userId] = cached;
      return Future.value(cached.$1);
    }
    final pending = _profileRequests[userId];
    if (pending != null) return pending;
    final request = _fetchUserProfile(userId).onError((error, stackTrace) {
      if (cached != null) return cached.$1;
      if (error != null) Error.throwWithStackTrace(error, stackTrace);
      throw StateError('Profile loading failed without an error.');
    });
    _profileRequests[userId] = request;
    return request.whenComplete(() => _profileRequests.remove(userId));
  }

  Future<UserProfileSummary> _fetchUserProfile(String userId) async {
    final profile = await _matrix.getUserProfile(
      userId,
      maxCacheAge: Duration.zero,
    );
    final avatarBytes = await _profileMedia(profile.avatarUrl, 512, 512);
    final bannerUri = Uri.tryParse(
      profile.additionalProperties[_profileBannerField] as String? ?? '',
    );
    final bannerBytes = await _profileOriginalMedia(bannerUri);
    final capability = await _profileCapability();
    CachedPresence? presence;
    try {
      presence = await _matrix.fetchCurrentPresence(userId);
    } catch (_) {
      // Profiles remain useful on homeservers with presence disabled.
    }
    final colorValue = profile.additionalProperties[_profileColorField];
    final result = UserProfileSummary(
      userId: userId,
      displayName:
          profile.displayname ?? userId.split(':').first.replaceFirst('@', ''),
      avatarBytes: avatarBytes,
      bannerBytes: bannerBytes,
      presence: switch (presence?.presence) {
        PresenceType.online => UserPresence.online,
        PresenceType.unavailable => UserPresence.away,
        _ => UserPresence.offline,
      },
      bio: profile.additionalProperties[_profileBioField] as String?,
      pronouns: profile.additionalProperties[_profilePronounsField] as String?,
      timezone: profile.mTz,
      statusMessage: presence?.statusMsg,
      profileColor: _parseProfileColor(colorValue),
      profileColorSecondary: _parseProfileColor(
        profile.additionalProperties[_profileColorSecondaryField],
      ),
      extensibleFieldsSupported: capability?.enabled == true,
      blocked: _matrix.ignoredUsers.contains(userId),
    );
    _profileCache.remove(userId);
    _profileCache[userId] = (result, DateTime.now());
    var mediaBytes = _profileCache.values.fold<int>(
      0,
      (total, entry) =>
          total +
          (entry.$1.avatarBytes?.length ?? 0) +
          (entry.$1.bannerBytes?.length ?? 0),
    );
    while (_profileCache.length > MatrixBackend._maximumCachedProfiles ||
        (mediaBytes > MatrixBackend._maximumCachedProfileMediaBytes &&
            _profileCache.length > 1)) {
      final removed = _profileCache.remove(_profileCache.keys.first);
      mediaBytes -=
          (removed?.$1.avatarBytes?.length ?? 0) +
          (removed?.$1.bannerBytes?.length ?? 0);
    }
    return result;
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
