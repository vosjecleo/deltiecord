import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_client_factory.dart';
import '../matrix/matrix_push_reconciliation.dart';
import 'avatar_media_pool.dart';
import 'chat_notifications.dart';

typedef AndroidPushResolver =
    Future<Map<String, Object?>?> Function(String roomId, String eventId);
typedef AndroidPushActivation =
    Future<void> Function(NotificationTarget target);
typedef AndroidPushAction =
    Future<bool> Function(
      String roomId,
      String eventId,
      String action,
      String? reply,
    );
typedef AndroidPushPusherReconcile = Future<String> Function(String endpoint);

/// Bidirectional boundary used by Android's background push worker.
///
/// The UnifiedPush gateway transports only room/event identifiers. Android
/// asks the already-running Matrix client (or a headless client) to sync and
/// decrypt locally, so plaintext and Matrix credentials never pass through the
/// distributor or push gateway.
final class AndroidPushBridge {
  AndroidPushBridge._();

  static const _channel = MethodChannel(
    'net.deltie.deltiecord/background_push',
  );

  static Future<void> bind({
    required AndroidPushResolver resolve,
    AndroidPushActivation? activate,
    AndroidPushAction? performAction,
    AndroidPushPusherReconcile? reconcilePusher,
  }) async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'resolveNotification') {
        final arguments = call.arguments;
        if (arguments is! Map) return null;
        final roomId = arguments['roomId'];
        final eventId = arguments['eventId'];
        if (roomId is! String || eventId is! String) return null;
        return resolve(roomId, eventId);
      }
      if (call.method == 'onNotificationActivated' && activate != null) {
        final arguments = call.arguments;
        if (arguments is! Map) return null;
        final roomId = arguments['roomId'];
        final eventId = arguments['eventId'];
        if (roomId is String && eventId is String) {
          await activate(NotificationTarget(roomId: roomId, eventId: eventId));
        }
      }
      if (call.method == 'performNotificationAction' && performAction != null) {
        final arguments = call.arguments;
        if (arguments is! Map) return false;
        final roomId = arguments['roomId'];
        final eventId = arguments['eventId'];
        final action = arguments['action'];
        final reply = arguments['reply'];
        if (roomId is String && eventId is String && action is String) {
          return performAction(
            roomId,
            eventId,
            action,
            reply is String ? reply : null,
          );
        }
        return false;
      }
      if (call.method == 'reconcilePusher' && reconcilePusher != null) {
        final arguments = call.arguments;
        if (arguments is! Map) return null;
        final endpoint = arguments['endpoint'];
        if (endpoint is String && endpoint.isNotEmpty) {
          return reconcilePusher(endpoint);
        }
        return null;
      }
      return null;
    });
    await _channel.invokeMethod<void>('ready');
    final initial = await _channel.invokeMapMethod<String, Object?>(
      'getInitialTarget',
    );
    final roomId = initial?['roomId'];
    final eventId = initial?['eventId'];
    if (activate != null && roomId is String && eventId is String) {
      await activate(NotificationTarget(roomId: roomId, eventId: eventId));
    }
  }

  static bool get _supported => !kIsWeb && Platform.isAndroid;
}

