# Networking and privacy

Deltiecord intentionally limits the network destinations it contacts.

## Configured Matrix homeserver

Automatic after login. Sync, authentication, room state, profile data, search,
media, encryption backup, and homeserver URL-preview requests go to the user's
configured homeserver. Federation is performed by homeservers and is not a
separate client connection.

Message link previews use only the Matrix homeserver preview endpoint. If the
homeserver cannot produce a preview, Deltiecord shows the plain link. It does
not automatically contact an arbitrary message URL from the user's IP address.

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

Older builds included direct webpage/FxTwitter preview fallbacks. They are not
used. Arbitrary webpages are never contacted automatically for preview data.
