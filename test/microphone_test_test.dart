import 'dart:async';

import 'package:deltiecord/services/microphone_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('microphone test forwards levels and releases native session', () async {
    final platform = _FakePlatform();
    final controller = MicrophoneTestController(platform: platform);

    await controller.start(
      const MicrophoneTestConfiguration(
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      ),
    );
    platform.session.levelController.add(0.64);
    await Future<void>.delayed(Duration.zero);
    expect(controller.level, 0.64);

    await controller.setListening(true);
    expect(platform.session.listening, isTrue);
    await controller.stop();
    expect(platform.session.disposed, isTrue);
    controller.dispose();
  });
}

class _FakePlatform implements MicrophoneTestPlatform {
  final session = _FakeSession();

  @override
  Future<MicrophoneTestSession> start(
    MicrophoneTestConfiguration config,
  ) async => session;
}

class _FakeSession implements MicrophoneTestSession {
  final levelController = StreamController<double>();
  bool listening = false;
  bool disposed = false;

  @override
  Stream<double> get levels => levelController.stream;

  @override
  Future<void> setListening(bool enabled) async => listening = enabled;

  @override
  Future<void> dispose() async {
    disposed = true;
    await levelController.close();
  }
}
