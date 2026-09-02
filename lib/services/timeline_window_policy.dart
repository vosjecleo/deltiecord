import 'dart:math';

enum TimelinePageDirection { older, newer }

/// Stateless helpers for Matrix timeline pagination and deduplication.
///
/// The active UI deliberately keeps one stable SDK-owned event list. The
/// window-moving helpers remain only for isolated list consumers and policy
/// regression tests; they must not be used to replace both ends of a live
/// Flutter sliver because doing so destroys its scroll anchor.
abstract final class TimelineWindowPolicy {
  static int hardCap({required int chunkSize, required int chunkCap}) =>
      min(120, max(1, chunkSize) * max(1, chunkCap));

  /// Database pagination must advance by fetched rows, independently of the
  /// bounded number of events Deltiecord keeps materialized in the timeline.
  static int advanceDatabaseOffset(int currentOffset, int fetchedCount) =>
      currentOffset + max(0, fetchedCount);

  /// Returns the greatest valid start for a full presentation window.
  static int maximumWindowStart({
    required int eventCount,
    required int capacity,
  }) => max(0, eventCount - max(1, capacity));

  /// Moves a presentation window toward older events without exposing a
  /// short, unstable tail at the end of the SDK-owned event list.
  static int moveOlder({
    required int currentStart,
    required int eventCount,
    required int capacity,
    required int pageSize,
  }) => min(
    maximumWindowStart(eventCount: eventCount, capacity: capacity),
    max(0, currentStart) + max(1, pageSize),
  );

  /// Moves a presentation window toward the live end of a newest-first list.
  static int moveNewer({required int currentStart, required int pageSize}) =>
      max(0, currentStart - max(1, pageSize));

  /// Clamps a desired window so a visible anchor cannot be evicted.
  ///
  /// The SDK list is newest-first. Page changes therefore replace events at
  /// one edge of the presentation window. Keeping the immutable anchor event
  /// inside the replacement prevents Flutter from clamping to either extent
  /// when rows at the opposite edge disappear.
  static int preserveAnchor({
    required int desiredStart,
    required int eventCount,
    required int capacity,
    int? anchorIndex,
  }) {
    final maximum = maximumWindowStart(
      eventCount: eventCount,
      capacity: capacity,
    );
    if (anchorIndex == null || anchorIndex < 0 || anchorIndex >= eventCount) {
      return desiredStart.clamp(0, maximum).toInt();
    }
    final minimumForAnchor = max(0, anchorIndex - max(1, capacity) + 1);
    final maximumForAnchor = min(maximum, anchorIndex);
    return desiredStart.clamp(minimumForAnchor, maximumForAnchor).toInt();
  }

  /// Removes repeated identities while preserving newest-first order.
  ///
  /// Fragmented Matrix history pages may overlap at their boundary. Removing
  /// that overlap before trimming prevents a boundary event from becoming a
  /// visibly repeated "first" message.
  static int deduplicateBy<T, K>(List<T> events, K Function(T event) keyOf) {
    final seen = <K>{};
    final originalLength = events.length;
    events.removeWhere((event) => !seen.add(keyOf(event)));
    return originalLength - events.length;
  }

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
