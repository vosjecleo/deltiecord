# Changelog

## Deltiecord 0.9.29 build 97 — 2026-09-16

- Reset every Android per-conversation alert cadence when Deltiecord opens, so
  the next message can vibrate immediately after the app is backgrounded.
- Prevented in-flight UnifiedPush workers from restoring a cleared cooldown or
  posting after the app/room was opened, and suppressed already-read events.
- Recreated animated image codecs after Android resume, recognized normalized
  GIF/APNG/WebP MIME metadata and GIF signatures, and made GIF-provider video
  renditions loop continuously while preserving Reduce Motion behavior.

## Deltiecord 0.9.29 build 96 — 2026-09-16

- Added first-party account registration for `matrix.deltie.net`, including
  password-manager autofill, password confirmation, Matrix UI-auth handling,
  friendly username/rate-limit errors, and automatic sign-in after creation.
- Automatically onboard newly registered accounts into the Deltie Space and
  its public Announcements and General channels, with explicit server-side
  registration throttling.
- Re-armed Android’s per-conversation five-minute alert cadence whenever its
  notification is opened, acted upon, or swiped away, without muting or
  disturbing other conversations.
- Prevented stale room membership state from evicting the already cached own
  profile avatar while a timeline hydrates.
- Added safe promotion of personal sticker and custom-emoji packs to a server:
  existing stable MXC media IDs are reused, the server pack is subscribed
  account-wide, and the personal source is removed only after publication.
- Renamed the user-facing Regular appearance option to Gray while preserving
  its stored setting and palette for compatibility.

## Deltiecord 0.9.29 build 95 — 2026-09-16

- Unified own-user, room-list, timeline, and profile avatar caching; validate
  sender avatar metadata on newly sent/received messages and propagate changed
  avatars throughout the app without re-downloading unchanged media.
- Made profiles cache-first with automatic background refresh on open, removed
  the manual refresh control, and increased status refresh frequency.
- Added an encrypted-room warning when the current device/account encryption
  setup is unverified or needs attention, and replaced low-level Base58 errors
  with an actionable invalid-recovery-key message.
- Repaired missing and incorrect GIF/image geometry from encoded dimensions,
  added full-image fallback when a Matrix thumbnail is unavailable, and refresh
  expiring YouTube playback URLs immediately before opening a video.
- Added Android keyboard image insertion, bounded Android Share-sheet import for
  text/images/videos, and an explicit mobile Paste image action.
- Removed clipboard object-replacement markers from attachment captions so
  Windows multi-image pastes no longer emit visible OBJ message rows.
- Fixed message grouping across member/system events after a display-name
  change and made desktop timeline avatars slightly larger and centered.
- Added a device-local appearance mode, four clearly named themes (Light,
  Regular, Dark, Night), a new deeper charcoal Dark palette, and a safe legacy
  theme migration.
- Fixed light-theme composer foregrounds, improved neutral high-contrast
  separators and avatar fallbacks, completed the curved mobile panel edge, and
  made reduced-motion settings navigation snap without constructing a
  transition.
- Prevented a cancelled mobile navigation swipe from becoming a message reply
  gesture.
- Fixed the Windows installer desktop-shortcut target and added a CI installer
  smoke test that verifies the shortcut points to the installed executable.
- Kept the Android first-run tour phone-only, with Close on its final page,
  Matrix homeserver caveats, password-manager-ready login/password fields, and
  detailed ntfy/UnifiedPush setup and public-rate-limit guidance.

## Deltiecord 0.9.28 build 94 — 2026-09-15

- Fixed Android’s five-minute alert cadence so each conversation owns an
  independent alert identity and atomically committed cooldown timestamp.
- Recreated mobile video players after Android suspend/resume, discarded stale
  near-end seek positions, learned natural video dimensions at playback time,
  and retained a generated poster-frame fallback for link-preview videos.
- Added bounded native first-frame extraction for Android camera uploads so
  newly sent videos include accurate rotation-aware dimensions, duration, and
  thumbnails without routing arbitrary conversion work through a public API.
- Made failed inline image loads retryable, preferred bounded Matrix thumbnails
  in the timeline, and retried stale media requests after returning to the app.
- Folded adjacent captionless image/video-only messages into compact media
  albums while excluding GIFs, captions, replies, and messages five minutes
  apart.
- Added editable trusted link-preview domains, including the ability to disable
  a bundled provider without weakening exact hostname-boundary checks.
- Added explicit personal/server destinations for imported sticker and emoji
  packs. Published server packs can be added account-wide and retain their
  stable Matrix room/state reference so owner edits propagate to subscribers.
- Rendered explicitly selected custom emoji in the Android composer, kept
  duplicate typed aliases literal until a specific result is selected, and
  added `:name\:` as a plaintext opt-out syntax.
- Prevented a cancelled room-panel swipe from becoming a message reply swipe,
  and standardised desktop presence badges at the avatar’s bottom-right.
- Added password-manager autofill semantics to login and account-password
  prompts, refreshed the first-login presentation, and documented limitations
  that custom homeservers may impose on optional Deltiecord services.
