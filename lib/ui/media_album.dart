import 'package:flutter/material.dart';

import '../models/chat_models.dart';

/// Finds adjacent, captionless image/video messages which can be presented as
/// one visual attachment group. The stable event IDs remain untouched so
/// receipts, replies, deletion and permalink navigation keep their semantics.
class MediaAlbumIndex {
  MediaAlbumIndex._(this.albums, this.hiddenMessageIds);

  factory MediaAlbumIndex.fromNewestFirst(List<ChatMessage> messages) {
    final albums = <String, List<ChatMessage>>{};
    final hidden = <String>{};
    for (var index = 0; index < messages.length;) {
      final first = messages[index];
      if (!_eligible(first)) {
        index++;
        continue;
      }
      final run = <ChatMessage>[first];
      var cursor = index + 1;
      while (cursor < messages.length) {
        final candidate = messages[cursor];
        final newer = run.last;
        if (!_eligible(candidate) ||
            candidate.senderId != first.senderId ||
            candidate.sender != first.sender ||
            newer.timestamp.difference(candidate.timestamp).abs() >=
                const Duration(minutes: 5)) {
          break;
        }
        run.add(candidate);
        cursor++;
      }
      if (run.length > 1) {
        albums[first.id] = run.reversed.toList(growable: false);
        hidden.addAll(run.skip(1).map((message) => message.id));
      }
      index = cursor;
    }
    return MediaAlbumIndex._(albums, hidden);
  }

  final Map<String, List<ChatMessage>> albums;
  final Set<String> hiddenMessageIds;

  static bool _eligible(ChatMessage message) {
    final attachment = message.attachment;
    if (attachment == null ||
        attachment.sticker ||
        attachment.animated ||
        attachment.caption?.trim().isNotEmpty == true ||
        message.system ||
        message.redacted ||
        message.poll != null ||
        message.reply != null) {
      return false;
    }
    return attachment.kind == AttachmentKind.image ||
        attachment.kind == AttachmentKind.video;
  }
}

/// Discord-style three-cell album: the first item owns the left half, the next
/// two share the right. Additional items are represented by a blurred +N tile.
class MediaAlbumGrid extends StatelessWidget {
  const MediaAlbumGrid({
    required this.messages,
    required this.itemBuilder,
    this.height = 280,
    super.key,
  });

  final List<ChatMessage> messages;
  final Widget Function(BuildContext context, ChatMessage message) itemBuilder;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget tile(int index) {
      final message = messages[index];
      final remaining = messages.length - 3;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            itemBuilder(context, message),
            if (index == 2 && remaining > 0) ...[
              ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
              Center(
                child: Text(
                  '+$remaining',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final count = messages.length.clamp(1, 3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: count == 2
            ? Row(
                children: [
                  Expanded(child: tile(0)),
                  const SizedBox(width: 2),
                  Expanded(child: tile(1)),
                ],
              )
            : Row(
                children: [
                  Expanded(child: tile(0)),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: tile(1)),
                        const SizedBox(height: 2),
                        Expanded(child: tile(2)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
