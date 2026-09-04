#!/usr/bin/env python3
"""Minimal rate-limited GIPHY search proxy for Deltiecord releases."""

from collections import OrderedDict, defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import gzip
import ipaddress
import io
from urllib.parse import parse_qs, quote, urlencode, urlparse
import json
import os
import re
import subprocess
import sys
import tempfile
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
TELEGRAM_CONVERT_RATE_LIMIT = int(
    os.environ.get("TELEGRAM_CONVERT_RATE_LIMIT", "120")
)
TELEGRAM_GLOBAL_CONVERT_RATE_LIMIT = int(
    os.environ.get("TELEGRAM_GLOBAL_CONVERT_RATE_LIMIT", "120")
)
MAX_RATE_CLIENTS = int(os.environ.get("MAX_RATE_CLIENTS", "10000"))
MAX_CONCURRENT_REQUESTS = int(os.environ.get("MAX_CONCURRENT_REQUESTS", "32"))
MAX_CONCURRENT_CONVERSIONS = int(
    os.environ.get("MAX_CONCURRENT_CONVERSIONS", "2")
)
TRUSTED_PROXY_NETWORKS = tuple(
    ipaddress.ip_network(value.strip())
    for value in os.environ.get("TRUSTED_PROXY_CIDRS", "127.0.0.0/8,::1/128").split(",")
    if value.strip()
)
RATE_WINDOW_SECONDS = 60
MAX_UPSTREAM_BYTES = 2 * 1024 * 1024
MAX_TELEGRAM_STICKER_BYTES = 1024 * 1024
MAX_TELEGRAM_EMOJI_BYTES = 256 * 1024
MAX_TELEGRAM_TGS_JSON_BYTES = 2 * 1024 * 1024
MAX_TELEGRAM_PACKS = 64
TELEGRAM_CACHE_SECONDS = 300
MAX_CONVERSION_CACHE_ITEMS = 128
MAX_CONVERSION_CACHE_BYTES = 64 * 1024 * 1024
FFMPEG_BIN = os.environ.get("FFMPEG_BIN", "/usr/bin/ffmpeg")
LOTTIE_CONVERT_BIN = os.environ.get(
    "LOTTIE_CONVERT_BIN",
    os.path.join(os.path.dirname(sys.executable), "lottie_convert.py"),
)
PRLIMIT_BIN = os.environ.get("PRLIMIT_BIN", "/usr/bin/prlimit")
VERSION = os.environ.get("DELTIECORD_VERSION", "0.9.27")
_requests = defaultdict(deque)
_requests_lock = threading.Lock()
_request_slots = threading.BoundedSemaphore(MAX_CONCURRENT_REQUESTS)
_conversion_slots = threading.BoundedSemaphore(MAX_CONCURRENT_CONVERSIONS)
_telegram_cache = OrderedDict()
_telegram_cache_lock = threading.Lock()
_conversion_cache = OrderedDict()
_conversion_cache_bytes = 0
_conversion_cache_lock = threading.Lock()


class ConversionBusy(RuntimeError):
    pass


