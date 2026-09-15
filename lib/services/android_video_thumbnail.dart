import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Android's platform decoder is substantially more reliable for camera video
/// than image codecs available on Dart's UI isolate. The bridge is deliberately
/// bounded: thumbnail generation is optional and must never duplicate an
/// arbitrarily large attachment across the platform channel.
abstract final class AndroidVideoThumbnail {
  static const _channel = MethodChannel(
    'net.deltie.deltiecord/video_thumbnail',
  );
  static const maximumSourceBytes = 128 * 1024 * 1024;

  static Future<MatrixVideoThumbnailResponse?> generate(
    MatrixVideoThumbnailArguments arguments,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        arguments.bytes.isEmpty ||
        arguments.bytes.length > maximumSourceBytes) {
      return null;
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('generate', <String, Object?>{
            'bytes': arguments.bytes,
            'mimeType': arguments.mimeType,
            'maxDimension': arguments.maxDimension.clamp(64, 1024),
          });
      final bytes = result?['bytes'];
      final width = result?['width'];
      final height = result?['height'];
      if (bytes is! Uint8List ||
          bytes.isEmpty ||
          bytes.length > 1024 * 1024 ||
          width is! int ||
          height is! int ||
          width <= 0 ||
          height <= 0) {
        return null;
      }
      return MatrixVideoThumbnailResponse(
        bytes: bytes,
        width: width,
        height: height,
        mimeType: 'image/jpeg',
        originalWidth: result?['originalWidth'] as int?,
        originalHeight: result?['originalHeight'] as int?,
        duration: result?['duration'] as int?,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
