import importlib.util
import pathlib
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).with_name("giphy_proxy.py")
SPEC = importlib.util.spec_from_file_location("giphy_proxy", MODULE_PATH)
PROXY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROXY)


class GiphyProxySecurityTests(unittest.TestCase):
    def setUp(self):
        with PROXY._requests_lock:
            PROXY._requests.clear()
        with PROXY._telegram_cache_lock:
            PROXY._telegram_cache.clear()

    def test_forwarded_address_only_trusted_from_configured_proxy(self):
        self.assertEqual(
            PROXY._client_identity("127.0.0.1", "203.0.113.20"),
            "203.0.113.20",
        )
        self.assertEqual(
            PROXY._client_identity("198.51.100.4", "203.0.113.20"),
            "198.51.100.4",
        )

    def test_invalid_forwarded_address_falls_back_to_peer(self):
        self.assertEqual(
            PROXY._client_identity("127.0.0.1", "not-an-address"),
            "127.0.0.1",
        )

    def test_rate_limit_map_rejects_new_identity_at_capacity(self):
        original = PROXY.MAX_RATE_CLIENTS
        PROXY.MAX_RATE_CLIENTS = 1
        try:
            self.assertTrue(PROXY._allowed("192.0.2.1"))
            self.assertFalse(PROXY._allowed("192.0.2.2"))
        finally:
            PROXY.MAX_RATE_CLIENTS = original

    def test_rate_limits_are_separate_by_service(self):
        self.assertTrue(PROXY._allowed("192.0.2.1", limit=1))
        self.assertFalse(PROXY._allowed("192.0.2.1", limit=1))
        self.assertTrue(
            PROXY._allowed("192.0.2.1", limit=1, namespace="telegram")
        )

    def test_telegram_pack_hides_file_ids_and_skips_animation(self):
        result = {
            "name": "Animals",
            "title": "Animals",
            "stickers": [
                {
                    "file_id": "private-file-id",
                    "width": 512,
                    "height": 420,
                    "file_size": 1234,
                    "is_animated": False,
                    "is_video": False,
                    "emoji": "🐈",
                },
                {
                    "file_id": "animated-file-id",
                    "width": 512,
                    "height": 512,
                    "file_size": 2048,
                    "is_animated": True,
                    "is_video": False,
                },
            ],
        }
        with mock.patch.object(PROXY, "_telegram_request", return_value=result):
            public = PROXY._public_telegram_pack(PROXY._telegram_pack("Animals"))
        self.assertEqual(public["unsupported_count"], 1)
        self.assertEqual(len(public["stickers"]), 1)
        self.assertEqual(public["stickers"][0]["emoji"], "🐈")
        self.assertNotIn("file_id", public["stickers"][0])

    def test_telegram_pack_rejects_oversized_static_media(self):
        result = {
            "name": "Huge",
            "title": "Huge",
            "stickers": [
                {
                    "file_id": "file-id",
                    "width": 512,
                    "height": 512,
                    "file_size": PROXY.MAX_TELEGRAM_STICKER_BYTES + 1,
                    "is_animated": False,
                    "is_video": False,
                }
            ],
        }
        with mock.patch.object(PROXY, "_telegram_request", return_value=result):
            with self.assertRaises(RuntimeError):
                PROXY._telegram_pack("Huge")


if __name__ == "__main__":
    unittest.main()
