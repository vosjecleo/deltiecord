import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/device_appearance_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device appearance replaces only visual preferences', () {
    const account = AppPreferences(
      themeMode: DeltiecordThemeMode.light,
      notificationSound: false,
      sendReadReceipts: false,
    );
    const local = AppPreferences(
      themeMode: DeltiecordThemeMode.dark,
      fontScale: 1.2,
      notificationSound: true,
      sendReadReceipts: true,
    );

    final merged = DeviceAppearanceSnapshot.capture(local).applyTo(account);

    expect(merged.themeMode, DeltiecordThemeMode.dark);
    expect(merged.fontScale, 1.2);
    expect(merged.syncAppearance, isFalse);
    expect(merged.notificationSound, isFalse);
    expect(merged.sendReadReceipts, isFalse);
  });
}
