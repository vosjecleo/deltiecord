import 'package:flutter/material.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import 'mobile_profile_sheet.dart';
import 'mobile_widgets.dart';
import '../member_management.dart';

class MobileDetailsPanel extends StatelessWidget {
  const MobileDetailsPanel({
    required this.backend,
    required this.room,
    required this.onDismiss,
    super.key,
  });

  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('mobile-details-panel'),
    onHorizontalDragEnd: (details) {
      if ((details.primaryVelocity ?? 0) > 250) onDismiss();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onDismiss,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: MobileAvatar(
              bytes: room.avatarBytes,
              fallback: room.name,
              presence: room.isDirect ? room.presence : null,
              size: 92,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            room.name,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (room.topic.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(room.topic, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: Text(backend.selectedRoomMuted ? 'Muted' : 'Enabled'),
            value: !backend.selectedRoomMuted,
            onChanged: (enabled) => backend.setSelectedRoomMuted(!enabled),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_outlined),
            title: const Text('Invite member'),
            onTap: () => showInviteMember(context, backend),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('Room aliases'),
            onTap: () => showRoomAliasEditor(context, backend, room),
          ),
          const Divider(height: 28),
          Text(
            'Members — ${backend.selectedRoomMembers.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          for (final member in backend.selectedRoomMembers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MobileAvatar(
                bytes: member.avatarBytes,
                fallback: member.displayName,
                presence: member.presence,
              ),
              title: Text(member.displayName),
              subtitle: Text(
                member.powerLevel >= 100
                    ? 'Administrator'
                    : member.powerLevel >= 50
                    ? 'Moderator'
                    : mobilePresenceLabel(member.presence),
              ),
              onTap: () =>
                  showMobileProfileSheet(context, backend, member.userId),
              onLongPress: () => showMemberManagement(context, backend, member),
            ),
        ],
      ),
    ),
  );
}
