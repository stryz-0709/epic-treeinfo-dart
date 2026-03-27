"""Regression tests for Story 3.1 mobile incidents read-only endpoint."""

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server


class MobileIncidentTests(unittest.TestCase):
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
        server.mobile_incident_records.clear()
        self.addCleanup(server.sessions.clear)
        self.addCleanup(server.mobile_access_sessions.clear)
        self.addCleanup(server.mobile_refresh_sessions.clear)
        self.addCleanup(server.mobile_incident_records.clear)

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

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
                    "payload_ref": "payload/inc-1.json",
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
                    "payload_ref": "payload/inc-2.json",
                },
                {
                    "incident_id": "inc-3",
                    "er_event_id": "er-1003",
                    "ranger_id": "rangeruser",
                    "mapping_status": "mapped",
                    "occurred_at": "2026-03-21T01:00:00Z",
                    "updated_at": "2026-03-21T02:00:00Z",
                    "title": "Patrol note",
                    "status": "closed",
                    "severity": "low",
                    "payload_ref": "payload/inc-3.json",
                },
                {
                    "incident_id": "inc-4",
                    "er_event_id": "er-1004",
                    "mapping_status": "unmapped",
                    "occurred_at": "2026-03-20T05:00:00Z",
                    "updated_at": "2026-03-20T06:00:00Z",
                    "title": "Unknown owner event",
                    "status": "open",
                    "severity": "medium",
                    "payload_ref": "payload/inc-4.json",
                },
            ]
        )

    def _restore_rate_limits(self):
        self.settings.rate_limit_login = self.original_rate_limit_login
        self.settings.rate_limit_api = self.original_rate_limit_api

    def _login_headers(self, username: str, password: str) -> dict:
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": username, "password": password},
        )
        self.assertEqual(200, response.status_code)
        token = response.json()["access_token"]
        return {"Authorization": f"Bearer {token}"}

    def test_ranger_scope_self_only_and_cross_scope_denial(self):
        headers = self._login_headers("rangeruser", "safe-ranger-password")

        denied = self.client.get(
            "/api/mobile/incidents",
            params={"ranger_id": "otherranger"},
            headers=headers,
        )
        self.assertEqual(403, denied.status_code)
        self.assertEqual({"detail": "Ranger scope violation"}, denied.json())

        allowed = self.client.get("/api/mobile/incidents", headers=headers)
        self.assertEqual(200, allowed.status_code)
        payload = allowed.json()

        self.assertEqual("ranger", payload["scope"]["role"])
        self.assertFalse(payload["scope"]["team_scope"])
        self.assertEqual("rangeruser", payload["scope"]["effective_ranger_id"])
        self.assertEqual(2, payload["pagination"]["total"])
        self.assertTrue(all(item["ranger_id"] == "rangeruser" for item in payload["items"]))
        self.assertTrue(all(item["mapping_status"] == "mapped" for item in payload["items"]))

    def test_leader_team_scope_and_ranger_filter(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        team_scope = self.client.get("/api/mobile/incidents", headers=headers)
        self.assertEqual(200, team_scope.status_code)
        team_payload = team_scope.json()

        self.assertEqual("leader", team_payload["scope"]["role"])
        self.assertTrue(team_payload["scope"]["team_scope"])
        self.assertIsNone(team_payload["scope"]["effective_ranger_id"])
        self.assertEqual(4, team_payload["pagination"]["total"])

        filtered = self.client.get(
            "/api/mobile/incidents",
            params={"ranger_id": "rangeruser"},
            headers=headers,
        )
        self.assertEqual(200, filtered.status_code)
        filtered_payload = filtered.json()

        self.assertFalse(filtered_payload["scope"]["team_scope"])
        self.assertEqual("rangeruser", filtered_payload["scope"]["effective_ranger_id"])
        self.assertEqual(2, filtered_payload["pagination"]["total"])
        self.assertTrue(all(item["ranger_id"] == "rangeruser" for item in filtered_payload["items"]))

    def test_incident_filters_and_pagination_metadata(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        filtered = self.client.get(
            "/api/mobile/incidents",
            params={
                "from": "2026-03-20",
                "to": "2026-03-21",
                "updated_since": "2026-03-20T00:00:00Z",
                "page": 1,
                "page_size": 1,
            },
            headers=headers,
        )
        self.assertEqual(200, filtered.status_code)
        payload = filtered.json()

        self.assertEqual("2026-03-20", payload["filters"]["from"])
        self.assertEqual("2026-03-21", payload["filters"]["to"])
        self.assertEqual("2026-03-20T00:00:00+00:00", payload["filters"]["updated_since"])
        self.assertEqual(1, payload["pagination"]["page"])
        self.assertEqual(1, payload["pagination"]["page_size"])
        self.assertEqual(3, payload["pagination"]["total"])
        self.assertEqual(3, payload["pagination"]["total_pages"])
        self.assertEqual(1, len(payload["items"]))
        self.assertTrue(payload["sync"]["has_more"])
        self.assertIsNone(payload["sync"]["last_synced_at"])

    def test_incident_pagination_page_exceeds_total_pages_returns_400(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/incidents",
            params={"page": 3, "page_size": 2},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual(
            {"detail": "Invalid pagination: page exceeds total_pages"},
            response.json(),
        )

    def test_incident_endpoint_ignores_malformed_mirrored_rows(self):
        headers = self._login_headers("leaderuser", "strong-password-123")
        server.mobile_incident_records.append("invalid-incident-row")

        response = self.client.get("/api/mobile/incidents", headers=headers)
        self.assertEqual(200, response.status_code)

        payload = response.json()
        self.assertEqual(4, payload["pagination"]["total"])
        self.assertTrue(all(isinstance(item, dict) for item in payload["items"]))

    def test_requested_ranger_scope_metadata_is_normalized(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/incidents",
            params={"ranger_id": "  rangeruser  "},
            headers=headers,
        )
        self.assertEqual(200, response.status_code)

        payload = response.json()
        self.assertEqual("rangeruser", payload["scope"]["requested_ranger_id"])
        self.assertEqual("rangeruser", payload["scope"]["effective_ranger_id"])

    def test_incident_filters_ignore_rows_with_malformed_timestamps(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        server.mobile_incident_records.extend(
            [
                {
                    "incident_id": "inc-bad-occurred",
                    "er_event_id": "er-bad-occurred",
                    "ranger_id": "rangeruser",
                    "mapping_status": "mapped",
                    "occurred_at": "not-a-datetime",
                    "updated_at": "2026-03-21T05:00:00Z",
                    "title": "Malformed occurred_at",
                    "status": "open",
                    "severity": "low",
                },
                {
                    "incident_id": "inc-bad-updated",
                    "er_event_id": "er-bad-updated",
                    "ranger_id": "rangeruser",
                    "mapping_status": "mapped",
                    "occurred_at": "2026-03-20T05:00:00Z",
                    "updated_at": "invalid-updated-at",
                    "title": "Malformed updated_at",
                    "status": "open",
                    "severity": "low",
                },
            ]
        )

        response = self.client.get(
            "/api/mobile/incidents",
            params={
                "from": "2026-03-19",
                "to": "2026-03-21",
                "updated_since": "2026-03-20T00:00:00Z",
            },
            headers=headers,
        )
        self.assertEqual(200, response.status_code)

        payload = response.json()
        self.assertEqual(3, payload["pagination"]["total"])
        returned_ids = {item["incident_id"] for item in payload["items"]}
        self.assertNotIn("inc-bad-occurred", returned_ids)
        self.assertNotIn("inc-bad-updated", returned_ids)

    def test_cursor_based_pagination_returns_deterministic_next_cursor(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        first_page = self.client.get(
            "/api/mobile/incidents",
            params={"cursor": "0", "page_size": 2},
            headers=headers,
        )
        self.assertEqual(200, first_page.status_code)
        first_payload = first_page.json()

        self.assertEqual(2, len(first_payload["items"]))
        self.assertTrue(first_payload["sync"]["has_more"])
        self.assertEqual("2", first_payload["sync"]["cursor"])
        self.assertIsNone(first_payload["sync"]["last_synced_at"])

        second_page = self.client.get(
            "/api/mobile/incidents",
            params={"cursor": first_payload["sync"]["cursor"], "page_size": 2},
            headers=headers,
        )
        self.assertEqual(200, second_page.status_code)
        second_payload = second_page.json()

        self.assertEqual(2, len(second_payload["items"]))
        self.assertFalse(second_payload["sync"]["has_more"])
        self.assertIsNone(second_payload["sync"]["cursor"])
        self.assertEqual(
            first_payload["items"][0]["updated_at"],
            second_payload["sync"]["last_synced_at"],
        )

        first_ids = {item["incident_id"] for item in first_payload["items"]}
        second_ids = {item["incident_id"] for item in second_payload["items"]}
        self.assertTrue(first_ids.isdisjoint(second_ids))

    def test_invalid_cursor_inputs_return_400(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        invalid_format = self.client.get(
            "/api/mobile/incidents",
            params={"cursor": "abc"},
            headers=headers,
        )
        self.assertEqual(400, invalid_format.status_code)
        self.assertEqual({"detail": "Invalid cursor format"}, invalid_format.json())

        conflicting_pagination = self.client.get(
            "/api/mobile/incidents",
            params={"cursor": "0", "page": 2},
            headers=headers,
        )
        self.assertEqual(400, conflicting_pagination.status_code)
        self.assertEqual(
            {"detail": "Invalid pagination: provide either page or cursor"},
            conflicting_pagination.json(),
        )

    def test_incident_endpoint_is_read_only_in_phase1(self):
        headers = self._login_headers("leaderuser", "strong-password-123")

        post_response = self.client.post("/api/mobile/incidents", headers=headers, json={})
        self.assertEqual(405, post_response.status_code)

        put_response = self.client.put("/api/mobile/incidents/inc-1", headers=headers, json={})
        self.assertIn(put_response.status_code, {404, 405})

        delete_response = self.client.delete("/api/mobile/incidents/inc-1", headers=headers)
        self.assertIn(delete_response.status_code, {404, 405})


if __name__ == "__main__":
    unittest.main()
