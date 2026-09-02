import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("giphy_proxy.py")
SPEC = importlib.util.spec_from_file_location("giphy_proxy", MODULE_PATH)
PROXY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROXY)


class GiphyProxySecurityTests(unittest.TestCase):
    def setUp(self):
        with PROXY._requests_lock:
            PROXY._requests.clear()

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


if __name__ == "__main__":
    unittest.main()
