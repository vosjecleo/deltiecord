import 'package:deltiecord/ui/relative_activity_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DM activity ages use compact bounded units', () {
    final now = DateTime(2026, 9, 2, 15);
    expect(compactActivityAge(null, now: now), isEmpty);
    expect(compactActivityAge(now, now: now), 'now');
    expect(
      compactActivityAge(now.subtract(const Duration(minutes: 12)), now: now),
      '12m',
    );
    expect(
      compactActivityAge(now.subtract(const Duration(hours: 3)), now: now),
      '3h',
    );
    expect(
      compactActivityAge(now.subtract(const Duration(days: 6)), now: now),
      '6d',
    );
    expect(
      compactActivityAge(now.subtract(const Duration(days: 21)), now: now),
      '3w',
    );
    expect(
      compactActivityAge(now.subtract(const Duration(days: 90)), now: now),
      '3M',
    );
    expect(
      compactActivityAge(now.subtract(const Duration(days: 730)), now: now),
      '2y',
    );
  });
}
