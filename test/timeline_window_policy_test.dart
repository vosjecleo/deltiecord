import 'package:deltiecord/services/timeline_window_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hard cap honors preferences but never exceeds 120', () {
    expect(TimelineWindowPolicy.hardCap(chunkSize: 30, chunkCap: 3), 90);
    expect(TimelineWindowPolicy.hardCap(chunkSize: 50, chunkCap: 9), 120);
  });

  test('loading older retains the oldest side of a newest-first window', () {
    final events = List.generate(150, (index) => index);
    final evicted = TimelineWindowPolicy.trimNewestFirst(
      events,
      hardCap: 120,
      loaded: TimelinePageDirection.older,
    );
    expect(evicted, 30);
    expect(events, List.generate(120, (index) => index + 30));
  });

  test('loading newer retains the newest side of a newest-first window', () {
    final events = List.generate(150, (index) => index);
    final evicted = TimelineWindowPolicy.trimNewestFirst(
      events,
      hardCap: 120,
      loaded: TimelinePageDirection.newer,
    );
    expect(evicted, 30);
    expect(events, List.generate(120, (index) => index));
  });

  test(
    'database pagination advances beyond the bounded materialized window',
    () {
      var offset = 30;
      final materialized = List.generate(30, (index) => index);
      for (var page = 0; page < 4; page++) {
        final fetched = List.generate(30, (index) => offset + index);
        offset = TimelineWindowPolicy.advanceDatabaseOffset(
          offset,
          fetched.length,
        );
        materialized.addAll(fetched);
        TimelineWindowPolicy.trimNewestFirst(
          materialized,
          hardCap: 90,
          loaded: TimelinePageDirection.older,
        );
      }

      expect(materialized.length, 90);
      expect(offset, 150);
      expect(offset, greaterThan(materialized.length));
    },
  );

  test('reports no eviction while the window remains below its cap', () {
    final events = List.generate(30, (index) => index);
    expect(
      TimelineWindowPolicy.trimNewestFirst(
        events,
        hardCap: 90,
        loaded: TimelinePageDirection.older,
      ),
      0,
    );
  });

  test('overlapping pages keep the newest occurrence of each event', () {
    final events = ['newest', 'middle', 'boundary', 'boundary', 'oldest'];
    expect(TimelineWindowPolicy.deduplicateBy(events, (event) => event), 1);
    expect(events, ['newest', 'middle', 'boundary', 'oldest']);
  });

  test('repeated older and newer churn never duplicates event identities', () {
    var window = List.generate(90, (index) => 'event-$index');
    for (var cycle = 0; cycle < 8; cycle++) {
      window.addAll(
        List.generate(30, (index) => 'event-${90 + cycle * 30 + index}'),
      );
      TimelineWindowPolicy.trimNewestFirst(
        window,
        hardCap: 90,
        loaded: TimelinePageDirection.older,
      );
      final olderWindow = List.of(window);
      expect(olderWindow.toSet().length, olderWindow.length);

      window.insertAll(0, List.generate(30, (index) => 'newer-$cycle-$index'));
      TimelineWindowPolicy.trimNewestFirst(
        window,
        hardCap: 90,
        loaded: TimelinePageDirection.newer,
      );
      expect(window.toSet().length, window.length);
    }
  });
}
