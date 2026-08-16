import 'package:deltiecord/services/link_preview_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never permits client-side origin fallback', () {
    expect(LinkPreviewNetworkPolicy.allowsDirectFallback, isFalse);
    expect(
      LinkPreviewNetworkPolicy.mayLoadMedia(
        Uri.parse('https://tracker.example/preview.jpg'),
      ),
      isFalse,
    );
    expect(
      LinkPreviewNetworkPolicy.mayLoadMedia(
        Uri.parse('mxc://matrix.example/media'),
      ),
      isTrue,
    );
  });
}
