import 'package:deltiecord/ui/profile_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('banner crop region keeps the requested aspect and position', () {
    final region = calculateProfileCropRegion(
      imageWidth: 4000,
      imageHeight: 2000,
      aspectRatio: 3,
      zoom: 2,
      horizontalPosition: 1,
      verticalPosition: 0.5,
    );

    expect(region.width / region.height, closeTo(3, 0.0001));
    expect(region.left + region.width, closeTo(4000, 0.001));
    expect(region.top, greaterThan(0));
  });

  test('avatar crop starts with the largest centered square', () {
    final region = calculateProfileCropRegion(
      imageWidth: 2400,
      imageHeight: 1600,
      aspectRatio: 1,
      zoom: 1,
      horizontalPosition: 0.5,
      verticalPosition: 0.5,
    );

    expect(region.width, 1600);
    expect(region.height, 1600);
    expect(region.left, 400);
    expect(region.top, 0);
  });
}
