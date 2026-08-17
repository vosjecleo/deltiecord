import 'package:deltiecord/services/unified_push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts the complete private ntfy capability endpoint', () {
    const endpoint = 'https://push.deltie.net/up-high-entropy?up=1';
    expect(normalizeUnifiedPushEndpoint('  $endpoint  '), endpoint);
  });

  test('rejects endpoints that could leak the push capability', () {
    expect(
      normalizeUnifiedPushEndpoint('http://push.deltie.net/up-secret'),
      isNull,
    );
    expect(
      normalizeUnifiedPushEndpoint('https://evil.example/up-secret'),
      isNull,
    );
    expect(
      normalizeUnifiedPushEndpoint('https://push.deltie.net:444/up-secret'),
      isNull,
    );
    expect(
      normalizeUnifiedPushEndpoint('https://user@push.deltie.net/up-secret'),
      isNull,
    );
    expect(normalizeUnifiedPushEndpoint('https://push.deltie.net/'), isNull);
  });
}
