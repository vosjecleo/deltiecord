import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/app_shortcuts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all configurable actions have distinct valid default bindings', () {
    expect(defaultShortcutBindings.keys, containsAll(AppShortcutAction.values));
    expect(
      defaultShortcutBindings.values.toSet().length,
      defaultShortcutBindings.length,
    );
    for (final binding in defaultShortcutBindings.values) {
      expect(decodeShortcut(binding), isA<SingleActivator>());
      expect(shortcutLabel(binding), isNot('Not set'));
    }
  });

  test('arbitrary logical key ids round-trip through the binding decoder', () {
    final decoded = decodeShortcut(
      'control+alt+id:${LogicalKeyboardKey.keyK.keyId}',
    );
    expect(decoded?.trigger, LogicalKeyboardKey.keyK);
    expect(decoded?.control, isTrue);
    expect(decoded?.alt, isTrue);
  });

  test('recorded shortcut matching is independent of widget focus', () {
    expect(
      matchesRecordedShortcut(
        'control+shift+id:${LogicalKeyboardKey.keyG.keyId}',
        LogicalKeyboardKey.keyG,
        control: true,
        shift: true,
        alt: false,
        meta: false,
      ),
      isTrue,
    );
    expect(
      matchesRecordedShortcut(
        'control+shift+id:${LogicalKeyboardKey.keyG.keyId}',
        LogicalKeyboardKey.keyG,
        control: true,
        shift: false,
        alt: false,
        meta: false,
      ),
      isFalse,
    );
  });
}
