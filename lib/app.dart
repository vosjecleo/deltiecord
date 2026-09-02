import 'dart:async';
import 'dart:io';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'backend/chat_backend.dart';
import 'models/chat_models.dart';
import 'services/desktop_window_service.dart';
import 'services/font_preferences.dart';
import 'services/chat_notifications.dart';
import 'ui/chat_shell.dart';
import 'ui/deltiecord_theme.dart';
import 'ui/login_screen.dart';
import 'ui/mobile/mobile_chat_shell.dart';
import 'ui/security_center.dart';
import 'ui/startup_update_gate.dart';

class DeltiecordApp extends StatelessWidget {
  const DeltiecordApp({
    required this.backend,
    this.platformOverride,
    super.key,
  });

  final ChatBackend backend;
  final TargetPlatform? platformOverride;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final preferences = backend.preferences;
        final emojiFontFamily = normalizeEmojiFontFamily(
          preferences.emojiFontFamily,
        );
        // Flutter widget tests default to an Android target platform even when
        // executing on a desktop host. Runtime platform detection keeps the
        // established desktop test/UI contract while [platformOverride] makes
        // the dedicated mobile tree directly widget-testable.
        final mobile =
            platformOverride == TargetPlatform.android ||
            (platformOverride == null && Platform.isAndroid);
        if (backend.status == SessionStatus.signedIn && !mobile) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => DesktopWindowService.apply(preferences),
          );
        }
        final contrast = preferences.highContrast;
        final basePalette = DeltiecordPalette.forMode(preferences.themeMode);
        final accent = Color(preferences.accentColor);
        final palette = contrast
            ? basePalette.copyWith(
                divider: accent,
                hover: accent.withValues(alpha: 0.18),
              )
            : basePalette;
        final brightness = preferences.themeMode == DeltiecordThemeMode.light
            ? Brightness.light
            : Brightness.dark;
        final colorScheme = ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
          contrastLevel: contrast ? 1 : 0,
        ).copyWith(surface: palette.surface, onSurface: palette.text);
        final baseText = ThemeData(brightness: brightness).textTheme;
        final textTheme = baseText
            .copyWith(
              displayLarge: baseText.displayLarge?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              displayMedium: baseText.displayMedium?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              displaySmall: baseText.displaySmall?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              headlineLarge: baseText.headlineLarge?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              headlineMedium: baseText.headlineMedium?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              headlineSmall: baseText.headlineSmall?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              titleLarge: baseText.titleLarge?.copyWith(
                fontSize: DeltiecordTypeScale.bigUi,
              ),
              titleMedium: baseText.titleMedium?.copyWith(
                fontSize: DeltiecordTypeScale.bigChat,
              ),
              titleSmall: baseText.titleSmall?.copyWith(
                fontSize: DeltiecordTypeScale.bigChat,
              ),
              bodyLarge: baseText.bodyLarge?.copyWith(
                fontSize: DeltiecordTypeScale.normal,
              ),
              bodyMedium: baseText.bodyMedium?.copyWith(
                fontSize: DeltiecordTypeScale.normal,
              ),
              bodySmall: baseText.bodySmall?.copyWith(
                fontSize: DeltiecordTypeScale.normal,
              ),
              labelLarge: baseText.labelLarge?.copyWith(
                fontSize: DeltiecordTypeScale.normal,
              ),
              labelMedium: baseText.labelMedium?.copyWith(
                fontSize: DeltiecordTypeScale.normal,
              ),
              labelSmall: baseText.labelSmall?.copyWith(
                fontSize: DeltiecordTypeScale.normal,
              ),
            )
            .apply(
              fontFamily: preferences.fontFamily == 'System'
                  ? null
                  : preferences.fontFamily,
              // Let each platform select its native colour-emoji face. The
              // old bundled Noto font did not shape reliably in Flutter and
              // changed ordinary text metrics on some hosts.
              fontFamilyFallback: null,
            );
        return MaterialApp(
          title: 'Deltiecord',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          theme: ThemeData(
            brightness: brightness,
            colorScheme: colorScheme,
            iconTheme: IconThemeData(color: colorScheme.primary),
            badgeTheme: BadgeThemeData(
              backgroundColor: colorScheme.primary,
              textColor: deltiecordContrastingForeground(colorScheme.primary),
            ),
            scaffoldBackgroundColor: palette.background,
            canvasColor: palette.surface,
            cardColor: palette.elevated,
            cardTheme: CardThemeData(
              color: palette.elevated,
              shape: RoundedRectangleBorder(
                borderRadius: DeltiecordCorners.borderRadius,
              ),
            ),
            dividerColor: palette.divider,
            extensions: [
              palette,
              DeltiecordEmojiTypography(
                fontFamily: emojiFontFamily == systemEmojiFontFamily
                    ? null
                    : emojiFontFamily,
              ),
            ],
            textTheme: textTheme,
            fontFamily: preferences.fontFamily == 'System'
                ? null
                : preferences.fontFamily,
            visualDensity: VisualDensity(
              horizontal: -2 * preferences.compactness,
              vertical: -2 * preferences.compactness,
            ),
            pageTransitionsTheme: preferences.reducedMotion
                ? const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.linux: _NoMotionPageTransitionsBuilder(),
                      TargetPlatform.android: _NoMotionPageTransitionsBuilder(),
                    },
                  )
                : const PageTransitionsTheme(),
            useMaterial3: true,
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: DeltiecordCorners.borderRadius,
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                backgroundColor: palette.elevated,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: DeltiecordCorners.borderRadius,
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: DeltiecordCorners.borderRadius,
                ),
              ),
            ),
            chipTheme: ChipThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: DeltiecordCorners.borderRadius,
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: DeltiecordCorners.borderRadius,
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: palette.surface,
              foregroundColor: palette.text,
              iconTheme: IconThemeData(color: colorScheme.primary),
              actionsIconTheme: IconThemeData(color: colorScheme.primary),
              surfaceTintColor: Colors.transparent,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: palette.input,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: DeltiecordCorners.borderRadius,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: DeltiecordCorners.borderRadius,
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: DeltiecordCorners.borderRadius,
              ),
            ),
            menuTheme: MenuThemeData(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(palette.elevated),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: DeltiecordCorners.borderRadius,
                  ),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 3),
                ),
              ),
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: palette.elevated,
              shape: RoundedRectangleBorder(
                borderRadius: DeltiecordCorners.borderRadius,
              ),
            ),
            tooltipTheme: TooltipThemeData(
              waitDuration: const Duration(milliseconds: 450),
              showDuration: const Duration(seconds: 4),
              decoration: BoxDecoration(
                color: palette.elevated,
                borderRadius: DeltiecordCorners.borderRadius,
              ),
              textStyle: TextStyle(
                color: palette.text,
                fontSize: DeltiecordTypeScale.normal,
              ),
            ),
          ),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final interfaceScale = preferences.interfaceScale;
            final scaledMedia = media.copyWith(
              size: media.size / interfaceScale,
              textScaler: TextScaler.linear(preferences.fontScale),
              disableAnimations: preferences.reducedMotion,
              highContrast: preferences.highContrast,
            );
            final content = MediaQuery(
              data: scaledMedia,
              child: mobile ? _InAppNotificationOverlay(child: child!) : child!,
            );
            if (interfaceScale == 1) return content;
            return ClipRect(
              child: FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: media.size.width / interfaceScale,
                  height: media.size.height / interfaceScale,
                  child: content,
                ),
              ),
            );
          },
          home: switch (backend.status) {
            SessionStatus.starting => const _StartupScreen(),
            SessionStatus.failed => _StartupFailure(
              message: backend.error ?? 'Deltiecord could not start.',
              onRetry: backend.initialize,
            ),
            SessionStatus.signedIn =>
              mobile
                  ? StartupUpdateGate(
                      child: _ReadReceiptLifecycle(
                        backend: backend,
                        child: _EncryptionRecoveryPrompt(
                          backend: backend,
                          child: MobileChatShell(backend: backend),
                        ),
                      ),
                    )
                  : StartupUpdateGate(
                      child: _ReadReceiptLifecycle(
                        backend: backend,
                        child: _EncryptionRecoveryPrompt(
                          backend: backend,
                          child: _DesktopActivityReporter(
                            backend: backend,
                            child: ChatShell(backend: backend),
                          ),
                        ),
                      ),
                    ),
            SessionStatus.signedOut ||
            SessionStatus.signingIn => LoginScreen(backend: backend),
          },
        );
      },
    );
  }
}

