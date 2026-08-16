import 'package:deltiecord/services/secret_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts tokens, crypto material, and local media capabilities', () {
    final redacted = redactSecrets(
      'Authorization: Bearer abc.def '
      'https://matrix.test/a?access_token=secret&x=1 '
      '{"recovery_key":"private recovery", "iv":"secret-iv"} '
      'http://127.0.0.1:1234/media/localCapability',
    );
    expect(redacted, isNot(contains('abc.def')));
    expect(redacted, isNot(contains('secret')));
    expect(redacted, isNot(contains('private recovery')));
    expect(redacted, isNot(contains('localCapability')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('safe errors are bounded', () {
    expect(safeErrorMessage(Exception('x' * 500)).length, 241);
  });
}