class ConversionUnavailable(RuntimeError):
    pass


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
        source_kind = (
            "tgs"
            if sticker.get("is_animated")
            else "webm"
            if sticker.get("is_video")
            else "static"
        )
        if source_kind != "static" and not _converter_available(source_kind):
            unsupported += 1
            continue
        width = sticker.get("width")
        height = sticker.get("height")
        size = sticker.get("file_size") or 512 * 1024
        file_id = sticker.get("file_id")
        file_unique_id = sticker.get("file_unique_id")
        if (
            not isinstance(file_id, str)
            or not file_id
            or not isinstance(file_unique_id, str)
            or not file_unique_id
            or len(file_unique_id) > 128
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
                "file_unique_id": file_unique_id,
                "source_kind": source_kind,
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


def _fit_dimensions(width, height, maximum):
    scale = min(1.0, maximum / max(width, height))
    return max(1, round(width * scale)), max(1, round(height * scale))


def _public_telegram_pack(pack, converted_size=256):
    return {
        "name": pack["name"],
        "title": pack["title"],
        "unsupported_count": pack["unsupported_count"],
        "stickers": [
            {
                **{
                    key: value
                    for key, value in sticker.items()
                    if key
                    not in {"file_id", "file_unique_id", "source_kind"}
                },
                "animated": sticker["source_kind"] != "static",
                "converted": sticker["source_kind"] != "static",
                **(
                    dict(
                        zip(
                            ("width", "height"),
                            _fit_dimensions(
                                sticker["width"],
                                sticker["height"],
                                converted_size,
                            ),
                        )
                    )
                    if sticker["source_kind"] != "static"
                    else {}
                ),
            }
            for sticker in pack["stickers"]
        ],
    }


def _converter_available(source_kind):
    if not os.path.isfile(PRLIMIT_BIN) or not os.access(PRLIMIT_BIN, os.X_OK):
        return False
    if source_kind == "webm":
        return os.path.isfile(FFMPEG_BIN) and os.access(FFMPEG_BIN, os.X_OK)
    if source_kind == "tgs":
        return os.path.isfile(LOTTIE_CONVERT_BIN) and os.access(
            LOTTIE_CONVERT_BIN, os.X_OK
        )
    return True


def _validate_tgs(body):
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(body)) as archive:
            decoded = archive.read(MAX_TELEGRAM_TGS_JSON_BYTES + 1)
        if len(decoded) > MAX_TELEGRAM_TGS_JSON_BYTES:
            raise RuntimeError("Telegram TGS expands beyond safe limit")
        animation = json.loads(decoded)
        if not isinstance(animation, dict):
            raise RuntimeError("Telegram TGS animation metadata is unsafe")
        width = animation.get("w")
        height = animation.get("h")
        frame_rate = animation.get("fr")
        first_frame = animation.get("ip")
        last_frame = animation.get("op")
        if (
            not isinstance(width, (int, float))
            or not isinstance(height, (int, float))
            or not isinstance(frame_rate, (int, float))
            or not isinstance(first_frame, (int, float))
            or not isinstance(last_frame, (int, float))
            or width <= 0
            or height <= 0
            or width > 512
            or height > 512
            or frame_rate <= 0
            or frame_rate > 60
            or last_frame <= first_frame
            or (last_frame - first_frame) / frame_rate > 3.1
        ):
            raise RuntimeError("Telegram TGS animation metadata is unsafe")
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        raise RuntimeError("invalid Telegram TGS data") from error


def _conversion_limit(converted_size):
    return (
        MAX_TELEGRAM_EMOJI_BYTES
        if converted_size == 128
        else MAX_TELEGRAM_STICKER_BYTES
    )


def _is_animated_webp(body):
    return (
        body.startswith(b"RIFF")
        and body[8:12] == b"WEBP"
        and b"ANIM" in body
        and b"ANMF" in body
    )


def _conversion_cache_get(key):
    with _conversion_cache_lock:
        value = _conversion_cache.get(key)
        if value is not None:
            _conversion_cache.move_to_end(key)
        return value


def _conversion_cache_put(key, value):
    global _conversion_cache_bytes
    with _conversion_cache_lock:
        previous = _conversion_cache.pop(key, None)
        if previous is not None:
            _conversion_cache_bytes -= len(previous)
        _conversion_cache[key] = value
        _conversion_cache_bytes += len(value)
        while (
            len(_conversion_cache) > MAX_CONVERSION_CACHE_ITEMS
            or _conversion_cache_bytes > MAX_CONVERSION_CACHE_BYTES
        ):
            _, removed = _conversion_cache.popitem(last=False)
            _conversion_cache_bytes -= len(removed)


def _conversion_command(source_kind, source, output, converted_size, quality):
    limit = _conversion_limit(converted_size)
    resource_limits = [
        PRLIMIT_BIN,
        f"--fsize={limit * 2}",
        "--cpu=15",
        "--as=536870912",
        "--nofile=64",
    ]
    if source_kind == "tgs":
        command = [
            LOTTIE_CONVERT_BIN,
            source,
            output,
            "--fps",
            "20" if quality >= 60 else "15",
            "--width",
            str(converted_size),
            "--height",
            str(converted_size),
            "--webp-quality",
            str(quality),
            "--webp-method",
            "4",
        ]
        if quality < 60:
            command.extend(["--webp-skip-frames", "1"])
        return resource_limits + ["--"] + command
    if source_kind == "webm":
        return resource_limits + [
            "--",
            FFMPEG_BIN,
            "-v",
            "error",
            "-nostdin",
            "-threads",
            "1",
            "-c:v",
            "libvpx-vp9",
            "-i",
            source,
            "-t",
            "3.1",
            "-an",
            "-vf",
            (
                f"fps={'20' if quality >= 60 else '15'},"
                f"scale={converted_size}:{converted_size}:"
                "force_original_aspect_ratio=decrease:flags=lanczos"
            ),
            "-c:v",
            "libwebp_anim",
            "-lossless",
            "0",
            "-quality",
            str(quality),
            "-compression_level",
            "4",
            "-loop",
            "0",
            "-y",
            output,
        ]
    raise ConversionUnavailable("unsupported Telegram animation format")


