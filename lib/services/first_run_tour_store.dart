import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-installation completion state for the signed-in introduction.
///
/// This deliberately does not use Matrix account data: a user signing in on a
/// new phone still needs that device's notification and privacy setup tour.
final class FirstRunTourStore {
  FirstRunTourStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String userId) {
    final digest = sha256.convert(utf8.encode(userId)).toString();
    return 'deltiecord.first_run_tour.$digest';
  }

  Future<bool> isComplete(String userId) async {
    try {
      return await _storage.read(key: _key(userId)) == '1';
    } catch (_) {
      // Failure to open a platform keyring must not prevent sign-in. Showing
      // the tour again is safer than silently claiming setup was completed.
      return false;
    }
  }

  Future<void> markComplete(String userId) async {
    try {
      await _storage.write(key: _key(userId), value: '1');
    } catch (_) {
      // The tour is advisory; inability to persist it is non-fatal.
    }
  }
}
