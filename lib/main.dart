import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:media_kit/media_kit.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;

import 'app.dart';
import 'matrix/matrix_backend.dart';
import 'services/chat_notifications.dart';
import 'services/app_sounds.dart';
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
  final backend = MatrixBackend(notifications: DesktopChatNotificationSink());
  runApp(DeltiecordApp(backend: backend));
  await backend.initialize();
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
