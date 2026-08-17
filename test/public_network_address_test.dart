import 'dart:io';

import 'package:deltiecord/services/public_network_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects private, local, and IPv4-mapped private addresses', () {
    for (final value in [
      '127.0.0.1',
      '10.2.3.4',
      '172.16.0.1',
      '192.168.1.1',
      '169.254.1.2',
      '100.64.1.2',
      '192.0.2.1',
      '198.51.100.4',
      '203.0.113.9',
      '::1',
      'fd00::1',
      '100::1',
      '2001:db8::1',
      '::ffff:192.168.1.1',
    ]) {
      expect(
        isPublicInternetAddress(InternetAddress(value)),
        isFalse,
        reason: value,
      );
    }
  });

  test('allows globally routable IPv4 and IPv6 addresses', () {
    expect(isPublicInternetAddress(InternetAddress('1.1.1.1')), isTrue);
    expect(
      isPublicInternetAddress(InternetAddress('2606:4700:4700::1111')),
      isTrue,
    );
  });
}