/// Resolves one Matrix event into bounded, secret-free notification data.
Future<Map<String, Object?>?> resolveAndroidPushNotification(
  Client client,
  String roomId,
  String eventId, {
  AvatarMediaPool? avatarPool,
}) async {
  if (!client.isLogged() || roomId.isEmpty || eventId.isEmpty) {
    return const {'resolutionStatus': 'session_unavailable'};
  }
  try {
    await client
        .oneShotSync(timeout: Duration.zero)
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // The event endpoint below can still resolve an event if sync is slow.
  }
  final room = client.getRoomById(roomId);
  if (room == null || room.membership != Membership.join) {
    return const {'resolutionStatus': 'event_unavailable'};
  }

  Event? event;
  try {
    event = await room.getEventById(eventId);
  } catch (_) {
    return const {'resolutionStatus': 'event_unavailable'};
  }
  if (event == null) {
    return const {'resolutionStatus': 'event_unavailable'};
  }
  var displayEvent = event;
  if (event.type == EventTypes.Encrypted && client.encryption != null) {
    try {
      displayEvent = await client.encryption!.decryptRoomEvent(event);
    } catch (_) {
      // A missing room key is represented honestly; later pushes can replace
      // this placeholder after the key arrives.
    }
  }

  final settings = client.accountData['net.deltiecord.settings']?.content;
  Map<String, Object?>? desktopActivity =
      client.accountData['net.deltiecord.device_activity']?.content;
  final userId = client.userID;
  if (userId != null) {
    try {
      desktopActivity = await client
          .getAccountData(userId, 'net.deltiecord.device_activity')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // The local copy remains a useful best-effort lease if account-data
      // refresh is temporarily unavailable.
    }
  }
  if (hasActiveDesktopLease(
    desktopActivity,
    currentDeviceId: client.deviceID,
  )) {
    return const {'resolutionStatus': 'suppressed_active_desktop'};
  }
  final previewsEnabled =
      settings?.tryGet<bool>('notification_previews') ?? true;
  final sender = displayEvent.senderFromMemoryOrFallback;
  final senderName = sender.calcDisplayname();
  final decrypted = displayEvent.type != EventTypes.Encrypted;
  final calculatedBody = displayEvent.type == EventTypes.Message
      ? displayEvent.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        )
      : 'New room activity';
  final body = previewsEnabled && decrypted && calculatedBody.trim().isNotEmpty
      ? calculatedBody.trim()
      : 'New message';

  final pool = avatarPool ?? AvatarMediaPool();
  Uint8List? avatar;
  final avatarUri = sender.avatarUrl;
  if (avatarUri != null && avatarUri.isScheme('mxc')) {
    try {
      avatar = await pool.load(
        avatarUri,
        AvatarMediaPool.rowDimension,
        () async {
          final response = await client.getContentThumbnail(
            avatarUri.host,
            avatarUri.pathSegments.join('/'),
            AvatarMediaPool.rowDimension,
            AvatarMediaPool.rowDimension,
            method: Method.crop,
            animated: false,
          );
          return response.data;
        },
      );
    } catch (_) {
      avatar = null;
    }
  }

  Uint8List? image;
  String? imageMimeType;
  if (previewsEnabled &&
      decrypted &&
      displayEvent.hasAttachment &&
      displayEvent.attachmentMimetype.startsWith('image/')) {
    final useThumbnail = displayEvent.hasThumbnail;
    final candidateSize = useThumbnail
        ? displayEvent.thumbnailInfoMap.tryGet<int>('size')
        : displayEvent.infoMap.tryGet<int>('size');
    if (candidateSize == null || candidateSize <= 3 * 1024 * 1024) {
      try {
        final file = await displayEvent.downloadAndDecryptAttachment(
          getThumbnail: useThumbnail,
        );
        if (file.bytes.length <= 3 * 1024 * 1024) {
          image = file.bytes;
          imageMimeType = file.mimeType.startsWith('image/')
              ? file.mimeType
              : displayEvent.attachmentMimetype;
        }
      } catch (_) {
        image = null;
      }
    }
  }

  return <String, Object?>{
    'roomId': room.id,
    'eventId': event.eventId,
    'roomName': room.getLocalizedDisplayname().take(160),
    'senderName': senderName.take(160),
    'body': body.take(4096),
    'timestamp': event.originServerTs.millisecondsSinceEpoch,
    'groupConversation': !room.isDirectChat,
    'senderAvatar': ?avatar,
    'image': ?image,
    'imageMimeType': ?imageMimeType,
    'sound': settings?.tryGet<bool>('notification_sound') ?? true,
    'vibrate': settings?.tryGet<bool>('notification_vibration') ?? true,
    'alertCadence':
        settings?.tryGet<String>('notification_alert_cadence') ??
        'fiveMinuteCooldown',
  };
}

/// Whether another desktop device currently owns the user's notification UI.
///
/// Desktop publishes a short renewable lease while foregrounded and active.
/// Android suppresses external push notifications only for that state; an
/// idle, backgrounded, expired, or mobile lease never silences the phone.
bool hasActiveDesktopLease(
  Map<String, Object?>? content, {
  required String? currentDeviceId,
  DateTime? now,
}) {
  final devices = content?.tryGetMap<String, Object?>('devices');
  if (devices == null) return false;
  final cutoff = (now ?? DateTime.now())
      .subtract(const Duration(minutes: 2))
      .millisecondsSinceEpoch;
  for (final entry in devices.entries) {
    if (entry.key == currentDeviceId || entry.value is! Map) continue;
    final lease = entry.value as Map;
    final platform = lease['platform'];
    final updatedAt = lease['updated_at'];
    final idle = lease['idle'];
    if ((platform == 'linux' || platform == 'windows' || platform == 'macos') &&
        updatedAt is num &&
        updatedAt.toInt() >= cutoff &&
        idle == false) {
      return true;
    }
  }
  return false;
}

/// Entry-point state for Android workers that run without an Activity.
final class HeadlessAndroidPushResolver {
  Client? _client;
  final AvatarMediaPool _avatarPool = AvatarMediaPool();

  Future<Map<String, Object?>?> resolve(String roomId, String eventId) async {
    final client = await _readyClient();
    if (client == null) return null;
    return resolveAndroidPushNotification(
      client,
      roomId,
      eventId,
      avatarPool: _avatarPool,
    );
  }

  Future<bool> perform(
    String roomId,
    String eventId,
    String action,
    String? reply,
  ) async {
    final client = await _readyClient();
    final room = client?.getRoomById(roomId);
    if (client == null || room == null) return false;
    try {
      switch (action) {
        case 'reply':
          final body = reply?.trim() ?? '';
          if (body.isEmpty) return false;
          final replyEvent = await room.getEventById(eventId);
          await room.sendTextEvent(
            body,
            inReplyTo: replyEvent,
            parseCommands: false,
            parseMarkdown: false,
          );
        case 'read':
          await room.setReadMarker(eventId, mRead: eventId);
        case 'mute':
          await room.setPushRuleState(PushRuleState.dontNotify);
        default:
          return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> reconcilePusher(String endpoint) async {
    final client = await _readyClient();
    if (client == null) return 'session_unavailable';
    return (await reconcileMatrixUnifiedPushPusher(client, endpoint)).name;
  }

  Future<Client?> _readyClient() async {
    var client = _client;
    if (client != null) return client;
    client = await createMatrixClient();
    client.backgroundSync = false;
    await client.init();
    if (!client.isLogged()) {
      await client.dispose();
      return null;
    }
    _client = client;
    return client;
  }
}

extension on String {
  String take(int maximum) => length <= maximum ? this : substring(0, maximum);
}
