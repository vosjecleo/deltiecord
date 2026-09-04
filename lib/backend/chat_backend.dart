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
  bool get shouldShowFirstRunTour => false;
  AppPreferences get preferences;
  EncryptionSetupState get encryptionSetup;
  List<SpaceSummary> get spaces;
  List<ChannelCategorySummary> get selectedSpaceCategories;
  String? get selectedSpaceId;
  List<RoomSummary> get rooms;
  int get directUnreadCount => rooms
      .where((room) => room.isDirect)
      .fold(0, (sum, room) => sum + room.unreadCount);
  int get serverPingCount => rooms
      .where((room) => !room.isDirect)
      .fold(0, (sum, room) => sum + room.highlightCount);
  int get totalAttentionCount => directUnreadCount + serverPingCount;
  int pingCountForSpace(String spaceId) => 0;
  RoomSummary? get selectedRoom;
  bool get selectedRoomMuted;
  RoomNotificationMode get selectedRoomNotificationMode => selectedRoomMuted
      ? RoomNotificationMode.muted
      : RoomNotificationMode.allMessages;
  DateTime? get selectedRoomMutedUntil => null;
  bool get notificationPreviewsEnabled;
  List<ChatMessage> get messages;
  List<MentionSuggestion> get mentionSuggestions;
  List<String> get typingUserNames;
  List<RoomMemberSummary> get selectedRoomMembers;
  List<ChatMessage> get pinnedMessages;
  List<ChatMessage> get bookmarkedMessages => const [];
  String? roomIdForMessage(String eventId) => selectedRoom?.id;
  List<ScheduledMessageSummary> get scheduledMessages => const [];
  List<InboxItemSummary> get unifiedInbox => const [];
  List<StickerPackSummary> get stickerPacks => const [];
  List<StickerSummary> get customEmojis => stickerPacks
      .expand((pack) => pack.stickers)
      .where((sticker) => sticker.assetType == StickerAssetType.emoji)
      .toList(growable: false);
  Future<Uint8List?> loadStickerPreview(StickerSummary sticker) async =>
      sticker.previewBytes;
  PresenceMode get presenceMode => PresenceMode.online;
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

  /// Reports whether the process is foregrounded and able to display chat.
  ///
  /// Matrix read markers must not advance merely because a background sync
  /// updated the selected room.
  void setApplicationForeground(bool foreground) {}

  /// Reconciles authoritative settings and lightweight transient state after
  /// an application resume without rebuilding the Matrix session/timelines.
  void refreshApplicationState() {}

  /// Publishes this desktop device's best-effort active/idle lease.
  ///
  /// Mobile push uses the expiring lease to avoid alerting while another
  /// Deltiecord desktop is actively being used.
  void setDesktopIdle(bool idle) {}

  /// Reports whether the selected conversation is actually visible.
  ///
  /// Mobile navigation/details layers keep the timeline mounted, so room
  /// selection alone is not sufficient evidence that a message was read.
  void setConversationVisible(bool visible) {}

  /// Reports whether the selected timeline is displaying its newest edge.
  ///
  /// A mounted room that is browsing old history must not acknowledge a new
  /// event that arrived outside the viewport.
  void setConversationAtPresent(bool atPresent) {}

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
  Future<void> kickMember(String userId, {String? reason}) async =>
      throw UnsupportedError('Kicking members is unavailable');
  Future<void> banMember(String userId, {String? reason}) async =>
      throw UnsupportedError('Banning members is unavailable');
  Future<void> timeoutMember(String userId, DateTime until) async =>
      throw UnsupportedError('Member timeouts are unavailable');
  Future<void> unbanMember(String userId) async =>
      throw UnsupportedError('Unbanning members is unavailable');
  Future<void> inviteMember(String userId, {String? reason}) async =>
      throw UnsupportedError('Inviting members is unavailable');
  Future<void> acceptRoomInvite(String roomId) async =>
      throw UnsupportedError('Joining invited rooms is unavailable');
  Future<void> rejectRoomInvite(String roomId) async =>
      throw UnsupportedError('Rejecting room invitations is unavailable');
  Future<void> approveKnock(String userId) async => inviteMember(userId);
  Future<void> rejectKnock(String userId) async =>
      kickMember(userId, reason: 'Join request declined');
  Future<List<String>> getRoomAliases(String roomId) async => const [];
  Future<void> addRoomAlias(String roomId, String alias) async =>
      throw UnsupportedError('Room aliases are unavailable');
  Future<void> deleteRoomAlias(String alias) async =>
      throw UnsupportedError('Room aliases are unavailable');
  Future<void> setRoomCanonicalAlias(String roomId, String? alias) async =>
      throw UnsupportedError('Room aliases are unavailable');

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
  Future<void> requestDeviceVerification(String deviceId) async =>
      throw UnsupportedError('Device verification is unavailable');
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
  Future<void> setRoomNotificationMode(
    String roomId,
    RoomNotificationMode mode,
  ) async => setRoomMuted(roomId, mode == RoomNotificationMode.muted);
  Future<void> muteRoomUntil(String roomId, DateTime? until) async =>
      setRoomMuted(roomId, until != null);
  Future<void> markRoomUnread(String roomId, bool unread) async {}
  Future<void> setNotificationPreviewsEnabled(bool enabled);

  /// Registers the private UnifiedPush capability endpoint with Matrix.
  /// Implementations must never log or display the full endpoint.
  Future<void> setUnifiedPushEndpoint(String endpoint) async {}

  /// Checks and repairs the current Android device's Matrix pusher.
  Future<String> reconcileUnifiedPushEndpoint(String endpoint) async =>
      'unsupported';

  Future<void> removeUnifiedPushEndpoint(String endpoint) async {}
  Future<void> updatePreferences(AppPreferences preferences);
  Future<void> loadMoreHistory({String? anchorEventId});
  Future<void> loadMoreFuture({String? anchorEventId});
  Future<List<ChatMessage>> loadPinnedMessages();
  Future<void> toggleMessagePinned(String messageId) async {}
  Future<void> toggleMessageBookmarked(String messageId) async {}
  Future<void> jumpToPresent();
  Future<void> jumpToEvent(String eventId);
  Future<void> sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  });
  Future<void> scheduleMessage(
    String text,
    DateTime sendAt, {
    String? roomId,
    String? replyToMessageId,
  }) async => throw UnsupportedError('Scheduled sending is unavailable');
  Future<void> cancelScheduledMessage(String scheduledMessageId) async {}
  Future<void> sendPoll(PollDraft poll, {String? roomId}) async =>
      throw UnsupportedError('Polls are unavailable');
  Future<void> answerPoll(String messageId, List<String> answerIds) async =>
      throw UnsupportedError('Polls are unavailable');
  Future<void> endPoll(String messageId) async =>
      throw UnsupportedError('Polls are unavailable');
  Future<void> sendSticker(StickerSummary sticker, {String? roomId}) async =>
      throw UnsupportedError('Stickers are unavailable');
  Future<void> refreshStickerPacks() async {}
  Future<void> savePersonalStickerPack(StickerPackDraft pack) async =>
      throw UnsupportedError('Sticker-pack editing is unavailable');
  bool canManageStickerPacksInRoom(String roomId) => false;
  Future<void> saveRoomStickerPack(
    String roomId,
    StickerPackDraft pack,
  ) async => throw UnsupportedError('Room sticker packs are unavailable');
  Future<void> deleteStickerPack(StickerPackSummary pack) async =>
      throw UnsupportedError('Sticker-pack deletion is unavailable');
  Future<void> setPresenceMode(PresenceMode mode) async {}
  Future<SpacePagesSummary> getSpacePages(String spaceId) async =>
      const SpacePagesSummary();
  Future<void> setSpacePages(String spaceId, SpacePagesSummary pages) async {}
  Future<SpaceProfileOverride?> getSpaceProfileOverride(String spaceId) async =>
      null;
  Future<void> setSpaceProfileOverride(SpaceProfileOverride profile) async {}
  Future<void> redactMessage(String messageId);
  Future<void> retryMessage(String messageId);
  Future<void> cancelPendingMessage(String messageId);
  Future<void> toggleReaction(
    String messageId,
    String key, {
    CustomEmojiReference? customEmoji,
  });
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
