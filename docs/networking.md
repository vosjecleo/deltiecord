# Networking and privacy

Deltiecord intentionally limits the network destinations it contacts.

## Configured Matrix homeserver

Automatic after login. Sync, authentication, room state, profile data, search,
media, encryption backup, and homeserver URL-preview requests go to the user's
configured homeserver. Federation is performed by homeservers and is not a
separate client connection.

Message link previews use the Matrix homeserver preview endpoint by default. If
the homeserver cannot produce a preview, Deltiecord normally shows the plain
link and does not contact that site from the user's IP address.

Privacy settings contain an optional `Fetch link previews directly on this
device` fallback. It is off on every new installation. When explicitly enabled,
the client may fetch a public HTTP(S) page only after the homeserver preview
fails. Every DNS result and redirect target must be public and the actual TLS
peer address is validated before sending a request, so DNS rebinding cannot
redirect preview traffic into a private network. Proxies and cookies are
disabled, documents and images are bounded, and strict content-type, redirect,
and timeout limits apply. Embedded video candidates are exposed only in this
opt-in mode after a bounded range probe validates their public host, redirects,
content type, and declared size. Pressing Play then streams from that validated
public media URL.
Matrix tokens and headers are never sent to a preview site.

## MatrixRTC and WebRTC infrastructure

User-triggered when joining a voice room/call or enabling camera/screen share.
MatrixRTC state is exchanged through Matrix. Media may connect to ICE, STUN,
TURN, and MatrixRTC infrastructure advertised by the homeserver/RTC setup.
Linux screen sharing uses standard desktop portals and PipeWire where required.

## GIPHY proxy and media

Opening the GIF picker can request trending results from
`https://deltie.net/api/servers/giphy/search`. Typing a search sends the query
to that HTTPS proxy. The proxy holds the shared GIPHY API key; release binaries
do not contain it. Selecting a result triggers a bounded download from an
HTTPS `giphy.com` host after DNS/public-address and redirect validation.

Search JSON is capped at 2 MiB and GIF downloads at 25 MiB. Both use connection
and inactivity timeouts, status/content-type validation, and bounded redirects.

## External links and files

User-triggered only. Choosing Open externally passes an explicitly selected URL
or a private temporary attachment file to the operating system. Deltiecord does
not fetch the destination first. Temporary decrypted files use randomized names
and private Unix permissions, then age out through cleanup.

## Local encrypted-media proxy

Automatic only while encrypted media is being played. Deltiecord binds an HTTP
range server to `127.0.0.1` on a random port. Random capability paths refer to
credentials and AES material held only in memory. URLs and logs never contain
Matrix access tokens, keys, or IVs. Entries expire, are LRU bounded, and are
removed when playback ends, on logout, and at shutdown.

## Removed integrations

The old automatic FxTwitter/direct fallback is not used. Direct webpage preview
traffic occurs only after the user enables the privacy setting described above.

## Android UnifiedPush

Opt-in and user-triggered from Android notification settings. Deltiecord uses
the standard external UnifiedPush distributor protocol and contains no Firebase
dependency or shared ntfy credentials. The selected distributor supplies a
private, high-entropy endpoint. Deltiecord registers that complete endpoint as
the Matrix pushkey through
`https://push.deltie.net/_matrix/push/v1/notify` and keeps it in private Android
preferences. The endpoint is a bearer capability and is never displayed in the
UI or written to logs.

The gateway and distributor receive Matrix push metadata sufficient to wake the
application and display a generic activity notification. Deltiecord obtains
room contents through normal authenticated Matrix sync after the notification is
opened; the push path is not treated as a source of decrypted plaintext.

## Release update checks

User-triggered only. The About page can fetch the bounded JSON release manifest
from `https://deltie.net/cord/releases.json` and open the public releases page.
No automatic update request is made during startup.
