const bundledEmojiFontFamily = 'Deltiecord Emoji';
const systemEmojiFontFamily = 'System';

/// Rejects stale or host-specific font values stored by older builds.
///
/// Platform fallback is the safe default: Android, Windows, and Linux can then
/// select their native colour-emoji face without applying emoji metrics to
/// ordinary digits and spaces. The bundled font remains an explicit advanced
/// option for users whose host has no complete colour font.
String normalizeEmojiFontFamily(String? value) => switch (value) {
  systemEmojiFontFamily => systemEmojiFontFamily,
  bundledEmojiFontFamily => bundledEmojiFontFamily,
  _ => systemEmojiFontFamily,
};
