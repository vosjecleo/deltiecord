import 'package:media_kit/media_kit.dart';

/// Playback boundary for short in-app sounds.
///
/// Desktop `SystemSound` APIs are not implemented consistently on Linux and
/// may never create an audio stream. Deltiecord therefore uses its existing
/// media engine, while keeping failures non-fatal to messaging and RTC state.
abstract interface class AppSoundPlayback {
  Future<void> play(String assetUri);

  Future<void> dispose();
}

final class MediaKitAppSoundPlayback implements AppSoundPlayback {
  Player? _player;
  bool _disposed = false;

  @override
  Future<void> play(String assetUri) async {
    if (_disposed) return;
    final player = _player ??= Player();
    await player.open(Media(assetUri), play: true);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player?.dispose();
    _player = null;
  }
}

abstract final class AppSounds {
  static AppSoundPlayback _playback = MediaKitAppSoundPlayback();

  static Future<void> notification() =>
      _play('asset:///assets/audio/notification.wav');

  static Future<void> callConnected() =>
      _play('asset:///assets/audio/call-connected.wav');

  static Future<void> callDisconnected() =>
      _play('asset:///assets/audio/call-disconnected.wav');

  static Future<void> _play(String assetUri) async {
    try {
      await _playback.play(assetUri);
    } catch (_) {
      // A missing/unsupported audio backend must not alter app or RTC state.
    }
  }

  static Future<void> dispose() => _playback.dispose();

  /// Replaces the output in tests without initializing native media plugins.
  static void replacePlaybackForTesting(AppSoundPlayback playback) {
    _playback = playback;
  }
}
