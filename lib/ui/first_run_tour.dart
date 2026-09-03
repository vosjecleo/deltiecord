import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/first_run_tour_store.dart';
import 'deltiecord_theme.dart';
import 'settings_screen.dart';

class FirstRunTourGate extends StatefulWidget {
  const FirstRunTourGate({
    required this.backend,
    required this.child,
    super.key,
  });

  final ChatBackend backend;
  final Widget child;

  @override
  State<FirstRunTourGate> createState() => _FirstRunTourGateState();
}

class _FirstRunTourGateState extends State<FirstRunTourGate> {
  final _store = FirstRunTourStore();
  bool _checking = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant FirstRunTourGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      oldWidget.backend.removeListener(_schedule);
      widget.backend.addListener(_schedule);
      _shown = false;
    }
    _schedule();
  }

  void _schedule() {
    if (!widget.backend.shouldShowFirstRunTour) return;
    final userId = widget.backend.userId;
    if (!mounted || _checking || _shown || userId == null) return;
    // Avoid stacking the tour over the mandatory recovery-key prompt.
    if (widget.backend.encryptionSetup.status ==
            EncryptionSetupStatus.needsRecovery ||
        widget.backend.encryptionSetup.status ==
            EncryptionSetupStatus.needsRepair) {
      return;
    }
    _checking = true;
    _store.isComplete(userId).then((complete) {
      _checking = false;
      if (!mounted || complete || _shown) return;
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(userId));
    });
  }

  Future<void> _show(String userId) async {
    if (!mounted) return;
    final openNotifications = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FirstRunTourDialog(backend: widget.backend),
    );
    await _store.markComplete(userId);
    if (openNotifications == true && mounted) {
      await showDeltiecordNotificationSettings(context, widget.backend);
    }
  }

  @override
  void dispose() {
    widget.backend.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FirstRunTourDialog extends StatefulWidget {
  const _FirstRunTourDialog({required this.backend});

  final ChatBackend backend;

  @override
  State<_FirstRunTourDialog> createState() => _FirstRunTourDialogState();
}

class _FirstRunTourDialogState extends State<_FirstRunTourDialog> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _TourPage(
        icon: Icons.waving_hand_outlined,
        title: 'Welcome to Deltiecord!',
        body:
            'Deltiecord is a Matrix client with desktop and phone interfaces. '
            'Your rooms and encryption remain Matrix-compatible, while a few '
            'Deltiecord preferences can sync between your devices.',
      ),
      _TourPage(
        icon: Icons.link_outlined,
        title: 'Choose how previews connect',
        body:
            'Deltiecord asks your Matrix homeserver for link previews first. '
            'A direct fallback can reveal your IP address and browsing metadata '
            'to linked websites.',
        child: DropdownButtonFormField<DirectLinkPreviewMode>(
          key: const ValueKey('tour-link-preview-mode'),
          initialValue: widget.backend.preferences.directLinkPreviewMode,
          decoration: const InputDecoration(labelText: 'Direct link previews'),
          items: const [
            DropdownMenuItem(
              value: DirectLinkPreviewMode.none,
              child: Text('Never contact linked sites directly'),
            ),
            DropdownMenuItem(
              value: DirectLinkPreviewMode.trustedProviders,
              child: Text('Known providers only'),
            ),
            DropdownMenuItem(
              value: DirectLinkPreviewMode.allPublicSites,
              child: Text('All public websites'),
            ),
          ],
          onChanged: (mode) {
            if (mode == null) return;
            widget.backend.updatePreferences(
              widget.backend.preferences.copyWith(directLinkPreviewMode: mode),
            );
          },
        ),
      ),
      _TourPage(
        icon: Icons.notifications_active_outlined,
        title: 'Set up private background notifications',
        body:
            'On Android, install the ntfy app and enable its UnifiedPush '
            'distributor. In ntfy, use https://push.deltie.net as the default '
            'server. Then open Deltiecord’s Notification settings, choose ntfy, '
            'and refresh the registration. The public ntfy.sh service can '
            'occasionally delay or rate-limit delivery; Deltiecord’s provider '
            'avoids that shared public limit.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://f-droid.org/packages/io.heckel.ntfy/'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Get ntfy from F-Droid'),
          ),
        ),
      ),
    ];
    return AlertDialog(
      title: Text('Getting started · ${_page + 1}/${pages.length}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: KeyedSubtree(key: ValueKey(_page), child: pages[_page]),
        ),
      ),
      actions: [
        if (_page > 0)
          TextButton(
            onPressed: () => setState(() => _page--),
            child: const Text('Back'),
          ),
        if (_page < pages.length - 1)
          FilledButton(
            onPressed: () => setState(() => _page++),
            child: const Text('Next'),
          )
        else
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('Open notification settings'),
          ),
      ],
    );
  }
}

class _TourPage extends StatelessWidget {
  const _TourPage({
    required this.icon,
    required this.title,
    required this.body,
    this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 14),
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Text(body, style: TextStyle(color: context.deltiecord.muted)),
      if (child != null) ...[const SizedBox(height: 18), child!],
    ],
  );
}