def _convert_telegram_sticker(body, sticker, converted_size):
    source_kind = sticker["source_kind"]
    if not _converter_available(source_kind):
        raise ConversionUnavailable("Telegram animation conversion unavailable")
    cache_key = (sticker["file_unique_id"], converted_size)
    cached = _conversion_cache_get(cache_key)
    if cached is not None:
        return cached
    if not _conversion_slots.acquire(timeout=2):
        raise ConversionBusy("Telegram animation conversion busy")
    try:
        cached = _conversion_cache_get(cache_key)
        if cached is not None:
            return cached
        suffix = ".tgs" if source_kind == "tgs" else ".webm"
        with tempfile.TemporaryDirectory(prefix="deltiecord-sticker-") as work:
            source = os.path.join(work, "source" + suffix)
            output = os.path.join(work, "converted.webp")
            with open(source, "xb") as source_file:
                source_file.write(body)
            limit = _conversion_limit(converted_size)
            for quality in (72, 52):
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass
                try:
                    subprocess.run(
                        _conversion_command(
                            source_kind,
                            source,
                            output,
                            converted_size,
                            quality,
                        ),
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=True,
                        timeout=18,
                        env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
                    )
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    continue
                try:
                    size = os.path.getsize(output)
                except FileNotFoundError:
                    continue
                if 0 < size <= limit:
                    with open(output, "rb") as converted_file:
                        converted = converted_file.read(limit + 1)
                    if (
                        len(converted) <= limit
                        and _is_animated_webp(converted)
                    ):
                        _conversion_cache_put(cache_key, converted)
                        return converted
            raise RuntimeError("converted Telegram sticker exceeds size limit")
    finally:
        _conversion_slots.release()


def _telegram_sticker(set_name, index, converted_size=256):
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
    source_kind = sticker["source_kind"]
    if source_kind == "tgs":
        if not body.startswith(b"\x1f\x8b"):
            raise RuntimeError("unexpected Telegram animated sticker format")
        _validate_tgs(body)
        return _convert_telegram_sticker(body, sticker, converted_size), "image/webp"
    if source_kind == "webm":
        if not body.startswith(b"\x1aE\xdf\xa3"):
            raise RuntimeError("unexpected Telegram video sticker format")
        return _convert_telegram_sticker(body, sticker, converted_size), "image/webp"
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
            self._handle_telegram(parsed, telegram_file, client)
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

    def _handle_telegram(self, parsed, file_request, client):
        parameters = parse_qs(parsed.query)
        set_name = parameters.get("set", [""])[0]
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", set_name):
            self._json({"error": "invalid sticker set"}, 400)
            return
        index = None
        try:
            converted_size = int(parameters.get("size", ["256"])[0])
        except ValueError:
            converted_size = 0
        if converted_size not in {128, 256}:
            self._json({"error": "invalid converted sticker size"}, 400)
            return
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
                pack = _telegram_pack(set_name)
                sticker = next(
                    (item for item in pack["stickers"] if item["index"] == index),
                    None,
                )
                if sticker is None:
                    raise LookupError("sticker not found")
                if sticker["source_kind"] != "static" and not _allowed(
                    client, TELEGRAM_CONVERT_RATE_LIMIT, "telegram-convert"
                ):
                    self._json({"error": "conversion rate limit exceeded"}, 429)
                    return
                if sticker["source_kind"] != "static" and not _allowed(
                    "all-clients",
                    TELEGRAM_GLOBAL_CONVERT_RATE_LIMIT,
                    "telegram-convert-global",
                ):
                    self._json({"error": "conversion capacity exceeded"}, 503)
                    return
                body, content_type = _telegram_sticker(
                    set_name, index, converted_size
                )
                self._bytes(body, content_type)
            else:
                self._json(
                    _public_telegram_pack(
                        _telegram_pack(set_name), converted_size
                    )
                )
        except FileNotFoundError:
            self._json({"error": "Telegram import is not configured"}, 503)
        except LookupError:
            self._json({"error": "sticker not found"}, 404)
        except ConversionBusy:
            self._json({"error": "sticker conversion busy"}, 503)
        except ConversionUnavailable:
            self._json({"error": "sticker conversion unavailable"}, 503)
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
