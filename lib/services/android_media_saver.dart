import 'package:flutter/services.dart';

/// Stores user-requested media through Android's scoped MediaStore API.
///
/// The native side owns filename sanitization and the Downloads/Deltiecord
/// destination. Keeping that boundary native avoids broad storage permissions
/// and the unreliable document-provider "save as" flow on Android.
final class AndroidMediaSaver {
  AndroidMediaSaver._();

  static const channelName = 'net.deltie.deltiecord/media_saver';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<String> save({
    required Uint8List bytes,
    required String suggestedName,
    required String mimeType,
  }) async {
    final savedName = await _channel.invokeMethod<String>('saveMedia', {
      'bytes': bytes,
      'suggestedName': suggestedName,
      'mimeType': mimeType,
    });
    if (savedName == null || savedName.isEmpty) {
      throw StateError('Android did not return the saved filename.');
    }
    return savedName;
  }
}
