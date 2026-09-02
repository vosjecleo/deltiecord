import 'package:deltiecord/services/android_push_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active desktop lease suppresses an Android push', () {
    final now = DateTime.utc(2026, 9, 2, 10);
    expect(
      hasActiveDesktopLease(
        {
          'devices': {
            'desktop': {
              'platform': 'linux',
              'idle': false,
              'updated_at': now
                  .subtract(const Duration(seconds: 30))
                  .millisecondsSinceEpoch,
            },
          },
        },
        currentDeviceId: 'phone',
        now: now,
      ),
      isTrue,
    );
  });

  test('idle, expired, mobile, and current-device leases do not suppress', () {
    final now = DateTime.utc(2026, 9, 2, 10);
    final stale = now
        .subtract(const Duration(minutes: 3))
        .millisecondsSinceEpoch;
    final recent = now.millisecondsSinceEpoch;
    expect(
      hasActiveDesktopLease(
        {
          'devices': {
            'idle-desktop': {
              'platform': 'windows',
              'idle': true,
              'updated_at': recent,
            },
            'expired-desktop': {
              'platform': 'linux',
              'idle': false,
              'updated_at': stale,
            },
            'other-phone': {
              'platform': 'android',
              'idle': false,
              'updated_at': recent,
            },
            'phone': {'platform': 'linux', 'idle': false, 'updated_at': recent},
          },
        },
        currentDeviceId: 'phone',
        now: now,
      ),
      isFalse,
    );
  });
}
