import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_client_factory.dart';
import 'avatar_media_pool.dart';
import 'chat_notifications.dart';

typedef AndroidPushResolver =
    Future<Map<String, Object?>?> Function(String roomId, String eventId);
typedef AndroidPushActivation =
    Future<void> Function(NotificationTarget target);

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
  if (!client.isLogged() || roomId.isEmpty || eventId.isEmpty) return null;
  try {
    await client
        .oneShotSync(timeout: Duration.zero)
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // The event endpoint below can still resolve an event if sync is slow.
  }
  final room = client.getRoomById(roomId);
  if (room == null || room.membership != Membership.join) return null;

  Event? event;
  try {
    event = await room.getEventById(eventId);
  } catch (_) {
    return null;
  }
  if (event == null) return null;
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
  if (_activeDesktopLeasePresent(client)) return null;
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

bool _activeDesktopLeasePresent(Client client) {
  final content = client.accountData['net.deltiecord.device_activity']?.content;
  final devices = content?.tryGetMap<String, Object?>('devices');
  if (devices == null) return false;
  final cutoff = DateTime.now()
      .subtract(const Duration(minutes: 2))
      .millisecondsSinceEpoch;
  for (final entry in devices.entries) {
    if (entry.key == client.deviceID || entry.value is! Map) continue;
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
    var client = _client;
    if (client == null) {
      client = await createMatrixClient();
      client.backgroundSync = false;
      await client.init();
      if (!client.isLogged()) {
        await client.dispose();
        return null;
      }
      _client = client;
    }
    return resolveAndroidPushNotification(
      client,
      roomId,
      eventId,
      avatarPool: _avatarPool,
    );
  }
}

extension on String {
  String take(int maximum) => length <= maximum ? this : substring(0, maximum);
}
