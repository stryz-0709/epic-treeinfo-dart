"""Regression tests for Story 4.6 request-id observability hardening."""

import re
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server


class RequestIDObservabilityTests(unittest.TestCase):
    def setUp(self):
        self.run_loop_patch = patch("src.server.run_loop", lambda: None)
        self.run_loop_patch.start()
        self.addCleanup(self.run_loop_patch.stop)

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    def test_generates_request_id_header_when_missing(self):
        response = self.client.get("/health")

        self.assertEqual(200, response.status_code)
        request_id = response.headers.get("X-Request-ID")
        self.assertIsNotNone(request_id)
        self.assertRegex(request_id, r"^[a-f0-9]{12}$")
        self.assertEqual("-", server.get_request_id())

    def test_preserves_valid_request_id_header(self):
        custom_request_id = "trace-abc123.DEF:456"

        response = self.client.get(
            "/health",
            headers={"X-Request-ID": custom_request_id},
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual(custom_request_id, response.headers.get("X-Request-ID"))
        self.assertEqual("-", server.get_request_id())

    def test_invalid_request_id_header_is_replaced(self):
        invalid_request_id = " bad request id with spaces "

        response = self.client.get(
            "/health",
            headers={"X-Request-ID": invalid_request_id},
        )

        self.assertEqual(200, response.status_code)
        request_id = response.headers.get("X-Request-ID")
        self.assertIsNotNone(request_id)
        self.assertNotEqual(invalid_request_id.strip(), request_id)
        self.assertRegex(request_id, r"^[a-f0-9]{12}$")
        self.assertEqual("-", server.get_request_id())

    def test_error_response_includes_request_id_header(self):
        response = self.client.get("/api/mobile/work-management")

        self.assertEqual(401, response.status_code)
        request_id = response.headers.get("X-Request-ID")
        self.assertIsNotNone(request_id)
        self.assertTrue(bool(re.fullmatch(r"[A-Za-z0-9._:-]+", request_id)))

    def test_request_logs_include_structured_performance_fields(self):
        with patch("src.server.log.info") as log_info_mock:
            response = self.client.get(
                "/health",
                headers={"X-Request-ID": "trace-health-001"},
            )

        self.assertEqual(200, response.status_code)

        matching_extras = [
            call.kwargs.get("extra", {})
            for call in log_info_mock.call_args_list
            if isinstance(call.kwargs.get("extra", {}), dict)
            and call.kwargs.get("extra", {}).get("path") == "/health"
        ]

        self.assertTrue(matching_extras)
        extra = matching_extras[0]
        self.assertEqual("GET", extra.get("method"))
        self.assertEqual(200, extra.get("status_code"))
        self.assertIn("duration_ms", extra)
        self.assertIn("client_ip", extra)

    def test_slow_request_warning_uses_configured_threshold(self):
        original_threshold = server._s.request_slow_threshold_ms
        server._s.request_slow_threshold_ms = 0.001
        self.addCleanup(
            setattr,
            server._s,
            "request_slow_threshold_ms",
            original_threshold,
        )

        with patch("src.server.log.warning") as log_warning_mock:
            response = self.client.get(
                "/health",
                headers={"X-Request-ID": "trace-health-slow"},
            )

        self.assertEqual(200, response.status_code)

        matching_extras = [
            call.kwargs.get("extra", {})
            for call in log_warning_mock.call_args_list
            if isinstance(call.kwargs.get("extra", {}), dict)
            and call.kwargs.get("extra", {}).get("path") == "/health"
        ]

        self.assertTrue(matching_extras)
        extra = matching_extras[0]
        self.assertEqual("GET", extra.get("method"))
        self.assertEqual(200, extra.get("status_code"))
        self.assertIn("duration_ms", extra)
        self.assertIn("slow_threshold_ms", extra)


if __name__ == "__main__":
    unittest.main()
