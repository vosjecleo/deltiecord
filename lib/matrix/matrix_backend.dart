import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:matrix/matrix.dart' hide RoomSummary;
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/chat_notifications.dart';
import '../services/message_search.dart';
import '../services/link_preview_policy.dart';
import '../services/secret_redaction.dart';
import '../services/timeline_window_policy.dart';
import 'matrix_client_factory.dart';
import 'media_range_proxy.dart';
import 'matrix_voice_controller.dart';

part 'matrix_event_mapping.dart';
part 'matrix_timeline_support.dart';
part 'matrix_room_metadata.dart';
part 'matrix_link_previews.dart';
part 'matrix_session.dart';
part 'matrix_crypto.dart';
part 'matrix_room_operations.dart';
part 'matrix_messages.dart';
part 'matrix_media.dart';
part 'matrix_profiles.dart';

final _webUrlPattern = RegExp(r'https?://[^\s<>]+');

/// Matrix integration built on matrix-dart-sdk. Element and FluffyChat were
/// consulted as behavioral references; no source from either client is copied.
/// See CREDITS.md for project links and license information.
class MatrixBackend extends ChatBackend {
  static const _settingsAccountDataType = 'net.deltiecord.settings';
  static const _roomPresentationEventType = deltiecordRoomPresentationEventType;
  static const _spaceChannelsEventType = deltiecordSpaceChannelsEventType;

  MatrixBackend({ChatNotificationSink? notifications})
    : _notifications = notifications ?? const SilentChatNotificationSink();

  final ChatNotificationSink _notifications;
  Client? _client;
  Timeline? _timeline;
  MatrixVoiceController? _voice;
  Timer? _typingStopTimer;
  Timer? _settingsSaveTimer;
  AppPreferences? _pendingPreferences;
  String? _typingRoomId;
  StreamSubscription<Object?>? _syncSubscription;
  StreamSubscription<Object?>? _loginSubscription;
  StreamSubscription<Object?>? _syncStatusSubscription;
  StreamSubscription<NotificationTarget>? _notificationSubscription;
  SessionStatus _status = SessionStatus.starting;
  ConnectionStatus _connectionStatus = ConnectionStatus.connecting;
  String? _error;
  String? _selectedRoomId;
  String? _selectedSpaceId;
  int _timelineGeneration = 0;
  bool _timelineLoading = false;
  bool _historyLoading = false;
  int _timelineDatabaseOffset = 0;
  bool _timelineDatabaseExhausted = false;
  bool _timelineServerExhausted = false;
  bool _timelineHasPrunedNewerEvents = false;
  final Set<String> _loadedBackupRoomIds = {};
  final Map<String, Uint8List> _avatarBytes = {};
  final Map<String, Uri?> _avatarUris = {};
  final Map<String, Uint8List> _senderAvatarBytes = {};
  final Map<String, Uri?> _senderAvatarUris = {};
  final Map<String, String> _decryptedPreviews = {};
  final Map<String, ReplyPreview> _replyPreviews = {};
  final Map<String, LinkPreview?> _linkPreviews = {};
  final Set<String> _outboundSessionsReset = {};
  bool _refreshingRoomMetadata = false;
  bool _roomMetadataRefreshRequested = false;
  final Set<String> _roomsMarkingRead = {};
  final Map<String, String> _lastMarkedReadEventIds = {};
  final Map<String, String?> _firstUnreadEventIds = {};
  final Map<String, String> _lastNotificationEventIds = {};
  final Map<String, RoomPresentation> _roomPresentationOverrides = {};
  final Map<String, Map<String, dynamic>> _spaceChannelLayoutOverrides = {};
  final Map<String, List<String>> _spaceRoomOrderOverrides = {};
  final Map<String, Set<String>> _collapsedChannelCategories = {};
  final LinkedHashMap<String, List<ChatMessage>> _roomMessageCache =
      LinkedHashMap();
  final Map<String, String> _offlineSendRooms = {};
  bool _retryingOfflineSends = false;
  bool _notificationsPrimed = false;
  bool _notificationPreviewsEnabled = true;
  AppPreferences _preferences = const AppPreferences();
  int? _maximumUploadBytes;
  List<DeviceSessionSummary> _deviceSessions = const [];
  bool _devicesLoading = false;
  String? _profileDisplayName;
  Uint8List? _profileAvatarBytes;
  UserPresence _profilePresence = UserPresence.offline;
  String? _profileStatusMessage;
  int? _profileColor;
  bool _profileLoading = false;
  ProfileFieldsCapability? _profileFieldsCapability;
  bool _profileFieldsCapabilityLoaded = false;
  int _storageUsageBytes = 0;
  bool _storageLoading = false;
  final MediaRangeProxy _mediaRangeProxy = MediaRangeProxy();
  final Map<String, MediaPlaybackSource> _mediaPlaybackSources = {};
  final Map<String, int> _mediaPlaybackReferences = {};
  EncryptionSetupState _encryptionSetup = const EncryptionSetupState(
    status: EncryptionSetupStatus.loading,
  );

