import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/chat_models.dart';

/// Device-local visual preferences used when appearance syncing is disabled.
///
/// The switch itself must not live in Matrix account data: doing so would make
/// another device capable of turning local-only mode off. Secure storage is
/// already available on every supported platform and gives each signed-in
/// account an isolated, private key without adding another database.
final class DeviceAppearanceStore {
  DeviceAppearanceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String userId) =>
      'deltiecord.device_appearance.'
      '${sha256.convert(utf8.encode(userId))}';

  Future<DeviceAppearanceSnapshot?> load(String userId) async {
    try {
      final value = await _storage.read(key: _key(userId));
      if (value == null) return null;
      final decoded = jsonDecode(value);
      return decoded is Map<String, Object?>
          ? DeviceAppearanceSnapshot.fromJson(decoded)
          : null;
    } catch (_) {
      // A missing platform keyring should fall back to synced appearance
      // rather than preventing Matrix from opening.
      return null;
    }
  }

  Future<void> save(String userId, AppPreferences preferences) async {
    try {
      await _storage.write(
        key: _key(userId),
        value: jsonEncode(DeviceAppearanceSnapshot.capture(preferences).json),
      );
    } catch (_) {
      // Visual preferences are non-critical. The in-memory choice remains in
      // effect for this run when a platform keyring is unavailable.
    }
  }

  Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {
      // See [save]; failure to reach a keyring is not a session failure.
    }
  }
}

final class DeviceAppearanceSnapshot {
  const DeviceAppearanceSnapshot({
    required this.density,
    required this.compactness,
    required this.themeMode,
    required this.interfaceScale,
    required this.fontScale,
    required this.roomPanelWidth,
    required this.sidePanelWidth,
    required this.reducedMotion,
    required this.highContrast,
    required this.autoplayGifs,
    required this.accentColor,
    required this.fontFamily,
    required this.emojiFontFamily,
    required this.showNativeTitleBar,
  });

  factory DeviceAppearanceSnapshot.capture(AppPreferences value) =>
      DeviceAppearanceSnapshot(
        density: value.density,
        compactness: value.compactness,
        themeMode: value.themeMode,
        interfaceScale: value.interfaceScale,
        fontScale: value.fontScale,
        roomPanelWidth: value.roomPanelWidth,
        sidePanelWidth: value.sidePanelWidth,
        reducedMotion: value.reducedMotion,
        highContrast: value.highContrast,
        autoplayGifs: value.autoplayGifs,
        accentColor: value.accentColor,
        fontFamily: value.fontFamily,
        emojiFontFamily: value.emojiFontFamily,
        showNativeTitleBar: value.showNativeTitleBar,
      );

  factory DeviceAppearanceSnapshot.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((value) => value.name == name).firstOrNull ?? fallback;

    return DeviceAppearanceSnapshot(
      density: enumValue(
        InterfaceDensity.values,
        json['density'] as String?,
        InterfaceDensity.compact,
      ),
      compactness: _number(json['compactness'], 0.5).clamp(0, 1),
      themeMode: enumValue(
        DeltiecordThemeMode.values,
        json['theme_mode'] as String?,
        DeltiecordThemeMode.regular,
      ),
      interfaceScale: _number(json['interface_scale'], 1).clamp(0.8, 1.4),
      fontScale: _number(json['font_scale'], 1).clamp(0.8, 1.4),
      roomPanelWidth: _number(json['room_panel_width'], 280).clamp(220, 420),
      sidePanelWidth: _number(json['side_panel_width'], 310).clamp(260, 460),
      reducedMotion: json['reduced_motion'] == true,
      highContrast: json['high_contrast'] == true,
      autoplayGifs: json['autoplay_gifs'] != false,
      accentColor: (json['accent_color'] as num?)?.toInt() ?? 0xff6975d9,
      fontFamily: json['font_family'] as String? ?? 'System',
      emojiFontFamily: json['emoji_font_family'] as String? ?? 'System',
      showNativeTitleBar: json['show_native_title_bar'] != false,
    );
  }

  final InterfaceDensity density;
  final double compactness;
  final DeltiecordThemeMode themeMode;
  final double interfaceScale;
  final double fontScale;
  final double roomPanelWidth;
  final double sidePanelWidth;
  final bool reducedMotion;
  final bool highContrast;
  final bool autoplayGifs;
  final int accentColor;
  final String fontFamily;
  final String emojiFontFamily;
  final bool showNativeTitleBar;

  AppPreferences applyTo(AppPreferences base) => base.copyWith(
    density: density,
    compactness: compactness,
    themeMode: themeMode,
    interfaceScale: interfaceScale,
    fontScale: fontScale,
    roomPanelWidth: roomPanelWidth,
    sidePanelWidth: sidePanelWidth,
    reducedMotion: reducedMotion,
    highContrast: highContrast,
    syncAppearance: false,
    autoplayGifs: autoplayGifs,
    accentColor: accentColor,
    fontFamily: fontFamily,
    emojiFontFamily: emojiFontFamily,
    showNativeTitleBar: showNativeTitleBar,
  );

  Map<String, Object?> get json => {
    'schema': 1,
    'density': density.name,
    'compactness': compactness,
    'theme_mode': themeMode.name,
    'interface_scale': interfaceScale,
    'font_scale': fontScale,
    'room_panel_width': roomPanelWidth,
    'side_panel_width': sidePanelWidth,
    'reduced_motion': reducedMotion,
    'high_contrast': highContrast,
    'autoplay_gifs': autoplayGifs,
    'accent_color': accentColor,
    'font_family': fontFamily,
    'emoji_font_family': emojiFontFamily,
    'show_native_title_bar': showNativeTitleBar,
  };
}

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;
