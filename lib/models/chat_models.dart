import 'dart:typed_data';

import 'package:webrtc_interface/webrtc_interface.dart';

import '../services/font_preferences.dart';

enum SessionStatus { starting, signedOut, signingIn, signedIn, failed }

enum ConnectionStatus { connecting, online, reconnecting, offline }

enum InterfaceDensity { compact, cozy }

enum DeltiecordThemeMode { light, dark, oled }

enum NotificationAlertCadence { fiveMinuteCooldown, everyMessage, silent }

/// Controls the privacy-sensitive fallback from Matrix URL previews to
/// contacting the linked origin from this device.
enum DirectLinkPreviewMode { none, trustedProviders, allPublicSites }

enum RoomNotificationMode { allMessages, mentionsOnly, muted }

enum PresenceMode { online, idle, doNotDisturb, invisible }

enum AppShortcutAction {
  openSettings,
  toggleMicrophone,
  toggleDeafen,
  disconnectVoice,
  openGifPicker,
  openEmojiPicker,
  openFilePicker,
  focusComposer,
  searchRoom,
  toggleMembers,
}

const defaultShortcutBindings = <AppShortcutAction, String>{
  AppShortcutAction.openSettings: 'control+comma',
  AppShortcutAction.toggleMicrophone: 'control+shift+m',
  AppShortcutAction.toggleDeafen: 'control+shift+d',
  AppShortcutAction.disconnectVoice: 'control+shift+backslash',
  AppShortcutAction.openGifPicker: 'control+g',
  AppShortcutAction.openEmojiPicker: 'control+e',
  AppShortcutAction.openFilePicker: 'control+u',
  AppShortcutAction.focusComposer: 'control+l',
  AppShortcutAction.searchRoom: 'control+f',
  AppShortcutAction.toggleMembers: 'control+shift+u',
};

class AppPreferences {
  const AppPreferences({
    this.density = InterfaceDensity.compact,
    this.compactness = 0.5,
    this.themeMode = DeltiecordThemeMode.dark,
    this.interfaceScale = 1,
    this.fontScale = 1,
    this.use24HourTime = true,
    this.roomPanelWidth = 280,
    this.sidePanelWidth = 310,
    this.reducedMotion = false,
    this.highContrast = false,
    this.autoplayGifs = true,
    this.notificationsEnabled = true,
    this.notificationSound = true,
    this.notificationVibration = true,
    this.notificationAlertCadence = NotificationAlertCadence.fiveMinuteCooldown,
    this.sendReadReceipts = true,
    this.sendTypingNotifications = true,
    this.sharePresence = true,
    this.desktopIdleMinutes = 5,
    this.directLinkPreviewMode = DirectLinkPreviewMode.none,
    this.improveTwitterLinks = true,
    this.accentColor = 0xff6975d9,
    this.fontFamily = 'System',
    this.emojiFontFamily = systemEmojiFontFamily,
    this.showNativeTitleBar = true,
    this.rememberWindowState = true,
    this.shortcutBindings = defaultShortcutBindings,
    this.sendWithCtrlEnter = false,
    this.readReceiptMemberThreshold = 10,
    this.timelineChunkSize = 30,
    this.timelineChunkCap = 3,
    this.preferredAudioInputId = '',
    this.preferredAudioOutputId = '',
    this.preferredCameraId = '',
    this.echoCancellation = true,
    this.noiseSuppression = true,
    this.autoGainControl = true,
    this.microphoneVolume = 1,
    this.outputVolume = 1,
    this.callSound = true,
    this.shareDesktopAudio = false,
    this.enableChannelDragAndDrop = false,
    this.participantVolumes = const {},
  });

