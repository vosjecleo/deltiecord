import 'package:deltiecord/ui/typing_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typing labels stay concise as participant count grows', () {
    expect(typingLabel(const []), isEmpty);
    expect(typingLabel(const ['Alice']), 'Alice is typing');
    expect(typingLabel(const ['Alice', 'Bob']), 'Alice and Bob are typing');
    expect(
      typingLabel(const ['Alice', 'Bob', 'Carol']),
      'Alice, Bob and Carol are typing',
    );
    expect(
      typingLabel(const ['Alice', 'Bob', 'Carol', 'Dave']),
      'Several people are typing',
    );
  });
}
