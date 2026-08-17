import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';

/// Matrix-independent application boundary consumed by Flutter widgets.
///
/// Keeping SDK objects behind this contract lets desktop and future Android
/// interfaces share the same session, room, timeline, and crypto behavior.
abstract class ChatBackend extends ChangeNotifier {
  SessionStatus get status;
  ConnectionStatus get connectionStatus;
  String? get error;
  String? get userId;
  String? get deviceId;
  Uri? get homeserver;
  String? get profileDisplayName;
  Uint8List? get profileAvatarBytes;
  UserPresence get profilePresence;
  String? get profileStatusMessage;
  int? get profileColor;
  bool get profileLoading;

  /// Changes whenever shared cached profile data is refreshed.
  ///
  /// Profile surfaces use this to replace their resolved Future without
  /// coupling widgets to Matrix streams or polling independently.
  int get profileRevision => 0;
  AppPreferences get preferences;
  EncryptionSetupState get encryptionSetup;
  List<SpaceSummary> get spaces;
  List<ChannelCategorySummary> get selectedSpaceCategories;
  String? get selectedSpaceId;
  List<RoomSummary> get rooms;
  RoomSummary? get selectedRoom;
  bool get selectedRoomMuted;
  bool get notificationPreviewsEnabled;
  List<ChatMessage> get messages;
  List<MentionSuggestion> get mentionSuggestions;
  List<String> get typingUserNames;
  List<RoomMemberSummary> get selectedRoomMembers;
  List<ChatMessage> get pinnedMessages;
  bool get timelineLoading;
  bool get historyLoading;
  bool get canLoadMoreHistory;
  bool get canLoadMoreFuture;
  bool get atTimelinePresent;
  String? get firstUnreadMessageId;
  VoiceConnectionStatus get voiceConnectionStatus;
  String? get activeVoiceRoomId;
  bool get voiceMuted;
  bool get voiceDeafened;
  bool get voiceCameraEnabled;
  bool get voiceScreenSharing;
  double get voiceInputLevel;
  String? get voiceError;
  List<AudioInputSummary> get audioInputs;
  String? get selectedAudioInputId;
  List<RtcDeviceSummary> get audioOutputs;
  String? get selectedAudioOutputId;
  List<RtcDeviceSummary> get cameras;
  String? get selectedCameraId;
  List<RtcMediaStreamSummary> get rtcMediaStreams;
  List<DeviceSessionSummary> get deviceSessions;
  bool get devicesLoading;
  int get storageUsageBytes;
  bool get storageLoading;
  List<String> get blockedUserIds;

