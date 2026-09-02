import 'package:flutter/material.dart';

import '../models/chat_models.dart';

/// Deltiecord's deliberately small desktop type scale.
///
/// Feature widgets should choose a semantic tier instead of inventing a new
/// point size. Font scaling remains available through accessibility settings.
abstract final class DeltiecordTypeScale {
  static const double small = 12;
  static const double normal = 14;
  static const double bigChat = 15;
  static const double bigUi = 17;
}

/// The single corner radius used by Deltiecord's rectangular surfaces.
/// Circular avatars and deliberately pill-shaped status controls are exempt.
abstract final class DeltiecordCorners {
  static const double radius = 12;
  static const Radius corner = Radius.circular(radius);
  static const BorderRadius borderRadius = BorderRadius.all(corner);
}

/// Chooses the higher-contrast monochrome foreground for a user-selected
/// colour. Profile colours are arbitrary, so theme defaults cannot guarantee
/// that action labels remain legible.
Color deltiecordContrastingForeground(Color background) {
  final luminance = background.computeLuminance();
  final whiteContrast = 1.05 / (luminance + 0.05);
  final blackContrast = (luminance + 0.05) / 0.05;
  return whiteContrast >= blackContrast ? Colors.white : Colors.black;
}

@immutable
class DeltiecordPalette extends ThemeExtension<DeltiecordPalette> {
  const DeltiecordPalette({
    required this.background,
    required this.rail,
    required this.panel,
    required this.surface,
    required this.elevated,
    required this.input,
    required this.island,
    required this.hover,
    required this.divider,
    required this.text,
    required this.muted,
  });

  final Color background;
  final Color rail;
  final Color panel;
  final Color surface;
  final Color elevated;
  final Color input;

  /// Stable lower-strip cards used by the own-profile and composer islands.
  final Color island;
  final Color hover;
  final Color divider;
  final Color text;
  final Color muted;

  static DeltiecordPalette forMode(DeltiecordThemeMode mode) => switch (mode) {
    DeltiecordThemeMode.light => const DeltiecordPalette(
      background: Color(0xfff7f5ef),
      rail: Color(0xffebe8df),
      panel: Color(0xfff1efe8),
      surface: Color(0xfff7f5ef),
      elevated: Color(0xfffffefa),
      input: Color(0xfffffefa),
      island: Color(0xfffffefa),
      hover: Color(0xffe5e2d9),
      divider: Color(0xffdedbd2),
      text: Color(0xff202225),
      muted: Color(0xff5c6068),
    ),
    DeltiecordThemeMode.dark => const DeltiecordPalette(
      background: Color(0xff26272c),
      rail: Color(0xff1e1f22),
      panel: Color(0xff202125),
      surface: Color(0xff26272c),
      elevated: Color(0xff303137),
      input: Color(0xff303137),
      island: Color(0xff303137),
      hover: Color(0xff34353b),
      divider: Color(0xff36373d),
      text: Color(0xfff2f3f5),
      muted: Color(0xffb5bac1),
    ),
    DeltiecordThemeMode.oled => const DeltiecordPalette(
      background: Color(0xff000000),
      rail: Color(0xff000000),
      panel: Color(0xff000000),
      surface: Color(0xff000000),
      elevated: Color(0xff000000),
      input: Color(0xff000000),
      island: Color(0xff000000),
      hover: Color(0xff000000),
      divider: Color(0xff292929),
      text: Color(0xfff5f5f5),
      muted: Color(0xffa9a9ad),
    ),
  };

  @override
  DeltiecordPalette copyWith({
    Color? background,
    Color? rail,
    Color? panel,
    Color? surface,
    Color? elevated,
    Color? input,
    Color? island,
    Color? hover,
    Color? divider,
    Color? text,
    Color? muted,
  }) => DeltiecordPalette(
    background: background ?? this.background,
    rail: rail ?? this.rail,
    panel: panel ?? this.panel,
    surface: surface ?? this.surface,
    elevated: elevated ?? this.elevated,
    input: input ?? this.input,
    island: island ?? this.island,
    hover: hover ?? this.hover,
    divider: divider ?? this.divider,
    text: text ?? this.text,
    muted: muted ?? this.muted,
  );

  @override
  DeltiecordPalette lerp(covariant DeltiecordPalette? other, double t) {
    if (other == null) return this;
    return DeltiecordPalette(
      background: Color.lerp(background, other.background, t)!,
      rail: Color.lerp(rail, other.rail, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      input: Color.lerp(input, other.input, t)!,
      island: Color.lerp(island, other.island, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

@immutable
class DeltiecordEmojiTypography
    extends ThemeExtension<DeltiecordEmojiTypography> {
  const DeltiecordEmojiTypography({required this.fontFamily});

  final String? fontFamily;

  @override
  DeltiecordEmojiTypography copyWith({String? fontFamily}) =>
      DeltiecordEmojiTypography(fontFamily: fontFamily ?? this.fontFamily);

  @override
  DeltiecordEmojiTypography lerp(
    covariant DeltiecordEmojiTypography? other,
    double t,
  ) => other ?? this;
}

extension DeltiecordThemeContext on BuildContext {
  DeltiecordPalette get deltiecord =>
      Theme.of(this).extension<DeltiecordPalette>()!;

  String? get deltiecordEmojiFont =>
      Theme.of(this).extension<DeltiecordEmojiTypography>()?.fontFamily;
}
