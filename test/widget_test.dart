import 'dart:async';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/backend/chat_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login controls when signed out', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Deltiecord'), findsOneWidget);
    expect(find.text('Homeserver'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('new installs defer emoji shaping to the platform font stack', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.textTheme.bodyMedium!.fontFamilyFallback, isNull);
  });

  testWidgets('shows joined rooms and opens a timeline', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello there',
          unreadCount: 2,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('general'), findsOneWidget);
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(backend.selectedRoom?.id, '!general:example.org');
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('opens the v0.4 settings workspace', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    expect(find.text('Advanced', skipOffstage: false), findsOneWidget);
    expect(find.text('@deltie:example.org'), findsWidgets);
  });

  testWidgets('appearance exposes themes, scaling, density, and exact colour', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('OLED'), findsOneWidget);
    expect(find.byKey(const Key('interface-scale-slider')), findsOneWidget);
    expect(find.byKey(const Key('compactness-slider')), findsOneWidget);
    final colourWheelButton = find.textContaining('Open colour wheel');
    await tester.ensureVisible(colourWheelButton);
    await tester.pumpAndSettle();
    await tester.tap(colourWheelButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accent-colour-wheel')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('accent-hex-field')),
      '#123456',
    );
    await tester.pump();
    expect(backend.preferences.accentColor, 0xff123456);
  });

  testWidgets('direct link previews require an explicit privacy opt-in', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(backend.preferences.fetchDirectLinkPreviews, isFalse);
    expect(find.textContaining('may expose your IP address'), findsOneWidget);
    await tester.tap(find.byKey(const Key('direct-link-previews-toggle')));
    await tester.pump();
    expect(backend.preferences.fetchDirectLinkPreviews, isTrue);
  });

  testWidgets('profile editor updates its preview before saving', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@deltie:example.org',
        displayName: 'Deltie',
        bio: 'Existing biography',
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Preview Name',
    );
    await tester.pump();

    expect(find.text('Preview Name'), findsWidgets);
    expect(find.text('Edit profile — live preview'), findsOneWidget);
    expect(find.text('Profile gradient — top'), findsOneWidget);
    expect(find.text('Profile gradient — bottom'), findsOneWidget);
  });

  testWidgets('shows an explicit offline state', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentConnectionStatus = ConnectionStatus.offline;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('opens settings with the control-comma shortcut', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!shortcut:example.org',
          name: 'shortcut-room',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('shortcut-room'));
    await tester.pump();
    await tester.tap(find.byType(QuillEditor));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Homeserver'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('shows SDK-independent Matrix device sessions', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..deviceList = const [
        DeviceSessionSummary(
          id: 'TESTDEVICE',
          displayName: 'Deltiecord Desktop',
          current: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices'));
    await tester.pump();

    expect(find.text('Deltiecord Desktop (this device)'), findsOneWidget);
    expect(find.textContaining('TESTDEVICE'), findsOneWidget);
  });

  testWidgets('removes another device only after password confirmation', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..deviceList = const [
        DeviceSessionSummary(
          id: 'OLDDEVICE',
          displayName: 'Old laptop',
          current: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove device'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(backend.removedDeviceId, 'OLDDEVICE');
    expect(backend.removalPassword, 'secret');
  });

  testWidgets('selects a Matrix Space from the server bar', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie Club'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.byTooltip('Deltie Club'), findsOneWidget);
    await tester.tap(find.byTooltip('Deltie Club'));
    await tester.pump();

    expect(backend.selectedSpaceId, '!space:example.org');
    expect(find.text('Deltie Club'), findsOneWidget);
  });

  testWidgets('right clicking a Space exposes its management actions', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(
      find.byKey(const ValueKey('space-button-Deltie')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Mute Space'), findsOneWidget);
    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.text('Space settings'), findsOneWidget);
    expect(find.text('Leave Space'), findsOneWidget);
    await tester.tap(find.text('Mute Space'));
    await tester.pumpAndSettle();
    expect(backend.mutedRooms, [('!space:example.org', true)]);
  });

  testWidgets('Space settings expose identity, notifications, and layout', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentPreferences = const AppPreferences(
        enableChannelDragAndDrop: true,
      )
      ..spaceList = const [
        SpaceSummary(
          id: '!space:example.org',
          name: 'Deltie',
          topic: 'A test Space',
        ),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!text:example.org',
          name: 'General',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!voice:example.org',
          name: 'Voice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(id: 'general', name: 'General', roomIds: []),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(
      find.byKey(const ValueKey('space-button-Deltie')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Space settings'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('space-settings-avatar-preview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('space-settings-name')), findsOneWidget);
    expect(find.byKey(const Key('space-settings-topic')), findsOneWidget);
    expect(find.byKey(const Key('space-settings-muted')), findsOneWidget);
    expect(
      find.byKey(const Key('space-settings-layout-slider')),
      findsOneWidget,
    );
    expect(
      find.text('1 text rooms  •  1 voice rooms  •  1 categories'),
      findsOneWidget,
    );
    expect(find.text('Copy Space link'), findsOneWidget);
  });

  testWidgets('Space categories collapse and expose accessible ordering', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentPreferences = const AppPreferences(
        enableChannelDragAndDrop: true,
      )
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!two:example.org',
          name: 'two',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'work',
          name: 'WORK',
          roomIds: ['!one:example.org', '!two:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('WORK'), findsOneWidget);
    await tester.tap(find.text('WORK'));
    await tester.pump();
    expect(backend.categoryCollapseChanges, [('work', true)]);

    await tester.tap(find.text('WORK'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);
  });

  testWidgets('channel layout controls follow the configured permission', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..mayArrangeChannels = false
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'work',
          name: 'WORK',
          roomIds: ['!one:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      find.byKey(const ValueKey('room-drag-grip-!one:example.org')),
      findsNothing,
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await tester.tap(find.text('WORK'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Rename category'), findsNothing);
  });

  testWidgets('channel drag handles are opt-in even for administrators', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..mayArrangeChannels = true
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      find.byKey(const ValueKey('room-drag-grip-!one:example.org')),
      findsNothing,
    );
  });

  testWidgets('rooms can be dragged into a Space category', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentPreferences = const AppPreferences(
        enableChannelDragAndDrop: true,
      )
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!loose:example.org',
          name: 'loose',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!work:example.org',
          name: 'work room',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'work',
          name: 'WORK',
          roomIds: ['!work:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final looseGrip = find.byKey(
      const ValueKey('room-drag-grip-!loose:example.org'),
    );
    final roomGripTransform = tester.widget<Transform>(
      find.descendant(of: looseGrip, matching: find.byType(Transform)).first,
    );
    expect(roomGripTransform.transform.getTranslation().y, 1);
    final categoryGrip = find.byKey(const ValueKey('category-drag-grip-work'));
    final categoryGripTransform = tester.widget<Transform>(
      find.descendant(of: categoryGrip, matching: find.byType(Transform)).first,
    );
    expect(categoryGripTransform.transform.getTranslation().y, 1);
    await tester.dragFrom(
      tester.getCenter(looseGrip),
      tester.getCenter(find.text('WORK')) - tester.getCenter(looseGrip),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(backend.roomMoves, contains(('!loose:example.org', 'work', null)));
  });

  testWidgets('opens voice rooms without exposing a message composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('VOICE ROOMS'), findsOneWidget);
    expect(find.text('Nobody is connected'), findsOneWidget);
    expect(find.byType(QuillEditor), findsNothing);
  });

  testWidgets('exposes connected MatrixRTC media controls', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentVoiceStatus = VoiceConnectionStatus.connected
      ..currentActiveVoiceId = '!voice:example.org'
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('Mute'), findsNothing);
    expect(find.byTooltip('Voice options'), findsOneWidget);
    await tester.tap(find.byTooltip('Voice options'));
    await tester.pumpAndSettle();
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Deafen'), findsOneWidget);
    expect(find.text('Camera on'), findsOneWidget);
    expect(find.text('Share screen'), findsOneWidget);
    expect(find.text('Share desktop audio'), findsOneWidget);
    await tester.tap(find.text('Deafen'));
    await tester.pump();
    expect(backend.deafened, isTrue);
  });

  testWidgets('shows RTC reconnect and a camera-off participant fallback', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentVoiceStatus = VoiceConnectionStatus.reconnecting
      ..currentActiveVoiceId = '!voice:example.org'
      ..cameraEnabled = true
      ..roomList = const [
        RoomSummary(
          id: '!voice:example.org',
          name: 'Lounge',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
          voiceParticipants: [
            VoiceParticipantSummary(
              userId: '@alice:example.org',
              displayName: 'Alice',
            ),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Lounge'));
    await tester.pump();

    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Alice · camera off'), findsOneWidget);
  });

  testWidgets('prompts an unverified device for recovery', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..security = const EncryptionSetupState(
        status: EncryptionSetupStatus.needsRecovery,
        keyBackupEnabled: true,
        crossSigningEnabled: true,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Fix encryption'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encryption'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open encryption & recovery'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AlertDialog, 'Recovery required'),
      findsOneWidget,
    );
    expect(find.text('Recover & verify'), findsOneWidget);
    expect(find.text('Encrypted key backup'), findsWidgets);
  });

  testWidgets('requires saving a newly generated recovery key', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..security = const EncryptionSetupState(
        status: EncryptionSetupStatus.needsSetup,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encryption'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open encryption & recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up encryption'));
    await tester.pumpAndSettle();

    expect(find.text('recovery-key'), findsOneWidget);
    expect(
      find.text('I saved this recovery key somewhere safe'),
      findsOneWidget,
    );
    final done = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Done'),
    );
    expect(done.onPressed, isNull);
  });

  testWidgets('renders replies as metadata above the message body', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Reply',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$reply',
          sender: 'Alice',
          body: 'My actual reply',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$reply',
            sender: 'Bob',
            body: 'Original message',
          ),
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(find.text('Original message'), findsOneWidget);
    expect(find.text('My actual reply'), findsOneWidget);
    expect(find.textContaining('> <'), findsNothing);

    await _revealMessageActions(tester, find.text('My actual reply'));
    tester
        .widget<IconButton>(find.byKey(const Key('message-action-reply')))
        .onPressed!();
    await tester.pump();
    expect(find.text('Replying to Alice'), findsOneWidget);
    await _enterComposer(tester, 'A second reply');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(backend.lastReplyToMessageId, r'$reply');
  });

  testWidgets('repeated reply jumps retain their event targets and blink', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!replies:example.org',
          name: 'replies',
          lastMessage: 'second response',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$response-two',
          sender: 'Bob',
          body: 'second response',
          timestamp: DateTime(2026, 8, 16, 12, 3),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$target-two',
            sender: 'Alice',
            body: 'second target body',
          ),
        ),
        ChatMessage(
          id: r'$target-two',
          sender: 'Alice',
          body: 'second target body',
          timestamp: DateTime(2026, 8, 16, 12, 2),
          pending: false,
        ),
        ChatMessage(
          id: r'$response-one',
          sender: 'Bob',
          body: 'first response',
          timestamp: DateTime(2026, 8, 16, 12, 1),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$target-one',
            sender: 'Alice',
            body: 'first target body',
          ),
        ),
        ChatMessage(
          id: r'$target-one',
          sender: 'Alice',
          body: 'first target body',
          timestamp: DateTime(2026, 8, 16, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('replies'));
    await tester.pump();

    await tester.tap(find.byKey(const Key(r'reply-preview-$response-one')));
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();
    var highlighted = tester.widget<AnimatedContainer>(
      find.byKey(const Key(r'message-row-$target-one')),
    );
    expect((highlighted.decoration as BoxDecoration).color, isNotNull);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key(r'reply-preview-$response-two')));
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();
    highlighted = tester.widget<AnimatedContainer>(
      find.byKey(const Key(r'message-row-$target-two')),
    );
    expect((highlighted.decoration as BoxDecoration).color, isNotNull);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('edits, deletes, and reacts through message actions', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Original',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$own',
          sender: 'Deltie',
          body: 'Original',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
          own: true,
          canRedact: true,
          reactions: const [
            ReactionSummary(key: '👍', count: 2, reactedByMe: true),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    await tester.tap(find.text('👍 2'));
    expect(backend.toggledReactions, [(r'$own', '👍')]);

    final hoverOnly = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hoverOnly.addPointer();
    await hoverOnly.moveTo(tester.getCenter(find.text('Original').last));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byTooltip('Reply'), findsNothing);
    await hoverOnly.removePointer();

    await _revealMessageActions(tester, find.text('Original').last);
    expect(find.byTooltip('Reply'), findsOneWidget);
    expect(find.byTooltip('Copy text'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byTooltip('Reply'), findsNothing);

    await _revealMessageActions(tester, find.text('Original').last);
    expect(find.byTooltip('Reply'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byTooltip('Reply'), findsNothing);

    await _revealMessageActions(tester, find.text('Original').last);
    tester
        .widget<IconButton>(find.byKey(const Key('message-action-react')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Emoji'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'tada');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emoji-picker-result-🎉')));
    await tester.pumpAndSettle();
    expect(backend.toggledReactions, [(r'$own', '👍'), (r'$own', '🎉')]);

    await _revealMessageActions(tester, find.text('Original').last);
    tester
        .widget<IconButton>(find.byKey(const Key('message-action-edit')))
        .onPressed!();
    await tester.pump();
    expect(find.text('Editing message'), findsOneWidget);
    await _enterComposer(tester, 'Changed');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(backend.lastEditMessageId, r'$own');

    await _revealMessageActions(tester, find.text('Original').last);
    tester
        .widget<IconButton>(find.byKey(const Key('message-action-delete')))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(backend.redactedMessageIds, [r'$own']);
  });

  testWidgets('loads older history from the timeline control', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Older messages exist',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$message',
          sender: 'Alice',
          body: 'Newest message',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await tester.tap(find.text('Load older messages'));

    expect(backend.historyRequests, 1);
  });

  testWidgets('history insertion preserves the visible event offset', (
    tester,
  ) async {
    late FakeBackend backend;
    final current = List.generate(
      44,
      (index) => ChatMessage(
        id: '\$current-$index',
        sender: 'Alice',
        body: 'Current message $index',
        timestamp: DateTime(2026, 8, 16, 12).subtract(Duration(minutes: index)),
        pending: false,
      ),
    );
    backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!anchor:example.org',
          name: 'anchor',
          lastMessage: 'Current message 0',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = current;
    backend.historyLoader = () async {
      backend.messageList = [
        ...current.skip(6),
        ...List.generate(
          14,
          (index) => ChatMessage(
            id: '\$older-$index',
            sender: 'Bob',
            body: 'Older message $index with a variable height\nsecond line',
            timestamp: DateTime(
              2026,
              8,
              16,
              11,
            ).subtract(Duration(minutes: index)),
            pending: false,
          ),
        ),
      ];
      backend.moreHistory = false;
      backend.notifyListeners();
    };

    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('anchor'));
    await tester.pump();
    final timelineScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('message-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    timelineScrollable.position.jumpTo(
      timelineScrollable.position.maxScrollExtent,
    );
    await tester.pump();
    final anchor = find.text('Current message 35');
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor).dy;

    tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Load older messages'),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
    expect(backend.lastHistoryAnchor, isNotNull);
  });

  testWidgets('delayed preview hydration preserves the visible event offset', (
    tester,
  ) async {
    final messages = List.generate(
      48,
      (index) => ChatMessage(
        id: '\$preview-$index',
        sender: 'Alice',
        body: 'Preview message $index',
        timestamp: DateTime(2026, 8, 16, 12).subtract(Duration(minutes: index)),
        pending: false,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!preview-anchor:example.org',
          name: 'preview anchor',
          lastMessage: 'Preview message 0',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = messages;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('preview anchor'));
    await tester.pump();
    final timeline = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('message-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    timeline.position.jumpTo(timeline.position.maxScrollExtent * 0.72);
    await tester.pump();
    final anchor = find.textContaining('Preview message').first;
    final anchorText = tester.widget<Text>(anchor).data!;
    final before = tester.getTopLeft(find.text(anchorText)).dy;

    backend.messageList = [
      for (final message in messages)
        if (message.id == r'$preview-20')
          ChatMessage(
            id: message.id,
            sender: message.sender,
            body: message.body,
            timestamp: message.timestamp,
            pending: false,
            linkPreview: LinkPreview(
              url: Uri.parse('https://example.org/article'),
              title: 'Hydrated preview title',
              description: 'Metadata arrived after the text timeline.',
              siteName: 'example.org',
              width: 640,
              height: 360,
            ),
          )
        else
          message,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(find.text(anchorText)).dy, closeTo(before, 1));
  });

  testWidgets('live messages keep a present timeline pinned to the bottom', (
    tester,
  ) async {
    final initialMessages = List.generate(
      30,
      (index) => ChatMessage(
        id: '\$live-$index',
        sender: index.isEven ? 'Alice' : 'Bob',
        body: 'Live message $index',
        timestamp: DateTime(2026, 8, 16, 12).subtract(Duration(minutes: index)),
        pending: false,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!live:example.org',
          name: 'live',
          lastMessage: 'Live message 0',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = initialMessages;

    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('live'));
    await tester.pumpAndSettle();
    final timeline = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('message-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(timeline.position.pixels, 0);

    backend.messageList = [
      ChatMessage(
        id: r'$live-new',
        sender: 'Alice',
        body: 'A new live message',
        timestamp: DateTime(2026, 8, 16, 12, 1),
        pending: false,
      ),
      ...initialMessages,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(timeline.position.pixels, 0);
    expect(find.text('A new live message'), findsOneWidget);

    // Homeserver acknowledgement may replace a local echo with a different
    // event ID while retaining the same visible message.
    backend.messageList = [
      ChatMessage(
        id: r'$live-accepted',
        sender: 'Alice',
        body: 'A new live message',
        timestamp: DateTime(2026, 8, 16, 12, 1),
        pending: false,
      ),
      ...initialMessages,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(timeline.position.pixels, 0);

    // Progressive reply/preview hydration can change a live row's height on a
    // later backend notification without introducing another event.
    backend.messageList = [
      ChatMessage(
        id: r'$live-accepted',
        sender: 'Alice',
        body: 'A new live message\nwith hydrated metadata',
        timestamp: DateTime(2026, 8, 16, 12, 1),
        pending: false,
      ),
      ...initialMessages,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(timeline.position.pixels, 0);
  });

  testWidgets('historical windows expose a load newer control', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreFuture = true
      ..roomList = const [
        RoomSummary(
          id: '!history:example.org',
          name: 'history',
          lastMessage: 'Historical message',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$historical',
          sender: 'Alice',
          body: 'Historical message',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('history'));
    await tester.pump();

    expect(find.text('Load newer messages'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('load-newer-messages')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('load-newer-messages')));
    await tester.pump();
    expect(backend.futureRequests, 1);
    expect(backend.lastFutureAnchor, r'$historical');
  });

  testWidgets('sends composer text and clears it after success', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'No messages yet',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    final composer = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(composer.focusNode.hasFocus, isTrue);
    await _enterComposer(tester, 'hello from Deltiecord');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(backend.sentMessages, ['hello from Deltiecord']);
    expect(find.text('hello from Deltiecord'), findsNothing);
    expect(composer.focusNode.hasFocus, isTrue);
  });

  testWidgets('typing during an in-flight send preserves the next draft', (
    tester,
  ) async {
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..sendGate = gate
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await _enterComposer(tester, 'first message');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    await _enterComposer(tester, 'next draft typed immediately');
    gate.complete();
    await tester.pumpAndSettle();

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(backend.sentMessages, ['first message']);
    expect(
      editor.controller.document.toPlainText(),
      'next draft typed immediately\n',
    );
  });

  testWidgets('an in-flight send keeps its original target room', (
    tester,
  ) async {
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..sendGate = gate
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!two:example.org',
          name: 'two',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('one'));
    await tester.pump();
    await _enterComposer(tester, 'keep this in room one');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.tap(find.text('two'));
    await tester.pump();

    expect(backend.sentMessageRoomIds, ['!one:example.org']);
    gate.complete();
    await tester.pump();
  });

  testWidgets('autocompletes Matrix user mentions into the composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..mentionList = const [
        MentionSuggestion(matrixId: '@alice:example.org', displayName: 'Alice'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await _enterComposer(tester, '@ali');

    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice').last);
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), '@alice:example.org \n');
  });

  testWidgets('autocompletes room links with a readable room name', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..mentionList = const [
        MentionSuggestion(
          matrixId: '!general:example.org',
          displayName: 'general',
          isRoom: true,
        ),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    await _enterComposer(tester, '@gen');

    expect(find.text('Room'), findsOneWidget);
    await tester.tap(find.text('general').last);
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), '#general \n');
  });

  testWidgets('renders Matrix rich text and revealable spoilers', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello secret',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$rich',
          sender: 'Alice',
          body: 'Hello secret',
          formattedBody:
              '<strong>Hello</strong> <span data-mx-spoiler>secret</span>',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    final richMessage = find.byType(MatrixHtmlText);
    final selectable = tester.widget<SelectableText>(
      find.descendant(of: richMessage, matching: find.byType(SelectableText)),
    );
    TextSpan? concealed;
    selectable.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text == 'secret') concealed = span;
      return true;
    });
    expect(concealed, isNotNull);
    expect(concealed!.style!.color, concealed!.style!.backgroundColor);
    expect(concealed!.recognizer, isA<TapGestureRecognizer>());
    (concealed!.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(
      find.descendant(
        of: richMessage,
        matching: find.textContaining('Hello secret'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('restores independent composer drafts while switching rooms', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!two:example.org',
          name: 'two',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('one'));
    await tester.pump();
    await _enterComposer(tester, 'draft one');

    await tester.tap(find.text('two'));
    await tester.pump();
    expect(
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller
          .document
          .toPlainText(),
      '\n',
    );
    await _enterComposer(tester, 'draft two');

    await tester.tap(find.text('one'));
    await tester.pump();
    expect(
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller
          .document
          .toPlainText(),
      'draft one\n',
    );
  });

  testWidgets('shows homeserver accepted and participant read states', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$newer-read',
          sender: 'Deltie',
          senderId: '@deltie:example.org',
          body: 'second message in the cluster',
          timestamp: DateTime(2026, 8, 15, 0, 1),
          pending: false,
          own: true,
          readBy: const [
            ReceiptReaderSummary(
              userId: '@alice:example.org',
              displayName: 'Alice',
            ),
          ],
        ),
        ChatMessage(
          id: r'$read',
          sender: 'Deltie',
          senderId: '@deltie:example.org',
          body: 'hello',
          timestamp: DateTime(2026, 8, 15),
          pending: false,
          own: true,
          readBy: const [
            ReceiptReaderSummary(
              userId: '@alice:example.org',
              displayName: 'Alice',
            ),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byTooltip('Read by Alice'), findsOneWidget);
  });

  testWidgets('chat timestamps default to 24-hour time and allow AM/PM', (
    tester,
  ) async {
    final today = DateTime.now();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!time:example.org',
          name: 'time',
          lastMessage: 'clock',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$time',
          sender: 'Alice',
          body: 'clock',
          timestamp: DateTime(today.year, today.month, today.day, 13, 5),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('time'));
    await tester.pump();

    expect(find.text('13:05'), findsOneWidget);
    backend.currentPreferences = backend.preferences.copyWith(
      use24HourTime: false,
    );
    backend.notifyListeners();
    await tester.pump();
    expect(find.text('1:05 PM'), findsOneWidget);
  });

  testWidgets('bottom panels align and typing indicator keeps their geometry', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentPreferences = const AppPreferences(fontScale: 1.6)
      ..roomList = const [
        RoomSummary(
          id: '!layout:example.org',
          name: 'layout',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('layout'));
    await tester.pumpAndSettle();

    final accountPanel = find.byKey(const Key('current-user-panel'));
    final composerPanel = find.byKey(const Key('message-composer-panel'));
    expect(
      tester.getTopLeft(accountPanel).dy,
      tester.getTopLeft(composerPanel).dy,
    );
    expect(
      tester.getSize(accountPanel).height,
      tester.getSize(composerPanel).height,
    );
    final accountIsland = find.byKey(const Key('current-user-island'));
    final composerIsland = find.byKey(const Key('message-composer-island'));
    expect(
      tester.getTopLeft(accountIsland).dx - tester.getTopLeft(accountPanel).dx,
      10,
    );
    expect(
      tester.getTopLeft(composerIsland).dx -
          tester.getTopLeft(composerPanel).dx,
      10,
    );
    expect(
      tester.getSize(accountIsland).height,
      tester.getSize(composerIsland).height,
    );
    final composerSurface = tester.widget<Container>(composerIsland);
    final composerBorder =
        (composerSurface.decoration! as BoxDecoration).border;
    expect(composerBorder, isNotNull);
    expect(composerBorder!.top.color, Colors.black);
    final composerTop = tester.getTopLeft(composerPanel).dy;

    backend.setTypingNames(const ['Alice']);
    await tester.pumpAndSettle();

    expect(find.text('Alice is typing…'), findsOneWidget);
    expect(tester.getTopLeft(composerPanel).dy, composerTop);
    expect(
      tester.getSize(find.byKey(const Key('typing-indicator'))).width,
      tester.getSize(find.byKey(const Key('conversation-timeline-area'))).width,
    );
  });

  testWidgets('multiline composer grows but remains within lower third', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!multiline:example.org',
          name: 'multiline',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('multiline'));
    await tester.pumpAndSettle();

    final composerPanel = find.byKey(const Key('message-composer-panel'));
    final initialHeight = tester.getSize(composerPanel).height;
    await _enterComposer(
      tester,
      List.generate(12, (index) => 'Line ${index + 1}').join('\n'),
    );
    await tester.pumpAndSettle();

    final expandedHeight = tester.getSize(composerPanel).height;
    expect(expandedHeight, greaterThan(initialHeight));
    expect(expandedHeight, lessThanOrEqualTo((900 - 56) / 3 + 0.1));
  });

  testWidgets('emoji completion overlays without resizing the composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji-overlay:example.org',
          name: 'emoji overlay',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('emoji overlay'));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('message-composer-panel'));
    final initialHeight = tester.getSize(composer).height;

    await _enterComposer(tester, ':so');
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.controller.replaceText(
      3,
      0,
      'b',
      const TextSelection.collapsed(offset: 4),
    );
    await tester.pumpAndSettle();

    expect(editor.controller.document.toPlainText(), ':sob\n');
    expect(
      find.byKey(const Key('emoji-completion-popup'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('😭', skipOffstage: false), findsOneWidget);
    final popup = find.byKey(
      const Key('emoji-completion-popup'),
      skipOffstage: false,
    );
    expect(tester.getSize(popup).width, 280);
    expect(tester.getSize(popup).height, lessThan(150));
    if (find
        .byKey(const Key('emoji-completion-result-1'))
        .evaluate()
        .isNotEmpty) {
      expect(
        tester
            .getTopLeft(find.byKey(const Key('emoji-completion-result-0')))
            .dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const Key('emoji-completion-result-1')))
              .dy,
        ),
      );
    }
    expect(tester.getSize(composer).height, initialHeight);
  });

  testWidgets('home DM rows expose presence and stronger visual hierarchy', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!alice:example.org',
          name: 'Alice',
          lastMessage: 'See you tomorrow',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
          presence: UserPresence.online,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      find.byKey(const Key('presence-!alice:example.org-online')),
      findsOneWidget,
    );
    final name = tester.widget<Text>(find.text('Alice'));
    expect(name.style?.fontSize, DeltiecordTypeScale.bigChat);
    expect(name.style?.fontWeight, FontWeight.w700);
    expect(find.text('See you tomorrow'), findsOneWidget);
  });

  testWidgets('room panel filters rooms and starts a new direct message', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!alice:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
        RoomSummary(
          id: '!garden:example.org',
          name: 'Garden club',
          lastMessage: 'plants',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(find.byTooltip('Search direct messages and groups'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('room-list-search')), 'garden');
    await tester.pump();
    expect(find.text('Garden club'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    await tester.tap(find.byTooltip('Clear room search'));
    await tester.pump();
    await tester.tap(find.byTooltip('Start chat or create room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start direct message'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-direct-message-id')),
      '@newfriend:example.org',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Message'));
    await tester.pumpAndSettle();

    expect(backend.startedDirectMessageWith, '@newfriend:example.org');
  });

  testWidgets('search close button does not reopen the room search', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(find.byTooltip('Search direct messages and groups'));
    await tester.pump();
    expect(find.byKey(const Key('room-search-popup')), findsOneWidget);
    await tester.tap(find.byTooltip('Search direct messages and groups'));
    await tester.pump();

    expect(find.byKey(const Key('room-search-popup')), findsNothing);
  });

  testWidgets('bottom user island exposes status, presence, mute, and deafen', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@deltie:example.org',
        displayName: 'Deltie',
        statusMessage: 'Building strange software',
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Building strange software'), findsOneWidget);
    expect(
      find.byKey(const Key('current-user-presence-online')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(backend.muted, isTrue);
    final mutedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.mic_off),
        matching: find.byType(IconButton),
      ),
    );
    final errorColor = Theme.of(
      tester.element(find.byIcon(Icons.mic_off)),
    ).colorScheme.error;
    expect(mutedButton.style?.foregroundColor?.resolve({}), errorColor);
    await tester.tap(find.byTooltip('Deafen'));
    await tester.pump();
    expect(backend.deafened, isTrue);
    final deafenedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.headset_off),
        matching: find.byType(IconButton),
      ),
    );
    expect(deafenedButton.style?.foregroundColor?.resolve({}), errorColor);
  });

  testWidgets('room panel width can be resized from its main-screen border', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.drag(
      find.byKey(const Key('room-panel-resize-handle')),
      const Offset(40, 0),
    );
    await tester.pump();

    expect(backend.preferences.roomPanelWidth, greaterThan(280));
  });

  testWidgets('room panel survives transient narrow window constraints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(470, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;

    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('room-panel-resize-handle')), findsOneWidget);
  });

  testWidgets('Space buttons remain square without selected side strips', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Test')];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      tester.getSize(find.byKey(const Key('space-button-Test'))),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('space-button-Create Space'))),
      const Size.square(48),
    );
  });

  testWidgets('offers jump to present after scrolling away from recent chat', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!history:example.org',
          name: 'history',
          lastMessage: 'latest',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = List.generate(
        40,
        (index) => ChatMessage(
          id: '\$history-$index',
          sender: index.isEven ? 'Alice' : 'Bob',
          senderId: index.isEven ? '@alice:example.org' : '@bob:example.org',
          body: 'Timeline message $index with enough content to fill a row.',
          timestamp: DateTime(2026, 8, 15, 0, index),
          pending: false,
        ),
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('history'));
    await tester.pumpAndSettle();

    expect(find.text('Jump to present'), findsNothing);
    await tester.drag(
      find.byKey(const Key('message-timeline')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jump to present'), findsOneWidget);
    await tester.tap(find.text('Jump to present'));
    await tester.pumpAndSettle();
    expect(backend.jumpPresentRequests, 1);
    expect(find.text('Jump to present'), findsNothing);
  });

  testWidgets('opens an anchored card then full profile from a sender', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!profile:example.org',
          name: 'profiles',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..testProfile = const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
        presence: UserPresence.online,
        bio: 'Matrix enthusiast',
        pronouns: 'she/her',
        timezone: 'Europe/Amsterdam',
        profileColor: 0xffaa2233,
        profileColorSecondary: 0xff2233aa,
      )
      ..messageList = [
        ChatMessage(
          id: r'$profile',
          sender: 'Alice',
          senderId: '@alice:example.org',
          body: 'hello',
          timestamp: DateTime(2026, 8, 15),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('profiles'));
    await tester.pump();
    final senderName = find.text('Alice').last;
    final senderTapPosition = tester.getCenter(senderName);
    await tester.tap(senderName);
    await tester.pumpAndSettle();

    expect(find.text('@alice:example.org'), findsOneWidget);
    expect(find.text('she/her'), findsOneWidget);
    expect(find.text('Matrix enthusiast'), findsOneWidget);
    final compactPopup = find.byKey(const Key('compact-profile-popup'));
    expect(compactPopup, findsOneWidget);
    final compactGradient = tester.widget<DecoratedBox>(
      find.byKey(const Key('compact-profile-gradient')),
    );
    expect((compactGradient.decoration as BoxDecoration).gradient, isNotNull);
    expect(
      tester.getTopLeft(compactPopup).dx,
      greaterThan(senderTapPosition.dx),
    );
    expect(find.byKey(const Key('profile-side-panel')), findsNothing);
    await tester.tap(find.text('View full profile'));
    await tester.pumpAndSettle();
    expect(backend.profileRefreshRequests, 1);
    expect(find.text('Online'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(
      find.textContaining('Europe/Amsterdam', skipOffstage: false),
      findsNothing,
    );
    final dialog = tester.widget<Dialog>(
      find.byKey(const Key('profile-side-panel')),
    );
    expect(dialog.alignment, Alignment.centerRight);
    expect(dialog.backgroundColor, Colors.transparent);
    final profileCard = tester.widget<Container>(
      find.byKey(const Key('profile-card')),
    );
    expect((profileCard.decoration! as BoxDecoration).gradient, isNotNull);
    await tester.tap(find.byKey(const Key('profile-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-side-panel')), findsNothing);
  });

  testWidgets('profile waits for extension data without generic-state flash', (
    tester,
  ) async {
    final profile = Completer<UserProfileSummary>();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..profileCompleter = profile
      ..roomList = const [
        RoomSummary(
          id: '!profile:example.org',
          name: 'profiles',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$profile-loading',
          sender: 'Alice',
          senderId: '@alice:example.org',
          body: 'hello',
          timestamp: DateTime(2026, 8, 16),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('profiles'));
    await tester.pump();
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(find.byKey(const Key('profile-loading-state')), findsOneWidget);
    expect(find.text('@alice:example.org'), findsNothing);
    profile.complete(
      const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
        bio: 'Loaded profile',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loaded profile'), findsOneWidget);
  });

  testWidgets('own profile card opens above the lower user panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final userIsland = find.byKey(const Key('current-user-island'));
    await tester.tap(userIsland);
    await tester.pumpAndSettle();

    final popup = find.byKey(const Key('compact-profile-popup'));
    expect(popup, findsOneWidget);
    expect(
      tester.getBottomLeft(popup).dy,
      lessThan(tester.getTopLeft(userIsland).dy),
    );
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Block'), findsNothing);
  });

  testWidgets('shows the direct recipient profile beside a wide conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!direct:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
          presence: UserPresence.online,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(userId: '@deltie:example.org', displayName: 'Deltie'),
        RoomMemberSummary(
          userId: '@alice:example.org',
          displayName: 'Alice',
          presence: UserPresence.online,
        ),
      ]
      ..testProfile = const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
        presence: UserPresence.online,
        bio: 'Matrix enthusiast',
        statusMessage: 'Building things',
        timezone: 'Europe/Amsterdam',
        profileColor: 0xffaa2233,
        profileColorSecondary: 0xff2233aa,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
    expect(find.text('@alice:example.org'), findsOneWidget);
    expect(find.text('Matrix enthusiast'), findsOneWidget);
    expect(find.text('View full profile'), findsOneWidget);
    expect(find.textContaining('UTC+02'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-presence-online')),
      findsOneWidget,
    );
    final recipientGradient = tester.widget<DecoratedBox>(
      find.byKey(const Key('recipient-profile-gradient')),
    );
    final recipientDecoration = recipientGradient.decoration as BoxDecoration;
    expect(recipientDecoration.gradient, isNotNull);
    expect(recipientDecoration.border, isNotNull);
    final panelRect = tester.getRect(
      find.byKey(const Key('recipient-profile-gradient')),
    );
    final aboutRect = tester.getRect(
      find.byKey(const Key('recipient-about-island')),
    );
    expect(
      aboutRect.left - panelRect.left,
      closeTo(panelRect.right - aboutRect.right, 0.5),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('view-full-profile-island'))).dy,
      tester.getTopLeft(find.byKey(const Key('message-composer-island'))).dy,
    );

    backend.testProfile = const UserProfileSummary(
      userId: '@alice:example.org',
      displayName: 'Alice',
      presence: UserPresence.away,
      statusMessage: 'Freshly hydrated',
    );
    backend.testProfileRevision++;
    backend.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Freshly hydrated'), findsOneWidget);
  });

  testWidgets('in-chat sender opens a popover without replacing recipient', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!direct-popover:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(userId: '@deltie:example.org', displayName: 'Deltie'),
        RoomMemberSummary(userId: '@alice:example.org', displayName: 'Alice'),
      ]
      ..testProfile = const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
      )
      ..messageList = [
        ChatMessage(
          id: r'$direct-profile-popover',
          sender: 'Alice',
          senderId: '@alice:example.org',
          body: 'hello from the timeline',
          timestamp: DateTime(2026, 8, 16),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey(r'message-sender-$direct-profile-popover')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-profile-popup')), findsOneWidget);
    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
  });

  testWidgets('server rooms show a collapsible member side panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'General',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(
          userId: '@admin:example.org',
          displayName: 'Admin',
          powerLevel: 100,
        ),
        RoomMemberSummary(userId: '@alice:example.org', displayName: 'Alice'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    expect(find.text('Members — 2'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
    await tester.tap(find.byTooltip('Members'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    final resizeHandle = find.byKey(const Key('side-panel-resize-handle'));
    final resizeTopLeft = tester.getTopLeft(resizeHandle);
    await tester.dragFrom(
      resizeTopLeft + const Offset(2, 100),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();
    expect(backend.preferences.sidePanelWidth, greaterThan(310));
    await tester.tap(find.byKey(const Key('side-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('group chats show their members in the right side panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!group:example.org',
          name: 'Friends',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(userId: '@deltie:example.org', displayName: 'Deltie'),
        RoomMemberSummary(userId: '@alice:example.org', displayName: 'Alice'),
        RoomMemberSummary(userId: '@bob:example.org', displayName: 'Bob'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-profile-panel')), findsNothing);
    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    expect(find.text('Members — 3'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('right clicking a DM exposes edit and leave actions', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!direct:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await _revealMessageActions(tester, find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Edit DM name'), findsOneWidget);
    expect(find.text('Copy room link'), findsOneWidget);
    expect(find.text('Leave room'), findsOneWidget);
    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();

    expect(backend.leftRoomId, '!direct:example.org');
  });

  testWidgets('converts a closed local emoji alias in the composer', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji:example.org',
          name: 'emoji',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('emoji'));
    await tester.pump();
    await _enterComposer(tester, ':sob:');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller
          .document
          .toPlainText(),
      '😭\n',
    );
  });

  testWidgets('Android Home shows the Space rail and DM-only navigation', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')]
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 1,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await _pumpMobile(tester, backend);

    expect(find.byKey(const ValueKey('mobile-space-rail')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-user-island')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-navigation-bottom-scrim')),
      findsOneWidget,
    );
  });

  testWidgets('Android exposes older history even before a row is mapped', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!empty-page:test',
          name: 'Sparse history',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Sparse history'));
    await tester.pumpAndSettle();

    expect(find.text('Load older messages'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    final before = backend.historyRequests;
    await tester.tap(find.text('Load older messages'));
    await tester.pump();
    expect(backend.historyRequests, before + 1);
  });

  testWidgets('Android composer completes local colon emoji aliases', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji-mobile:test',
          name: 'Emoji mobile',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Emoji mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      ':sob:',
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile-composer-field')),
    );
    expect(field.controller!.text, '😭');
  });

  testWidgets('Android composer searches the complete local emoji catalogue', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!emoji-search-mobile:test',
          name: 'Emoji search mobile',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Emoji search mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      'hello :cat',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-emoji-completion-popup')),
      findsOneWidget,
    );
    expect(find.textContaining(':cat'), findsWidgets);
  });

  testWidgets('Android room opening and navigation slide preserve selection', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-timeline')), findsOneWidget);
    expect(backend.selectedRoom?.id, '!dm:test');

    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-room-list')), findsOneWidget);
    expect(backend.selectedRoom?.id, '!dm:test');
  });

  testWidgets('Android header alone opens details and Back dismisses it', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!room:test',
          name: 'General',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-details-panel')).hitTestable(),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('mobile-open-details')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-details-panel')).hitTestable(),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-details-panel')).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('Android sender opens a large dismissible profile sheet', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@alice:test',
        displayName: 'Alice Profile',
        bio: 'About Alice',
      )
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$event',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'hello',
          timestamp: DateTime(2026),
          pending: false,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey(r'swipe-$event')),
        matching: find.text('Alice'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alice Profile'), findsOneWidget);
    expect(find.text('About Alice'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('About Alice'), findsNothing);
  });

  testWidgets('Android message swipe replies and long press exposes actions', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$event',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'swipe this',
          timestamp: DateTime(2026),
          pending: false,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey(r'swipe-$event')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replying to Alice'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey(r'swipe-$event')));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsWidgets);
    expect(find.text('React'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    await tester.tap(find.text('Copy text'));
    await tester.pumpAndSettle();
    expect(copiedText, 'swipe this');
  });

  testWidgets('Android timeline groups messages and labels calendar days', (
    tester,
  ) async {
    final now = DateTime.now();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dates:test',
          name: 'Dates',
          lastMessage: 'Today two',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$today-two',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'Today two',
          timestamp: now,
          pending: false,
        ),
        ChatMessage(
          id: r'$today-one',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'Today one',
          timestamp: now.subtract(const Duration(minutes: 1)),
          pending: false,
        ),
        ChatMessage(
          id: r'$yesterday',
          sender: 'Bob',
          senderId: '@bob:test',
          body: 'Yesterday message',
          timestamp: now.subtract(const Duration(days: 1)),
          pending: false,
        ),
      ];

    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Dates'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('Android drafts survive room navigation', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!a:test',
          name: 'Alice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
        RoomSummary(
          id: '!b:test',
          name: 'Bob',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      'room A draft',
    );
    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('room A draft'), findsOneWidget);
  });

  testWidgets('Android keeps an RTC island while browsing another room', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentActiveVoiceId = '!voice:test'
      ..currentVoiceStatus = VoiceConnectionStatus.connected
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
        RoomSummary(
          id: '!voice:test',
          name: 'Voice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ];
    await _pumpMobile(tester, backend);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-call-island')), findsOneWidget);
  });
}

