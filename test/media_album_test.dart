import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/media_album.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups adjacent captionless still media by sender and time', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    final messages = [
      _media('new', now, AttachmentKind.image),
      _media(
        'middle',
        now.subtract(const Duration(minutes: 2)),
        AttachmentKind.video,
      ),
      _media(
        'old',
        now.subtract(const Duration(minutes: 4)),
        AttachmentKind.image,
      ),
    ];
    final index = MediaAlbumIndex.fromNewestFirst(messages);
    expect(index.albums['new']?.map((message) => message.id), [
      'old',
      'middle',
      'new',
    ]);
    expect(index.hiddenMessageIds, {'middle', 'old'});
  });

  test('does not fold captions, GIFs, other senders, or five-minute gaps', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    final captioned = _media(
      'captioned',
      now,
      AttachmentKind.image,
      caption: 'hello',
    );
    final gif = _media(
      'gif',
      now.subtract(const Duration(minutes: 1)),
      AttachmentKind.image,
      animated: true,
    );
    final late = _media(
      'late',
      now.subtract(const Duration(minutes: 7)),
      AttachmentKind.video,
    );
    final index = MediaAlbumIndex.fromNewestFirst([captioned, gif, late]);
    expect(index.albums, isEmpty);
    expect(index.hiddenMessageIds, isEmpty);
  });
}

ChatMessage _media(
  String id,
  DateTime timestamp,
  AttachmentKind kind, {
  String? caption,
  bool animated = false,
}) => ChatMessage(
  id: id,
  sender: 'Alice',
  senderId: '@alice:example.org',
  body: caption ?? '$id.jpg',
  timestamp: timestamp,
  pending: false,
  attachment: ChatAttachment(
    kind: kind,
    name: '$id.jpg',
    mimeType: kind == AttachmentKind.video ? 'video/mp4' : 'image/jpeg',
    size: 100,
    encrypted: true,
    spoiler: false,
    caption: caption,
    animated: animated,
  ),
);
