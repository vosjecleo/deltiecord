import 'package:deltiecord/services/poll_tally.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Matrix voter-keyed responses are tallied per answer', () {
    final responses = <String, Set<String>>{
      '@alice:example.org': {'cats'},
      '@bob:example.org': {'cats', 'dogs'},
    };

    expect(pollVoteCount(responses, 'cats'), 2);
    expect(pollVoteCount(responses, 'dogs'), 1);
    expect(
      pollAnswerSelectedBy(responses, '@alice:example.org', 'cats'),
      isTrue,
    );
    expect(
      pollAnswerSelectedBy(responses, '@alice:example.org', 'dogs'),
      isFalse,
    );
  });
}
