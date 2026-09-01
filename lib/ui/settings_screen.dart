import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../version.dart';
import '../services/app_sounds.dart';
import '../services/font_preferences.dart';
import '../services/microphone_test.dart';
import '../services/secret_redaction.dart';
import '../services/unified_push.dart';
import '../services/update_checker.dart';
import 'accent_color_picker.dart';
import 'security_center.dart';
import 'app_shortcuts.dart';
import 'profile_card.dart';
import 'profile_editor_dialog.dart';
import 'deltiecord_theme.dart';

enum _SettingsPage {
  account,
  devices,
  encryption,
  audioVideo,
  notifications,
  privacy,
  appearance,
  accessibility,
  storage,
  shortcuts,
  advanced,
  about,
}

enum _SettingPlatform { cross, desktop, mobile }

_SettingPlatform _availabilityFor(_SettingsPage page) => switch (page) {
  _SettingsPage.shortcuts => _SettingPlatform.desktop,
  _ => _SettingPlatform.cross,
};

bool _availableOnCurrentPlatform(
  _SettingsPage page,
) => switch (_availabilityFor(page)) {
  _SettingPlatform.cross => true,
  _SettingPlatform.desktop => defaultTargetPlatform != TargetPlatform.android,
  _SettingPlatform.mobile => defaultTargetPlatform == TargetPlatform.android,
};