  final InterfaceDensity density;
  final double compactness;
  final DeltiecordThemeMode themeMode;
  final double interfaceScale;
  final double fontScale;
  final bool use24HourTime;
  final double roomPanelWidth;
  final double sidePanelWidth;
  final bool reducedMotion;
  final bool highContrast;
  final bool autoplayGifs;
  final bool notificationsEnabled;
  final bool notificationSound;
  final bool notificationVibration;
  final NotificationAlertCadence notificationAlertCadence;
  final bool sendReadReceipts;
  final bool sendTypingNotifications;
  final bool sharePresence;
  final int desktopIdleMinutes;

  /// Allows privacy-sensitive fallback preview requests to linked websites.
  ///
  /// Homeserver-generated Matrix previews remain enabled regardless. New
  /// installations deliberately default this to false.
  final DirectLinkPreviewMode directLinkPreviewMode;

  /// Compatibility view for older call sites and stored settings.
  bool get fetchDirectLinkPreviews =>
      directLinkPreviewMode != DirectLinkPreviewMode.none;
  final bool improveTwitterLinks;
  final int accentColor;
  final String fontFamily;
  final String emojiFontFamily;
  final bool showNativeTitleBar;
  final bool rememberWindowState;
  final Map<AppShortcutAction, String> shortcutBindings;
  final bool sendWithCtrlEnter;
  final int readReceiptMemberThreshold;
  final int timelineChunkSize;
  final int timelineChunkCap;
  final String preferredAudioInputId;
  final String preferredAudioOutputId;
  final String preferredCameraId;
  final bool echoCancellation;
  final bool noiseSuppression;
  final bool autoGainControl;
  final double microphoneVolume;
  final double outputVolume;
  final bool callSound;
  final bool shareDesktopAudio;
  final bool enableChannelDragAndDrop;
  final Map<String, double> participantVolumes;

