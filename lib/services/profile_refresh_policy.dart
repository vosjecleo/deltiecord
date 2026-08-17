/// Refresh intervals for profile data with different volatility.
///
/// Profile media is deliberately absent from this policy. Avatars, profile
/// banners, and voice backgrounds remain pooled until the user explicitly
/// refreshes a full profile (or edits their own profile), avoiding repeated
/// downloads of comparatively large immutable blobs.
abstract final class ProfileRefreshPolicy {
  /// Status messages are presence data, but some homeservers do not include
  /// every status change in `/sync`; poll recently viewed profiles as backup.
  static const statusInterval = Duration(minutes: 1);

  /// Extensible profile text has no standard Matrix push notification.
  static const metadataInterval = Duration(minutes: 5);

  /// Stop polling profiles that are no longer represented by visible/recent
  /// UI. They remain in the LRU media pool and refresh when accessed again.
  static const activeProfileWindow = Duration(minutes: 10);

  static bool statusIsStale(DateTime fetchedAt, DateTime now) =>
      now.difference(fetchedAt) >= statusInterval;

  static bool metadataIsStale(DateTime fetchedAt, DateTime now) =>
      now.difference(fetchedAt) >= metadataInterval;

  static bool wasRecentlyAccessed(DateTime accessedAt, DateTime now) =>
      now.difference(accessedAt) < activeProfileWindow;
}
