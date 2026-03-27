"""Regression tests for Story 4.6 performance and observability hardening."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server
from src.logging_config import JSONFormatter


class _JSONCaptureHandler(logging.Handler):
    """Capture JSON-formatted log records for assertion-friendly inspection."""

    def __init__(self):
        super().__init__()
        self.setFormatter(JSONFormatter())
        self.entries: list[dict] = []

    def emit(self, record: logging.LogRecord) -> None:
        payload = self.format(record)
        self.entries.append(json.loads(payload))


class MobilePerformanceObservabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.users_file = Path(self.temp_dir.name) / "users.json"

        users = {
            "leaderuser": {
                "password": server._hash_pw("strong-password-123"),
                "role": "admin",
                "display_name": "Leader User",
            },
            "rangeruser": {
                "password": server._hash_pw("safe-ranger-password"),
                "role": "viewer",
                "display_name": "Ranger User",
            },
            "otherranger": {
                "password": server._hash_pw("another-ranger-password"),
                "role": "viewer",
                "display_name": "Other Ranger",
            },
        }
        self.users_file.write_text(json.dumps(users, ensure_ascii=False, indent=2), encoding="utf-8")

        self.users_patch = patch("src.server.USERS_FILE", str(self.users_file))
        self.run_loop_patch = patch("src.server.run_loop", lambda: None)
        self.users_patch.start()
        self.run_loop_patch.start()
        self.addCleanup(self.users_patch.stop)
        self.addCleanup(self.run_loop_patch.stop)

        self.settings = server.get_settings()
        self.original_rate_limit_login = self.settings.rate_limit_login
        self.original_rate_limit_api = self.settings.rate_limit_api
        self.settings.rate_limit_login = "1000/minute"
        self.settings.rate_limit_api = "1000/minute"
        self.addCleanup(self._restore_rate_limits)

        server.sessions.clear()
        server.mobile_access_sessions.clear()
        server.mobile_refresh_sessions.clear()
        server.mobile_schedule_records.clear()
        server.mobile_work_summary_records.clear()
        server.mobile_daily_checkins.clear()
        server.mobile_incident_records.clear()
        self.addCleanup(server.sessions.clear)
        self.addCleanup(server.mobile_access_sessions.clear)
        self.addCleanup(server.mobile_refresh_sessions.clear)
        self.addCleanup(server.mobile_schedule_records.clear)
        self.addCleanup(server.mobile_work_summary_records.clear)
        self.addCleanup(server.mobile_daily_checkins.clear)
        self.addCleanup(server.mobile_incident_records.clear)

        server.mobile_work_summary_records.extend(
            [
                {
                    "ranger_id": "rangeruser",
                    "day_key": "2026-03-19",
                    "has_checkin": True,
                    "summary": {"patrol_count": 1},
                },
                {
                    "ranger_id": "otherranger",
                    "day_key": "2026-03-20",
                    "has_checkin": False,
                    "summary": {"patrol_count": 2},
                },
            ]
        )

        server.mobile_incident_records.extend(
            [
                {
                    "incident_id": "inc-1",
                    "er_event_id": "er-1001",
                    "ranger_id": "rangeruser",
                    "mapping_status": "mapped",
                    "occurred_at": "2026-03-19T01:00:00Z",
                    "updated_at": "2026-03-19T02:00:00Z",
                    "title": "Fence broken",
                    "status": "open",
                    "severity": "medium",
                },
                {
                    "incident_id": "inc-2",
                    "er_event_id": "er-1002",
                    "ranger_id": "otherranger",
                    "mapping_status": "mapped",
                    "occurred_at": "2026-03-20T01:00:00Z",
                    "updated_at": "2026-03-20T03:00:00Z",
                    "title": "Camera alert",
                    "status": "open",
                    "severity": "high",
                },
            ]
        )

        server.mobile_schedule_records.update(
            {
                "seed-1": {
                    "schedule_id": "seed-1",
                    "ranger_id": "rangeruser",
                    "work_date": "2026-03-19",
                    "note": "Morning route",
                    "updated_by": "leaderuser",
                    "created_at": "2026-03-18T10:00:00+00:00",
                    "updated_at": "2026-03-18T10:00:00+00:00",
                },
                "seed-2": {
                    "schedule_id": "seed-2",
                    "ranger_id": "otherranger",
                    "work_date": "2026-03-20",
                    "note": "Bridge watch",
                    "updated_by": "leaderuser",
                    "created_at": "2026-03-19T10:00:00+00:00",
                    "updated_at": "2026-03-19T10:00:00+00:00",
                },
            }
        )

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    def _restore_rate_limits(self):
        self.settings.rate_limit_login = self.original_rate_limit_login
        self.settings.rate_limit_api = self.original_rate_limit_api

    def _login_headers(self, username: str = "leaderuser", password: str = "strong-password-123") -> dict:
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": username, "password": password},
        )
        self.assertEqual(200, response.status_code)
        token = response.json()["access_token"]
        return {"Authorization": f"Bearer {token}"}

    def test_work_management_rejects_excessive_date_window(self):
        headers = self._login_headers()

        response = self.client.get(
            "/api/mobile/work-management",
            params={"from": "2020-01-01", "to": "2026-12-31"},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertIn("Date range exceeds maximum window", response.json()["detail"])

    def test_incidents_rejects_stale_updated_since(self):
        headers = self._login_headers()

        response = self.client.get(
            "/api/mobile/incidents",
            params={"updated_since": "2000-01-01T00:00:00Z"},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertIn("updated_since is too old", response.json()["detail"])

    def test_schedules_rejects_stale_updated_since(self):
        headers = self._login_headers()

        response = self.client.get(
            "/api/mobile/schedules",
            params={"updated_since": "2000-01-01T00:00:00Z"},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertIn("updated_since is too old", response.json()["detail"])

    def test_mobile_endpoint_summary_logs_include_request_scope_and_paging(self):
        headers = self._login_headers()
        headers["X-Request-ID"] = "trace-perf-obs-001"

        capture_handler = _JSONCaptureHandler()
        logger = logging.getLogger("src.server")
        logger.addHandler(capture_handler)
        logger.setLevel(logging.INFO)
        self.addCleanup(lambda: logger.removeHandler(capture_handler))

        response = self.client.get(
            "/api/mobile/work-management",
            params={"from": "2026-03-19", "to": "2026-03-20", "page": 1, "page_size": 10},
            headers=headers,
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual("trace-perf-obs-001", response.headers.get("X-Request-ID"))

        summary_logs = [
            entry
            for entry in capture_handler.entries
            if entry.get("event") == "mobile_endpoint_summary"
            and entry.get("path") == "/api/mobile/work-management"
        ]

        self.assertTrue(summary_logs, "Expected structured mobile endpoint summary log")
        summary = summary_logs[-1]
        self.assertEqual("trace-perf-obs-001", summary.get("request_id"))
        self.assertEqual("leader", summary.get("role"))
        self.assertEqual(2, summary.get("item_count"))
        self.assertEqual(1, summary.get("page"))
        self.assertEqual(10, summary.get("page_size"))


if __name__ == "__main__":
    unittest.main()
