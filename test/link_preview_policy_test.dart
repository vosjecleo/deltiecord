import 'package:deltiecord/services/link_preview_policy.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct fallback requires an explicit preference', () {
    expect(const AppPreferences().fetchDirectLinkPreviews, isFalse);
    final trusted = Uri.parse('https://youtube.com/watch?v=test');
    final unknown = Uri.parse('https://tracker.example/video');
    expect(
      LinkPreviewNetworkPolicy.allowsDirectFallback(
        DirectLinkPreviewMode.none,
        trusted,
      ),
      isFalse,
    );
    expect(
      LinkPreviewNetworkPolicy.allowsDirectFallback(
        DirectLinkPreviewMode.trustedProviders,
        trusted,
      ),
      isTrue,
    );
    expect(
      LinkPreviewNetworkPolicy.allowsDirectFallback(
        DirectLinkPreviewMode.trustedProviders,
        unknown,
      ),
      isFalse,
    );
    expect(
      LinkPreviewNetworkPolicy.allowsDirectFallback(
        DirectLinkPreviewMode.allPublicSites,
        unknown,
      ),
      isTrue,
    );
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

  test('trusted providers use exact host boundaries', () {
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('https://media.giphy.com/media/example/giphy.gif'),
      ),
      isTrue,
    );
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('https://youtube.com.attacker.example/watch?v=1'),
      ),
      isFalse,
    );
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('https://notyoutube.com/watch?v=1'),
      ),
      isFalse,
    );
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('http://youtube.com/watch?v=1'),
      ),
      isTrue,
    );
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('ftp://youtube.com/watch?v=1'),
      ),
      isFalse,
    );
  });

  test('trusted provider customisations preserve host boundaries', () {
    final custom = Uri.parse('https://cdn.example.org/video');
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        custom,
        added: const {'example.org'},
      ),
      isTrue,
    );
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('https://example.org.attacker.invalid/video'),
        added: const {'example.org'},
      ),
      isFalse,
    );
    expect(
      LinkPreviewNetworkPolicy.isTrustedProviderUrl(
        Uri.parse('https://youtube.com/watch?v=x'),
        removed: const {'youtube.com'},
      ),
      isFalse,
    );
  });
}