  Client get _matrix => _client!;

  @override
  SessionStatus get status => _status;
  @override
  ConnectionStatus get connectionStatus => _connectionStatus;
  @override
  String? get error => _error;
  @override
  String? get userId => _client?.userID;
  @override
  String? get deviceId => _client?.deviceID;
  @override
  Uri? get homeserver => _client?.homeserver;
  @override
  String? get profileDisplayName => _profileDisplayName;
  @override
  Uint8List? get profileAvatarBytes => _profileAvatarBytes;
  @override
  UserPresence get profilePresence => _profilePresence;
  @override
  String? get profileStatusMessage => _profileStatusMessage;
  @override
  int? get profileColor => _profileColor;
  @override
  bool get profileLoading => _profileLoading;
  @override
  AppPreferences get preferences => _preferences;
  @override
  EncryptionSetupState get encryptionSetup => _encryptionSetup;
  @override
  String? get selectedSpaceId => _selectedSpaceId;
  @override
  List<SpaceSummary> get spaces => _joinedRooms
      .where((room) => room.isSpace)
      .map(
        (room) => SpaceSummary(
          id: room.id,
          name: room.getLocalizedDisplayname(),
          avatarBytes: _avatarBytes[room.id],
          topic: room.topic,
          muted: room.pushRuleState == PushRuleState.dontNotify,
        ),
      )
      .toList(growable: false);
  @override
  List<ChannelCategorySummary> get selectedSpaceCategories =>
      _channelCategoriesFor(_selectedSpaceId);
  @override
  bool get timelineLoading => _timelineLoading;
  @override
  bool get historyLoading => _historyLoading;
  @override
  bool get canLoadMoreHistory =>
      !_timelineServerExhausted && (_timeline?.canRequestHistory ?? false);
  @override
  bool get canLoadMoreFuture =>
      _timelineHasPrunedNewerEvents || (_timeline?.canRequestFuture ?? false);
  @override
  bool get atTimelinePresent =>
      !_timelineHasPrunedNewerEvents && !(_timeline?.canRequestFuture ?? false);
  @override
  String? get firstUnreadMessageId => _firstUnreadEventIds[_selectedRoomId];
  @override
  VoiceConnectionStatus get voiceConnectionStatus =>
      _voice?.status ?? VoiceConnectionStatus.disconnected;
  @override
  String? get activeVoiceRoomId => _voice?.activeRoomId;
  @override
  bool get voiceMuted => _voice?.muted ?? false;
  @override
  bool get voiceDeafened => _voice?.deafened ?? false;
  @override
  bool get voiceCameraEnabled => _voice?.cameraEnabled ?? false;
  @override
  bool get voiceScreenSharing => _voice?.screenSharing ?? false;
  @override
  double get voiceInputLevel => _voice?.inputLevel ?? 0;
  @override
  String? get voiceError => _voice?.error;
  @override
  List<AudioInputSummary> get audioInputs => _voice?.audioInputs ?? const [];
  @override
  String? get selectedAudioInputId => _voice?.selectedAudioInputId;
  @override
  List<RtcDeviceSummary> get audioOutputs => _voice?.audioOutputs ?? const [];
  @override
  String? get selectedAudioOutputId => _voice?.selectedAudioOutputId;
  @override
  List<RtcDeviceSummary> get cameras => _voice?.cameras ?? const [];
  @override
  String? get selectedCameraId => _voice?.selectedCameraId;
  @override
  List<RtcMediaStreamSummary> get rtcMediaStreams =>
      _voice?.mediaStreams ?? const [];
  @override
  List<DeviceSessionSummary> get deviceSessions => _deviceSessions;
  @override
  bool get devicesLoading => _devicesLoading;
  @override
  int get storageUsageBytes => _storageUsageBytes;
  @override
  bool get storageLoading => _storageLoading;
  @override
  List<String> get blockedUserIds => _client?.ignoredUsers ?? const [];
  @override
  List<MentionSuggestion> get mentionSuggestions {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final suggestions = room
        .getParticipants()
        .map(
          (user) => MentionSuggestion(
            matrixId: user.id,
            displayName: user.calcDisplayname(),
          ),
        )
        .toList();
    suggestions.addAll(
      _joinedRooms
          .where((room) => !room.isSpace)
          .map(
            (room) => MentionSuggestion(
              matrixId: room.id,
              displayName: room.getLocalizedDisplayname(),
              isRoom: true,
            ),
          ),
    );
    suggestions.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return suggestions;
  }

