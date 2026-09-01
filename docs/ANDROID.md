# Android implementation and testing

Deltiecord's Android application uses the shared `ChatBackend`, Matrix backend,
models, encryption/session storage, timeline, media, profile, settings, and
MatrixRTC layers. Phone-specific presentation lives in `lib/ui/mobile`; the
desktop widget tree is selected independently.

## Navigation model

The phone shell keeps navigation, timeline, and room details as animated layers
instead of replacing routes. This preserves the selected room, bounded timeline,
scroll position, and local per-room draft while panels move on or off screen.

- Right swipe on the timeline opens Home/Space navigation.
- Left swipe on visible navigation restores the timeline.
- Tapping the room header opens details from the right. A right swipe or Back
  closes it.
- Tapping a person opens a draggable profile sheet from the bottom.
- A local left swipe on a message replies without invoking global navigation.
- Android Back closes temporary UI, details, and then the timeline in that
  order before deferring to the operating system.

## Signing

Release CI requires a persistent signing identity. It will fail rather than
silently produce an APK with a GitHub runner's temporary debug certificate.
Provide the keystore through the `DELTIECORD_ANDROID_KEYSTORE_BASE64`,
`DELTIECORD_ANDROID_STORE_PASSWORD`, and `DELTIECORD_ANDROID_KEY_PASSWORD`
repository secrets. `DELTIECORD_ANDROID_KEY_ALIAS` is optional because CI can
derive the first key alias from the keystore. Local release builds may
use ignored `android/key.properties` values with the equivalent fields. Never
commit a keystore or signing password.

Changing signing identities prevents an in-place Android upgrade. Builds 62 and
63 were signed by ephemeral CI debug identities, which caused the reported
"App not installed" upgrades. Users of those APKs need one uninstall before the
first persistently signed build; upgrades after that keep working. Back up the
release keystore independently before publishing that build.

## Notifications and background operation

Deltiecord creates an Android message notification channel and preserves the
existing encrypted-preview privacy preference. Notification payloads select the
corresponding room/event when the process receives them.

Notifications settings use the standard UnifiedPush Android connector. Install
and configure an external distributor (such as the ntfy Android app) for
`https://push.deltie.net`, select it in Deltiecord, then Deltiecord registers the
complete private distributor endpoint with the Matrix HTTP push gateway at
`https://push.deltie.net/_matrix/push/v1/notify`. Neither distributor credentials
nor generated endpoint capabilities are shipped or logged by Deltiecord.

The embedded Firebase-compatible distributor is not enabled in release builds.
Matrix requires a WebPush-capable gateway and VAPID configuration for that
route; silently falling back to an unconfigured embedded distributor would
leave notifications registered but undeliverable.

Release CI produces architecture-specific APKs for `arm64-v8a`,
`armeabi-v7a`, and `x86_64`, plus an AAB. Most current physical phones should
use the smaller `arm64-v8a` APK.

Push payloads are treated as generic Matrix activity wake-ups, not as trusted
plaintext message content. Opening a push resumes normal authenticated Matrix
sync. The distributor and gateway therefore improve suspended-app delivery
without making them a source for decrypted message text.

An active MatrixRTC session may also be constrained by vendor background policy.
The in-app persistent call island is implemented, but a production Android
foreground-call service still needs broader device validation.

## Platform permissions

Internet access is always required. Notification, microphone, camera, and screen
capture permissions are requested when the corresponding feature needs them.
Screen sharing uses the WebRTC/Android MediaProjection path exposed by the
current plugin and begins only after explicit user action.

Secure Matrix credentials use `flutter_secure_storage`; files and databases use
the normal Android application-data/cache directories. Media/file picking,
clipboard access, external URLs, camera/microphone capture, media playback, and
RTC continue through the existing cross-platform services and plugins.

## Real-device validation

CI proves that the APK and AAB compile, not that every Android integration works
on every device. Before a stable release, test at least Android 10 through the
current Android version on multiple vendors:

- login, encrypted session restoration, recovery, and secure-storage persistence
- DM/Space navigation, gestures, Back behavior, drafts, and orientation changes
- encrypted text/media send, receive, streaming, seeking, suspend, and resume
- notification permission, privacy, delivery, and room/event deep links
- clipboard, file/media picker, camera and microphone permissions
- voice-room join/reconnect, mute, deafen, speaker/Bluetooth routing, and levels
- camera switching, group video, screen capture, and capture cancellation
- app backgrounding, vendor battery management, and ongoing RTC behavior

The official CI workflow is `.github/workflows/android.yml`. It pins and verifies
Flutter and Rust inputs, runs formatting, analysis, and the complete test suite,
then produces both a sideloadable APK and an AAB.
