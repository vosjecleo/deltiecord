#!/usr/bin/env python3
"""Minimal rate-limited GIPHY search proxy for Deltiecord releases."""

from collections import OrderedDict, defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
from urllib.parse import parse_qs, quote, urlencode, urlparse
import json
import os
import re
import threading
import time
import urllib.request

HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8091"))
KEY_FILE = os.environ.get("GIPHY_API_KEY_FILE", "/etc/deltiecord/giphy-api-key")
TELEGRAM_TOKEN_FILE = os.environ.get(
    "TELEGRAM_BOT_TOKEN_FILE", "/etc/deltiecord/telegram-bot-token"
)
RATE_LIMIT = int(os.environ.get("RATE_LIMIT", "60"))
TELEGRAM_RATE_LIMIT = int(os.environ.get("TELEGRAM_RATE_LIMIT", "240"))
MAX_RATE_CLIENTS = int(os.environ.get("MAX_RATE_CLIENTS", "10000"))
MAX_CONCURRENT_REQUESTS = int(os.environ.get("MAX_CONCURRENT_REQUESTS", "32"))
TRUSTED_PROXY_NETWORKS = tuple(
    ipaddress.ip_network(value.strip())
    for value in os.environ.get("TRUSTED_PROXY_CIDRS", "127.0.0.0/8,::1/128").split(",")
    if value.strip()
)
RATE_WINDOW_SECONDS = 60
MAX_UPSTREAM_BYTES = 2 * 1024 * 1024
MAX_TELEGRAM_STICKER_BYTES = 1024 * 1024
MAX_TELEGRAM_PACKS = 64
TELEGRAM_CACHE_SECONDS = 300
VERSION = os.environ.get("DELTIECORD_VERSION", "0.9.27")
_requests = defaultdict(deque)
_requests_lock = threading.Lock()
_request_slots = threading.BoundedSemaphore(MAX_CONCURRENT_REQUESTS)
_telegram_cache = OrderedDict()
_telegram_cache_lock = threading.Lock()


def _read_key():
    with open(KEY_FILE, "r", encoding="utf-8") as key_file:
        return key_file.read().strip()


def _allowed(client, limit=RATE_LIMIT, namespace="giphy"):
    now = time.monotonic()
    identity = f"{namespace}:{client}"
    with _requests_lock:
        # Expired buckets are removed before admitting a new identity, keeping
        # spoofed/high-cardinality input from growing the map without bound.
        for bucket_identity in list(_requests):
            bucket = _requests[bucket_identity]
            while bucket and now - bucket[0] >= RATE_WINDOW_SECONDS:
                bucket.popleft()
            if not bucket:
                del _requests[bucket_identity]
        if identity not in _requests and len(_requests) >= MAX_RATE_CLIENTS:
            return False
        timestamps = _requests[identity]
        while timestamps and now - timestamps[0] >= RATE_WINDOW_SECONDS:
            timestamps.popleft()
        if len(timestamps) >= limit:
            return False
        timestamps.append(now)
        return True


def _client_identity(peer, forwarded):
    try:
        peer_address = ipaddress.ip_address(peer)
    except ValueError:
        return peer
    if not any(peer_address in network for network in TRUSTED_PROXY_NETWORKS):
        return peer
    if not forwarded:
        return peer
    candidate = forwarded.split(",", 1)[0].strip()
    try:
        return str(ipaddress.ip_address(candidate))
    except ValueError:
        return peer


