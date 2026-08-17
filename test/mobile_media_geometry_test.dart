import 'package:deltiecord/ui/mobile/mobile_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown mobile media reserves a portrait three-by-four frame', () {
    final size = mobileMediaFrameSize(maxWidth: 360, maxHeight: 400);

    expect(size.height, 400);
    expect(size.width, 300);
  });

  test('preview frames preserve landscape and portrait metadata', () {
    final landscape = mobileMediaFrameSize(
      maxWidth: 360,
      maxHeight: 400,
      width: 1920,
      height: 1080,
    );
    final portrait = mobileMediaFrameSize(
      maxWidth: 360,
      maxHeight: 400,
      width: 1080,
      height: 1920,
    );

    expect(landscape.width / landscape.height, closeTo(16 / 9, 0.001));
    expect(portrait.width / portrait.height, closeTo(9 / 16, 0.001));
    expect(landscape.width, 360);
    expect(portrait.height, 400);
  });
}
