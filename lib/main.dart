import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:media_kit/media_kit.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;

import 'app.dart';
import 'matrix/matrix_backend.dart';
import 'models/chat_models.dart';
import 'services/chat_notifications.dart';
import 'services/app_sounds.dart';
import 'services/android_push_bridge.dart';
import 'services/temporary_attachment_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop Flutter defaults to a 100 MiB decoded-image cache. Deltiecord also
  // keeps bounded Matrix timeline data, WebRTC, and video decoders resident,
  // so a smaller cache avoids retaining old media previews unnecessarily.
  PaintingBinding.instance.imageCache
    ..maximumSize = 250
    ..maximumSizeBytes = 48 * 1024 * 1024;
  MediaKit.ensureInitialized();
  timezone_data.initializeTimeZones();
  final temporaryAttachments = TemporaryAttachmentStore.instance;
  await temporaryAttachments.initialize();
  WidgetsBinding.instance.addObserver(
    _TemporaryAttachmentLifecycle(temporaryAttachments),
  );
  // Matrix only constructs its E2EE engine when Vodozemac is ready first.
  await vodozemac.init();
  final backend = MatrixBackend(notifications: PlatformChatNotificationSink());
  final initialization = backend.initialize();
  runApp(DeltiecordApp(backend: backend));
  unawaited(
    AndroidPushBridge.bind(
      resolve: (roomId, eventId) async {
        await initialization;
        if (backend.status != SessionStatus.signedIn) return null;
        return backend.resolveAndroidPush(roomId, eventId);
      },
      activate: (target) async {
        await initialization;
        await backend.openAndroidPushTarget(target);
      },
    ),
  );
  await initialization;
}

/// Headless Android entry point started by WorkManager for encrypted pushes.
///
/// It restores the same Matrix SDK database and crypto store as the UI client,
/// performs a bounded sync, and returns only renderable notification fields to
/// Android. Access tokens and room keys never cross the method channel.
@pragma('vm:entry-point')
Future<void> deltiecordPushBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  timezone_data.initializeTimeZones();
  await vodozemac.init();
  final resolver = HeadlessAndroidPushResolver();
  await AndroidPushBridge.bind(resolve: resolver.resolve);
  await Completer<void>().future;
}

class _TemporaryAttachmentLifecycle with WidgetsBindingObserver {
  _TemporaryAttachmentLifecycle(this.store);

  final TemporaryAttachmentStore store;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      store.cleanup();
      AppSounds.dispose();
    }
  }
}
