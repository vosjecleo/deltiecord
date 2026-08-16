import 'package:deltiecord/services/message_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires every search term and rejects unrelated context events', () {
    expect(
      matchesMessageSearch(
        body: 'Matrix search now finds the right message',
        sender: 'Alice',
        query: 'right message',
      ),
      isTrue,
    );
    expect(
      matchesMessageSearch(
        body: 'This event merely surrounded the actual result',
        sender: 'Bob',
        query: 'right message',
      ),
      isFalse,
    );
  });

  test('matches sender names without making term matching fuzzy', () {
    expect(
      matchesMessageSearch(
        body: 'hello there',
        sender: 'Avery Morgan',
        query: 'avery hello',
      ),
      isTrue,
    );
  });
}