  AppPreferences copyWith({
    InterfaceDensity? density,
    double? compactness,
    DeltiecordThemeMode? themeMode,
    double? interfaceScale,
    double? fontScale,
    bool? use24HourTime,
    double? roomPanelWidth,
    double? sidePanelWidth,
    bool? reducedMotion,
    bool? highContrast,
    bool? autoplayGifs,
    bool? notificationsEnabled,
    bool? notificationSound,
    bool? notificationVibration,
    NotificationAlertCadence? notificationAlertCadence,
    bool? sendReadReceipts,
    bool? sendTypingNotifications,
    bool? sharePresence,
    int? desktopIdleMinutes,
    DirectLinkPreviewMode? directLinkPreviewMode,
    bool? fetchDirectLinkPreviews,
    bool? improveTwitterLinks,
    int? accentColor,
    String? fontFamily,
    String? emojiFontFamily,
    bool? showNativeTitleBar,
    bool? rememberWindowState,
    Map<AppShortcutAction, String>? shortcutBindings,
    bool? sendWithCtrlEnter,
    int? readReceiptMemberThreshold,
    int? timelineChunkSize,
    int? timelineChunkCap,
    String? preferredAudioInputId,
    String? preferredAudioOutputId,
    String? preferredCameraId,
    bool? echoCancellation,
    bool? noiseSuppression,
    bool? autoGainControl,
    double? microphoneVolume,
    double? outputVolume,
    bool? callSound,
    bool? shareDesktopAudio,
    bool? enableChannelDragAndDrop,
    Map<String, double>? participantVolumes,
  }) => AppPreferences(
    density: density ?? this.density,
    compactness: compactness ?? this.compactness,
    themeMode: themeMode ?? this.themeMode,
    interfaceScale: interfaceScale ?? this.interfaceScale,
    fontScale: fontScale ?? this.fontScale,
    use24HourTime: use24HourTime ?? this.use24HourTime,
    roomPanelWidth: roomPanelWidth ?? this.roomPanelWidth,
    sidePanelWidth: sidePanelWidth ?? this.sidePanelWidth,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    highContrast: highContrast ?? this.highContrast,
    autoplayGifs: autoplayGifs ?? this.autoplayGifs,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    notificationSound: notificationSound ?? this.notificationSound,
    notificationVibration: notificationVibration ?? this.notificationVibration,
    notificationAlertCadence:
        notificationAlertCadence ?? this.notificationAlertCadence,
    sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
    sendTypingNotifications:
        sendTypingNotifications ?? this.sendTypingNotifications,
    sharePresence: sharePresence ?? this.sharePresence,
    desktopIdleMinutes: desktopIdleMinutes ?? this.desktopIdleMinutes,
    directLinkPreviewMode:
        directLinkPreviewMode ??
        (fetchDirectLinkPreviews == null
            ? this.directLinkPreviewMode
            : fetchDirectLinkPreviews
            ? DirectLinkPreviewMode.allPublicSites
            : DirectLinkPreviewMode.none),
    improveTwitterLinks: improveTwitterLinks ?? this.improveTwitterLinks,
    accentColor: accentColor ?? this.accentColor,
    fontFamily: fontFamily ?? this.fontFamily,
    emojiFontFamily: emojiFontFamily ?? this.emojiFontFamily,
    showNativeTitleBar: showNativeTitleBar ?? this.showNativeTitleBar,
    rememberWindowState: rememberWindowState ?? this.rememberWindowState,
    shortcutBindings: shortcutBindings ?? this.shortcutBindings,
    sendWithCtrlEnter: sendWithCtrlEnter ?? this.sendWithCtrlEnter,
    readReceiptMemberThreshold:
        readReceiptMemberThreshold ?? this.readReceiptMemberThreshold,
    timelineChunkSize: timelineChunkSize ?? this.timelineChunkSize,
    timelineChunkCap: timelineChunkCap ?? this.timelineChunkCap,
    preferredAudioInputId: preferredAudioInputId ?? this.preferredAudioInputId,
    preferredAudioOutputId:
        preferredAudioOutputId ?? this.preferredAudioOutputId,
    preferredCameraId: preferredCameraId ?? this.preferredCameraId,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    autoGainControl: autoGainControl ?? this.autoGainControl,
    microphoneVolume: microphoneVolume ?? this.microphoneVolume,
    outputVolume: outputVolume ?? this.outputVolume,
    callSound: callSound ?? this.callSound,
    shareDesktopAudio: shareDesktopAudio ?? this.shareDesktopAudio,
    enableChannelDragAndDrop:
        enableChannelDragAndDrop ?? this.enableChannelDragAndDrop,
    participantVolumes: participantVolumes ?? this.participantVolumes,
  );
}

enum EncryptionSetupStatus {
  loading,
  ready,
  needsRecovery,
  needsRepair,
  needsSetup,
  unavailable,
  error,
}

class EncryptionSetupState {
  const EncryptionSetupState({
    required this.status,
    this.keyBackupEnabled = false,
    this.crossSigningEnabled = false,
    this.deviceVerified = false,
    this.message,
  });

  final EncryptionSetupStatus status;
  final bool keyBackupEnabled;
  final bool crossSigningEnabled;
  final bool deviceVerified;
  final String? message;

  bool get needsAttention =>
      status != EncryptionSetupStatus.ready &&
      status != EncryptionSetupStatus.loading;
}

class SpaceSummary {
  const SpaceSummary({
    required this.id,
    required this.name,
    this.avatarBytes,
    this.topic = '',
    this.muted = false,
  });

  final String id;
  final String name;
  final Uint8List? avatarBytes;
  final String topic;
  final bool muted;
}

enum RoomPresentation { text, voice }

/// Deltiecord channel grouping stored on a Matrix Space.
class ChannelCategorySummary {
  const ChannelCategorySummary({
    required this.id,
    required this.name,
    required this.roomIds,
    this.collapsed = false,
  });

  final String id;
  final String name;
  final List<String> roomIds;
  final bool collapsed;
}

enum VoiceConnectionStatus {
  disconnected,
  connecting,
  reconnecting,
  connected,
  disconnecting,
  error,
}

class AudioInputSummary {
  const AudioInputSummary({required this.id, required this.label});

