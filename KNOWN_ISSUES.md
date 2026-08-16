# Known issues and validation status

This file tracks real remaining limitations. Items fixed during the v0.9.16
hardening pass are retained below so prerelease testers know what changed.

## Remaining manual validation

- Long-history scrolling received stable event-ID anchoring, bounded-window
  churn fixes, stale correction cancellation, and repeated older/newer tests in
  v0.9.16. It still needs an extended authenticated soak across unusually tall
  media/reply-heavy timelines before the 1.0 release.
- Audio output selection now calls the native WebRTC output selector and
  reports failures without crashing. It must still be exercised with multiple
  real PipeWire/Pulse outputs and on Windows hardware.
- Notification and call sounds now use a real media_kit playback stream rather
  than an unsupported desktop system-sound call. Native PipeWire/Pulse and
  Windows playback remain part of the manual release checklist.
- Windows builds compile in CI, but notifications, secure storage, media
  acceleration, clipboard/drag-and-drop, RTC devices, and screen sharing still
  require physical Windows 10/11 testing.
- MatrixRTC voice, video, and screen sharing depend on the homeserver RTC stack,
  platform permissions, and desktop portal support. Unsupported or unavailable
  devices should degrade clearly, but broad hardware coverage is still needed.

## Fixed in v0.9.16

- Timeline page insertion/eviction now preserves the visible Matrix event and
  offset, suppresses stale pagination corrections, and serializes metadata
  hydration rather than allowing overlapping row-height updates.
- Repeated reply/search navigation clears stale event keys, reconstructs the
  correct bounded target window, and blinks the destination row twice.
- Extensible profiles show a loading state instead of flashing an incomplete
  generic profile. Compact profiles include timezone/local time when present.
- Members and Profile are alternate views of the shared collapsible right-hand
  panel.
- Escape closes Settings consistently.
- Configurable shortcuts are dispatched at the root hardware-key level and work
  while the rich-text composer owns focus. Conflict detection remains active.
- Settings includes a microphone test with a live input meter, optional local
  monitoring, selected-device processing constraints, and deterministic
  resource cleanup.
- Spaces support interoperable room ordering, Deltiecord category state,
  collapsible local category state, drag/drop insertion, category reordering,
  and non-drag Move up/down/Move to category actions.

