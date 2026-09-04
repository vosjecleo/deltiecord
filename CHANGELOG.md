# Changelog

## Deltiecord 0.9.27 build 84 — 2026-09-04

- Restyled sticker selection and pack management as bounded desktop dialogs
  while retaining draggable mobile sheets, and made every pack/import action
  reachable through a properly scrollable viewport.
- Nudged the active Android Matrix timeline through its existing SDK
  subscription whenever the app resumes, so messages received during a long
  suspension appear without switching rooms or sending a message.
- Removed repeated room-hero database loads and repeated last-event decryption
  from every sync, prioritised the selected room, and reused already-decoded DM
  avatars directly in the timeline sender cache.
- Added a strict, channel-selectable release command that drives the existing
  platform CI, verifies the exact artifact set, and atomically publishes
  `latest`, `stable`, or both on deltie.net.

## Deltiecord 0.9.27 build 83 — 2026-09-04

- Added custom/server emoji on top of Matrix image packs, including 120-item
  packs, strict 128×128 and 256 KiB per-emoji limits, animated inline
  rendering, stable MXC references, fallback names, autocomplete, picker and
  reaction support, server-scoped permissions, Telegram import, and deletion.
- Preserved custom-emoji references in mobile drafts and kept legacy image
  packs that advertised both `sticker` and `emoticon` usage as stickers.
- Reconciled the mobile navigation subtree and transient gesture/open state
  after Android resumes, so Home and Space selection cannot remain frozen.

- Added selective import of public static Telegram sticker packs through a
  bounded, token-hiding Deltiecord proxy. Animated TGS and WebM stickers are
  identified and skipped until cross-platform rendering is ready.
- Raised personal image packs from 50 to 120 stickers, added aggregate media
  and metadata limits, and preserved each sticker's actual MIME type.
- Made sticker-pack refresh metadata-only and lazily loaded visible previews
  with at most four concurrent requests.
- Made Space categories and channels substantially denser on desktop and
  mobile while retaining full-row interaction and trailing collapse controls.
- Reduced the timeline-to-composer gutter to the typing row's actual height
  and tightened all aligned desktop bottom panels accordingly.

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