  @override
  List<String> get typingUserNames {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    return room.typingUsers
        .where((user) => user.id != _matrix.userID)
        .map((user) => user.calcDisplayname())
        .toList(growable: false);
  }

  @override
  List<RoomMemberSummary> get selectedRoomMembers {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final members = room
        .getParticipants()
        .map((user) {
          // The SDK's synchronous cache is required while building this getter;
          // network refreshes arrive through sync and notify the UI separately.
          // ignore: deprecated_member_use
          final presence = _matrix.presences[user.id]?.presence;
          return RoomMemberSummary(
            userId: user.id,
            displayName: user.calcDisplayname(),
            avatarBytes:
                _senderAvatarBytes['${room.id}|${user.id}'] ??
                _senderAvatarBytes[user.id],
            presence: switch (presence) {
              PresenceType.online => UserPresence.online,
              PresenceType.unavailable => UserPresence.away,
              _ => UserPresence.offline,
            },
            powerLevel: user.powerLevel.level,
            canChangePowerLevel:
                room.canChangePowerLevel &&
                user.id != _matrix.userID &&
                user.powerLevel < room.ownPowerLevel,
            maxAssignablePowerLevel: room.ownPowerLevel.level,
          );
        })
        .toList(growable: false);
    members.sort((a, b) {
      final presenceOrder = a.presence.index.compareTo(b.presence.index);
      return presenceOrder != 0
          ? presenceOrder
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return members;
  }

  @override
  List<ChatMessage> get pinnedMessages {
    final room = _client?.getRoomById(_selectedRoomId ?? '');
    if (room == null) return const [];
    final pinned = room.pinnedEventIds.toSet();
    return messages.where((message) => pinned.contains(message.id)).toList();
  }

  @override
  List<ChatMessage> searchMessages(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return messages
        .where(
          (message) => matchesMessageSearch(
            body: message.body,
            sender: message.sender,
            query: normalized,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> searchRoomHistory(String query) =>
      _searchRoomHistory(query);

  @override
  bool get notificationPreviewsEnabled => _notificationPreviewsEnabled;

  @override
  List<RoomSummary> get rooms {
    final selectedSpaceId = _selectedSpaceId;
    final visible = selectedSpaceId == null
        ? _homeRooms
        : _roomsForSpace(selectedSpaceId);
    return visible.map(_roomSummary).toList(growable: false);
  }

  List<Room> get _joinedRooms =>
      _client?.rooms
          .where((room) => room.membership == Membership.join)
          .toList(growable: false) ??
      const [];

  Set<String> get _allSpaceChildIds => _joinedRooms
      .where((room) => room.isSpace)
      .expand((space) => space.spaceChildren)
      .map((child) => child.roomId)
      .whereType<String>()
      .toSet();

  List<Room> get _homeRooms => _joinedRooms
      .where(
        (room) =>
            !room.isSpace &&
            (room.isDirectChat || !_allSpaceChildIds.contains(room.id)),
      )
      .toList(growable: false);

  @override
  RoomSummary? get selectedRoom => _selectedRoomSummary;

  @override
  bool get selectedRoomMuted => _selectedRoomIsMuted;

  @override
  List<ChatMessage> get messages {
    if (_timeline != null) return _mappedMessages;
    return _roomMessageCache[_selectedRoomId] ?? const [];
  }

  void _cacheCurrentRoomMessages() {
    final roomId = _selectedRoomId;
    if (roomId == null || _timeline == null) return;
    final snapshot = _mappedMessages;
    _roomMessageCache
      ..remove(roomId)
      ..[roomId] = List.unmodifiable(snapshot);
    while (_roomMessageCache.length > 4) {
      _roomMessageCache.remove(_roomMessageCache.keys.first);
    }
  }

  void _notifyBackendListeners() => notifyListeners();

  @override
  Future<void> initialize() => _initializeSession();

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) => _loginSession(
    homeserver: homeserver,
    username: username,
    password: password,
  );

  @override
  Future<void> logout() => _logoutSession();

  @override
  Future<void> refreshAudioInputs() => _refreshAudioInputs();

  @override
  Future<void> selectAudioInput(String? deviceId) =>
      _selectAudioInput(deviceId);

  @override
  Future<void> selectAudioOutput(String? deviceId) =>
      _selectAudioOutputAndRemember(deviceId);

  @override
  Future<void> selectCamera(String? deviceId) =>
      _selectCameraAndRemember(deviceId);

  @override
  Future<void> refreshDevices() => _refreshDevices();

  @override
  Future<void> refreshProfile() => _refreshProfile();

  @override
  Future<void> setProfileDisplayName(String displayName) =>
      _setProfileDisplayName(displayName);

  @override
  Future<void> setProfileAvatar(
    Uint8List? bytes, {
    String fileName = 'avatar.png',
    String mimeType = 'image/png',
  }) => _setProfileAvatar(bytes, fileName: fileName, mimeType: mimeType);

  @override
  Future<void> removeDevice(String deviceId, String password) =>
      _removeDevice(deviceId, password);

  @override
  Future<void> deleteAccount(String password) => _deleteAccount(password);

  @override
  Future<void> joinVoiceRoom(String roomId) => _joinVoiceRoom(roomId);

  @override
  Future<void> setVoiceMuted(bool muted) => _setVoiceMuted(muted);

  @override
  Future<void> setVoiceDeafened(bool deafened) =>
      _voice?.setDeafened(deafened) ?? Future.value();

  @override
  Future<void> setVoiceCameraEnabled(bool enabled) =>
      _voice?.setCameraEnabled(enabled) ?? Future.value();

  @override
  Future<void> setVoiceScreenSharing(bool enabled) =>
      _voice?.setScreenSharing(enabled) ?? Future.value();

  @override
  Future<void> setParticipantVolume(String userId, double volume) =>
      _setParticipantVolumeAndRemember(userId, volume);

  @override
  Future<void> setParticipantLocallyMuted(String userId, bool muted) =>
      _voice?.setParticipantLocallyMuted(userId, muted) ?? Future.value();

  @override
  Future<void> leaveVoiceRoom() => _leaveVoiceRoom();

  @override
  Future<void> setComposerTyping(bool typing) => _setComposerTyping(typing);

  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) =>
      _setNotificationPreviewsEnabled(enabled);

  @override
  Future<void> updatePreferences(AppPreferences preferences) =>
      _updatePreferences(preferences);

  @override
  void clearError() => _clearSessionError();
  @override
  Future<void> refreshEncryptionSetup() => _refreshEncryptionSetup();

  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) =>
      _recoverEncryption(recoveryKeyOrPassphrase);

  @override
  Future<String> createEncryptionSetup() => _createEncryptionSetup();
  @override
  void selectSpace(String? spaceId) => _selectSpace(spaceId);

  @override
  Future<void> selectRoom(String roomId) => _selectRoom(roomId);

  @override
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) => _setRoomPresentation(roomId, presentation);

  @override
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
    String topic = '',
    bool encrypted = true,
  }) => _createRoom(
    name: name,
    presentation: presentation,
    topic: topic,
    encrypted: encrypted,
  );

  @override
  Future<void> createSpace({required String name, String topic = ''}) =>
      _createSpace(name: name, topic: topic);
  @override
  Future<void> createChannelCategory(String name) =>
      _createChannelCategory(name);
  @override
  Future<void> renameChannelCategory(String categoryId, String name) =>
      _renameChannelCategory(categoryId, name);
  @override
  Future<void> deleteChannelCategory(String categoryId) =>
      _deleteChannelCategory(categoryId);
  @override
  Future<void> reorderChannelCategory(String categoryId, int newIndex) =>
      _reorderChannelCategory(categoryId, newIndex);
  @override
  Future<void> setChannelCategoryCollapsed(String categoryId, bool collapsed) =>
      _setChannelCategoryCollapsed(categoryId, collapsed);
  @override
  Future<void> moveRoomInSpace(
    String roomId, {
    String? categoryId,
    String? beforeRoomId,
  }) => _moveRoomInSpace(
    roomId,
    categoryId: categoryId,
    beforeRoomId: beforeRoomId,
  );

  @override
  Future<void> renameRoom(String roomId, String name) =>
      _renameRoom(roomId, name);

  @override
  Future<void> setRoomTopic(String roomId, String topic) =>
      _setRoomTopic(roomId, topic);

  @override
  Future<void> setRoomAvatar(String roomId, Uint8List? bytes) =>
      _setRoomAvatar(roomId, bytes);

  @override
  Future<void> leaveRoom(String roomId) => _leaveRoom(roomId);

  @override
  Future<void> setRoomMuted(String roomId, bool muted) =>
      _setRoomMuted(roomId, muted);

  @override
  Future<void> setMemberPowerLevel(String userId, int powerLevel) =>
      _setMemberPowerLevel(userId, powerLevel);

  @override
  Future<void> refreshStorageUsage() => _refreshStorageUsage();

  @override
  Future<void> clearMediaCache() => _clearMediaCache();

  @override
  Future<UserProfileSummary> getUserProfile(String userId) =>
      _getUserProfile(userId);

  @override
  Future<void> updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    String? statusMessage,
    int? profileColor,
    int? profileColorSecondary,
    Uint8List? bannerBytes,
    bool removeBanner = false,
  }) => _updateOwnProfileFields(
    bio: bio,
    pronouns: pronouns,
    timezone: timezone,
    statusMessage: statusMessage,
    profileColor: profileColor,
    profileColorSecondary: profileColorSecondary,
    bannerBytes: bannerBytes,
    removeBanner: removeBanner,
  );

  @override
  Future<List<SpaceDirectoryEntry>> searchPublicSpaces(String query) =>
      _searchPublicSpaces(query);

  @override
  Future<void> joinPublicSpace(String roomId) => _joinPublicSpace(roomId);

  @override
  Future<void> startDirectChat(String userId) => _startDirectChat(userId);

  @override
  Future<void> setUserBlocked(String userId, bool blocked) =>
      _setUserBlocked(userId, blocked);

  @override
  Future<void> setSelectedRoomMuted(bool muted) => _setSelectedRoomMuted(muted);
  @override
  Future<void> loadMoreHistory() => _loadMoreHistory();
  @override
  Future<void> loadMoreFuture() => _loadMoreFuture();
  @override
  Future<List<ChatMessage>> loadPinnedMessages() => _loadPinnedMessages();
  @override
  Future<void> jumpToPresent() => _jumpToPresent();
  @override
  Future<void> jumpToEvent(String eventId) => _jumpToEvent(eventId);

  @override
  Future<void> sendMessage(
    String body, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) => _sendMessage(
    body,
    roomId: roomId,
    formattedBody: formattedBody,
    replyToMessageId: replyToMessageId,
    editMessageId: editMessageId,
  );

  @override
  Future<void> redactMessage(String messageId) => _redactMessage(messageId);

  @override
  Future<void> retryMessage(String messageId) => _retryMessage(messageId);

  @override
  Future<void> cancelPendingMessage(String messageId) =>
      _cancelPendingMessage(messageId);

  @override
  Future<void> toggleReaction(String messageId, String key) =>
      _toggleReaction(messageId, key);
  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) => _sendAttachment(
    attachment,
    roomId: roomId,
    replyToMessageId: replyToMessageId,
  );

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) => _downloadAttachment(messageId, thumbnail: thumbnail);

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) =>
      _getMediaPlaybackSource(messageId);

  @override
  Future<void> releaseMediaPlaybackSource(String messageId) async =>
      _releaseMediaPlaybackSource(messageId);

  @override
  Future<String?> getAttachmentReference(String messageId) async =>
      _getAttachmentReference(messageId);

  Future<void> _closeTimeline() async {
    _timelineGeneration++;
    _timeline?.cancelSubscriptions();
    _timeline = null;
    _timelineDatabaseOffset = 0;
    _timelineDatabaseExhausted = false;
    _timelineServerExhausted = false;
    _timelineHasPrunedNewerEvents = false;
    _replyPreviews.clear();
    _linkPreviews.clear();
    _mediaPlaybackSources.clear();
    _mediaPlaybackReferences.clear();
    _mediaRangeProxy.clear();
  }

  String _friendlyError(Object exception) {
    return safeErrorMessage(exception);
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _settingsSaveTimer?.cancel();
    final voice = _voice;
    _voice = null;
    voice?.removeListener(notifyListeners);
    voice?.dispose();
    _timeline?.cancelSubscriptions();
    _syncSubscription?.cancel();
    _loginSubscription?.cancel();
    _syncStatusSubscription?.cancel();
    _notificationSubscription?.cancel();
    _client?.dispose();
    unawaited(_notifications.dispose());
    unawaited(_mediaRangeProxy.close());
    _offlineSendRooms.clear();
    super.dispose();
  }
}
