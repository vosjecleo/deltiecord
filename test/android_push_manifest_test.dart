import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UnifiedPush receiver can wake Deltiecord while Flutter is stopped', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final receiverStart =
        RegExp(
          r'<receiver\s+android:name="\.DeltiecordPushService"',
        ).firstMatch(manifest)?.start ??
        -1;
    expect(receiverStart, greaterThanOrEqualTo(0));
    final receiverEnd = manifest.indexOf('</receiver>', receiverStart);
    expect(receiverEnd, greaterThan(receiverStart));
    final declaration = manifest.substring(receiverStart, receiverEnd);

    expect(declaration, contains('android:exported="true"'));
    for (final action in [
      'MESSAGE',
      'UNREGISTERED',
      'NEW_ENDPOINT',
      'REGISTRATION_FAILED',
    ]) {
      expect(
        declaration,
        contains('org.unifiedpush.android.connector.$action'),
      );
    }
    expect(declaration, isNot(contains('PUSH_EVENT')));
  });

  test('background push decrypts locally into bounded rich notifications', () {
    final receiver = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushService.kt',
    ).readAsStringSync();
    final publisher = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordNotificationPublisher.kt',
    ).readAsStringSync();
    final worker = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushWorker.kt',
    ).readAsStringSync();

    expect(publisher, contains('.setContentText("New message")'));
    expect(receiver, isNot(contains('New Matrix activity')));
    expect(receiver, contains('sender_display_name'));
    expect(receiver, contains('room_name'));
    expect(receiver, contains('event_id'));
    expect(receiver, contains('DeltiecordPushWorker.enqueue'));
    expect(worker, contains('deltiecordPushBackgroundMain'));
    expect(worker, contains('resolveNotification'));
    expect(publisher, contains('Notification.MessagingStyle'));
    expect(publisher, contains('setData(mime, uri)'));
    expect(
      publisher,
      contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.P'),
    );
    expect(publisher, contains('R.mipmap.ic_launcher_round'));
  });
}
