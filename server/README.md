# Deltiecord service helpers

`giphy_proxy.py` is the dependency-free reference deployment for shared GIF
search and trending results. Keep the GIPHY key in a root/service-user-readable file with mode
`0600`, run the service on loopback, and expose only its `/search` endpoint
through an HTTPS reverse proxy. The production endpoint is rate-limited and
does not return or log the shared key. Clients request trending results from
the same endpoint with `mode=trending`.

The desktop client defaults to
`https://deltie.net/api/servers/giphy/search`. Alternative deployments can set
`GIPHY_PROXY_URL` at build time; this value is an ordinary public URL, not a
secret.