def _giphy_request(query=None):
    parameters = {
        "api_key": _read_key(),
        "limit": 24,
        "rating": "pg-13",
    }
    endpoint = "trending" if query is None else "search"
    if query is not None:
        parameters.update({"q": query, "lang": "en"})
    params = urlencode(parameters)
    request = urllib.request.Request(
        f"https://api.giphy.com/v1/gifs/{endpoint}?" + params,
        headers={"User-Agent": f"Deltiecord-Giphy-Proxy/{VERSION}"},
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        if response.status != 200:
            raise RuntimeError("unexpected GIPHY status")
        content_type = response.headers.get_content_type()
        if content_type != "application/json":
            raise RuntimeError("unexpected GIPHY content type")
        declared_length = response.headers.get("Content-Length")
        if declared_length and int(declared_length) > MAX_UPSTREAM_BYTES:
            raise RuntimeError("GIPHY response too large")
        body = response.read(MAX_UPSTREAM_BYTES + 1)
        if len(body) > MAX_UPSTREAM_BYTES:
            raise RuntimeError("GIPHY response too large")
        return json.loads(body)


def _telegram_request(method, parameters):
    token = _read_secret(TELEGRAM_TOKEN_FILE)
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/{method}?" + urlencode(parameters),
        headers={"User-Agent": f"Deltiecord-Telegram-Proxy/{VERSION}"},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 200 or response.headers.get_content_type() != "application/json":
            raise RuntimeError("unexpected Telegram status")
        body = response.read(MAX_UPSTREAM_BYTES + 1)
        if len(body) > MAX_UPSTREAM_BYTES:
            raise RuntimeError("Telegram response too large")
        decoded = json.loads(body)
        if decoded.get("ok") is not True:
            raise RuntimeError("Telegram request failed")
        return decoded["result"]


def _read_secret(path):
    with open(path, "r", encoding="utf-8") as secret_file:
        value = secret_file.read().strip()
    if not value:
        raise RuntimeError("secret is empty")
    return value


def _telegram_pack(set_name):
    now = time.monotonic()
    with _telegram_cache_lock:
        cached = _telegram_cache.get(set_name)
        if cached and now - cached[0] < TELEGRAM_CACHE_SECONDS:
            _telegram_cache.move_to_end(set_name)
            return cached[1]
        if cached:
            del _telegram_cache[set_name]

    result = _telegram_request("getStickerSet", {"name": set_name})
    stickers = result.get("stickers", [])
    if not isinstance(stickers, list) or len(stickers) > 120:
        raise RuntimeError("invalid Telegram pack size")
    supported = []
    unsupported = 0
    for index, sticker in enumerate(stickers):
        if not isinstance(sticker, dict):
            raise RuntimeError("invalid Telegram sticker")
        if sticker.get("is_animated") or sticker.get("is_video"):
            unsupported += 1
            continue
        width = sticker.get("width")
        height = sticker.get("height")
        size = sticker.get("file_size") or 512 * 1024
        file_id = sticker.get("file_id")
        if (
            not isinstance(file_id, str)
            or not file_id
            or not isinstance(width, int)
            or not isinstance(height, int)
            or not isinstance(size, int)
            or width <= 0
            or height <= 0
            or width > 512
            or height > 512
            or size <= 0
            or size > MAX_TELEGRAM_STICKER_BYTES
        ):
            raise RuntimeError("invalid Telegram sticker metadata")
        supported.append(
            {
                "index": index,
                "emoji": str(sticker.get("emoji") or "")[:16],
                "mime_type": "image/webp",
                "width": width,
                "height": height,
                "size": size,
                "file_id": file_id,
            }
        )
    pack = {
        "name": str(result.get("name") or set_name)[:64],
        "title": str(result.get("title") or set_name)[:80],
        "stickers": supported,
        "unsupported_count": unsupported,
    }
    with _telegram_cache_lock:
        _telegram_cache[set_name] = (now, pack)
        _telegram_cache.move_to_end(set_name)
        while len(_telegram_cache) > MAX_TELEGRAM_PACKS:
            _telegram_cache.popitem(last=False)
    return pack


def _public_telegram_pack(pack):
    return {
        "name": pack["name"],
        "title": pack["title"],
        "unsupported_count": pack["unsupported_count"],
        "stickers": [
            {key: value for key, value in sticker.items() if key != "file_id"}
            for sticker in pack["stickers"]
        ],
    }


def _telegram_sticker(set_name, index):
    pack = _telegram_pack(set_name)
    sticker = next(
        (item for item in pack["stickers"] if item["index"] == index), None
    )
    if sticker is None:
        raise LookupError("sticker not found")
    file_info = _telegram_request("getFile", {"file_id": sticker["file_id"]})
    file_path = file_info.get("file_path")
    if not isinstance(file_path, str) or not file_path:
        raise RuntimeError("invalid Telegram file")
    token = _read_secret(TELEGRAM_TOKEN_FILE)
    request = urllib.request.Request(
        f"https://api.telegram.org/file/bot{token}/{quote(file_path, safe='/')}",
        headers={"User-Agent": f"Deltiecord-Telegram-Proxy/{VERSION}"},
    )
    with urllib.request.urlopen(request, timeout=12) as response:
        if response.status != 200:
            raise RuntimeError("unexpected Telegram file status")
        body = response.read(MAX_TELEGRAM_STICKER_BYTES + 1)
        if len(body) > MAX_TELEGRAM_STICKER_BYTES:
            raise RuntimeError("Telegram sticker too large")
    if body.startswith(b"\x89PNG\r\n\x1a\n"):
        return body, "image/png"
    if body.startswith(b"RIFF") and body[8:12] == b"WEBP":
        return body, "image/webp"
    raise RuntimeError("unexpected Telegram sticker format")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json({"ok": True})
            return
        telegram_list = parsed.path in {
            "/telegram/stickers",
            "/api/servers/telegram/stickers",
        }
        telegram_file = parsed.path in {
            "/telegram/stickers/file",
            "/api/servers/telegram/stickers/file",
        }
        if not telegram_list and not telegram_file and parsed.path not in {
            "/search",
            "/api/servers/giphy/search",
        }:
            self._json({"error": "not found"}, 404)
            return
        client = _client_identity(
            self.client_address[0],
            self.headers.get("X-Real-IP") or self.headers.get("X-Forwarded-For"),
        )
        if telegram_list or telegram_file:
            if not _allowed(client, TELEGRAM_RATE_LIMIT, "telegram"):
                self._json({"error": "rate limit exceeded"}, 429)
                return
            self._handle_telegram(parsed, telegram_file)
            return
        if not _allowed(client):
            self._json({"error": "rate limit exceeded"}, 429)
            return
        parameters = parse_qs(parsed.query)
        trending = parameters.get("mode", [""])[0] == "trending"
        query = parameters.get("q", [""])[0].strip()
        if (not trending and not query) or len(query) > 100:
            self._json({"error": "invalid query"}, 400)
            return
        if not _request_slots.acquire(blocking=False):
            self._json({"error": "GIF search busy"}, 503)
            return
        try:
            self._json(_giphy_request(None if trending else query))
        except Exception:
            # Upstream details can contain request material; keep them server-side.
            self._json({"error": "GIF search unavailable"}, 502)
        finally:
            _request_slots.release()

    def _handle_telegram(self, parsed, file_request):
        parameters = parse_qs(parsed.query)
        set_name = parameters.get("set", [""])[0]
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", set_name):
            self._json({"error": "invalid sticker set"}, 400)
            return
        index = None
        if file_request:
            try:
                index = int(parameters.get("index", [""])[0])
            except ValueError:
                self._json({"error": "invalid sticker index"}, 400)
                return
            if index < 0 or index >= 120:
                self._json({"error": "invalid sticker index"}, 400)
                return
        if not _request_slots.acquire(blocking=False):
            self._json({"error": "sticker import busy"}, 503)
            return
        try:
            if file_request:
                body, content_type = _telegram_sticker(set_name, index)
                self._bytes(body, content_type)
            else:
                self._json(_public_telegram_pack(_telegram_pack(set_name)))
        except FileNotFoundError:
            self._json({"error": "Telegram import is not configured"}, 503)
        except LookupError:
            self._json({"error": "sticker not found"}, 404)
        except Exception:
            # Bot credentials and upstream URLs must never reach clients/logs.
            self._json({"error": "Telegram sticker import unavailable"}, 502)
        finally:
            _request_slots.release()

    def _json(self, payload, status=200):
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        if len(body) > MAX_UPSTREAM_BYTES:
            payload = {"error": "GIF search response too large"}
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            status = 502
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _bytes(self, body, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "public, max-age=86400")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        # Avoid query-string logging; it can include user-entered search text.
        print(f"{self.address_string()} - {self.command} {urlparse(self.path).path}")


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
