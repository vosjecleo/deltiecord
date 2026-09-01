import 'package:deltiecord/services/unified_push.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('accepts HTTPS endpoints returned by other distributors', () {
    expect(
      normalizeUnifiedPushEndpoint('https://evil.example/up-secret'),
      'https://evil.example/up-secret',
    );
  });

  test('rejects unsafe endpoint origins and shapes', () {
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

  test(
    'registration consumes the asynchronous native callback state',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('net.deltie.deltiecord/unified_push');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'register');
            return <String, Object?>{
              'distributor': 'io.heckel.ntfy',
              'endpoint': 'https://push.deltie.net/up-private?up=1',
              'error': null,
            };
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final state = await UnifiedPushPlatform.instance.register('@alice:test');

      expect(state.registered, isTrue);
      expect(state.distributor, 'io.heckel.ntfy');
      expect(state.endpoint, 'https://push.deltie.net/up-private?up=1');
    },
  );

  test('external ntfy is preferred over arbitrary distributor order', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('net.deltie.deltiecord/unified_push');
    String? selected;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getState':
              return <String, Object?>{
                'distributor': null,
                'endpoint': null,
                'error': null,
              };
            case 'getDistributors':
              return <Object?>[
                <String, Object?>{
                  'packageName': 'org.example.other',
                  'label': 'Other Push',
                },
                <String, Object?>{
                  'packageName': 'io.heckel.ntfy',
                  'label': 'ntfy',
                },
              ];
            case 'selectDistributor':
              selected = (call.arguments as Map)['distributor'] as String;
              return <String, Object?>{
                'distributor': selected,
                'endpoint': 'https://push.deltie.net/up-private?up=1',
                'error': null,
              };
          }
          fail('Unexpected method ${call.method}');
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await UnifiedPushPlatform.instance.ensureDefaultDistributor('@a:test'),
      isTrue,
    );
    expect(selected, 'io.heckel.ntfy');
  });
}
