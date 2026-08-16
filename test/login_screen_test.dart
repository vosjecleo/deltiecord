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
}
