# Credits and acknowledgements

Deltiecord is original application code built on open-source libraries and
public services. No third-party client repository has been cloned or vendored
into this repository, and no source from the reference clients below has been
copied or adapted. Where Deltiecord directly uses a package, that package stays
an external dependency under its own license.

## Matrix foundations and client references

- [matrix-dart-sdk](https://github.com/famedly/matrix-dart-sdk) provides the
  Matrix client, sync, room, timeline, E2EE, cross-signing, key-backup, media,
  and MatrixRTC APIs used by the backend. Licensed under AGPL-3.0.
- [FluffyChat](https://github.com/krille-chan/fluffychat) was consulted as a
  reference for how a Flutter Matrix client organizes SDK-backed behavior and
  presents interoperable Matrix features. Licensed under AGPL-3.0.
- [Element](https://github.com/element-hq/element-web) and
  [Element X](https://github.com/element-hq/element-x-android) were consulted
  as behavioral/interoperability references for Matrix rooms, recovery,
  replies, media, and calls. No Element code or assets are included.
- The compact three-column layout was inspired by Discord UX. Deltiecord does not use Discord branding, artwork, source,
  or proprietary assets.

## Feature libraries and services

- [Flutter](https://github.com/flutter/flutter) and Dart provide the application
  framework and Linux desktop runtime. Flutter is BSD-3-Clause licensed.
- [flutter-webrtc](https://github.com/flutter-webrtc/flutter-webrtc) provides
  native WebRTC bindings used with matrix-dart-sdk's MatrixRTC implementation.
  Licensed under MIT.
- [media_kit](https://github.com/media-kit/media-kit) provides inline and
  full-window audio/video playback. Licensed under MIT.
- [super_clipboard](https://github.com/superlistapp/super_native_extensions)
  and [super_drag_and_drop](https://github.com/superlistapp/super_native_extensions)
  provide desktop clipboard image access and native file drag/drop. Licensed
  under MIT.
- [flutter_quill](https://github.com/singerdmx/flutter-quill),
  [vsc_quill_delta_to_html](https://github.com/visual-space/vsc_quill_delta_to_html),
  and [markdown](https://github.com/dart-lang/tools/tree/main/pkgs/markdown)
  provide document editing/serialization and typed-markup parsing.
- [flutter_vodozemac](https://github.com/famedly/dart-vodozemac) and Vodozemac
  provide the cryptographic implementation used through the Matrix SDK.
- [flutter_secure_storage](https://github.com/juliansteenbakker/flutter_secure_storage)
  provides OS-keyring-backed storage for sessions and private configuration.
- [UnifiedPush Android connector](https://codeberg.org/UnifiedPush/android-connector)
  provides the standard distributor integration used for private Android push.
  The connector is Apache-2.0 licensed. Deltiecord's configured Matrix gateway
  uses [ntfy](https://github.com/binwiederhier/ntfy), which is Apache-2.0 and
  GPL-2.0 licensed depending on the component; no ntfy server code is bundled.
- [GIPHY](https://developers.giphy.com/) supplies GIF search results through its
  public API. Deltiecord contains its own small client; a rate-limited HTTPS
  proxy holds the shared API key so client binaries never contain it.
- [Jome](https://github.com/eepp/jome) supplies the local Unicode emoji name
  and keyword dataset used for offline emoji search and colon completion.
  Deltiecord vendors only `emojis.json`; Jome is MIT licensed.
- Liberation Sans is bundled as Deltiecord's portable interface font under the
  SIL Open Font License. Noto Color Emoji is bundled as the default emoji
  fallback under the SIL Open Font License. Their license texts are shipped in
  `assets/fonts/licenses/`.

Additional Dart and Flutter packages are declared in `pubspec.yaml` and retain
their upstream copyright notices and licenses.

## Linux packaging

- [linuxdeploy](https://github.com/linuxdeploy/linuxdeploy) and its AppImage
  output plugin assemble the portable Linux bundle. Licensed under MIT.
- [AppImage](https://github.com/AppImage/appimagetool) supplies the AppImage
  runtime and final packaging tooling. Licensed under MIT.

Thanks to the Matrix specification authors, SDK maintainers, client developers,
package maintainers, and Deltiecord's hands-on testers:
Yeen, Tecilis and Gabe.

And lastly, thanks to the AI developers at Alibaba cloud for building an LLM capable of doing the work of building the base of this app.
