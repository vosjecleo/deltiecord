import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/font_preferences.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OLED uses true black for every background role', () {
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.oled);
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
    expect(preferences.fontFamily, 'Liberation Sans');
    expect(preferences.emojiFontFamily, 'Deltiecord Emoji');
  });

  test('stale emoji font values migrate to the bundled color font', () {
    expect(normalizeEmojiFontFamily('<none>'), bundledEmojiFontFamily);
    expect(normalizeEmojiFontFamily(''), bundledEmojiFontFamily);
    expect(
      normalizeEmojiFontFamily(systemEmojiFontFamily),
      systemEmojiFontFamily,
    );
  });

  test('rectangular surfaces share one corner radius', () {
    expect(DeltiecordCorners.radius, 12);
    expect(DeltiecordTypeScale.small, DeltiecordTypeScale.normal - 2);
  });

  test('dark mode distinguishes floating control islands', () {
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.dark);
    expect(palette.background, const Color(0xff26272c));
    expect(palette.panel, const Color(0xff202125));
    expect(palette.input, const Color(0xff1e1f22));
    expect(palette.island, const Color(0xff2b2d31));
    expect(palette.island, isNot(palette.background));
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