  Future<void> initialize();
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  });
  Future<void> logout();
  void clearError();
  Future<void> refreshEncryptionSetup();
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase);
  Future<String> createEncryptionSetup();

  /// Rotates Matrix Secure Secret Storage while retaining the connected
  /// cross-signing identity and online key backup.
  ///
  /// Implementations must reject this unless the current device already has
  /// the identity secrets locally: rotation from an unverified device could
  /// otherwise destroy the only recoverable copy.
  Future<String> regenerateEncryptionRecoveryKey() =>
      throw UnsupportedError('Recovery-key rotation is unavailable');
  void selectSpace(String? spaceId);
  Future<void> selectRoom(String roomId);
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  );
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
    String topic,
    bool encrypted,
  });
  Future<void> createSpace({required String name, String topic});
  Future<void> createChannelCategory(String name);
  Future<void> renameChannelCategory(String categoryId, String name);
  Future<void> deleteChannelCategory(String categoryId);
  Future<void> reorderChannelCategory(String categoryId, int newIndex);
  Future<void> setChannelCategoryCollapsed(String categoryId, bool collapsed);
  Future<void> moveRoomInSpace(
    String roomId, {
    String? categoryId,
    String? beforeRoomId,
  });
  int spaceChannelLayoutPowerLevel(String spaceId) => 100;
  bool canManageSpaceChannelLayout(String spaceId) => false;
  bool canSetSpaceChannelLayoutPowerLevel(String spaceId) => false;
  Future<void> setSpaceChannelLayoutPowerLevel(
    String spaceId,
    int powerLevel,
  ) async {}
  Future<void> renameRoom(String roomId, String name);
  Future<void> setRoomTopic(String roomId, String topic);
  Future<void> setRoomAvatar(String roomId, Uint8List? bytes);
  Future<void> leaveRoom(String roomId);
  Future<void> setMemberPowerLevel(String userId, int powerLevel);

  /// Returns a field-aware cached profile.
  ///
  /// Presence follows Matrix sync continuously, status and textual profile
  /// fields refresh periodically, and large profile media remains pooled.
  /// Setting [refresh] explicitly refreshes every field and re-downloads the
  /// avatar, profile banner, and voice background.
  Future<UserProfileSummary> getUserProfile(
    String userId, {
    bool refresh = false,
  });
  Future<void> updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    String? statusMessage,
    int? profileColor,
    int? profileColorSecondary,
    Uint8List? bannerBytes,
    bool removeBanner,
  });

  /// Updates Deltiecord's optional RTC tile presentation fields.
  Future<void> updateOwnVoicePresentation({
    int? color,
    Uint8List? backgroundBytes,
    bool removeColor = false,
    bool removeBackground = false,
  }) async {}
  Future<void> startDirectChat(String userId);
  Future<List<SpaceDirectoryEntry>> searchPublicSpaces(String query);
  Future<void> joinPublicSpace(String roomId);
  Future<void> setUserBlocked(String userId, bool blocked);
  Future<void> refreshAudioInputs();
  Future<void> selectAudioInput(String? deviceId);
  Future<void> selectAudioOutput(String? deviceId);
  Future<void> selectCamera(String? deviceId);
  Future<void> refreshDevices();
  Future<void> refreshProfile();
  Future<void> setProfileDisplayName(String displayName);
  Future<void> setProfileAvatar(
    Uint8List? bytes, {
    String fileName = 'avatar.png',
    String mimeType = 'image/png',
  });
  Future<void> removeDevice(String deviceId, String password);
  Future<void> deleteAccount(String password);
  Future<void> refreshStorageUsage();
  Future<void> clearMediaCache();
  Future<void> joinVoiceRoom(String roomId);
  Future<void> leaveVoiceRoom();
  Future<void> setVoiceMuted(bool muted);
  Future<void> setVoiceDeafened(bool deafened);
  Future<void> setVoiceCameraEnabled(bool enabled);
  Future<void> setVoiceScreenSharing(bool enabled);
  Future<void> setParticipantVolume(String userId, double volume);
  Future<void> setParticipantLocallyMuted(String userId, bool muted);
  Future<void> setComposerTyping(bool typing);
  List<ChatMessage> searchMessages(String query);
  Future<List<ChatMessage>> searchRoomHistory(String query);
  Future<void> setSelectedRoomMuted(bool muted);
  Future<void> setRoomMuted(String roomId, bool muted);
  Future<void> setNotificationPreviewsEnabled(bool enabled);

  /// Registers the private UnifiedPush capability endpoint with Matrix.
  /// Implementations must never log or display the full endpoint.
  Future<void> setUnifiedPushEndpoint(String endpoint) async {}

  Future<void> removeUnifiedPushEndpoint(String endpoint) async {}
  Future<void> updatePreferences(AppPreferences preferences);
  Future<void> loadMoreHistory();
  Future<void> loadMoreFuture();
  Future<List<ChatMessage>> loadPinnedMessages();
  Future<void> jumpToPresent();
  Future<void> jumpToEvent(String eventId);
  Future<void> sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  });
  Future<void> redactMessage(String messageId);
  Future<void> retryMessage(String messageId);
  Future<void> cancelPendingMessage(String messageId);
  Future<void> toggleReaction(String messageId, String key);
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  });
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  });
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId);

  /// Releases credentials and local proxy capability state held for playback.
  ///
  /// Backends without retained playback resources may keep the default no-op.
  Future<void> releaseMediaPlaybackSource(String messageId) async {}
  Future<String?> getAttachmentReference(String messageId);
}
