"""Unit tests for bridge_py.ssl_certs (Linux-safe; no live network)."""
from __future__ import annotations

import os
import ssl
import unittest
from unittest import mock


class TestSslCertsConfigure(unittest.TestCase):
    def setUp(self):
        # Isolate env so user CA overrides don't leak into assertions.
        self._env = os.environ.copy()
        for k in ("SSL_CERT_FILE", "REQUESTS_CA_BUNDLE"):
            os.environ.pop(k, None)
        self._prev_ctx = ssl._create_default_https_context

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._env)
        ssl._create_default_https_context = self._prev_ctx
        # Reset module globals so later tests see a clean helper.
        from bridge_py import ssl_certs

        ssl_certs._configured = False
        ssl_certs._ca_path = None

    def test_configure_sets_env_and_default_context(self):
        import certifi
        from bridge_py import ssl_certs

        path = ssl_certs.configure()
        self.assertEqual(path, certifi.where())
        self.assertEqual(os.environ["SSL_CERT_FILE"], path)
        self.assertEqual(os.environ["REQUESTS_CA_BUNDLE"], path)
        self.assertTrue(ssl_certs.is_configured())
        self.assertEqual(ssl_certs.last_ca_path(), path)

        ctx = ssl._create_default_https_context()
        # Default context should be able to verify against our CA file.
        self.assertIsInstance(ctx, ssl.SSLContext)
        # Spot-check that the factory still returns a context when called again.
        ctx2 = ssl.create_default_context(cafile=path)
        self.assertIsInstance(ctx2, ssl.SSLContext)

    def test_configure_respects_existing_env(self):
        from bridge_py import ssl_certs

        os.environ["SSL_CERT_FILE"] = "/custom/ca.pem"
        os.environ["REQUESTS_CA_BUNDLE"] = "/custom/bundle.pem"
        path = ssl_certs.configure()
        self.assertEqual(os.environ["SSL_CERT_FILE"], "/custom/ca.pem")
        self.assertEqual(os.environ["REQUESTS_CA_BUNDLE"], "/custom/bundle.pem")
        # Patch still points at certifi path for urllib.
        self.assertEqual(path, ssl_certs.ca_bundle_path())

    def test_ca_bundle_path_uses_certifi(self):
        import certifi
        from bridge_py import ssl_certs

        with mock.patch.object(certifi, "where", return_value="/mocked/cacert.pem"):
            self.assertEqual(ssl_certs.ca_bundle_path(), "/mocked/cacert.pem")


if __name__ == "__main__":
    unittest.main()
