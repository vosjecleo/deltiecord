import 'package:deltiecord/services/unified_push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts the complete private ntfy capability endpoint', () {
    const endpoint = 'https://push.deltie.net/up-high-entropy?up=1';
    expect(normalizeUnifiedPushEndpoint('  $endpoint  '), endpoint);
  });

  test('upgrades the fixed ntfy origin when a distributor reports http', () {
    expect(
      normalizeUnifiedPushEndpoint(
        'http://push.deltie.net/up-high-entropy?up=1',
      ),
      'https://push.deltie.net/up-high-entropy?up=1',
    );
  });

  test('normalizes harmless connector wrappers around the capability', () {
    expect(
      normalizeUnifiedPushEndpoint(
        '\u200bpush.deltie.net/upVeryPrivateTopic?up=1#connector-metadata\n',
      ),
      'https://push.deltie.net/upVeryPrivateTopic?up=1',
    );
  });

  test('rejects endpoints that could leak the push capability', () {
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