Future<void> _pumpMobile(WidgetTester tester, FakeBackend backend) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterComposer(WidgetTester tester, String text) async {
  final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
  editor.controller.document = Document()..insert(0, text);
  editor.controller.updateSelection(
    TextSelection.collapsed(offset: text.length),
    ChangeSource.local,
  );
  await tester.pump();
}

Future<void> _revealMessageActions(WidgetTester tester, Finder message) async {
  final mouse = await tester.createGesture(
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await mouse.addPointer();
  final position = tester.getCenter(message);
  await mouse.moveTo(position);
  await mouse.down(position);
  await mouse.up();
  await tester.pump();
  await mouse.moveTo(Offset.zero);
  await tester.pump();
  await mouse.removePointer();
}

class FakeBackend extends ChatBackend {
  @override
  List<ChannelCategorySummary> get selectedSpaceCategories => categoryList;

  @override
  Future<void> createChannelCategory(String name) async {}

  @override
  Future<void> renameChannelCategory(String categoryId, String name) async {}

  @override
  Future<void> deleteChannelCategory(String categoryId) async {}

  @override
  Future<void> reorderChannelCategory(String categoryId, int newIndex) async {}

  @override
  Future<void> setChannelCategoryCollapsed(
    String categoryId,
    bool collapsed,
  ) async => categoryCollapseChanges.add((categoryId, collapsed));

  @override
  bool canManageSpaceChannelLayout(String spaceId) => mayArrangeChannels;

  @override
  Future<void> moveRoomInSpace(
    String roomId, {
    String? categoryId,
    String? beforeRoomId,
  }) async => roomMoves.add((roomId, categoryId, beforeRoomId));

  SessionStatus currentStatus = SessionStatus.starting;
  ConnectionStatus currentConnectionStatus = ConnectionStatus.online;
  List<RoomSummary> roomList = const [];
  RoomSummary? currentRoom;
  List<SpaceSummary> spaceList = const [];
  List<ChannelCategorySummary> categoryList = const [];
  String? currentSpaceId;
  List<ChatMessage> messageList = const [];
  List<DeviceSessionSummary> deviceList = const [];
  List<MentionSuggestion> mentionList = const [];
  List<RoomMemberSummary> memberList = const [];
  List<String> typingNames = const [];
  AppPreferences currentPreferences = const AppPreferences();
  bool moreHistory = false;
  bool moreFuture = false;
  VoiceConnectionStatus currentVoiceStatus = VoiceConnectionStatus.disconnected;
  String? currentActiveVoiceId;
  bool deafened = false;
  bool muted = false;
  bool cameraEnabled = false;
  bool mayArrangeChannels = true;
  Completer<void>? sendGate;
  int historyRequests = 0;
  int futureRequests = 0;
  String? lastHistoryAnchor;
  String? lastFutureAnchor;
  int jumpPresentRequests = 0;
  int profileRefreshRequests = 0;
  Future<void> Function()? historyLoader;
  final List<String> sentMessages = [];
  final List<String?> sentMessageRoomIds = [];
  final List<String?> sentAttachmentRoomIds = [];
  final List<String> redactedMessageIds = [];
  final List<(String, String)> toggledReactions = [];
  final List<(String, bool)> mutedRooms = [];
  final List<(String, bool)> categoryCollapseChanges = [];
  final List<(String, String?, String?)> roomMoves = [];
  final List<String> jumpedEventIds = [];
  String? lastReplyToMessageId;
  String? lastEditMessageId;
  String? removedDeviceId;
  String? removalPassword;
  String? startedDirectMessageWith;
  String? leftRoomId;
  UserProfileSummary? testProfile;
  int testProfileRevision = 0;
  Completer<UserProfileSummary>? profileCompleter;
  EncryptionSetupState security = const EncryptionSetupState(
    status: EncryptionSetupStatus.ready,
    keyBackupEnabled: true,
    crossSigningEnabled: true,
    deviceVerified: true,
  );

  @override
  String? get error => null;
  @override
  String? get deviceId => 'TESTDEVICE';
  @override
  Uri? get homeserver => Uri.parse('https://matrix.example.org');
  @override
  String? get profileDisplayName => 'Deltie';
  @override
  Uint8List? get profileAvatarBytes => null;
  @override
  UserPresence get profilePresence => UserPresence.online;
  @override
  String? get profileStatusMessage => testProfile?.statusMessage;
  @override
  int? get profileColor => testProfile?.profileColor;
  @override
  bool get profileLoading => false;
  @override
  int get profileRevision => testProfileRevision;
  @override
  AppPreferences get preferences => currentPreferences;
  @override
  EncryptionSetupState get encryptionSetup => security;
  @override
  List<ChatMessage> get messages => messageList;
  @override
  List<MentionSuggestion> get mentionSuggestions => mentionList;
  @override
  List<String> get typingUserNames => typingNames;

  void setTypingNames(List<String> names) {
    typingNames = names;
    notifyListeners();
  }

  @override
  List<RoomMemberSummary> get selectedRoomMembers => memberList;
  @override
  int get storageUsageBytes => 0;
  @override
  bool get storageLoading => false;
  @override
  List<String> get blockedUserIds => const [];
  @override
  List<ChatMessage> get pinnedMessages => const [];
  @override
  List<RoomSummary> get rooms => roomList;
  @override
  List<SpaceSummary> get spaces => spaceList;
  @override
  String? get selectedSpaceId => currentSpaceId;
  @override
  RoomSummary? get selectedRoom => currentRoom;
  @override
  bool get selectedRoomMuted => false;
  @override
  bool get notificationPreviewsEnabled => true;
  @override
  SessionStatus get status => currentStatus;
  @override
  ConnectionStatus get connectionStatus => currentConnectionStatus;
  @override
  bool get timelineLoading => false;
  @override
  bool get historyLoading => false;
  @override
  bool get canLoadMoreHistory => moreHistory;
  @override
  bool get canLoadMoreFuture => moreFuture;
  @override
  bool get atTimelinePresent => !moreFuture;
  @override
  String? get firstUnreadMessageId => null;
  @override
  VoiceConnectionStatus get voiceConnectionStatus => currentVoiceStatus;
  @override
  String? get activeVoiceRoomId => currentActiveVoiceId;
  @override
  bool get voiceMuted => muted;
  @override
  bool get voiceDeafened => deafened;
  @override
  bool get voiceCameraEnabled => cameraEnabled;
  @override
  bool get voiceScreenSharing => false;
  @override
  double get voiceInputLevel => 0;
  @override
  String? get voiceError => null;
  @override
  List<AudioInputSummary> get audioInputs => const [];
  @override
  String? get selectedAudioInputId => null;
  @override
  List<RtcDeviceSummary> get audioOutputs => const [];
  @override
  String? get selectedAudioOutputId => null;
  @override
  List<RtcDeviceSummary> get cameras => const [];
  @override
  String? get selectedCameraId => null;
  @override
  List<RtcMediaStreamSummary> get rtcMediaStreams => const [];
  @override
  List<DeviceSessionSummary> get deviceSessions => deviceList;
  @override
  bool get devicesLoading => false;
  @override
  String? get userId => '@deltie:example.org';

  @override
  Future<void> initialize() async {}
  @override
  void clearError() {}
  @override
  Future<String> createEncryptionSetup() async => 'recovery-key';
  @override
  Future<void> recoverEncryption(String recoveryKeyOrPassphrase) async {}
  @override
  Future<void> refreshEncryptionSetup() async {}
  @override
  void selectSpace(String? spaceId) {
    currentSpaceId = spaceId;
    currentRoom = null;
    notifyListeners();
  }

  @override
  Future<void> login({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> selectRoom(String roomId) async {
    currentRoom = roomList.firstWhere((room) => room.id == roomId);
    notifyListeners();
  }

  @override
  Future<void> setSelectedRoomMuted(bool muted) async {}
  @override
  Future<void> setRoomMuted(String roomId, bool muted) async {
    mutedRooms.add((roomId, muted));
  }

  @override
  Future<void> setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) async {}
  @override
  Future<void> createRoom({
    required String name,
    required RoomPresentation presentation,
    String topic = '',
    bool encrypted = true,
  }) async {}
  @override
  Future<void> createSpace({required String name, String topic = ''}) async {}
  @override
  Future<void> renameRoom(String roomId, String name) async {}
  @override
  Future<void> setRoomTopic(String roomId, String topic) async {}
  @override
  Future<void> setRoomAvatar(String roomId, Uint8List? bytes) async {}
  @override
  Future<void> leaveRoom(String roomId) async {
    leftRoomId = roomId;
    roomList = roomList.where((room) => room.id != roomId).toList();
    if (currentRoom?.id == roomId) currentRoom = null;
    notifyListeners();
  }

  @override
  Future<void> setMemberPowerLevel(String userId, int powerLevel) async {}
  @override
  Future<UserProfileSummary> getUserProfile(
    String userId, {
    bool refresh = false,
  }) async {
    if (refresh) profileRefreshRequests++;
    return profileCompleter?.future ??
        testProfile ??
        UserProfileSummary(userId: userId, displayName: userId);
  }

  @override
  Future<void> updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    String? statusMessage,
    int? profileColor,
    int? profileColorSecondary,
    Uint8List? bannerBytes,
    bool removeBanner = false,
  }) async {}
  @override
  Future<void> startDirectChat(String userId) async {
    startedDirectMessageWith = userId;
  }

  @override
  Future<List<SpaceDirectoryEntry>> searchPublicSpaces(String query) async =>
      const [];
  @override
  Future<void> joinPublicSpace(String roomId) async {}
  @override
  Future<void> setUserBlocked(String userId, bool blocked) async {}
  @override
  Future<void> refreshStorageUsage() async {}
  @override
  Future<void> clearMediaCache() async {}
  @override
  Future<void> jumpToPresent() async {
    jumpPresentRequests++;
  }

  @override
  Future<void> loadMoreFuture({String? anchorEventId}) async {
    futureRequests++;
    lastFutureAnchor = anchorEventId;
  }

  @override
  Future<List<ChatMessage>> loadPinnedMessages() async => pinnedMessages;
  @override
  Future<void> jumpToEvent(String eventId) async {
    jumpedEventIds.add(eventId);
  }

  @override
  Future<void> setNotificationPreviewsEnabled(bool enabled) async {}
  @override
  Future<void> updatePreferences(AppPreferences preferences) async {
    currentPreferences = preferences;
    notifyListeners();
  }

  @override
  Future<void> refreshAudioInputs() async {}
  @override
  Future<void> selectAudioInput(String? deviceId) async {}
  @override
  Future<void> selectAudioOutput(String? deviceId) async {}
  @override
  Future<void> selectCamera(String? deviceId) async {}
  @override
  Future<void> refreshDevices() async {}
  @override
  Future<void> refreshProfile() async {}
  @override
  Future<void> setProfileDisplayName(String displayName) async {}
  @override
  Future<void> setProfileAvatar(
    Uint8List? bytes, {
    String fileName = 'avatar.png',
    String mimeType = 'image/png',
  }) async {}
  @override
  Future<void> removeDevice(String deviceId, String password) async {
    removedDeviceId = deviceId;
    removalPassword = password;
  }

  @override
  Future<void> deleteAccount(String password) async {}
  @override
  Future<void> joinVoiceRoom(String roomId) async {}
  @override
  Future<void> leaveVoiceRoom() async {}
  @override
  Future<void> setVoiceMuted(bool value) async {
    muted = value;
    notifyListeners();
  }

  @override
  Future<void> setVoiceDeafened(bool value) async {
    deafened = value;
    notifyListeners();
  }

  @override
  Future<void> setVoiceCameraEnabled(bool enabled) async {}
  @override
  Future<void> setVoiceScreenSharing(bool enabled) async {}
  @override
  Future<void> setParticipantVolume(String userId, double volume) async {}
  @override
  Future<void> setParticipantLocallyMuted(String userId, bool muted) async {}
  @override
  Future<void> setComposerTyping(bool typing) async {}
  @override
  List<ChatMessage> searchMessages(String query) => const [];
  @override
  Future<List<ChatMessage>> searchRoomHistory(String query) async =>
      searchMessages(query);

  @override
  Future<void> loadMoreHistory({String? anchorEventId}) async {
    historyRequests++;
    lastHistoryAnchor = anchorEventId;
    await historyLoader?.call();
  }

  @override
  Future<void> sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    sentMessages.add(text);
    sentMessageRoomIds.add(roomId);
    lastReplyToMessageId = replyToMessageId;
    lastEditMessageId = editMessageId;
    await sendGate?.future;
  }

  @override
  Future<void> redactMessage(String messageId) async {
    redactedMessageIds.add(messageId);
  }

  @override
  Future<void> retryMessage(String messageId) async {}
  @override
  Future<void> cancelPendingMessage(String messageId) async {}

  @override
  Future<void> toggleReaction(String messageId, String key) async {
    toggledReactions.add((messageId, key));
  }

  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    sentAttachmentRoomIds.add(roomId);
  }

  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => Uint8List(0);

  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) async =>
      null;
  @override
  Future<String?> getAttachmentReference(String messageId) async => null;
}
