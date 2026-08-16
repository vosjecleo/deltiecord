import 'dart:io';

enum DeltiecordDesktopPlatform { linux, windows, other }

/// Centralizes native desktop capability decisions.
///
/// UI code consumes platform services rather than branching on operating
/// systems. Native integrations can therefore degrade to explicit no-ops on an
/// unsupported target instead of throwing during application startup.
class DesktopPlatformCapabilities {
  const DesktopPlatformCapabilities._(this.platform);

  factory DesktopPlatformCapabilities.forOperatingSystem(String name) =>
      DesktopPlatformCapabilities._(switch (name) {
        'linux' => DeltiecordDesktopPlatform.linux,
        'windows' => DeltiecordDesktopPlatform.windows,
        _ => DeltiecordDesktopPlatform.other,
      });

  static final current = DesktopPlatformCapabilities.forOperatingSystem(
    Platform.operatingSystem,
  );

  final DeltiecordDesktopPlatform platform;

  bool get supportsDesktopWindowChannel =>
      platform == DeltiecordDesktopPlatform.linux ||
      platform == DeltiecordDesktopPlatform.windows;

  bool get supportsGtkWindowPreferences =>
      platform == DeltiecordDesktopPlatform.linux;

  bool get usesUnixFilePermissions =>
      platform == DeltiecordDesktopPlatform.linux;
}
