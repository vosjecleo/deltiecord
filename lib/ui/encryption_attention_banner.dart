import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'security_center.dart';

class EncryptionAttentionBanner extends StatelessWidget {
  const EncryptionAttentionBanner({
    required this.backend,
    required this.room,
    super.key,
  });

  final ChatBackend backend;
  final RoomSummary room;

  @override
  Widget build(BuildContext context) {
    final state = backend.encryptionSetup;
    if (!room.encrypted || !state.needsAttention) {
      return const SizedBox.shrink();
    }
    final label = state.deviceVerified
        ? 'Encryption needs attention on this account.'
        : 'This device is not verified. Encrypted history may be unavailable.';
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        key: const Key('conversation-encryption-warning'),
        onTap: () => showSecurityCenter(context, backend),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              const Icon(Icons.gpp_maybe_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(label)),
              const Text('Review'),
            ],
          ),
        ),
      ),
    );
  }
}
