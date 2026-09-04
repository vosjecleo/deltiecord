import 'package:deltiecord/services/android_media_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidMediaSaver.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'passes media to Android without asking the user for a filename',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return 'photo.png';
          });

      final savedName = await AndroidMediaSaver.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'photo.png',
        mimeType: 'image/png',
      );

      expect(savedName, 'photo.png');
      expect(received?.method, 'saveMedia');
      expect(received?.arguments, {
        'bytes': Uint8List.fromList([1, 2, 3]),
        'suggestedName': 'photo.png',
        'mimeType': 'image/png',
      });
    },
  );
}
