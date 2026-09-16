import 'package:deltiecord/ui/lifecycle_memory_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only GIF-like preview providers request looping playback', () {
    expect(
      shouldLoopLinkPreview(Uri.parse('https://media.giphy.com/media/x/giphy.mp4')),
      isTrue,
    );
    expect(
      shouldLoopLinkPreview(Uri.parse('https://tenor.com/view/example')),
      isTrue,
    );
    expect(
      shouldLoopLinkPreview(Uri.parse('https://example.org/animation.gif')),
      isTrue,
    );
    expect(
      shouldLoopLinkPreview(Uri.parse('https://example.org/video.mp4')),
      isFalse,
    );
  });
}
