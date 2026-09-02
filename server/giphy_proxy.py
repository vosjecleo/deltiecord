#!/usr/bin/env python3
"""Minimal rate-limited GIPHY search proxy for Deltiecord releases."""

from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse
import json
import os
import threading
import time
import urllib.request

HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8091"))
KEY_FILE = os.environ.get("GIPHY_API_KEY_FILE", "/etc/deltiecord/giphy-api-key")
RATE_LIMIT = int(os.environ.get("RATE_LIMIT", "60"))
RATE_WINDOW_SECONDS = 60
MAX_UPSTREAM_BYTES = 2 * 1024 * 1024
VERSION = os.environ.get("DELTIECORD_VERSION", "0.9.25")
_requests = defaultdict(deque)
_requests_lock = threading.Lock()


def _read_key():
    with open(KEY_FILE, "r", encoding="utf-8") as key_file:
        return key_file.read().strip()


def _allowed(client):
    now = time.monotonic()
    with _requests_lock:
        timestamps = _requests[client]
        while timestamps and now - timestamps[0] >= RATE_WINDOW_SECONDS:
            timestamps.popleft()
        if len(timestamps) >= RATE_LIMIT:
            return False
        timestamps.append(now)
        return True


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


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json({"ok": True})
            return
        if parsed.path not in {"/search", "/api/servers/giphy/search"}:
            self._json({"error": "not found"}, 404)
            return
        client = self.headers.get("X-Real-IP", self.client_address[0])
        if not _allowed(client):
            self._json({"error": "rate limit exceeded"}, 429)
            return
        parameters = parse_qs(parsed.query)
        trending = parameters.get("mode", [""])[0] == "trending"
        query = parameters.get("q", [""])[0].strip()
        if (not trending and not query) or len(query) > 100:
            self._json({"error": "invalid query"}, 400)
            return
        try:
            self._json(_giphy_request(None if trending else query))
        except Exception:
            # Upstream details can contain request material; keep them server-side.
            self._json({"error": "GIF search unavailable"}, 502)

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

    def log_message(self, format_string, *args):
        # Avoid query-string logging; it can include user-entered search text.
        print(f"{self.address_string()} - {self.command} {urlparse(self.path).path}")


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
