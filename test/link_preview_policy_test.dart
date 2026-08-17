import 'package:deltiecord/services/link_preview_policy.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct fallback requires an explicit preference', () {
    expect(const AppPreferences().fetchDirectLinkPreviews, isFalse);
    expect(LinkPreviewNetworkPolicy.allowsDirectFallback(false), isFalse);
    expect(LinkPreviewNetworkPolicy.allowsDirectFallback(true), isTrue);
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