Future<void> showDeltiecordSettings(
  BuildContext context,
  ChatBackend backend,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _SettingsScreen(backend: backend),
    fullscreenDialog: true,
  ),
);

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({required this.backend});

  final ChatBackend backend;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  _SettingsPage _page = _SettingsPage.account;
  bool _mobilePageOpen = false;
  Future<UserProfileSummary>? _ownProfile;
  Future<UnifiedPushState>? _unifiedPushState;
  bool _checkingForUpdates = false;
  late final MicrophoneTestController _microphoneTest =
      MicrophoneTestController();

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    backend.refreshAudioInputs();
    backend.refreshDevices();
    backend.refreshProfile();
    backend.refreshStorageUsage();
    _reloadOwnProfile();
    if (UnifiedPushPlatform.instance.supported) _reloadUnifiedPush();
  }

  void _reloadOwnProfile() {
    final userId = backend.userId;
    if (userId != null) _ownProfile = backend.getUserProfile(userId);
  }

  void _reloadUnifiedPush() {
    final userId = backend.userId;
    if (userId == null) return;
    setState(() {
      _unifiedPushState = UnifiedPushPlatform.instance.state(userId);
    });
  }

  @override
  void dispose() {
    _microphoneTest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    void closeTopmost() {
      if (mobile && _mobilePageOpen) {
        setState(() => _mobilePageOpen = false);
      } else {
        Navigator.of(context).maybePop();
      }
    }

    return PopScope(
      canPop: !mobile || !_mobilePageOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _mobilePageOpen) {
          setState(() => _mobilePageOpen = false);
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): closeTopmost,
        },
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: backend,
            builder: (context, _) => Scaffold(
              appBar: AppBar(
                title: Text(
                  mobile && _mobilePageOpen ? _labelFor(_page) : 'Settings',
                ),
                leading: IconButton(
                  tooltip: mobile && _mobilePageOpen
                      ? 'Back to settings'
                      : 'Close settings',
                  onPressed: closeTopmost,
                  icon: Icon(
                    mobile && _mobilePageOpen ? Icons.arrow_back : Icons.close,
                  ),
                ),
              ),
              body: mobile
                  ? ClipRect(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(
                          'mobile-settings-transition-$_mobilePageOpen-${_page.name}',
                        ),
                        tween: Tween(begin: 1, end: 0),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        builder: (context, progress, child) =>
                            Transform.translate(
                              offset: Offset(
                                MediaQuery.sizeOf(context).width *
                                    0.14 *
                                    progress *
                                    (_mobilePageOpen ? 1 : -1),
                                0,
                              ),
                              child: child,
                            ),
                        child: _mobilePageOpen
                            ? _settingsPagePane(
                                key: ValueKey('mobile-settings-${_page.name}'),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  20,
                                ),
                              )
                            : _settingsNavigation(
                                key: const ValueKey(
                                  'mobile-settings-navigation',
                                ),
                                mobile: true,
                              ),
                      ),
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: _settingsNavigation(mobile: false),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _settingsPagePane()),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsNavigation({required bool mobile, Key? key}) => Material(
    key: key,
    color: context.deltiecord.panel,
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              for (final page in _SettingsPage.values)
                if (_availableOnCurrentPlatform(page))
                  ListTile(
                    selected: !mobile && _page == page,
                    leading: Icon(_iconFor(page), size: 21),
                    title: Text(_labelFor(page)),
                    trailing: mobile ? const Icon(Icons.chevron_right) : null,
                    onTap: () => setState(() {
                      _page = page;
                      if (mobile) _mobilePageOpen = true;
                    }),
                  ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, size: 21),
          title: const Text('Log out'),
          onTap: backend.logout,
        ),
        const SizedBox(height: 6),
      ],
    ),
  );

  Widget _settingsPagePane({Key? key, EdgeInsets? padding}) =>
      SingleChildScrollView(
        key: key,
        padding: padding ?? const EdgeInsets.fromLTRB(28, 22, 32, 40),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _pageBody(),
          ),
        ),
      );

  Widget _pageBody() => switch (_page) {
    _SettingsPage.account => _account(),
    _SettingsPage.devices => _devices(),
    _SettingsPage.encryption => _section('Encryption & recovery', [
      _value('Status', _encryptionLabel(backend.encryptionSetup.status)),
      _value(
        'Encrypted key backup',
        backend.encryptionSetup.keyBackupEnabled ? 'Enabled' : 'Not configured',
      ),
      _value(
        'This device',
        backend.encryptionSetup.deviceVerified ? 'Verified' : 'Not verified',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => showSecurityCenter(context, backend),
        icon: const Icon(Icons.shield_outlined),
        label: const Text('Open encryption & recovery'),
      ),
    ]),
    _SettingsPage.audioVideo => _section('Audio & video', [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: backend.selectedAudioInputId,
              decoration: const InputDecoration(
                labelText: 'Microphone',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('System default'),
                ),
                for (final input in backend.audioInputs)
                  DropdownMenuItem(value: input.id, child: Text(input.label)),
              ],
              onChanged: backend.selectAudioInput,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh microphones',
            onPressed: backend.refreshAudioInputs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (backend.audioOutputs.isNotEmpty) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: backend.selectedAudioOutputId,
          decoration: const InputDecoration(
            labelText: 'Audio output',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('System default')),
            for (final output in backend.audioOutputs)
              DropdownMenuItem(value: output.id, child: Text(output.label)),
          ],
          onChanged: backend.selectAudioOutput,
        ),
      ],
      if (backend.cameras.isNotEmpty) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: backend.selectedCameraId,
          decoration: const InputDecoration(
            labelText: 'Camera',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('System default')),
            for (final camera in backend.cameras)
              DropdownMenuItem(value: camera.id, child: Text(camera.label)),
          ],
          onChanged: backend.selectCamera,
        ),
      ],
      const SizedBox(height: 18),
      Text(
        'Microphone volume — '
        '${(backend.preferences.microphoneVolume * 100).round()}%',
      ),
      Slider(
        key: const Key('microphone-volume-slider'),
        value: backend.preferences.microphoneVolume,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(microphoneVolume: value),
        ),
      ),
      const SizedBox(height: 14),
      AnimatedBuilder(
        animation: _microphoneTest,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Microphone test',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  key: const Key('microphone-test-level'),
                  value: _microphoneTest.level,
                ),
                if (_microphoneTest.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _microphoneTest.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _microphoneTest.starting
                          ? null
                          : _microphoneTest.running
                          ? _microphoneTest.stop
                          : () => _microphoneTest.start(
                              MicrophoneTestConfiguration(
                                deviceId: backend.selectedAudioInputId,
                                echoCancellation:
                                    backend.preferences.echoCancellation,
                                noiseSuppression:
                                    backend.preferences.noiseSuppression,
                                autoGainControl:
                                    backend.preferences.autoGainControl,
                              ),
                            ),
                      icon: Icon(
                        _microphoneTest.running ? Icons.stop : Icons.mic,
                      ),
                      label: Text(
                        _microphoneTest.starting
                            ? 'Starting…'
                            : _microphoneTest.running
                            ? 'Stop test'
                            : 'Start test',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _microphoneTest.running
                          ? () => _microphoneTest.setListening(
                              !_microphoneTest.listening,
                            )
                          : null,
                      icon: Icon(
                        _microphoneTest.listening
                            ? Icons.hearing_disabled
                            : Icons.hearing,
                      ),
                      label: Text(
                        _microphoneTest.listening
                            ? 'Stop listening'
                            : 'Listen locally',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use headphones before listening locally to avoid feedback.',
                ),
              ],
            ),
          ),
        ),
      ),
      Text(
        'Output volume — ${(backend.preferences.outputVolume * 100).round()}%',
      ),
      Slider(
        key: const Key('output-volume-slider'),
        value: backend.preferences.outputVolume,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(outputVolume: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Echo cancellation'),
        subtitle: const Text('Reduce feedback from speakers into your mic.'),
        value: backend.preferences.echoCancellation,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(echoCancellation: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Background noise suppression'),
        subtitle: const Text('Filter steady room and equipment noise.'),
        value: backend.preferences.noiseSuppression,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(noiseSuppression: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Automatic microphone gain'),
        value: backend.preferences.autoGainControl,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(autoGainControl: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Call sounds'),
        subtitle: const Text('Play a cue when connecting or disconnecting.'),
        value: backend.preferences.callSound,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(callSound: value),
        ),
      ),
      OutlinedButton.icon(
        onPressed: AppSounds.callConnected,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Test call sound'),
      ),
      if (defaultTargetPlatform == TargetPlatform.linux) ...[
        const SizedBox(height: 12),
        const Text(
          'Screen selection uses the standard desktop portal on Linux/Wayland.',
        ),
      ],
    ]),
    _SettingsPage.notifications => _section('Notifications', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          defaultTargetPlatform == TargetPlatform.android
              ? 'System notifications'
              : 'Desktop notifications',
        ),
        subtitle: const Text('Notify for new Matrix messages.'),
        value: backend.preferences.notificationsEnabled,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(notificationsEnabled: value),
        ),
      ),
      OutlinedButton.icon(
        onPressed: AppSounds.notification,
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Test notification sound'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show message content'),
        subtitle: const Text(
          'Include decrypted message previews in notifications.',
        ),
        value: backend.notificationPreviewsEnabled,
        onChanged: backend.setNotificationPreviewsEnabled,
      ),
      if (defaultTargetPlatform == TargetPlatform.android)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notification vibration'),
          subtitle: const Text('Allow message alerts to vibrate the device.'),
          value: backend.preferences.notificationVibration,
          onChanged: (value) => backend.updatePreferences(
            backend.preferences.copyWith(notificationVibration: value),
          ),
        ),
      const SizedBox(height: 8),
      DropdownButtonFormField<NotificationAlertCadence>(
        initialValue: backend.preferences.notificationAlertCadence,
        decoration: const InputDecoration(labelText: 'Alert cadence'),
        items: const [
          DropdownMenuItem(
            value: NotificationAlertCadence.fiveMinuteCooldown,
            child: Text('Once every 5 minutes per conversation'),
          ),
          DropdownMenuItem(
            value: NotificationAlertCadence.everyMessage,
            child: Text('Every message'),
          ),
          DropdownMenuItem(
            value: NotificationAlertCadence.silent,
            child: Text('Silent'),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          backend.updatePreferences(
            backend.preferences.copyWith(notificationAlertCadence: value),
          );
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Notification sound'),
        subtitle: Text(
          defaultTargetPlatform == TargetPlatform.android
              ? 'Allow Android message alerts to play sound.'
              : 'Allow the desktop notification service to play sound.',
        ),
        value: backend.preferences.notificationSound,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(notificationSound: value),
        ),
      ),
      if (UnifiedPushPlatform.instance.supported) ...[
        const Divider(height: 28),
        Text('UnifiedPush', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Uses a distributor app such as ntfy to wake Deltiecord for Matrix '
          'activity. The distributor endpoint and Matrix gateway are kept on '
          'the same ntfy server, including custom servers.',
        ),
        if (_unifiedPushState case final stateFuture?)
          FutureBuilder<UnifiedPushState>(
            future: stateFuture,
            builder: (context, snapshot) {
              final state = snapshot.data;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  state?.registered == true
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                ),
                title: Text(
                  state?.registered == true
                      ? 'UnifiedPush registered'
                      : 'UnifiedPush not registered',
                ),
                subtitle: Text(
                  state?.error != null
                      ? 'Distributor error: ${state!.error}'
                      : [
                          state?.distributor ??
                              'Install and configure a UnifiedPush distributor.',
                          if (state?.lastMessageReceived case final received?)
                            'Last background push: ${received.toLocal()}',
                          if (state?.lastNotificationPosted case final posted?)
                            'Last native alert: ${posted.toLocal()}',
                        ].join('\n'),
                ),
                trailing: snapshot.connectionState != ConnectionState.done
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              );
            },
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _chooseUnifiedPushDistributor,
              icon: const Icon(Icons.hub_outlined),
              label: const Text('Choose distributor'),
            ),
            OutlinedButton.icon(
              onPressed: _refreshUnifiedPushRegistration,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh registration'),
            ),
            TextButton.icon(
              onPressed: _disableUnifiedPush,
              icon: const Icon(Icons.link_off),
              label: const Text('Disable'),
            ),
          ],
        ),
        const Text(
          'The private push endpoint is stored by Android and is never shown '
          'or written to logs. Notification content is fetched from Matrix.',
        ),
      ],
    ]),
    _SettingsPage.privacy => _privacy(),
    _SettingsPage.appearance => _appearance(),
    _SettingsPage.accessibility => _accessibility(),
    _SettingsPage.storage => _section('Storage', [
      const Text(
        'Encrypted session data, room keys, thumbnails, and timeline caches are '
        'stored in Deltiecord’s private per-user application-data directory.',
      ),
      const SizedBox(height: 12),
      _value('Application data', _formatBytes(backend.storageUsageBytes)),
      const Text(
        'This includes the encrypted Matrix database and locally cached media. '
        'Clearing media cache does not remove room keys or your signed-in session.',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: backend.storageLoading
                ? null
                : backend.refreshStorageUsage,
            icon: const Icon(Icons.refresh),
            label: const Text('Recalculate'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: backend.storageLoading ? null : backend.clearMediaCache,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear media cache'),
          ),
        ],
      ),
    ]),
    _SettingsPage.shortcuts => _shortcuts(),
    _SettingsPage.advanced => _section('Advanced diagnostics', [
      DropdownButtonFormField<String>(
        initialValue: normalizeEmojiFontFamily(
          backend.preferences.emojiFontFamily,
        ),
        decoration: const InputDecoration(
          labelText: 'Fallback emoji font',
          helperText:
              'System fallback is recommended and avoids changing text spacing.',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: 'Deltiecord Emoji',
            child: Text('Bundled Noto Color Emoji'),
          ),
          DropdownMenuItem(value: 'System', child: Text('System emoji font')),
        ],
        onChanged: (font) {
          if (font != null) {
            backend.updatePreferences(
              backend.preferences.copyWith(emojiFontFamily: font),
            );
          }
        },
      ),
      const SizedBox(height: 18),
      _value('Deltiecord', 'v$deltiecordVersion ($deltiecordBuildNumber)'),
      _value('Session', backend.status.name),
      _value('Connection', backend.connectionStatus.name),
      _value('Voice', backend.voiceConnectionStatus.name),
      _value('Selected room', backend.selectedRoom?.id ?? 'None'),
      const SizedBox(height: 18),
      Text(
        'Timeline message chunk size — ${backend.preferences.timelineChunkSize}',
      ),
      Slider(
        value: backend.preferences.timelineChunkSize.toDouble(),
        min: 10,
        max: 100,
        divisions: 9,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(timelineChunkSize: value.round()),
        ),
      ),
      Text(
        'Timeline message chunk cap — ${backend.preferences.timelineChunkCap}',
      ),
      Slider(
        value: backend.preferences.timelineChunkCap.toDouble(),
        min: 1,
        max: 10,
        divisions: 9,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(timelineChunkCap: value.round()),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () {
          final report = [
            'Deltiecord v$deltiecordVersion ($deltiecordBuildNumber)',
            'session=${backend.status.name}',
            'homeserver=${backend.homeserver}',
            'device=${backend.deviceId}',
            'voice=${backend.voiceConnectionStatus.name}',
          ].join('\n');
          Clipboard.setData(ClipboardData(text: report));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Safe diagnostics copied')),
          );
        },
        icon: const Icon(Icons.copy),
        label: const Text('Copy safe diagnostics'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Diagnostics deliberately exclude access tokens, recovery material, '
        'decrypted messages, and media encryption keys.',
      ),
    ]),
    _SettingsPage.about => _section('About Deltiecord', [
      Text(
        'Deltiecord v$deltiecordVersion\n'
        'A compact, old-school ${defaultTargetPlatform == TargetPlatform.android ? 'mobile' : 'desktop'} Matrix client built with Flutter.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('check-for-updates'),
            onPressed: _checkingForUpdates ? null : _checkForUpdates,
            icon: _checkingForUpdates
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            label: Text(
              _checkingForUpdates ? 'Checking…' : 'Check for updates',
            ),
          ),
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(deltiecordReleasesPage),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Release downloads'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Matrix connectivity and encryption use matrix-dart-sdk. MatrixRTC, '
        'media_kit, Flutter WebRTC, Flutter Quill, GIPHY, Element, and '
        'FluffyChat informed or support parts of the implementation.',
      ),
      const SizedBox(height: 12),
      const SelectableText(
        'Full acknowledgements and upstream license links are in CREDITS.md.',
      ),
      const SizedBox(height: 20),
      const Text(
        'Made for dense desktops, strange little computers, and friends.',
      ),
    ]),
  };

  Widget _shortcuts() {
    final bindings = backend.preferences.shortcutBindings;
    String? conflictFor(AppShortcutAction action, String candidate) {
      for (final entry in bindings.entries) {
        if (entry.key != action && entry.value == candidate) {
          return shortcutActionLabel(entry.key);
        }
      }
      return null;
    }

    return _section('Keyboard shortcuts', [
      Text(
        'Configurable shortcuts',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      for (final action in AppShortcutAction.values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(shortcutActionLabel(action))),
              ShortcutRecorder(
                value: bindings[action] ?? defaultShortcutBindings[action]!,
                conflict: (candidate) => conflictFor(action, candidate),
                onRecorded: (value) => backend.updatePreferences(
                  backend.preferences.copyWith(
                    shortcutBindings: {...bindings, action: value},
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => backend.updatePreferences(
          backend.preferences.copyWith(
            shortcutBindings: defaultShortcutBindings,
          ),
        ),
        icon: const Icon(Icons.restore),
        label: const Text('Restore defaults'),
      ),
      const Divider(height: 30),
      Text('Fixed shortcuts', style: Theme.of(context).textTheme.titleMedium),
      _shortcut('Close topmost popup or dialog', 'Escape'),
      _shortcut(
        'Send message',
        backend.preferences.sendWithCtrlEnter ? 'Ctrl + Enter' : 'Enter',
      ),
      _shortcut(
        'New line',
        backend.preferences.sendWithCtrlEnter ? 'Enter' : 'Shift + Enter',
      ),
      _shortcut('Paste attachment', 'Ctrl + V'),
    ]);
  }

  Widget _account() => _section('Account', [
    if (_ownProfile case final profileFuture?)
      FutureBuilder<UserProfileSummary>(
        future: profileFuture,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return DeltiecordProfileCard(
            profile: profile,
            onEdit: () async {
              final changed = await showProfileEditor(
                context,
                backend,
                profile,
              );
              if (changed && mounted) {
                setState(_reloadOwnProfile);
              }
            },
          );
        },
      )
    else
      const Text('Profile unavailable.'),
    const Divider(height: 28),
    _value('Homeserver', backend.homeserver?.toString() ?? 'Unavailable'),
    _value('Device ID', backend.deviceId ?? 'Unavailable'),
    const SizedBox(height: 28),
    Text(
      'Danger zone',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
    const Text(
      'Permanently deactivate this Matrix account and request data erasure.',
    ),
    OutlinedButton.icon(
      onPressed: _confirmDeleteAccount,
      icon: const Icon(Icons.delete_forever_outlined),
      label: const Text('Delete account'),
    ),
  ]);

  Widget _appearance() {
    final preferences = backend.preferences;
    return _section('Appearance', [
      const Text('Theme'),
      SegmentedButton<DeltiecordThemeMode>(
        segments: const [
          ButtonSegment(
            value: DeltiecordThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: DeltiecordThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Dark'),
          ),
          ButtonSegment(
            value: DeltiecordThemeMode.oled,
            icon: Icon(Icons.contrast),
            label: Text('OLED'),
          ),
        ],
        selected: {preferences.themeMode},
        onSelectionChanged: (value) => backend.updatePreferences(
          preferences.copyWith(themeMode: value.first),
        ),
      ),
      const SizedBox(height: 20),
      Text('Interface scale — ${(preferences.interfaceScale * 100).round()}%'),
      Slider(
        key: const Key('interface-scale-slider'),
        value: preferences.interfaceScale,
        min: 0.8,
        max: 1.3,
        divisions: 10,
        label: '${(preferences.interfaceScale * 100).round()}%',
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(interfaceScale: value),
        ),
      ),
      const Text(
        'Scales panels, controls, icons, media, and text together. Text-only '
        'scaling is under Accessibility.',
      ),
      const SizedBox(height: 20),
      Text('Compactness — ${(preferences.compactness * 100).round()}%'),
      Slider(
        key: const Key('compactness-slider'),
        value: preferences.compactness,
        min: 0,
        max: 1,
        divisions: 20,
        label: '${(preferences.compactness * 100).round()}%',
        onChanged: (value) =>
            backend.updatePreferences(preferences.copyWith(compactness: value)),
      ),
      const Text(
        'Lower values give text and controls more breathing room; higher '
        'values fit more information on screen.',
      ),
      const SizedBox(height: 20),
      if (defaultTargetPlatform != TargetPlatform.android) ...[
        Text('Room panel — ${preferences.roomPanelWidth.round()} px'),
        Slider(
          value: preferences.roomPanelWidth,
          min: 220,
          max: 420,
          divisions: 10,
          onChanged: (value) => backend.updatePreferences(
            preferences.copyWith(roomPanelWidth: value),
          ),
        ),
        Text('Side panel — ${preferences.sidePanelWidth.round()} px'),
        Slider(
          value: preferences.sidePanelWidth,
          min: 260,
          max: 460,
          divisions: 10,
          onChanged: (value) => backend.updatePreferences(
            preferences.copyWith(sidePanelWidth: value),
          ),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Autoplay GIFs'),
        value: preferences.autoplayGifs,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(autoplayGifs: value),
        ),
      ),
      if (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows)
        SwitchListTile(
          key: const Key('channel-drag-drop-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable channel drag and drop'),
          subtitle: const Text(
            'Off by default to prevent accidental room and category moves. '
            'Permission checks still apply.',
          ),
          value: preferences.enableChannelDragAndDrop,
          onChanged: (value) => backend.updatePreferences(
            preferences.copyWith(enableChannelDragAndDrop: value),
          ),
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: preferences.fontFamily,
        decoration: const InputDecoration(
          labelText: 'Interface font',
          border: OutlineInputBorder(),
        ),
        items:
            const [
                  'System',
                  'Noto Sans',
                  'DejaVu Sans',
                  'Liberation Sans',
                  'monospace',
                ]
                .map((font) => DropdownMenuItem(value: font, child: Text(font)))
                .toList(growable: false),
        onChanged: (font) {
          if (font != null) {
            backend.updatePreferences(preferences.copyWith(fontFamily: font));
          }
        },
      ),
      const SizedBox(height: 16),
      const Text('Accent colour'),
      const SizedBox(height: 8),
      AccentColorPickerButton(
        color: preferences.accentColor,
        label: 'Open colour wheel',
        onChanged: (color) => backend.updatePreferences(
          backend.preferences.copyWith(accentColor: color),
        ),
      ),
      if (defaultTargetPlatform == TargetPlatform.linux) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Native title bar'),
          subtitle: const Text(
            'Show GTK window decorations on Linux. Applies after restart.',
          ),
          value: preferences.showNativeTitleBar,
          onChanged: (value) => backend.updatePreferences(
            preferences.copyWith(showNativeTitleBar: value),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remember window size and position'),
          value: preferences.rememberWindowState,
          onChanged: (value) => backend.updatePreferences(
            preferences.copyWith(rememberWindowState: value),
          ),
        ),
      ],
    ]);
  }

  Widget _privacy() {
    final preferences = backend.preferences;
    return _section('Privacy & presence', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send read receipts'),
        subtitle: const Text('Let rooms know which messages you have read.'),
        value: preferences.sendReadReceipts,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(sendReadReceipts: value),
        ),
      ),
      Text(
        'Show per-message receipts up to ${preferences.readReceiptMemberThreshold} members',
      ),
      Slider(
        value: preferences.readReceiptMemberThreshold.toDouble(),
        min: 2,
        max: 100,
        divisions: 98,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(readReceiptMemberThreshold: value.round()),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send typing notifications'),
        value: preferences.sendTypingNotifications,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(sendTypingNotifications: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Share online presence'),
        subtitle: const Text(
          'Turning this off reports this device as offline.',
        ),
        value: preferences.sharePresence,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(sharePresence: value),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('direct-link-previews-toggle'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Fetch link previews directly on this device'),
        subtitle: const Text(
          'Direct previews contact websites from your device and may expose '
          'your IP address and browsing metadata to those sites. This is used '
          'only when the Matrix homeserver cannot provide a preview. Playing '
          'an embedded video also contacts its public media host.',
        ),
        value: preferences.fetchDirectLinkPreviews,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(fetchDirectLinkPreviews: value),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('improve-twitter-links-toggle'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Improve X/Twitter links with FxTwitter'),
        subtitle: const Text(
          'Uses FxTwitter for previews and rewrites newly sent X/Twitter '
          'links. Disable this to preserve the original host.',
        ),
        value: preferences.improveTwitterLinks,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(improveTwitterLinks: value),
        ),
      ),
      const Divider(height: 28),
      Text('Blocked users', style: Theme.of(context).textTheme.titleMedium),
      if (backend.blockedUserIds.isEmpty)
        const Text('No blocked Matrix users.')
      else
        for (final userId in backend.blockedUserIds)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block, size: 18),
            title: SelectableText(userId),
            trailing: TextButton(
              onPressed: () => backend.setUserBlocked(userId, false),
              child: const Text('Unblock'),
            ),
          ),
    ]);
  }

  Future<void> _chooseUnifiedPushDistributor() async {
    final platform = UnifiedPushPlatform.instance;
    final userId = backend.userId;
    if (userId == null) return;
    try {
      final distributors = await platform.distributors();
      if (!mounted) return;
      if (distributors.isEmpty) {
        _showSettingMessage(
          'No configured UnifiedPush distributor was found. Install ntfy and '
          'configure it with https://push.deltie.net first.',
        );
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Choose UnifiedPush distributor'),
          children: [
            for (final distributor in distributors)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(dialogContext, distributor.packageName),
                child: Text(
                  distributor.label == distributor.packageName
                      ? distributor.label
                      : '${distributor.label}\n${distributor.packageName}',
                ),
              ),
          ],
        ),
      );
      if (selected == null) return;
      final state = await platform.selectDistributor(selected, userId);
      await _waitForUnifiedPushEndpoint(userId, initialState: state);
    } catch (exception) {
      if (mounted) _showSettingMessage('UnifiedPush setup failed: $exception');
    }
  }

  Future<void> _refreshUnifiedPushRegistration() async {
    final userId = backend.userId;
    if (userId == null) return;
    try {
      final platform = UnifiedPushPlatform.instance;
      final state = await platform.register(userId);
      await _waitForUnifiedPushEndpoint(userId, initialState: state);
    } catch (exception) {
      if (mounted) {
        _showSettingMessage('UnifiedPush refresh failed: $exception');
      }
    }
  }

  Future<void> _waitForUnifiedPushEndpoint(
    String userId, {
    UnifiedPushState? initialState,
  }) async {
    final platform = UnifiedPushPlatform.instance;
    final state = await platform.waitForEndpoint(
      userId,
      initialState: initialState,
    );
    if (state.endpoint case final endpoint?) {
      await backend.setUnifiedPushEndpoint(endpoint);
      if (mounted) {
        _reloadUnifiedPush();
        _showSettingMessage('UnifiedPush registered.');
      }
      return;
    }
    if (mounted) {
      _reloadUnifiedPush();
      _showSettingMessage(
        state.error == null
            ? 'The distributor has not returned an endpoint yet. Check its '
                  'account and connection, then refresh registration.'
            : 'The distributor rejected registration (${state.error}).',
      );
    }
  }

  Future<void> _disableUnifiedPush() async {
    final userId = backend.userId;
    if (userId == null) return;
    final platform = UnifiedPushPlatform.instance;
    final state = await platform.state(userId);
    if (state.endpoint case final endpoint?) {
      await backend.removeUnifiedPushEndpoint(endpoint);
    }
    await platform.unregister(userId);
    if (mounted) {
      _reloadUnifiedPush();
      _showSettingMessage('UnifiedPush disabled.');
    }
  }

  void _showSettingMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _devices() => _section('Devices', [
    Row(
      children: [
        const Expanded(
          child: Text(
            'Matrix sessions currently associated with this account.',
          ),
        ),
        IconButton(
          tooltip: 'Refresh devices',
          onPressed: backend.devicesLoading ? null : backend.refreshDevices,
          icon: backend.devicesLoading
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    ),
    if (!backend.devicesLoading && backend.deviceSessions.isEmpty)
      const Text('No device information is available.')
    else
      for (final device in backend.deviceSessions)
        Card(
          child: ListTile(
            leading: Icon(
              device.current ? Icons.computer : Icons.devices_other,
            ),
            title: Text(
              '${device.displayName}${device.current ? ' (this device)' : ''}',
            ),
            subtitle: Text(
              [
                device.id,
                if (device.lastSeenAt != null)
                  'Last seen ${_formatDeviceTime(device.lastSeenAt!)}',
                if (device.lastSeenIp != null) device.lastSeenIp!,
              ].join(' · '),
            ),
            trailing: device.current
                ? null
                : IconButton(
                    tooltip: 'Remove device',
                    onPressed: () => _confirmRemoveDevice(device),
                    icon: const Icon(Icons.logout),
                  ),
          ),
        ),
    const Text(
      'Session removal requires interactive Matrix authentication and will be '
      'added with the permission-aware management pass in v0.5.',
    ),
  ]);

  Widget _accessibility() {
    final preferences = backend.preferences;
    return _section('Accessibility', [
      Text('Text size — ${(preferences.fontScale * 100).round()}%'),
      Slider(
        key: const Key('font-scale-slider'),
        value: preferences.fontScale,
        min: 0.8,
        max: 1.4,
        divisions: 6,
        label: '${(preferences.fontScale * 100).round()}%',
        onChanged: (value) =>
            backend.updatePreferences(preferences.copyWith(fontScale: value)),
      ),
      const Text('Changes text size without enlarging the rest of the UI.'),
      const SizedBox(height: 12),
      SwitchListTile(
        key: const Key('use-24-hour-time'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Use 24-hour timestamps'),
        subtitle: const Text('Turn off to show chat timestamps with AM/PM.'),
        value: preferences.use24HourTime,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(use24HourTime: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reduce motion'),
        subtitle: const Text('Avoid non-essential interface animation.'),
        value: preferences.reducedMotion,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(reducedMotion: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Higher contrast'),
        subtitle: const Text('Strengthen panel borders and text contrast.'),
        value: preferences.highContrast,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(highContrast: value),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'All primary workflows remain keyboard reachable and use visible focus '
        'indicators. Deltiecord does not communicate status by colour alone.',
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      ...children.map(
        (child) =>
            Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ),
    ],
  );

  Widget _value(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 170, child: Text(label)),
      Expanded(child: SelectableText(value)),
    ],
  );

  Widget _shortcut(String action, String keys) => _value(action, keys);

  Future<String?> _askForPassword(String title, String warning) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) =>
          _PasswordPromptDialog(title: title, warning: warning),
    );
    return password?.isNotEmpty == true ? password : null;
  }

  Future<void> _confirmRemoveDevice(DeviceSessionSummary device) async {
    final password = await _askForPassword(
      'Remove ${device.displayName}?',
      'This signs that device out and removes its Matrix device keys. '
          'Encrypted history stored only on that device may become unavailable.',
    );
    if (password != null) {
      await _runSettingAction(() => backend.removeDevice(device.id, password));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final password = await _askForPassword(
      'Permanently delete account?',
      'This deactivates ${backend.userId}, signs out all devices, and requests '
          'server-side data erasure. This cannot be undone.',
    );
    if (password != null) {
      await _runSettingAction(() => backend.deleteAccount(password));
    }
  }

  Future<void> _runSettingAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(safeErrorMessage(exception))));
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingForUpdates = true);
    final checker = UpdateChecker();
    try {
      final result = await checker.check(
        currentVersion: deltiecordVersion,
        currentBuild: int.parse(deltiecordBuildNumber),
      );
      if (!mounted) return;
      final message = result.updateAvailable
          ? 'Deltiecord v${result.version} build ${result.build} is available.'
          : 'Deltiecord is up to date.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: result.updateAvailable
              ? SnackBarAction(
                  label: 'Downloads',
                  onPressed: () => launchUrl(
                    Uri.parse(deltiecordReleasesPage),
                    mode: LaunchMode.externalApplication,
                  ),
                )
              : null,
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(safeErrorMessage(exception))));
    } finally {
      checker.close();
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({required this.title, required this.warning});

  final String title;
  final String warning;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.warning),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Matrix account password',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Confirm'),
      ),
    ],
  );
}

