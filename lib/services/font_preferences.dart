const systemEmojiFontFamily = 'System';

/// Rejects stale or host-specific font values stored by older builds.
///
/// Platform fallback is the safe default: Android, Windows, and Linux can then
/// select their native colour-emoji face without applying emoji metrics to
/// ordinary digits and spaces. Builds before 80 offered an incompatible
/// bundled Noto font; that stored value now migrates to the platform font.
String normalizeEmojiFontFamily(String? value) => switch (value) {
  systemEmojiFontFamily => systemEmojiFontFamily,
  _ => systemEmojiFontFamily,
};