- Reworked the first-run tour’s Android notification guidance with ntfy setup,
  battery/rate-limit notes, and a dedicated-provider explanation. Desktop no
  longer sees the Android page and the tour now ends with Close.

## Deltiecord 0.9.27 build 93 — 2026-09-04

- Made transparent-canvas trimming the default for imported and reprocessed
  static custom emoji while keeping it optional, with a stable live preview.
- Added editing for manageable personal and server emoji packs: reopen a pack,
  reprocess its artwork, rename aliases, and rename the pack without replacing
  unrelated personal packs.
- Rendered emoji-only messages at 64 logical pixels for both Unicode and custom
  emoji, while returning inline custom emoji to a compact 20-pixel size.
- Raised the stock mobile text scale to 110% without changing the desktop
  default or overwriting deliberate existing accessibility sizes.
- Replaced Android's unreliable save-as image flow with a single Save image
  action that writes through scoped storage to Downloads/Deltiecord.
- Kept cached generated build tooling outside CI formatting checks and made
  verified Flutter archive cache guards portable across Linux containers.

## Deltiecord 0.9.27 build 90 — 2026-09-04

- Fixed custom-emoji imports silently completing without becoming available
  in the emoji picker or `:alias:` autocomplete.
- Stored ordinary personal packs together in Matrix's interoperable personal
  image-pack event, with opaque per-pack identities and collision-safe item
  keys so importing emoji preserves existing sticker and emoji packs.
- Added authoritative post-write verification and SDK-cache reconciliation so
  a paused `/sync` cannot leave a successfully uploaded pack invisible.
- Preserved legacy personal packs during migration and made deletion remove
  only the selected pack from a merged personal collection.

## Deltiecord 0.9.27 build 89 — 2026-09-04

- Fixed personal sticker and custom-emoji imports replacing the previously
  saved pack by assigning additional packs distinct synced account-data slots.
- Kept the first personal pack in Matrix's interoperable image-pack slot,
  added independent removal and safe reuse for up to 64 active personal packs.
- Waited for authoritative Matrix sync after personal-pack writes and refreshed
  packs when synced sources change, so imported emoji appear without reopening
  the picker repeatedly.
- Added visible progress while uploading imported packs and increased inline
  custom-emoji rendering from 20 to 26 logical pixels.

## Deltiecord 0.9.27 build 88 — 2026-09-04

- Added optional transparent-padding trimming when importing static custom
  emoji, fitting visible artwork into a centred 128×128 canvas without
  stretching it; animated emoji retain their original animation and canvas.
- Made inline custom emoji tappable/clickable in message timelines so their
  accessible source pack can be inspected and added on mobile or desktop.
- Preserved a stable source-pack hint in newly sent custom emoji while still
  resolving older emoji by their immutable Matrix media ID and degrading
  gracefully when a pack is unavailable.

## Deltiecord 0.9.27 build 87 — 2026-09-04

- Fixed sticker and custom-emoji previews permanently waiting on a
  self-referential completion future, including inline historical emoji.
- Added bounded in-memory reuse for Matrix sticker media and newly uploaded
  pack assets, while retaining timeouts and graceful name fallbacks.
- Made custom emoji available immediately in the picker, grouped them by pack,
  and added validated per-item aliases for Telegram and local imports.
- Applied the selected Dark, OLED, or Light palette to attachment, sticker,
  emoji, and pack-management surfaces.
- Made Telegram imports more resilient to intermittent upstream stalls with
  bounded retries, earlier upstream timeouts, and cached static and converted
  media that avoids redundant Telegram downloads.

## Deltiecord 0.9.27 build 86 — 2026-09-04

- Added bounded server-side conversion of Telegram TGS and WebM animations to
  animated WebP, with separate 128px emoji and 256px sticker outputs.
- Restricted conversion to Bot API-resolved pack items and added fixed media
  bounds, subprocess resource limits, per-client and global quotas, two
  conversion workers, and a bounded result cache; arbitrary uploads and URLs
  are never accepted.
- Reworked the sticker picker into compact, theme-aware mobile sheets and
  desktop dialogs, including search, favourites, pack actions, removal, and
  Matrix-compatible global room-pack enablement.
- Rendered `m.sticker` events as dedicated 128px stickers, opened their pack
  instead of generic image actions, and included stable pack hints in newly
  sent events without breaking standard Matrix clients.
- Added retryable, four-at-a-time Telegram preview/import downloads and made
  transient failures recover instead of poisoning the download cache.
- Added aspect-preserving 128×128 custom-emoji preparation with transparent
  centring and a previewable bicubic/bilinear choice for oversized assets.
- Fixed Android room/Space navigation after long background suspension,
  notification dismissal races when opening a room, desktop AFK detection
  during keyboard/pointer activity, and desktop bottom-island spacing.

## Deltiecord 0.9.27 build 85 — 2026-09-04

- Fixed Telegram pack links copied from rich message text being rejected when
  they contain invisible direction/format characters, wrappers, harmless
  query strings, trailing slashes, or current `addemoji` link forms.
- Added an explicit release-publisher option for clearing an invalidated
  stable channel while preserving historical artifacts.

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
