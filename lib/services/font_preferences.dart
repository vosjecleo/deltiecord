const bundledEmojiFontFamily = 'Deltiecord Emoji';
const systemEmojiFontFamily = 'System';

/// Rejects stale or host-specific font values stored by older builds.
///
/// In particular, early appearance settings could persist `<none>`. Passing
/// that value to Flutter disables Deltiecord's bundled color-emoji fallback
/// without providing a real replacement font.
String normalizeEmojiFontFamily(String? value) => switch (value) {
  systemEmojiFontFamily => systemEmojiFontFamily,
  bundledEmojiFontFamily => bundledEmojiFontFamily,
  _ => bundledEmojiFontFamily,
};
