import 'package:flutter/services.dart';

/// Small platform-sound boundary used where Linux/desktop owns actual output.
/// Desktop notifications still ask the notification daemon to play its
/// configured sound; these methods provide previews and unobtrusive call cues.
abstract final class AppSounds {
  static Future<void> notification() => _play(SystemSoundType.alert);

  static Future<void> callConnected() => _play(SystemSoundType.click);

  static Future<void> callDisconnected() => _play(SystemSoundType.alert);

  // Sound support varies between Linux desktop shells. A missing platform
  // implementation must never interrupt messaging or an RTC state change.
  static Future<void> _play(SystemSoundType type) async {
    try {
      await SystemSound.play(type);
    } catch (_) {
      // The host notification daemon still supplies real notification sounds.
    }
  }
}
