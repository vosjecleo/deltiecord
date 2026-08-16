import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import 'desktop_platform.dart';

/// Small native window-control boundary shared by Linux and Windows runners.
///
/// Unsupported targets and widget tests degrade to no-ops rather than making
/// session restoration depend on a registered native channel.
class DesktopWindowService {
  DesktopWindowService._();

  static const _channel = MethodChannel('net.deltie.deltiecord/window');
  static AppPreferences? _applied;

  static Future<void> apply(AppPreferences preferences) async {
    if (!DesktopPlatformCapabilities.current.supportsDesktopWindowChannel ||
        _sameWindowSettings(_applied, preferences)) {
      return;
    }
    _applied = preferences;
    try {
      await _channel.invokeMethod<void>('configure', {
        'showNativeTitleBar': preferences.showNativeTitleBar,
        'rememberWindowState': preferences.rememberWindowState,
      });
    } on MissingPluginException {
      // Widget tests and non-desktop targets do not register the GTK channel.
    }
  }

  static Future<void> present() async {
    if (!DesktopPlatformCapabilities.current.supportsDesktopWindowChannel) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('present');
    } on MissingPluginException {
      // Widget tests and non-desktop targets do not register the GTK channel.
    }
  }

  static bool _sameWindowSettings(
    AppPreferences? previous,
    AppPreferences current,
  ) =>
      previous?.showNativeTitleBar == current.showNativeTitleBar &&
      previous?.rememberWindowState == current.rememberWindowState;
}
