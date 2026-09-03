import 'dart:io';

import 'package:deltiecord/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime version matches pubspec release metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^+\s]+)\+(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(deltiecordVersion, match!.group(1));
    expect(deltiecordBuildNumber, match.group(2));

    final archPackage = File('packaging/arch/PKGBUILD').readAsStringSync();
    final packageRelease = RegExp(
      r'^pkgrel=(\d+)\s*$',
      multiLine: true,
    ).firstMatch(archPackage);
    expect(packageRelease, isNotNull);
    expect(packageRelease!.group(1), match.group(2));
  });
}
