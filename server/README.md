# Deltiecord service helpers

`giphy_proxy.py` is the dependency-free reference deployment for shared GIF
search and trending results. Keep the GIPHY key in a root/service-user-readable file with mode
`0600`, run the service on loopback, and expose only its `/search` endpoint
through an HTTPS reverse proxy. The production endpoint is rate-limited and
does not return or log the shared key. Clients request trending results from
the same endpoint with `mode=trending`.

Set `TRUSTED_PROXY_CIDRS` to the explicit reverse-proxy networks allowed to
supply `X-Real-IP`/`X-Forwarded-For`; the default trusts loopback only. Direct
clients cannot spoof those headers. `MAX_RATE_CLIENTS` bounds rate-limit state
and `MAX_CONCURRENT_REQUESTS` bounds upstream worker concurrency. Deploy one
process per configured capacity or put a shared limiter in front of multiple
processes; the in-process limits are intentionally not distributed.

The desktop client defaults to
`https://deltie.net/api/servers/giphy/search`. Alternative deployments can set
`GIPHY_PROXY_URL` at build time; this value is an ordinary public URL, not a
secret.

The same process optionally exposes public Telegram sticker-set imports at
`/api/servers/telegram/stickers`. Put a dedicated Telegram bot token in
`/etc/deltiecord/telegram-bot-token` with mode `0600`, or set
`TELEGRAM_BOT_TOKEN_FILE` to another private file. Clients submit only a
validated public sticker-set short name; the proxy resolves Bot API file IDs
and never returns its bot token or Telegram file URLs. Static PNG/WebP media is
bounded to 1 MiB per item, sets to 120 entries, upstream concurrency to the
shared request semaphore, and metadata caching to 64 sets for five minutes.
Animated TGS and WebM sets are reported but not proxied yet.

`TELEGRAM_RATE_LIMIT` defaults to 240 requests per client per minute so four
bounded client download workers can import a full 120-item set. Place a shared
limiter in front when running multiple proxy processes; like the GIPHY limiter,
this process-local limit is intentionally not distributed.