IconData _iconFor(_SettingsPage page) => switch (page) {
  _SettingsPage.account => Icons.person_outline,
  _SettingsPage.devices => Icons.devices_outlined,
  _SettingsPage.encryption => Icons.shield_outlined,
  _SettingsPage.audioVideo => Icons.headset_mic_outlined,
  _SettingsPage.notifications => Icons.notifications_outlined,
  _SettingsPage.privacy => Icons.visibility_outlined,
  _SettingsPage.appearance => Icons.palette_outlined,
  _SettingsPage.accessibility => Icons.accessibility_new,
  _SettingsPage.storage => Icons.storage_outlined,
  _SettingsPage.shortcuts => Icons.keyboard_outlined,
  _SettingsPage.advanced => Icons.terminal,
  _SettingsPage.about => Icons.info_outline,
};

String _labelFor(_SettingsPage page) => switch (page) {
  _SettingsPage.account => 'Account',
  _SettingsPage.devices => 'Devices',
  _SettingsPage.encryption => 'Encryption',
  _SettingsPage.audioVideo => 'Audio & video',
  _SettingsPage.notifications => 'Notifications',
  _SettingsPage.privacy => 'Privacy',
  _SettingsPage.appearance => 'Appearance',
  _SettingsPage.accessibility => 'Accessibility',
  _SettingsPage.storage => 'Storage',
  _SettingsPage.shortcuts => 'Shortcuts',
  _SettingsPage.advanced => 'Advanced',
  _SettingsPage.about => 'About',
};

String _encryptionLabel(EncryptionSetupStatus status) => switch (status) {
  EncryptionSetupStatus.ready => 'Protected',
  EncryptionSetupStatus.loading => 'Checking…',
  EncryptionSetupStatus.needsRecovery => 'Recovery required',
  EncryptionSetupStatus.needsRepair => 'Needs repair',
  EncryptionSetupStatus.needsSetup => 'Not configured',
  EncryptionSetupStatus.unavailable => 'Unavailable',
  EncryptionSetupStatus.error => 'Error',
};

String _formatDeviceTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
}
