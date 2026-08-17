import 'dart:convert';
import 'dart:io';

import 'bounded_http.dart';

const deltiecordReleasesPage = 'https://deltie.net/cord/';
const _releaseManifestUrl = 'https://deltie.net/cord/releases.json';

/// A bounded, user-triggered check against Deltiecord's release manifest.
///
/// This intentionally does not run during startup. Apart from avoiding another
/// background request, a manual check makes the release-site contact visible to
/// the user and keeps normal Matrix startup independent of deltie.net.
class UpdateChecker {
  UpdateChecker({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<ReleaseCheckResult> check({
    required String currentVersion,
    required int currentBuild,
  }) async {
    final request = await _client
        .getUrl(Uri.parse(_releaseManifestUrl))
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Release server returned HTTP ${response.statusCode}.',
      );
    }
    if (!hasContentType(response, const ['application/json', 'text/json'])) {
      await response.drain<void>();
      throw const FormatException(
        'Release server returned an unexpected file.',
      );
    }
    final bytes = await readBoundedResponse(
      response,
      maximumBytes: 1024 * 1024,
      inactivityTimeout: const Duration(seconds: 8),
    );
    return parseReleaseManifest(
      utf8.decode(bytes),
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }

  void close() => _client.close(force: true);
}

class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.version,
    required this.build,
    required this.updateAvailable,
  });

  final String version;
  final int build;
  final bool updateAvailable;
}

ReleaseCheckResult parseReleaseManifest(
  String source, {
  required String currentVersion,
  required int currentBuild,
}) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid release manifest.');
  }
  final version = decoded['version'];
  final buildValue = decoded['build'];
  final build = buildValue is int
      ? buildValue
      : int.tryParse(buildValue?.toString() ?? '');
  if (version is! String ||
      version.length > 32 ||
      !_versionPattern.hasMatch(version) ||
      build == null ||
      build < 0) {
    throw const FormatException('Invalid release version metadata.');
  }
  final comparison = compareVersions(version, currentVersion);
  return ReleaseCheckResult(
    version: version,
    build: build,
    updateAvailable:
        comparison > 0 || (comparison == 0 && build > currentBuild),
  );
}

final _versionPattern = RegExp(r'^\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$');

int compareVersions(String left, String right) {
  List<int> parts(String value) => value
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: true);
  final a = parts(left);
  final b = parts(right);
  final length = a.length > b.length ? a.length : b.length;
  while (a.length < length) {
    a.add(0);
  }
  while (b.length < length) {
    b.add(0);
  }
  for (var index = 0; index < length; index++) {
    if (a[index] != b[index]) return a[index].compareTo(b[index]);
  }
  return 0;
}
