# Changelog

## Deltiecord 0.9.26 build 82 — 2026-09-03

- Fixed mobile attachment-only image and video events rendering an empty text
  row above their media.
- Anchored Home and Space attention badges to their full navigation buttons.
- Made mobile's rail separator follow the rounded room-card corner and removed
  the final physical-pixel seam between the typing backdrop and composer.
- Aligned mobile composer text with timeline content while tightening its side
  margins.
- Removed the desktop resize gutter from layout flow so the timeline and
  composer move left together and the user island no longer crosses into chat.
- Slightly reduced and vertically centred desktop timeline avatars.
- Restyled category labels on desktop and mobile with preserved casing, a
  one-pixel-smaller bold font, leading-panel alignment, and trailing chevrons.

## Deltiecord 0.9.26 build 81 — 2026-09-03

- Added per-installation first-run guidance for preview privacy, Matrix
  recovery, and private Android notification setup with ntfy/UnifiedPush.
- Reworked preview privacy into Never, Known providers, and All public sites;
  homeserver previews remain first, and opted-in provider enrichment adds
  playable YouTube and GIF/media cards where available.
- Fixed Android notification history retaining already-read messages, made
  room notifications clear when their conversation opens, and prevented
  foreground mobile banners from appearing over the active room.
- Added structured Matrix mention/reply highlighting, DM and Space ping
  badges, and a ping-focused inbox model.
- Added local favourites for GIFs, emoji, and stickers, plus bounded creation
  and ZIP import for Matrix-compatible personal sticker packs.
- Fixed poll responses not refreshing their Matrix aggregation after voting.
- Hardened resume handling for stale Android keyboard metrics, interrupted
  gestures, endpoint reconciliation, and account-setting refresh.
- Made the typing backdrop persistent and gradual, while reserving just enough
  timeline space to avoid covering message text.
- Tightened desktop/mobile message and composer alignment, filled mobile Space
  avatars, and added a subtle rail separator.
- Removed obsolete compactness/font controls and the unreliable bundled font;
  merged diagnostics into About and added device-aware session icons.
- Replaced desktop message/call cues with HaelDB's CC0 UI sound #8. Call sound
  remains a separate asset slot for straightforward future replacement.
- Extended reduced motion to snap navigation/settings transitions and disable
  automatic animated-attachment playback.
