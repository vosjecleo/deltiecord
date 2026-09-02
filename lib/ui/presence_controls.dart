import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

Future<void> showPresenceControls(
  BuildContext context,
  ChatBackend backend,
) async {
  final mode = await showModalBottomSheet<PresenceMode>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          const ListTile(
            title: Text('Set presence'),
            subtitle: Text(
              'Synced through Matrix presence and Deltiecord settings',
            ),
          ),
          for (final mode in PresenceMode.values)
            ListTile(
              leading: Icon(
                backend.presenceMode == mode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _presenceColor(mode),
              ),
              title: Text(_presenceLabel(mode)),
              subtitle: mode == PresenceMode.doNotDisturb
                  ? const Text('Suppress notifications on desktop and mobile')
                  : mode == PresenceMode.invisible
                  ? const Text('Appear offline')
                  : null,
              onTap: () => Navigator.pop(context, mode),
            ),
        ],
      ),
    ),
  );
  if (mode != null) await backend.setPresenceMode(mode);
}

String _presenceLabel(PresenceMode mode) => switch (mode) {
  PresenceMode.online => 'Online',
  PresenceMode.idle => 'Idle',
  PresenceMode.doNotDisturb => 'Do not disturb',
  PresenceMode.invisible => 'Invisible',
};

Color _presenceColor(PresenceMode mode) => switch (mode) {
  PresenceMode.online => const Color(0xff43b581),
  PresenceMode.idle => const Color(0xffffc857),
  PresenceMode.doNotDisturb => const Color(0xffe5484d),
  PresenceMode.invisible => const Color(0xff747680),
};
