"""Regression tests for Story 2.1 mobile work-management summary endpoint."""

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server


class MobileWorkManagementTests(unittest.TestCase):
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
        server.mobile_incident_records.clear()
        server.mobile_schedule_sequence = 0
        self.addCleanup(server.sessions.clear)
        self.addCleanup(server.mobile_access_sessions.clear)
        self.addCleanup(server.mobile_refresh_sessions.clear)
        self.addCleanup(server.mobile_schedule_records.clear)
        self.addCleanup(server.mobile_work_summary_records.clear)
        self.addCleanup(server.mobile_incident_records.clear)
        self.addCleanup(self._reset_schedule_sequence)

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

        server.mobile_work_summary_records.extend(
            [
                {
                    "ranger_id": "rangeruser",
                    "day_key": "2026-03-18",
                    "has_checkin": True,
                    "summary": {"patrol_count": 1},
                },
                {
                    "ranger_id": "rangeruser",
                    "day_key": "2026-03-19",
                    "has_checkin": False,
                    "summary": {"patrol_count": 0},
                },
                {
                    "ranger_id": "otherranger",
                    "day_key": "2026-03-19",
                    "has_checkin": True,
                    "summary": {"patrol_count": 2},
                },
                {
                    "ranger_id": "otherranger",
                    "day_key": "2026-03-20",
                    "has_checkin": False,
                    "summary": {"patrol_count": 1},
                },
            ]
        )

    def _restore_rate_limits(self):
        self.settings.rate_limit_login = self.original_rate_limit_login
        self.settings.rate_limit_api = self.original_rate_limit_api

    def _reset_schedule_sequence(self):
        server.mobile_schedule_sequence = 0

    def _login_headers(self, username: str, password: str) -> dict:
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": username, "password": password},
        )
        self.assertEqual(200, response.status_code)
        token = response.json()["access_token"]
        return {"Authorization": f"Bearer {token}"}

    def test_ranger_self_scope_and_cross_ranger_denial(self):
        headers = self._login_headers("rangeruser", "safe-ranger-password")

        denied = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "otherranger"},
            headers=headers,
        )
        self.assertEqual(403, denied.status_code)
        self.assertEqual({"detail": "Ranger scope violation"}, denied.json())

        allowed = self.client.get("/api/mobile/work-management", headers=headers)
        self.assertEqual(200, allowed.status_code)
        payload = allowed.json()

        self.assertEqual("ranger", payload["scope"]["role"])
        self.assertFalse(payload["scope"]["team_scope"])
        self.assertEqual("rangeruser", payload["scope"]["effective_ranger_id"])
        self.assertEqual(2, payload["pagination"]["total"])
        self.assertEqual(2, len(payload["items"]))

        self.assertIn("has_checkin", payload["items"][0])
        self.assertIn("checkin_indicator", payload["items"][0])

    def test_leader_team_scope_and_ranger_filter(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        team_scope = self.client.get("/api/mobile/work-management", headers=headers)
        self.assertEqual(200, team_scope.status_code)
        team_payload = team_scope.json()

        self.assertEqual("leader", team_payload["scope"]["role"])
        self.assertTrue(team_payload["scope"]["team_scope"])
        self.assertIsNone(team_payload["scope"]["effective_ranger_id"])
        self.assertEqual(4, team_payload["pagination"]["total"])

        filtered = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "otherranger"},
            headers=headers,
        )
        self.assertEqual(200, filtered.status_code)
        filtered_payload = filtered.json()

        self.assertFalse(filtered_payload["scope"]["team_scope"])
        self.assertEqual("otherranger", filtered_payload["scope"]["effective_ranger_id"])
        self.assertEqual(2, filtered_payload["pagination"]["total"])
        self.assertTrue(all(item["ranger_id"] == "otherranger" for item in filtered_payload["items"]))

    def test_date_filters_and_pagination_metadata(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        filtered = self.client.get(
            "/api/mobile/work-management",
            params={"from": "2026-03-19", "to": "2026-03-20", "page": 1, "page_size": 1},
            headers=headers,
        )
        self.assertEqual(200, filtered.status_code)
        payload = filtered.json()

        self.assertEqual("2026-03-19", payload["filters"]["from"])
        self.assertEqual("2026-03-20", payload["filters"]["to"])
        self.assertEqual(1, payload["pagination"]["page"])
        self.assertEqual(1, payload["pagination"]["page_size"])
        self.assertEqual(3, payload["pagination"]["total"])
        self.assertEqual(3, payload["pagination"]["total_pages"])
        self.assertEqual(1, len(payload["items"]))

        self.assertIn(payload["items"][0]["checkin_indicator"], {"confirmed", "none"})

    def test_invalid_date_range_returns_400(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/work-management",
            params={"from": "2026-03-21", "to": "2026-03-20"},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual({"detail": "Invalid date range: from must be <= to"}, response.json())

    def test_malformed_day_key_rows_are_ignored(self):
        server.mobile_work_summary_records.append(
            {
                "ranger_id": "rangeruser",
                "day_key": "not-a-day",
                "has_checkin": True,
                "summary": {"patrol_count": 9},
            }
        )

        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get("/api/mobile/work-management", headers=headers)

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual(4, payload["pagination"]["total"])
        self.assertTrue(all(item["day_key"] != "not-a-day" for item in payload["items"]))

    def test_invalid_session_claims_return_401(self):
        headers = self._login_headers("leaderuser", "strong-password-123")
        access_token = headers["Authorization"].split(" ", 1)[1]
        server.mobile_access_sessions[access_token]["role"] = None

        response = self.client.get("/api/mobile/work-management", headers=headers)

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid access token"}, response.json())

    def test_malformed_access_session_payload_returns_401(self):
        headers = self._login_headers("leaderuser", "strong-password-123")
        access_token = headers["Authorization"].split(" ", 1)[1]
        server.mobile_access_sessions[access_token] = "malformed-session"

        response = self.client.get("/api/mobile/work-management", headers=headers)

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid access token"}, response.json())

    def test_duplicate_rows_dedup_and_checkin_flag_coercion(self):
        server.mobile_work_summary_records.append(
            {
                "ranger_id": "rangeruser",
                "day_key": "2026-03-19",
                "has_checkin": "false",
                "summary": {"late_checkin": 1},
            }
        )
        server.mobile_work_summary_records.append(
            {
                "ranger_id": "rangeruser",
                "day_key": "2026-03-21",
                "has_checkin": "false",
                "summary": {"patrol_count": 3},
            }
        )

        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "rangeruser"},
            headers=headers,
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual(3, payload["pagination"]["total"])

        day_2026_03_19 = [item for item in payload["items"] if item["day_key"] == "2026-03-19"]
        self.assertEqual(1, len(day_2026_03_19))
        self.assertFalse(day_2026_03_19[0]["has_checkin"])
        self.assertEqual("none", day_2026_03_19[0]["checkin_indicator"])

        day_2026_03_21 = [item for item in payload["items"] if item["day_key"] == "2026-03-21"]
        self.assertEqual(1, len(day_2026_03_21))
        self.assertFalse(day_2026_03_21[0]["has_checkin"])
        self.assertEqual("none", day_2026_03_21[0]["checkin_indicator"])

    def test_page_above_total_pages_returns_400(self):
        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get(
            "/api/mobile/work-management",
            params={"page": 99, "page_size": 2},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual({"detail": "Invalid pagination: page exceeds total_pages"}, response.json())

    def test_empty_result_page_above_one_returns_400(self):
        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get(
            "/api/mobile/work-management",
            params={"from": "2030-01-01", "to": "2030-01-02", "page": 2, "page_size": 10},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual({"detail": "Invalid pagination: page exceeds total_pages"}, response.json())

    def test_non_dict_rows_are_ignored_defensively(self):
        server.mobile_work_summary_records.append(None)
        server.mobile_work_summary_records.append("unexpected-row")

        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get("/api/mobile/work-management", headers=headers)

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual(4, payload["pagination"]["total"])

    def test_has_checkin_null_falls_back_to_checkin_confirmed(self):
        server.mobile_work_summary_records.append(
            {
                "ranger_id": "rangeruser",
                "day_key": "2026-03-22",
                "has_checkin": None,
                "checkin_confirmed": True,
                "summary": {"patrol_count": 4},
            }
        )

        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "rangeruser"},
            headers=headers,
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()

        item = next(entry for entry in payload["items"] if entry["day_key"] == "2026-03-22")
        self.assertTrue(item["has_checkin"])
        self.assertEqual("confirmed", item["checkin_indicator"])

    def test_empty_result_page_one_returns_total_pages_one(self):
        headers = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get(
            "/api/mobile/work-management",
            params={"from": "2030-01-01", "to": "2030-01-02", "page": 1, "page_size": 10},
            headers=headers,
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual(0, payload["pagination"]["total"])
        self.assertEqual(1, payload["pagination"]["total_pages"])


if __name__ == "__main__":
    unittest.main()
