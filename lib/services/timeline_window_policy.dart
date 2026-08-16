import 'dart:math';

enum TimelinePageDirection { older, newer }

/// Applies Deltiecord's bounded moving-window rules to newest-first events.
///
/// Matrix timelines expose index zero as the newest event. Loading older
/// context therefore evicts from the beginning, while moving toward the
/// present evicts from the end. Scroll anchoring remains a UI responsibility.
abstract final class TimelineWindowPolicy {
  static int hardCap({required int chunkSize, required int chunkCap}) =>
      min(120, max(1, chunkSize) * max(1, chunkCap));

  /// Database pagination must advance by fetched rows, independently of the
  /// bounded number of events Deltiecord keeps materialized in the timeline.
  static int advanceDatabaseOffset(int currentOffset, int fetchedCount) =>
      currentOffset + max(0, fetchedCount);

  /// Trims the window and returns how many events were evicted.
  ///
  /// Callers use the result to distinguish an SDK timeline that is genuinely
  /// at the live end from one whose newest events Deltiecord deliberately
  /// evicted to stay within the bounded materialized window.
  static int trimNewestFirst<T>(
    List<T> events, {
    required int hardCap,
    required TimelinePageDirection loaded,
  }) {
    if (events.length <= hardCap) return 0;
    final overflow = events.length - hardCap;
    switch (loaded) {
      case TimelinePageDirection.older:
        events.removeRange(0, overflow);
      case TimelinePageDirection.newer:
        events.removeRange(hardCap, events.length);
    }
    return overflow;
  }
}
