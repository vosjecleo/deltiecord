import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_checker.dart';

/// Performs one silent, bounded release check after the signed-in UI appears.
///
/// Update discovery must never delay Matrix startup. Network and parse errors
/// are intentionally ignored here; the explicit checker in Settings remains
/// available for diagnostics and retrying.
class StartupUpdateGate extends StatefulWidget {
  const StartupUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends State<StartupUpdateGate> {
  static bool _checkedThisProcess = false;

  @override
  void initState() {
    super.initState();
    if (!_checkedThisProcess) {
      _checkedThisProcess = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_check());
      });
    }
  }

  Future<void> _check() async {
    final checker = UpdateChecker();
    try {
      final package = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(package.buildNumber) ?? 0;
      final result = await checker.check(
        currentVersion: package.version,
        currentBuild: currentBuild,
        stableOnly: true,
      );
      if (!mounted || !result.updateAvailable) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Deltiecord update available'),
          content: Text(
            'Version ${result.version} build ${result.build} is available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                launchUrl(
                  Uri.parse(deltiecordReleasesPage),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('View release'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Startup update checks are advisory and must not affect the session.
    } finally {
      checker.close();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
