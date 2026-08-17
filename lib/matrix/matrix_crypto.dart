part of 'matrix_backend.dart';

/// Cross-signing, secret storage, key-backup, and device recovery operations.
///
/// These methods deliberately delegate protocol and cryptographic behavior to
/// matrix-dart-sdk instead of duplicating security-sensitive algorithms.
extension _MatrixCrypto on MatrixBackend {
  Future<void> _refreshEncryptionSetup() async {
    if (_client == null || !_matrix.isLogged()) return;
    _encryptionSetup = const EncryptionSetupState(
      status: EncryptionSetupStatus.loading,
    );
    _notifyBackendListeners();
    try {
      final encryption = _matrix.encryption;
      if (encryption == null) {
        _encryptionSetup = const EncryptionSetupState(
          status: EncryptionSetupStatus.unavailable,
          message: 'End-to-end encryption is unavailable on this device.',
        );
      } else {
        final state = await _matrix.getCryptoIdentityState();
        final ownDevice = _matrix
            .userDeviceKeys[_matrix.userID]
            ?.deviceKeys[_matrix.deviceID];
        final deviceVerified = ownDevice?.verified ?? false;
        final hasSecureStorage = encryption.ssss.defaultKeyId != null;
        final status = state.initialized
            ? state.connected && deviceVerified
                  ? EncryptionSetupStatus.ready
                  : EncryptionSetupStatus.needsRecovery
            : hasSecureStorage ||
                  state.keyBackupEnabled ||
                  state.crossSigningEnabled
            ? EncryptionSetupStatus.needsRepair
            : EncryptionSetupStatus.needsSetup;
        _encryptionSetup = EncryptionSetupState(
          status: status,
          keyBackupEnabled: state.keyBackupEnabled,
          crossSigningEnabled: state.crossSigningEnabled,
          deviceVerified: deviceVerified,
        );
      }
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: EncryptionSetupStatus.error,
        message: _friendlyError(exception),
      );
    }
    _notifyBackendListeners();
  }

  Future<void> _recoverEncryption(String recoveryKeyOrPassphrase) async {
    final credential = recoveryKeyOrPassphrase.trim();
    if (credential.isEmpty) throw ArgumentError('Enter a recovery key.');
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (current.initialized) {
        if (!current.connected) {
          await _matrix.restoreCryptoIdentity(credential);
        } else {
          await _matrix.encryption!.crossSigning.selfSign(
            keyOrPassphrase: credential,
          );
        }
      } else {
        await _matrix.initCryptoIdentity(
          reuseExistingStorageRecoveryKeyOrPassphrase: credential,
          wipeSecureStorage: false,
          wipeKeyBackup: false,
          wipeCrossSigning: false,
          setupMasterKey: !current.crossSigningEnabled,
          setupSelfSigningKey: !current.crossSigningEnabled,
          setupUserSigningKey: !current.crossSigningEnabled,
          setupOnlineKeyBackup: !current.keyBackupEnabled,
        );
      }
      await refreshEncryptionSetup();
      unawaited(_refreshRoomMetadata());
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<String> _createEncryptionSetup() async {
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (current.initialized ||
          _matrix.encryption?.ssss.defaultKeyId != null) {
        throw StateError(
          'Existing encrypted identity data was found. Recover it instead of replacing it.',
        );
      }
      final recoveryKey = await _matrix.initCryptoIdentity(
        keyName: 'Deltiecord recovery key',
        wipeSecureStorage: false,
        wipeKeyBackup: false,
        wipeCrossSigning: false,
      );
      await refreshEncryptionSetup();
      return recoveryKey;
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<String> _regenerateEncryptionRecoveryKey() async {
    try {
      final current = await _matrix.getCryptoIdentityState();
      if (!current.initialized || !current.connected) {
        throw StateError(
          'Recover and verify this device before replacing the recovery key.',
        );
      }
      // The SDK rewrites Secure Secret Storage with a new key while retaining
      // the already-connected cross-signing identity and online key backup.
      // Never run this from an unconnected device: the local identity secrets
      // are what make a non-destructive rotation possible.
      final recoveryKey = await _matrix.initCryptoIdentity(
        keyName: 'Deltiecord recovery key',
        wipeSecureStorage: true,
        wipeKeyBackup: false,
        wipeCrossSigning: false,
        setupMasterKey: true,
        setupSelfSigningKey: true,
        setupUserSigningKey: true,
        setupOnlineKeyBackup: true,
      );
      await refreshEncryptionSetup();
      return recoveryKey;
    } catch (exception) {
      _encryptionSetup = EncryptionSetupState(
        status: _encryptionSetup.status,
        keyBackupEnabled: _encryptionSetup.keyBackupEnabled,
        crossSigningEnabled: _encryptionSetup.crossSigningEnabled,
        deviceVerified: _encryptionSetup.deviceVerified,
        message: _friendlyError(exception),
      );
      _notifyBackendListeners();
      rethrow;
    }
  }
}
