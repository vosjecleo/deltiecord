import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desktop_window_service.dart';

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
    bool sound = true,
  });

  Future<void> dispose();
}

/// Native Linux, Windows, and Android notification implementation.
///
/// Activation first emits a Matrix-independent target, then asks the platform
/// window service to foreground the existing process.
class PlatformChatNotificationSink implements ChatNotificationSink {
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
    bool sound = true,
  }) => _plugin.show(
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
    bool sound = true,
  }) async {}

  @override
  Future<void> dispose() async {}
}
