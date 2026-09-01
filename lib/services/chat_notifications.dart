import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_window_service.dart';
import '../models/chat_models.dart';

class InAppChatNotification {
  const InAppChatNotification({
    required this.title,
    required this.body,
    required this.onTap,
    this.avatar,
  });

  final String title;
  final String body;
  final Uint8List? avatar;
  final VoidCallback onTap;
}

/// Foreground-only notification surface shared by mobile and desktop shells.
abstract final class InAppNotificationCenter {
  static final current = ValueNotifier<InAppChatNotification?>(null);
  static Timer? _dismissTimer;

  static void show(InAppChatNotification notification) {
    current.value = notification;
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 5), dismiss);
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    current.value = null;
  }
}

/// Safe, bounded navigation data carried by a desktop notification.
class NotificationTarget {
  const NotificationTarget({required this.roomId, required this.eventId});

  final String roomId;
  final String eventId;
}

String encodeNotificationTarget(NotificationTarget target) =>
    jsonEncode({'room_id': target.roomId, 'event_id': target.eventId});

NotificationTarget? decodeNotificationTarget(String? payload) {
  if (payload == null || payload.length > 8192) return null;
  try {
    final data = jsonDecode(payload);
    if (data is! Map<String, dynamic>) return null;
    final roomId = data['room_id'];
    final eventId = data['event_id'];
    if (roomId is! String || roomId.isEmpty || roomId.length > 1024) {
      return null;
    }
    if (eventId is! String || eventId.isEmpty || eventId.length > 1024) {
      return null;
    }
    return NotificationTarget(roomId: roomId, eventId: eventId);
  } catch (_) {
    return null;
  }
}

/// Platform boundary for notifications emitted by the Matrix backend.
abstract interface class ChatNotificationSink {
  Stream<NotificationTarget> get activations;
  Future<void> initialize();
  Future<void> show({
    required String title,
    required String body,
    required String roomId,
    required String eventId,
    String? senderName,
    String? roomName,
    bool groupConversation = false,
    Uint8List? senderAvatar,
    Uint8List? image,
    String? imageMimeType,
    DateTime? timestamp,
    bool sound = true,
    bool vibrate = true,
    NotificationAlertCadence alertCadence =
        NotificationAlertCadence.fiveMinuteCooldown,
  });

  /// Warms the native background-notification avatar cache for [roomId].
  ///
  /// UnifiedPush can wake Android while Flutter is not running, so the native
  /// receiver cannot decrypt Matrix media or query the homeserver itself. The
  /// cache contains only already-renderable avatar bytes, never credentials.
  Future<void> cacheRoomAvatar(String roomId, Uint8List avatar);

  Future<void> dispose();
}

/// Native Linux, Windows, and Android notification implementation.
///
/// Activation first emits a Matrix-independent target, then asks the platform
/// window service to foreground the existing process.
class PlatformChatNotificationSink implements ChatNotificationSink {
  static const _nativeAssets = MethodChannel(
    'net.deltie.deltiecord/notification_assets',
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _activations = StreamController<NotificationTarget>.broadcast();
  var _nextId = 1;
  bool _initialized = false;

  void _activatePayload(String? payload) {
    final target = decodeNotificationTarget(payload);
    if (target == null) return;
    _activations.add(target);
    unawaited(DesktopWindowService.present());
  }

  @override
  Stream<NotificationTarget> get activations => _activations.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open Deltiecord',
        ),
        windows: WindowsInitializationSettings(
          appName: 'Deltiecord',
          appUserModelId: 'Deltie.Deltiecord.Desktop',
          guid: '2e5e8db4-f62b-4e91-b4c4-2ca41edcc91f',
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _activatePayload(response.payload),
    );
    _initialized = true;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _activatePayload(launch?.notificationResponse?.payload);
      }
    } on UnimplementedError {
      // flutter_local_notifications does not currently implement launch-detail
      // discovery on Linux. Runtime notification callbacks still work.
    }
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String roomId,
    required String eventId,
    String? senderName,
    String? roomName,
    bool groupConversation = false,
    Uint8List? senderAvatar,
    Uint8List? image,
    String? imageMimeType,
    DateTime? timestamp,
    bool sound = true,
    bool vibrate = true,
    NotificationAlertCadence alertCadence =
        NotificationAlertCadence.fiveMinuteCooldown,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _nativeAssets.invokeMethod<void>('showRichNotification', {
          'roomId': roomId,
          'eventId': eventId,
          'roomName': roomName ?? title,
          'senderName': senderName ?? title.split(' in ').first,
          'groupConversation': groupConversation,
          'body': body,
          'timestamp': (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
          'senderAvatar': ?senderAvatar,
          'image': ?image,
          'imageMimeType': ?imageMimeType,
          'sound': sound,
          'vibrate': vibrate,
          'alertCadence': alertCadence.name,
        });
        return;
      } on MissingPluginException {
        // Fall through for old/debug Android runners.
      } on PlatformException {
        // Native notification enrichment is optional.
      }
    }
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      payload: encodeNotificationTarget(
        NotificationTarget(roomId: roomId, eventId: eventId),
      ),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'deltiecord_messages',
          'Messages',
          channelDescription: 'Encrypted Matrix message notifications',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          playSound: sound,
          enableVibration: vibrate,
          largeIcon: senderAvatar == null
              ? null
              : ByteArrayAndroidBitmap(senderAvatar),
        ),
        linux: LinuxNotificationDetails(
          category: LinuxNotificationCategory.imReceived,
          urgency: LinuxNotificationUrgency.normal,
          suppressSound: !sound,
        ),
        windows: WindowsNotificationDetails(
          audio: sound ? null : WindowsNotificationAudio.silent(),
        ),
      ),
    );
  }

  @override
  Future<void> cacheRoomAvatar(String roomId, Uint8List avatar) async {
    if (roomId.isEmpty || avatar.isEmpty) return;
    try {
      await _nativeAssets.invokeMethod<void>('cacheRoomAvatar', {
        'roomId': roomId,
        'avatar': avatar,
      });
    } on MissingPluginException {
      // Desktop platforms and older Android builds have no native push cache.
    } on PlatformException {
      // Avatar enrichment is optional. A stale native cache must never make
      // room/profile hydration fail or interrupt message synchronization.
    }
  }

  @override
  Future<void> dispose() => _activations.close();
}

class SilentChatNotificationSink implements ChatNotificationSink {
  const SilentChatNotificationSink();

  @override
  Stream<NotificationTarget> get activations => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required String title,
    required String body,
    required String roomId,
    required String eventId,
    String? senderName,
    String? roomName,
    bool groupConversation = false,
    Uint8List? senderAvatar,
    Uint8List? image,
    String? imageMimeType,
    DateTime? timestamp,
    bool sound = true,
    bool vibrate = true,
    NotificationAlertCadence alertCadence =
        NotificationAlertCadence.fiveMinuteCooldown,
  }) async {}

  @override
  Future<void> cacheRoomAvatar(String roomId, Uint8List avatar) async {}

  @override
  Future<void> dispose() async {}
}
