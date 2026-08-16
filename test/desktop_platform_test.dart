import 'package:deltiecord/services/desktop_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop platform capabilities isolate native integrations', () {
    final linux = DesktopPlatformCapabilities.forOperatingSystem('linux');
    final windows = DesktopPlatformCapabilities.forOperatingSystem('windows');
    final unsupported = DesktopPlatformCapabilities.forOperatingSystem('web');

    expect(linux.supportsDesktopWindowChannel, isTrue);
    expect(linux.supportsGtkWindowPreferences, isTrue);
    expect(linux.usesUnixFilePermissions, isTrue);
    expect(windows.supportsDesktopWindowChannel, isTrue);
    expect(windows.supportsGtkWindowPreferences, isFalse);
    expect(windows.usesUnixFilePermissions, isFalse);
    expect(unsupported.supportsDesktopWindowChannel, isFalse);
  });
}