  final String id;
  final String label;
}

class RtcDeviceSummary {
  const RtcDeviceSummary({required this.id, required this.label});

  final String id;
  final String label;
}

class RtcMediaStreamSummary {
  const RtcMediaStreamSummary({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.stream,
    required this.local,
    required this.screenShare,
    required this.videoMuted,
  });

  final String id;
  final String userId;
  final String displayName;
  final MediaStream stream;
  final bool local;
  final bool screenShare;
  final bool videoMuted;
}

class DeviceSessionSummary {
  const DeviceSessionSummary({
    required this.id,
    required this.displayName,
    required this.current,
    this.lastSeenAt,
    this.lastSeenIp,
    this.verified = false,
    this.crossSigned = false,
  });

  final String id;
  final String displayName;
  final bool current;
  final DateTime? lastSeenAt;
  final String? lastSeenIp;
  final bool verified;
  final bool crossSigned;
}

enum UserPresence { online, away, doNotDisturb, offline }

class RoomMemberSummary {
  const RoomMemberSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.presence = UserPresence.offline,
    this.powerLevel = 0,
    this.canChangePowerLevel = false,
    this.maxAssignablePowerLevel = 0,
    this.membership = 'join',
    this.canKick = false,
    this.canBan = false,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final UserPresence presence;
  final int powerLevel;
  final bool canChangePowerLevel;
  final int maxAssignablePowerLevel;
  final String membership;
  final bool canKick;
  final bool canBan;
}

class UserProfileSummary {
  const UserProfileSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.bannerBytes,
    this.presence = UserPresence.offline,
    this.bio,
    this.pronouns,
    this.timezone,
    this.statusMessage,
    this.profileColor,
    this.profileColorSecondary,
    this.voiceColor,
    this.voiceBackgroundBytes,
    this.extensibleFieldsSupported = true,
    this.blocked = false,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final Uint8List? bannerBytes;
  final UserPresence presence;
  final String? bio;
  final String? pronouns;
  final String? timezone;
  final String? statusMessage;

  /// Top colour of Deltiecord's interoperable, client-namespaced gradient.
  final int? profileColor;

  /// Bottom colour of Deltiecord's interoperable, client-namespaced gradient.
  final int? profileColorSecondary;

  /// Optional Deltiecord voice-tile colour. When absent, clients derive a
  /// colour from the avatar rather than reusing the profile banner.
  final int? voiceColor;

  /// Optional independently cropped background used only in RTC tiles.
  final Uint8List? voiceBackgroundBytes;
  final bool extensibleFieldsSupported;
  final bool blocked;
}

class SpaceDirectoryEntry {
  const SpaceDirectoryEntry({
    required this.roomId,
    required this.name,
    required this.memberCount,
    this.topic = '',
    this.avatarBytes,
  });

  final String roomId;
  final String name;
  final int memberCount;
  final String topic;
  final Uint8List? avatarBytes;
}

class VoiceParticipantSummary {
  const VoiceParticipantSummary({
    required this.userId,
    required this.displayName,
    this.avatarBytes,
    this.speaking = false,
    this.localVolume = 1,
    this.locallyMuted = false,
  });

  final String userId;
  final String displayName;
  final Uint8List? avatarBytes;
  final bool speaking;
  final double localVolume;
  final bool locallyMuted;
}

