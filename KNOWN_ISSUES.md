# Known issues

No currently confirmed desktop regression remains on the build 62 checklist.
Android is newly supported and the device-specific limitations below still need
broader testing. Beta testers may
still encounter hardware-, homeserver-, or desktop-specific behavior and should
report reproducible problems with relevant platform details.

## Android validation still required

- Background message notifications currently depend on the Matrix sync process
  remaining alive. Deltiecord deliberately does not bundle Firebase/Google push,
  and vendor battery management may suspend background sync.
- Voice/video RTC, encrypted media seeking, screen sharing, notification deep
  links, camera switching, suspend/resume, and orientation changes need testing
  across more physical Android devices.
- Android exposes fewer explicit input/output routing controls than desktop on
  some devices; unsupported routing choices degrade to the system route.

## Fixed in v0.9.18 build 62

- Homeserver preview responses with non-uniform OpenGraph field shapes are now
  parsed consistently, transient failures no longer poison event previews
  indefinitely, and repeated URLs share a bounded cache.
- Link previews hydrate progressively and cannot block the initial room text.
- Optional on-device previews are explicitly opt-in and validate DNS, connected
  addresses, redirects, content types, timeouts, and response sizes.

## Fixed in v0.9.17 build 61

- Corrected the optical vertical alignment of permitted room/category drag grips.
- Made the About Me island fill the centered recipient-panel content column.
- Added the direct recipient's live presence state to the conversation header.
- Expanded Space settings with an avatar preview, fuller identity fields, Space
  information and link copying, notification muting, room/category counts, and
  an arbitrary Matrix-synced channel-layout power-level control.
