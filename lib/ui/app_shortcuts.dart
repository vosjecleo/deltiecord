import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';

SingleActivator? decodeShortcut(String encoded) {
  final parts = encoded.split('+');
  if (parts.isEmpty) return null;
  final key = _decodeKey(parts.last);
  if (key == null) return null;
  return SingleActivator(
    key,
    control: parts.contains('control'),
    shift: parts.contains('shift'),
    alt: parts.contains('alt'),
    meta: parts.contains('meta'),
  );
}

String encodeShortcut(KeyDownEvent event) {
  final key = event.logicalKey;
  final parts = <String>[
    if (HardwareKeyboard.instance.isControlPressed) 'control',
    if (HardwareKeyboard.instance.isShiftPressed) 'shift',
    if (HardwareKeyboard.instance.isAltPressed) 'alt',
    if (HardwareKeyboard.instance.isMetaPressed) 'meta',
    'id:${key.keyId}',
  ];
  return parts.join('+');
}

/// Matches a recorded shortcut independently of the focused widget.
///
/// Composer editors are allowed to consume ordinary text keys, so application
/// commands are dispatched from the root hardware-key handler instead of
/// relying exclusively on focus-local [Shortcuts] propagation.
bool matchesRecordedShortcut(
  String encoded,
  LogicalKeyboardKey key, {
  required bool control,
  required bool shift,
  required bool alt,
  required bool meta,
}) {
  final binding = decodeShortcut(encoded);
  return binding != null &&
      binding.trigger == key &&
      binding.control == control &&
      binding.shift == shift &&
      binding.alt == alt &&
      binding.meta == meta;
}

String shortcutLabel(String encoded) {
  final binding = decodeShortcut(encoded);
  if (binding == null) return 'Not set';
  final parts = <String>[
    if (binding.control) 'Ctrl',
    if (binding.alt) 'Alt',
    if (binding.shift) 'Shift',
    if (binding.meta) 'Meta',
    _keyLabel(binding.trigger),
  ];
  return parts.join(' + ');
}

bool isModifierKey(LogicalKeyboardKey key) => {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
}.contains(key);

LogicalKeyboardKey? _decodeKey(String token) {
  if (token.startsWith('id:')) {
    final id = int.tryParse(token.substring(3));
    return id == null ? null : LogicalKeyboardKey(id);
  }
  return switch (token) {
    'comma' => LogicalKeyboardKey.comma,
    'm' => LogicalKeyboardKey.keyM,
    'd' => LogicalKeyboardKey.keyD,
    'backslash' => LogicalKeyboardKey.backslash,
    'g' => LogicalKeyboardKey.keyG,
    'e' => LogicalKeyboardKey.keyE,
    'u' => LogicalKeyboardKey.keyU,
    'l' => LogicalKeyboardKey.keyL,
    'f' => LogicalKeyboardKey.keyF,
    _ => null,
  };
}

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.comma) return ',';
  if (key == LogicalKeyboardKey.backslash) return r'\';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key == LogicalKeyboardKey.enter) return 'Enter';
  if (key == LogicalKeyboardKey.space) return 'Space';
  return key.keyLabel.isEmpty ? 'Key ${key.keyId}' : key.keyLabel.toUpperCase();
}

String shortcutActionLabel(AppShortcutAction action) => switch (action) {
  AppShortcutAction.openSettings => 'Open Settings',
  AppShortcutAction.toggleMicrophone => 'Mute / unmute microphone',
  AppShortcutAction.toggleDeafen => 'Deafen / undeafen',
  AppShortcutAction.disconnectVoice => 'Disconnect voice',
  AppShortcutAction.openGifPicker => 'Open GIF picker',
  AppShortcutAction.openEmojiPicker => 'Open emoji picker',
  AppShortcutAction.openFilePicker => 'Open file picker',
  AppShortcutAction.focusComposer => 'Focus composer',
  AppShortcutAction.searchRoom => 'Search current room',
  AppShortcutAction.toggleMembers => 'Toggle member list',
};

class ShortcutRecorder extends StatefulWidget {
  const ShortcutRecorder({
    required this.value,
    required this.onRecorded,
    this.conflict,
    super.key,
  });

  final String value;
  final ValueChanged<String> onRecorded;
  final String? Function(String value)? conflict;

  @override
  State<ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends State<ShortcutRecorder> {
  final _focusNode = FocusNode();
  bool _recording = false;
  String? _error;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = false);
      return KeyEventResult.handled;
    }
    if (isModifierKey(event.logicalKey)) return KeyEventResult.handled;
    final encoded = encodeShortcut(event);
    final conflict = widget.conflict?.call(encoded);
    if (conflict != null) {
      setState(() => _error = 'Already used by $conflict');
      return KeyEventResult.handled;
    }
    widget.onRecorded(encoded);
    setState(() {
      _recording = false;
      _error = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    onKeyEvent: (_, event) => _onKey(event),
    child: OutlinedButton(
      onPressed: () {
        setState(() {
          _recording = true;
          _error = null;
        });
        _focusNode.requestFocus();
      },
      child: Text(
        _error ??
            (_recording ? 'Press shortcut…' : shortcutLabel(widget.value)),
        style: TextStyle(color: _error == null ? null : Colors.redAccent),
      ),
    ),
  );
}
