import 'package:deltiecord/services/app_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sound service creates playback and releases it', () async {
    final playback = _FakePlayback();
    AppSounds.replacePlaybackForTesting(playback);

    await AppSounds.notification();
    await AppSounds.callConnected();
    await AppSounds.callDisconnected();
    await AppSounds.dispose();

    expect(playback.assets, [
      'asset:///assets/audio/notification.wav',
      'asset:///assets/audio/call-connected.wav',
      'asset:///assets/audio/call-disconnected.wav',
    ]);
    expect(playback.disposed, isTrue);
  });
}

class _FakePlayback implements AppSoundPlayback {
  final assets = <String>[];
  bool disposed = false;

  @override
  Future<void> play(String assetUri) async => assets.add(assetUri);

  @override
  Future<void> dispose() async => disposed = true;
}
