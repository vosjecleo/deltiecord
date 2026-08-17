import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

Future<void> showSecurityCenter(BuildContext context, ChatBackend backend) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SecurityDialog(backend: backend),
    );

class _SecurityDialog extends StatefulWidget {
  const _SecurityDialog({required this.backend});

  final ChatBackend backend;

  @override
  State<_SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<_SecurityDialog> {
  final _recoveryKey = TextEditingController();
  bool _working = false;
  bool _hideRecoveryKey = true;
  bool _savedGeneratedKey = false;
  String? _generatedRecoveryKey;
  String? _localError;

  @override
  void dispose() {
    _recoveryKey.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    if (_recoveryKey.text.trim().isEmpty) {
      setState(() => _localError = 'Enter your recovery key or passphrase.');
      return;
    }
    setState(() {
      _working = true;
      _localError = null;
    });
    try {
      await widget.backend.recoverEncryption(_recoveryKey.text);
      if (mounted &&
          widget.backend.encryptionSetup.status ==
              EncryptionSetupStatus.ready) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _localError =
              widget.backend.encryptionSetup.message ??
              'The recovery key could not unlock this account.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createSetup() async {
    setState(() {
      _working = true;
      _localError = null;
    });
    try {
      final key = await widget.backend.createEncryptionSetup();
      if (mounted) setState(() => _generatedRecoveryKey = key);
    } catch (_) {
      if (mounted) {
        setState(() {
          _localError =
              widget.backend.encryptionSetup.message ??
              'Encryption setup could not be completed.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _regenerateRecoveryKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace recovery key?'),
        content: const Text(
          'Your existing recovery key will stop working. Cross-signing and '
          'encrypted key backup will be kept, but you must save the new key '
          'before closing Deltiecord.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _localError = null;
      _savedGeneratedKey = false;
    });
    try {
      final key = await widget.backend.regenerateEncryptionRecoveryKey();
      if (mounted) setState(() => _generatedRecoveryKey = key);
    } catch (_) {
      if (mounted) {
        setState(() {
          _localError =
              widget.backend.encryptionSetup.message ??
              'The recovery key could not be replaced.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = widget.backend.encryptionSetup;
    final generatedKey = _generatedRecoveryKey;
    return PopScope(
      canPop: generatedKey == null || _savedGeneratedKey,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined),
            SizedBox(width: 10),
            Text('Encryption & recovery'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: generatedKey != null
                ? _GeneratedKey(
                    recoveryKey: generatedKey,
                    saved: _savedGeneratedKey,
                    onSavedChanged: (value) =>
                        setState(() => _savedGeneratedKey = value ?? false),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SecurityStatus(state: security),
                      if (security.status ==
                              EncryptionSetupStatus.needsRecovery ||
                          security.status ==
                              EncryptionSetupStatus.needsRepair) ...[
                        const SizedBox(height: 18),
                        TextField(
                          controller: _recoveryKey,
                          enabled: !_working,
                          obscureText: _hideRecoveryKey,
                          minLines: 1,
                          maxLines: _hideRecoveryKey ? 1 : 4,
                          decoration: InputDecoration(
                            labelText: 'Recovery key or passphrase',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _hideRecoveryKey ? 'Show' : 'Hide',
                              onPressed: () => setState(
                                () => _hideRecoveryKey = !_hideRecoveryKey,
                              ),
                              icon: Icon(
                                _hideRecoveryKey
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _working ? null : _recover(),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This credential is used only to unlock Matrix Secure Secret Storage. Deltiecord does not save the text you enter.',
                          style: TextStyle(
                            fontSize: DeltiecordTypeScale.normal,
                          ),
                        ),
                      ],
                      if (_localError case final error?) ...[
                        const SizedBox(height: 12),
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        actions: [
          if (generatedKey == null)
            TextButton(
              onPressed: _working ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          if (security.status == EncryptionSetupStatus.needsRecovery ||
              security.status == EncryptionSetupStatus.needsRepair)
            FilledButton.icon(
              onPressed: _working ? null : _recover,
              icon: const Icon(Icons.key),
              label: Text(_working ? 'Unlocking…' : 'Recover & verify'),
            ),
          if (security.status == EncryptionSetupStatus.needsSetup &&
              generatedKey == null)
            FilledButton(
              onPressed: _working ? null : _createSetup,
              child: Text(_working ? 'Setting up…' : 'Set up encryption'),
            ),
          if (security.status == EncryptionSetupStatus.ready &&
              generatedKey == null)
            FilledButton.tonalIcon(
              onPressed: _working ? null : _regenerateRecoveryKey,
              icon: const Icon(Icons.key_outlined),
              label: const Text('Replace recovery key'),
            ),
          if (generatedKey != null)
            FilledButton(
              onPressed: _savedGeneratedKey
                  ? () => Navigator.of(context).pop()
                  : null,
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}

class _SecurityStatus extends StatelessWidget {
  const _SecurityStatus({required this.state});

  final EncryptionSetupState state;

  @override
  Widget build(BuildContext context) {
    final (title, description, icon, color) = switch (state.status) {
      EncryptionSetupStatus.loading => (
        'Checking encryption…',
        'Reading cross-signing and key-backup state.',
        Icons.hourglass_top,
        Theme.of(context).colorScheme.primary,
      ),
      EncryptionSetupStatus.ready => (
        'This device is verified',
        'Cross-signing is connected and encrypted message keys can be backed up and recovered.',
        Icons.verified_user,
        Colors.green,
      ),
      EncryptionSetupStatus.needsRecovery => (
        'Recovery required',
        'Enter the recovery key or security passphrase from another Matrix client to authorize this device and unlock key backup.',
        Icons.key,
        Colors.amber,
      ),
      EncryptionSetupStatus.needsRepair => (
        'Encryption setup is incomplete',
        'Existing secure storage was found. Unlock it to repair missing cross-signing or key-backup components without replacing your recovery key.',
        Icons.build_circle_outlined,
        Colors.amber,
      ),
      EncryptionSetupStatus.needsSetup => (
        'No encrypted backup is configured',
        'This appears to be a new encryption identity. Setup will create cross-signing, encrypted key backup, and a recovery key that you must save.',
        Icons.shield_outlined,
        Colors.amber,
      ),
      EncryptionSetupStatus.unavailable => (
        'Encryption unavailable',
        state.message ?? 'This build cannot use end-to-end encryption.',
        Icons.gpp_bad_outlined,
        Theme.of(context).colorScheme.error,
      ),
      EncryptionSetupStatus.error => (
        'Could not check encryption',
        state.message ?? 'Try again after the client finishes syncing.',
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _StatusLine(label: 'Cross-signing', enabled: state.crossSigningEnabled),
        _StatusLine(
          label: 'Encrypted key backup',
          enabled: state.keyBackupEnabled,
        ),
        _StatusLine(
          label: 'This device authorized',
          enabled: state.deviceVerified,
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(
          enabled ? Icons.check_circle : Icons.cancel,
          size: 17,
          color: enabled ? Colors.green : Colors.amber,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}

class _GeneratedKey extends StatelessWidget {
  const _GeneratedKey({
    required this.recoveryKey,
    required this.saved,
    required this.onSavedChanged,
  });

  final String recoveryKey;
  final bool saved;
  final ValueChanged<bool?> onSavedChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Save this recovery key now',
        style: TextStyle(
          fontSize: DeltiecordTypeScale.bigUi,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'It is the only way to recover encrypted message history if all authorized devices are lost. Deltiecord will not show it again.',
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff191a1e),
          border: Border.all(color: const Color(0xff4a4c56)),
          borderRadius: DeltiecordCorners.borderRadius,
        ),
        child: SelectableText(
          recoveryKey,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: DeltiecordTypeScale.bigChat,
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => Clipboard.setData(ClipboardData(text: recoveryKey)),
        icon: const Icon(Icons.copy, size: 18),
        label: const Text('Copy recovery key'),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        value: saved,
        onChanged: onSavedChanged,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('I saved this recovery key somewhere safe'),
      ),
    ],
  );
}