class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.unreadCount,
    this.highlightCount = 0,
    required this.usesChannelIcon,
    this.presentation = RoomPresentation.text,
    this.voiceParticipants = const [],
    this.avatarBytes,
    this.topic = '',
    this.isDirect = false,
    this.presence = UserPresence.offline,
    this.notificationMode = RoomNotificationMode.allMessages,
    this.mutedUntil,
    this.markedUnread = false,
    this.lastActivityAt,
  });

  final String id;
  final String name;
  final String lastMessage;
  final int unreadCount;
  final int highlightCount;
  final bool usesChannelIcon;
  final RoomPresentation presentation;
  final List<VoiceParticipantSummary> voiceParticipants;
  final Uint8List? avatarBytes;
  final String topic;
  final bool isDirect;
  final UserPresence presence;
  final RoomNotificationMode notificationMode;
  final DateTime? mutedUntil;
  final bool markedUnread;

  /// Timestamp of the newest event represented by [lastMessage].
  ///
  /// Navigation UIs use this for compact relative activity labels. It remains
  /// nullable for rooms whose homeserver has not supplied any timeline event.
  final DateTime? lastActivityAt;

  bool get isVoice => presentation == RoomPresentation.voice;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.pending,
    this.failed = false,
    this.transferStatus,
    this.system = false,
    this.own = false,
    this.canRedact = false,
    this.edited = false,
    this.redacted = false,
    this.reactions = const [],
    this.attachment,
    this.formattedBody,
    this.reply,
    this.avatarBytes,
    this.linkPreview,
    this.additionalLinkPreviews = const [],
    this.readBy = const [],
    this.senderId,
    this.blocked = false,
    this.queued = false,
    this.poll,
    this.bookmarked = false,
    this.pinned = false,
    this.pingedCurrentUser = false,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool pending;
  final bool failed;
  final String? transferStatus;
  final bool system;
  final bool own;
  final bool canRedact;
  final bool edited;
  final bool redacted;
  final List<ReactionSummary> reactions;
  final ChatAttachment? attachment;
  final String? formattedBody;
  final ReplyPreview? reply;
  final Uint8List? avatarBytes;
  final LinkPreview? linkPreview;
  final List<LinkPreview> additionalLinkPreviews;

  List<LinkPreview> get linkPreviews => [
    ?linkPreview,
    ...additionalLinkPreviews,
  ];
  final List<ReceiptReaderSummary> readBy;
  final String? senderId;
  final bool blocked;
  final bool queued;
  final PollSummary? poll;
  final bool bookmarked;
  final bool pinned;
  final bool pingedCurrentUser;
}

class PollSummary {
  const PollSummary({
    required this.question,
    required this.answers,
    required this.maxSelections,
    required this.ended,
    required this.disclosed,
  });

  final String question;
  final List<PollAnswerSummary> answers;
  final int maxSelections;
  final bool ended;
  final bool disclosed;
}

class PollAnswerSummary {
  const PollAnswerSummary({
    required this.id,
    required this.text,
    required this.votes,
    this.selectedByMe = false,
  });

  final String id;
  final String text;
  final int votes;
  final bool selectedByMe;
}

class PollDraft {
  const PollDraft({
    required this.question,
    required this.answers,
    this.maxSelections = 1,
    this.disclosed = false,
  });

  final String question;
  final List<String> answers;
  final int maxSelections;
  final bool disclosed;
}

class ScheduledMessageSummary {
  const ScheduledMessageSummary({
    required this.id,
    required this.roomId,
    required this.body,
    required this.sendAt,
    this.replyToMessageId,
  });

  final String id;
  final String roomId;
  final String body;
  final DateTime sendAt;
  final String? replyToMessageId;
}

enum InboxItemKind { mention, reply, reaction, missedCall, invite }

class InboxItemSummary {
  const InboxItemSummary({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.kind,
    required this.timestamp,
    required this.preview,
    this.eventId,
    this.avatarBytes,
    this.isSpace = false,
  });

  final String id;
  final String roomId;
  final String roomName;
  final InboxItemKind kind;
  final DateTime timestamp;
  final String preview;
  final String? eventId;
  final Uint8List? avatarBytes;
  final bool isSpace;
}

class StickerPackSummary {
  const StickerPackSummary({
    required this.id,
    required this.name,
    required this.stickers,
    this.roomScoped = false,
  });

  final String id;
  final String name;
  final List<StickerSummary> stickers;
  final bool roomScoped;
}

class StickerSummary {
  const StickerSummary({
    required this.id,
    required this.name,
    required this.mxcUri,
    this.body,
    this.width,
    this.height,
    this.previewBytes,
  });

