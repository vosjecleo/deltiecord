import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/font_preferences.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Night uses true black for every background role', () {
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.night);
    expect(
      {
        palette.background,
        palette.rail,
        palette.panel,
        palette.surface,
        palette.elevated,
        palette.input,
        palette.island,
        palette.hover,
      },
      {const Color(0xff000000)},
    );
  });

  test('new installs start at half compactness', () {
    const preferences = AppPreferences();
    expect(preferences.compactness, 0.5);
    expect(preferences.fontFamily, 'System');
    expect(preferences.emojiFontFamily, systemEmojiFontFamily);
  });

  test('stale emoji font values migrate to the system color font', () {
    expect(normalizeEmojiFontFamily('<none>'), systemEmojiFontFamily);
    expect(normalizeEmojiFontFamily(''), systemEmojiFontFamily);
    expect(
      normalizeEmojiFontFamily(systemEmojiFontFamily),
      systemEmojiFontFamily,
    );
  });

  test('rectangular surfaces share one corner radius', () {
    expect(DeltiecordCorners.radius, 12);
    expect(DeltiecordTypeScale.small, DeltiecordTypeScale.normal - 2);
  });

  test('regular mode preserves the familiar charcoal palette', () {
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.regular);
    expect(palette.background, const Color(0xff26272c));
    expect(palette.rail, const Color(0xff1e1f22));
    expect(palette.panel, const Color(0xff202125));
    expect(palette.input, const Color(0xff303137));
    expect(palette.island, const Color(0xff303137));
    expect(palette.hover, const Color(0xff34353b));
    expect(palette.divider, const Color(0xff36373d));
    expect(palette.island, isNot(palette.background));
  });

  test('dark mode sits between regular and true-black night', () {
    final regular = DeltiecordPalette.forMode(DeltiecordThemeMode.regular);
    final dark = DeltiecordPalette.forMode(DeltiecordThemeMode.dark);
    final night = DeltiecordPalette.forMode(DeltiecordThemeMode.night);
    expect(
      dark.background.computeLuminance(),
      lessThan(regular.background.computeLuminance()),
    );
    expect(
      dark.background.computeLuminance(),
      greaterThan(night.background.computeLuminance()),
    );
  });

  test('profile actions choose a legible foreground for arbitrary colours', () {
    expect(
      deltiecordContrastingForeground(const Color(0xfff4d6dd)),
      Colors.black,
    );
    expect(
      deltiecordContrastingForeground(const Color(0xff351044)),
      Colors.white,
    );
  });
}
