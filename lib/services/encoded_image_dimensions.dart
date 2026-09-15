import 'dart:typed_data';
import 'dart:ui' as ui;

/// Reads encoded image dimensions without decoding a full frame.
///
/// This is used only to repair absent/incorrect Matrix metadata. The pixel
/// bound prevents a hostile image header from reserving absurd UI geometry.
Future<({int width, int height})?> readEncodedImageDimensions(
  Uint8List bytes, {
  int maximumPixels = 40000000,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0 || width * height > maximumPixels) {
      return null;
    }
    return (width: width, height: height);
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
