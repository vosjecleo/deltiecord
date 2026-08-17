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

Prerelease CI builds use Android's development signing identity so testers can
sideload the APK without a secret committed to Git. This identity is not suitable
for a stable public release. A production keystore and its passwords must be
provided to Gradle through CI secrets or an ignored local properties file. Never
commit a keystore or signing password.

Changing signing identities later prevents an in-place upgrade of an APK signed
with the old identity. Choose and securely back up the production identity before
the stable Android release.

## Notifications and background operation

Deltiecord creates an Android message notification channel and preserves the
existing encrypted-preview privacy preference. Notification payloads select the
corresponding room/event when the process receives them.

The application deliberately has no Firebase Cloud Messaging dependency. In the
current prerelease, incoming notifications rely on the Matrix sync process being
alive. Android or vendor battery management may suspend that process. Reliable
private mobile push will require a separately documented Matrix-compatible push
gateway design; it is not silently routed through Google infrastructure.

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
