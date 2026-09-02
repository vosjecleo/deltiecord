import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

Future<void> showMemberManagement(
  BuildContext context,
  ChatBackend backend,
  RoomMemberSummary member,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            title: Text(member.displayName),
            subtitle: Text(member.userId),
          ),
          if (member.membership == 'knock') ...[
            ListTile(
              leading: const Icon(Icons.how_to_reg_outlined),
              title: const Text('Approve join request'),
              onTap: () => Navigator.pop(context, 'approve-knock'),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Decline join request'),
              onTap: () => Navigator.pop(context, 'reject-knock'),
            ),
          ],
          if (member.canChangePowerLevel)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Edit power level'),
              subtitle: Text('${member.powerLevel}'),
              onTap: () => Navigator.pop(context, 'power'),
            ),
          if (member.canKick)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Timeout for 10 minutes'),
              onTap: () => Navigator.pop(context, 'timeout'),
            ),
          if (member.canKick)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('Kick'),
              onTap: () => Navigator.pop(context, 'kick'),
            ),
          if (member.canBan)
            ListTile(
              leading: Icon(
                Icons.block,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Ban',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'ban'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'approve-knock':
      await backend.approveKnock(member.userId);
    case 'reject-knock':
      await backend.rejectKnock(member.userId);
    case 'power':
      final level = await _askPowerLevel(context, member);
      if (level != null) {
        await backend.setMemberPowerLevel(member.userId, level);
      }
    case 'timeout':
      await backend.timeoutMember(
        member.userId,
        DateTime.now().add(const Duration(minutes: 10)),
      );
    case 'kick':
      final reason = await _askReason(context, 'Kick ${member.displayName}?');
      if (reason != null) {
        await backend.kickMember(member.userId, reason: reason);
      }
    case 'ban':
      final reason = await _askReason(context, 'Ban ${member.displayName}?');
      if (reason != null) {
        await backend.banMember(member.userId, reason: reason);
      }
  }
}

Future<void> showInviteMember(BuildContext context, ChatBackend backend) async {
  final controller = TextEditingController();
  final userId = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Invite to room'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '@user:homeserver.tld'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Invite'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (userId?.startsWith('@') == true) await backend.inviteMember(userId!);
}

Future<void> showRoomAliasEditor(
  BuildContext context,
  ChatBackend backend,
  RoomSummary room,
) async {
  final aliases = await backend.getRoomAliases(room.id);
  if (!context.mounted) return;
  final mutableAliases = aliases.toList(growable: true);
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Room aliases'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final alias in mutableAliases)
                ListTile(
                  dense: true,
                  title: Text(alias),
                  subtitle: const Text('Tap to make canonical'),
                  onTap: () async {
                    await backend.setRoomCanonicalAlias(room.id, alias);
                    if (context.mounted) Navigator.pop(context);
                  },
                  trailing: IconButton(
                    tooltip: 'Delete alias',
                    onPressed: () async {
                      await backend.deleteRoomAlias(alias);
                      setState(() => mutableAliases.remove(alias));
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'New alias',
                  hintText: '#room:homeserver.tld',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await backend.setRoomCanonicalAlias(room.id, null);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Clear canonical'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              final alias = controller.text.trim();
              if (!alias.startsWith('#')) return;
              await backend.addRoomAlias(room.id, alias);
              await backend.setRoomCanonicalAlias(room.id, alias);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add and set canonical'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

Future<int?> _askPowerLevel(
  BuildContext context,
  RoomMemberSummary member,
) async {
  var value = member.powerLevel.clamp(0, member.maxAssignablePowerLevel);
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Power level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$value'),
            Slider(
              value: value.toDouble(),
              min: 0,
              max: member.maxAssignablePowerLevel.toDouble(),
              divisions: member.maxAssignablePowerLevel,
              onChanged: (next) => setState(() => value = next.round()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _askReason(BuildContext context, String title) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Reason (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  final reason = controller.text.trim();
  controller.dispose();
  return confirmed == true ? reason : null;
}