class _DesktopActivityReporter extends StatefulWidget {
  const _DesktopActivityReporter({required this.backend, required this.child});

  final ChatBackend backend;
  final Widget child;

  @override
  State<_DesktopActivityReporter> createState() =>
      _DesktopActivityReporterState();
}

class _DesktopActivityReporterState extends State<_DesktopActivityReporter>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activity();
  }

  void _activity() {
    if (!_foreground) return;
    widget.backend.setDesktopIdle(false);
    _idleTimer?.cancel();
    _idleTimer = Timer(
      Duration(minutes: widget.backend.preferences.desktopIdleMinutes),
      () => widget.backend.setDesktopIdle(true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _activity();
    } else {
      _idleTimer?.cancel();
      widget.backend.setDesktopIdle(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    widget.backend.setDesktopIdle(true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent) _activity();
      return KeyEventResult.ignored;
    },
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity(),
      onPointerMove: (_) => _activity(),
      onPointerSignal: (_) => _activity(),
      child: widget.child,
    ),
  );
}

class _InAppNotificationOverlay extends StatelessWidget {
  const _InAppNotificationOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      ValueListenableBuilder<InAppChatNotification?>(
        valueListenable: InAppNotificationCenter.current,
        builder: (context, notification, _) {
          if (notification == null) return const SizedBox.shrink();
          return Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.paddingOf(context).top + 10,
            child: SafeArea(
              bottom: false,
              child: Material(
                elevation: 12,
                color: context.deltiecord.elevated,
                shape: RoundedRectangleBorder(
                  borderRadius: DeltiecordCorners.borderRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: notification.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 21,
                          foregroundImage: notification.avatar == null
                              ? null
                              : MemoryImage(notification.avatar!),
                          child: notification.avatar == null
                              ? Text(notification.title.characters.first)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                notification.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                notification.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.deltiecord.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: InAppNotificationCenter.dismiss,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

class _ReadReceiptLifecycle extends StatefulWidget {
  const _ReadReceiptLifecycle({required this.backend, required this.child});

  final ChatBackend backend;
  final Widget child;

  @override
  State<_ReadReceiptLifecycle> createState() => _ReadReceiptLifecycleState();
}

class _ReadReceiptLifecycleState extends State<_ReadReceiptLifecycle>
    with WidgetsBindingObserver {
  bool _lifecycleForeground = true;
  bool _viewFocused = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _publish(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didUpdateWidget(covariant _ReadReceiptLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      oldWidget.backend.setApplicationForeground(false);
      _publish(WidgetsBinding.instance.lifecycleState);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _publish(state);

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    _viewFocused = event.state == ViewFocusState.focused;
    _syncBackend();
  }

  void _publish(AppLifecycleState? state) {
    // A null lifecycle is used by some Flutter test bindings before their
    // first frame; the active widget tree is considered foregrounded there.
    _lifecycleForeground = state == null || state == AppLifecycleState.resumed;
    _syncBackend();
  }

  void _syncBackend() => widget.backend.setApplicationForeground(
    _lifecycleForeground && _viewFocused,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.backend.setApplicationForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _EncryptionRecoveryPrompt extends StatefulWidget {
  const _EncryptionRecoveryPrompt({required this.backend, required this.child});

  final ChatBackend backend;
  final Widget child;

  @override
  State<_EncryptionRecoveryPrompt> createState() =>
      _EncryptionRecoveryPromptState();
}

class _EncryptionRecoveryPromptState extends State<_EncryptionRecoveryPrompt> {
  bool _dialogOpen = false;
  bool _promptedForCurrentNeed = false;

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_encryptionChanged);
    _encryptionChanged();
  }

  @override
  void didUpdateWidget(covariant _EncryptionRecoveryPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      oldWidget.backend.removeListener(_encryptionChanged);
      widget.backend.addListener(_encryptionChanged);
    }
    _encryptionChanged();
  }

  void _encryptionChanged() {
    if (!mounted) return;
    final status = widget.backend.encryptionSetup.status;
    final needsCredential =
        status == EncryptionSetupStatus.needsRecovery ||
        status == EncryptionSetupStatus.needsRepair;
    if (!needsCredential) {
      _promptedForCurrentNeed = false;
      return;
    }
    if (_dialogOpen || _promptedForCurrentNeed) return;
    _promptedForCurrentNeed = true;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showSecurityCenter(context, widget.backend);
      _dialogOpen = false;
    });
  }

  @override
  void dispose() {
    widget.backend.removeListener(_encryptionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NoMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoMotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Opening Deltiecord…'),
        ],
      ),
    ),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    ),
  );
}
