import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'backend/chat_backend.dart';
import 'models/chat_models.dart';
import 'services/desktop_window_service.dart';
import 'services/font_preferences.dart';
import 'ui/chat_shell.dart';
import 'ui/deltiecord_theme.dart';
import 'ui/login_screen.dart';
import 'ui/mobile/mobile_chat_shell.dart';

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
              // Keep emoji rendering deterministic across Linux and Windows.
              // Without an explicit fallback, Skia delegates missing glyphs
              // to the host font configuration and can select monochrome or
              // incomplete emoji fonts on otherwise identical installs.
              fontFamilyFallback: emojiFontFamily == systemEmojiFontFamily
                  ? null
                  : <String>[emojiFontFamily],
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
                side: BorderSide(color: palette.divider),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: palette.surface,
              foregroundColor: palette.text,
              surfaceTintColor: Colors.transparent,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: palette.input,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: palette.divider),
                borderRadius: DeltiecordCorners.borderRadius,
              ),
            ),
            menuTheme: MenuThemeData(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(palette.elevated),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: DeltiecordCorners.borderRadius,
                    side: BorderSide(color: palette.divider),
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
                side: BorderSide(color: palette.divider),
              ),
            ),
            tooltipTheme: TooltipThemeData(
              waitDuration: const Duration(milliseconds: 450),
              showDuration: const Duration(seconds: 4),
              decoration: BoxDecoration(
                color: palette.elevated,
                border: Border.fromBorderSide(
                  BorderSide(color: palette.divider),
                ),
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
            final content = MediaQuery(data: scaledMedia, child: child!);
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
                  ? MobileChatShell(backend: backend)
                  : ChatShell(backend: backend),
            SessionStatus.signedOut ||
            SessionStatus.signingIn => LoginScreen(backend: backend),
          },
        );
      },
    );
  }
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
