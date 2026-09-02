import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android excludes all app-private state from backup and transfer', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('@xml/backup_rules'));
    expect(manifest, contains('@xml/data_extraction_rules'));

    final legacy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final modern = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ]) {
      expect('$legacy\n$modern', contains('domain="$domain"'));
    }
  });

  test(
    'notification bridge bounds bitmap allocation and reply persistence',
    () {
      final decoder = File(
        'android/app/src/main/kotlin/net/deltie/deltiecord/'
        'NotificationBitmapDecoder.kt',
      ).readAsStringSync();
      final worker = File(
        'android/app/src/main/kotlin/net/deltie/deltiecord/'
        'DeltiecordPushWorker.kt',
      ).readAsStringSync();
      final replyStore = File(
        'android/app/src/main/kotlin/net/deltie/deltiecord/'
        'NotificationReplyStore.kt',
      ).readAsStringSync();
      final publisher = File(
        'android/app/src/main/kotlin/net/deltie/deltiecord/'
        'DeltiecordNotificationPublisher.kt',
      ).readAsStringSync();
      final dartResolver = File(
        'lib/matrix/matrix_session.dart',
      ).readAsStringSync();

      expect(decoder, contains('inJustDecodeBounds = true'));
      expect(decoder, contains('MAX_PIXELS'));
      expect(decoder, contains('MAX_DIMENSION'));
      expect(worker, isNot(contains('.putString(KEY_REPLY, reply)')));
      expect(worker, contains('NotificationReplyStore.put'));
      expect(replyStore, contains('context.noBackupFilesDir'));
      expect(replyStore, contains('MAX_AGE_MS'));
      expect(publisher, contains('HISTORY_DIRECTORY'));
      expect(publisher, isNot(contains('deltiecord_notification_history')));
      expect(dartResolver, contains('declaredSize == null'));
      expect(dartResolver, contains('width * height > 8000000'));
    },
  );

  test('push diagnostics distinguish gateway throttling from registration', () {
    final diagnostics = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushDiagnostics.kt',
    ).readAsStringSync();
    expect(diagnostics, contains('LOCAL_TEST_COOLDOWN_MS'));
    expect(diagnostics, contains('responseCode == 429'));
    expect(diagnostics, contains('gateway_rate_limited'));
    expect(diagnostics, contains('Registration remains unchanged'));
  });

  test('persistent Android identifiers use SHA-256 rather than hashCode', () {
    final worker = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushWorker.kt',
    ).readAsStringSync();
    final stable = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'StableIdentifier.kt',
    ).readAsStringSync();
    expect(worker, isNot(contains('.hashCode()')));
    expect(stable, contains('SHA-256'));
    expect(stable, contains('workName'));
  });

  test('exported receiver delegates capability validation to UnifiedPush', () {
    final receiver = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushService.kt',
    ).readAsStringSync();
    expect(receiver, contains('MessagingReceiver'));
    expect(receiver, isNot(contains('BroadcastReceiver()')));
  });
}
