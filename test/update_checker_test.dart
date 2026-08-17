import 'package:deltiecord/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest compares version and build independently', () {
    final newerBuild = parseReleaseManifest(
      '{"version":"0.9.19","build":65}',
      currentVersion: '0.9.19',
      currentBuild: 64,
    );
    final newerVersion = parseReleaseManifest(
      '{"version":"0.10.0","build":1}',
      currentVersion: '0.9.19',
      currentBuild: 64,
    );
    final older = parseReleaseManifest(
      '{"version":"0.9.18","build":999}',
      currentVersion: '0.9.19',
      currentBuild: 64,
    );

    expect(newerBuild.updateAvailable, isTrue);
    expect(newerVersion.updateAvailable, isTrue);
    expect(older.updateAvailable, isFalse);
  });

  test('release manifest rejects malformed and unreasonable metadata', () {
    expect(
      () => parseReleaseManifest(
        '{"version":"latest","build":64}',
        currentVersion: '0.9.19',
        currentBuild: 64,
      ),
      throwsFormatException,
    );
    expect(
      () => parseReleaseManifest(
        '{"version":"0.9.19","build":-1}',
        currentVersion: '0.9.19',
        currentBuild: 64,
      ),
      throwsFormatException,
    );
  });
}
