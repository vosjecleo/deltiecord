import 'package:deltiecord/services/chat_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification payload preserves room and event navigation target', () {
    const target = NotificationTarget(
      roomId: '!room:example.org',
      eventId: r'$event',
    );
    final decoded = decodeNotificationTarget(encodeNotificationTarget(target));

    expect(decoded?.roomId, target.roomId);
    expect(decoded?.eventId, target.eventId);
  });

  test(
    'malformed and unreasonably large notification payloads are ignored',
    () {
      expect(decodeNotificationTarget('{not json'), isNull);
      expect(decodeNotificationTarget('{"room_id":"!room"}'), isNull);
      expect(decodeNotificationTarget(List.filled(8193, 'x').join()), isNull);
    },
  );
}