  final String id;
  final String name;
  final Uri mxcUri;
  final String? body;
  final int? width;
  final int? height;
  final Uint8List? previewBytes;
}

class StickerPackDraft {
  const StickerPackDraft({required this.name, required this.stickers});

  final String name;
  final List<StickerDraftItem> stickers;
}

class StickerDraftItem {
  const StickerDraftItem({
    required this.shortcode,
    required this.bytes,
    required this.mimeType,
  });

  final String shortcode;
  final Uint8List bytes;
  final String mimeType;
}

class SpacePagesSummary {
  const SpacePagesSummary({
    this.welcome = '',
    this.rules = '',
    this.suggestedNotificationMode = RoomNotificationMode.mentionsOnly,
  });

  final String welcome;
  final String rules;
  final RoomNotificationMode suggestedNotificationMode;
}

class SpaceProfileOverride {
  const SpaceProfileOverride({
    required this.spaceId,
    this.nickname,
    this.pronouns,
    this.avatarBytes,
    this.bannerBytes,
    this.bio,
    this.statusMessage,
    this.timezone,
    this.accentColor,
    this.accentColorSecondary,
    this.voiceColor,
    this.voiceBackgroundBytes,
  });

  final String spaceId;
  final String? nickname;
  final String? pronouns;
  final Uint8List? avatarBytes;
  final Uint8List? bannerBytes;
  final String? bio;
  final String? statusMessage;
  final String? timezone;
  final int? accentColor;
  final int? accentColorSecondary;
  final int? voiceColor;
  final Uint8List? voiceBackgroundBytes;
}

class ReceiptReaderSummary {
  const ReceiptReaderSummary({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
}

class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.imageBytes,
    this.videoUrl,
    this.width,
    this.height,
  });

  final Uri url;
  final String? title;
  final String? description;
  final String? siteName;
  final Uint8List? imageBytes;
  final Uri? videoUrl;
  final int? width;
  final int? height;
}

enum AttachmentKind { image, video, audio, file }

class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.encrypted,
    required this.spoiler,
    this.caption,
    this.hasThumbnail = false,
    this.animated = false,
    this.width,
    this.height,
    this.thumbnailSize,
    this.thumbnailWidth,
    this.thumbnailHeight,
  });

  final AttachmentKind kind;
  final String name;
  final String mimeType;
  final int? size;
  final bool encrypted;
  final bool spoiler;
  final String? caption;
  final bool hasThumbnail;
  final bool animated;
  final int? width;
  final int? height;
  final int? thumbnailSize;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
}

class AttachmentDraft {
  const AttachmentDraft({
    required this.bytes,
    required this.name,
    required this.mimeType,
    required this.spoiler,
    this.caption,
    this.voiceMessage = false,
    this.durationMilliseconds,
    this.waveform,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
  final bool spoiler;
  final String? caption;
  final bool voiceMessage;
  final int? durationMilliseconds;
  final List<int>? waveform;
}

class MediaPlaybackSource {
  const MediaPlaybackSource({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class MentionSuggestion {
  const MentionSuggestion({
    required this.matrixId,
    required this.displayName,
    this.isRoom = false,
  });

  /// Matrix user ID or room ID targeted by the generated matrix.to link.
  final String matrixId;
  final String displayName;
  final bool isRoom;
}

class ReactionSummary {
  const ReactionSummary({
    required this.key,
    required this.count,
    required this.reactedByMe,
    this.latestSenderId,
    this.latestSender,
    this.latestTimestamp,
  });

  final String key;
  final int count;
  final bool reactedByMe;
  final String? latestSenderId;
  final String? latestSender;
  final DateTime? latestTimestamp;
}

class ReplyPreview {
  const ReplyPreview({
    required this.eventId,
    required this.sender,
    required this.body,
  });

  final String eventId;
  final String sender;
  final String body;
}
