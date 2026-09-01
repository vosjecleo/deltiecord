import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UnifiedPush receiver can wake Deltiecord while Flutter is stopped', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final receiverStart = manifest.indexOf(
      '<receiver\n            android:name=".DeltiecordPushService"',
    );
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
}
