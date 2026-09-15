import 'package:deltiecord/ui/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('homeserver normalization', () {
    test('prepends HTTPS to a bare hostname', () {
      expect(
        normalizedHomeserverUri('matrix.example.org'),
        Uri.parse('https://matrix.example.org'),
      );
    });

    test('preserves a complete HTTPS URL', () {
      expect(
        normalizedHomeserverUri(' https://matrix.example.org/path '),
        Uri.parse('https://matrix.example.org/path'),
      );
    });

    test('rejects empty and insecure addresses', () {
      expect(normalizedHomeserverUri(''), isNull);
      expect(normalizedHomeserverUri('http://matrix.example.org'), isNull);
    });
  });

  group('Matrix login name normalization', () {
    test('extracts the localpart from a full Matrix ID', () {
      expect(normalizedMatrixLoginName('@alice:example.org'), 'alice');
    });

    test('preserves a username', () {
      expect(normalizedMatrixLoginName(' alice '), 'alice');
    });
  });

  group('deltie.net registration names', () {
    test('accepts Matrix-safe localparts', () {
      expect(isValidDeltiecordLocalpart('alice_2'), isTrue);
      expect(isValidDeltiecordLocalpart('alice/example'), isTrue);
    });

    test('rejects full IDs, uppercase, whitespace, and empty names', () {
      expect(isValidDeltiecordLocalpart('@alice:deltie.net'), isFalse);
      expect(isValidDeltiecordLocalpart('Alice'), isFalse);
      expect(isValidDeltiecordLocalpart('alice smith'), isFalse);
      expect(isValidDeltiecordLocalpart(''), isFalse);
    });
  });
}
