import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';

final class AndroidSharedContent {
  AndroidSharedContent._();

  static final instance = AndroidSharedContent._();
  static const _channel = MethodChannel('net.deltie.deltiecord/shared_content');
  final _arrivals = StreamController<void>.broadcast();
  bool _ready = false;

  Stream<void> get arrivals => _arrivals.stream;

  void initialize() {
    if (_ready || defaultTargetPlatform != TargetPlatform.android) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'available') _arrivals.add(null);
    });
  }

  Future<({String? text, List<AttachmentDraft> attachments})?> consume() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    initialize();
    final raw = await _channel.invokeMapMethod<String, Object?>('consume');
    if (raw == null) return null;
    final attachments = <AttachmentDraft>[];
    for (final item in (raw['items'] as List? ?? const [])) {
      if (item is! Map) continue;
      final bytes = item['bytes'];
      if (bytes is! Uint8List || bytes.isEmpty) continue;
      attachments.add(
        AttachmentDraft(
          bytes: bytes,
          name: item['name']?.toString() ?? 'shared-media',
          mimeType: item['mimeType']?.toString() ?? 'application/octet-stream',
          spoiler: false,
        ),
      );
    }
    final text = raw['text']?.toString().trim();
    return (
      text: text?.isEmpty == true ? null : text,
      attachments: attachments,
    );
  }
}
