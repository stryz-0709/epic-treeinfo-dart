"""Regression tests for Story 2.2 mobile check-in ingest endpoint."""

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import threading
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server


class MobileCheckinTests(unittest.TestCase):
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
        server.mobile_schedule_sequence = 0
        self.addCleanup(server.sessions.clear)
        self.addCleanup(server.mobile_access_sessions.clear)
        self.addCleanup(server.mobile_refresh_sessions.clear)
        self.addCleanup(server.mobile_schedule_records.clear)
        self.addCleanup(server.mobile_work_summary_records.clear)
        self.addCleanup(server.mobile_daily_checkins.clear)
        self.addCleanup(server.mobile_incident_records.clear)
        self.addCleanup(self._reset_schedule_sequence)

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

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

    def test_checkin_uses_project_timezone_day_key(self):
        fixed_now_utc = datetime(2026, 3, 20, 17, 30, tzinfo=timezone.utc)  # 00:30 in Asia/Ho_Chi_Minh
        with patch("src.server._utcnow", return_value=fixed_now_utc):
            ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")
            response = self.client.post(
                "/api/mobile/checkins",
                headers=ranger_headers,
                json={"idempotency_key": "client-checkin-001"},
            )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual("created", payload["status"])
        self.assertEqual("2026-03-21", payload["day_key"])
        self.assertEqual("Asia/Ho_Chi_Minh", payload["timezone"])
        self.assertEqual("rangeruser", payload["user_id"])
        self.assertEqual(1, len(server.mobile_daily_checkins))

    def test_checkin_project_timezone_day_key_boundary_cases(self):
        ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")

        cases = [
            (datetime(2026, 3, 20, 16, 59, 59, tzinfo=timezone.utc), "2026-03-20"),
            (datetime(2026, 3, 20, 17, 0, 0, tzinfo=timezone.utc), "2026-03-21"),
            (datetime(2026, 3, 20, 17, 0, 1, tzinfo=timezone.utc), "2026-03-21"),
        ]

        for now_utc, expected_day_key in cases:
            with self.subTest(now_utc=now_utc.isoformat()):
                server.mobile_daily_checkins.clear()
                server.mobile_work_summary_records.clear()

                with patch("src.server._utcnow", return_value=now_utc):
                    response = self.client.post(
                        "/api/mobile/checkins",
                        headers=ranger_headers,
                        json={"idempotency_key": f"boundary-{now_utc.isoformat()}"},
                    )

                self.assertEqual(200, response.status_code)
                payload = response.json()
                self.assertEqual("created", payload["status"])
                self.assertEqual(expected_day_key, payload["day_key"])

    def test_repeat_checkin_same_user_day_returns_already_exists_without_duplicates(self):
        fixed_now_utc = datetime(2026, 3, 20, 1, 0, tzinfo=timezone.utc)
        with patch("src.server._utcnow", return_value=fixed_now_utc):
            ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")
            first = self.client.post(
                "/api/mobile/checkins",
                headers=ranger_headers,
                json={"idempotency_key": "k1"},
            )
            second = self.client.post(
                "/api/mobile/checkins",
                headers=ranger_headers,
                json={"idempotency_key": "k2"},
            )

        self.assertEqual(200, first.status_code)
        self.assertEqual(200, second.status_code)
        self.assertEqual("created", first.json()["status"])
        self.assertEqual("already_exists", second.json()["status"])
        self.assertEqual(1, len(server.mobile_daily_checkins))

        rows_for_day = [
            row
            for row in server.mobile_work_summary_records
            if row.get("ranger_id") == "rangeruser" and row.get("day_key") == "2026-03-20"
        ]
        self.assertEqual(1, len(rows_for_day))
        self.assertTrue(rows_for_day[0]["has_checkin"])

    def test_offline_queue_replay_returns_stable_existing_record(self):
        fixed_now_utc = datetime(2026, 3, 20, 1, 0, tzinfo=timezone.utc)
        with patch("src.server._utcnow", return_value=fixed_now_utc):
            first_headers = self._login_headers("rangeruser", "safe-ranger-password")
            created = self.client.post(
                "/api/mobile/checkins",
                headers=first_headers,
                json={
                    "idempotency_key": "offline-queue-001",
                    "client_time": "2026-03-20T08:00:00+07:00",
                    "timezone": "Asia/Ho_Chi_Minh",
                    "app_version": "1.0.0",
                },
            )

            replay_headers = self._login_headers("rangeruser", "safe-ranger-password")
            replayed = self.client.post(
                "/api/mobile/checkins",
                headers=replay_headers,
                json={
                    "idempotency_key": "offline-queue-001",
                    "client_time": "2026-03-20T08:05:00+07:00",
                    "timezone": "Asia/Ho_Chi_Minh",
                    "app_version": "1.1.0",
                },
            )

        self.assertEqual(200, created.status_code)
        self.assertEqual(200, replayed.status_code)

        created_payload = created.json()
        replay_payload = replayed.json()
        self.assertEqual("created", created_payload["status"])
        self.assertEqual("already_exists", replay_payload["status"])
        self.assertEqual("offline-queue-001", replay_payload["idempotency_key"])
        self.assertEqual(created_payload["server_time"], replay_payload["server_time"])
        self.assertEqual(1, len(server.mobile_daily_checkins))

    def test_same_idempotency_key_is_isolated_by_ranger_identity(self):
        fixed_now_utc = datetime(2026, 3, 20, 1, 0, tzinfo=timezone.utc)
        with patch("src.server._utcnow", return_value=fixed_now_utc):
            ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")
            other_headers = self._login_headers("otherranger", "another-ranger-password")

            ranger_response = self.client.post(
                "/api/mobile/checkins",
                headers=ranger_headers,
                json={"idempotency_key": "shared-client-queue-id"},
            )
            other_response = self.client.post(
                "/api/mobile/checkins",
                headers=other_headers,
                json={"idempotency_key": "shared-client-queue-id"},
            )

        self.assertEqual(200, ranger_response.status_code)
        self.assertEqual(200, other_response.status_code)
        self.assertEqual("created", ranger_response.json()["status"])
        self.assertEqual("created", other_response.json()["status"])
        self.assertEqual(2, len(server.mobile_daily_checkins))
        self.assertIn(("rangeruser", "2026-03-20"), server.mobile_daily_checkins)
        self.assertIn(("otherranger", "2026-03-20"), server.mobile_daily_checkins)

    def test_concurrent_ingest_same_user_day_creates_single_effective_record(self):
        fixed_now_utc = datetime(2026, 3, 20, 1, 0, tzinfo=timezone.utc)
        mobile_user = {"username": "rangeruser", "role": "ranger"}

        statuses: list[str] = []
        errors: list[Exception] = []

        def worker(index: int) -> None:
            try:
                payload = server.MobileCheckinRequest(idempotency_key=f"thread-{index}")
                result = server._ingest_mobile_checkin(mobile_user, payload)
                statuses.append(result["status"])
            except Exception as exc:  # pragma: no cover - test helper guard
                errors.append(exc)

        with patch("src.server._utcnow", return_value=fixed_now_utc):
            threads = [threading.Thread(target=worker, args=(idx,)) for idx in range(10)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()

        self.assertEqual([], errors)
        self.assertEqual(1, statuses.count("created"))
        self.assertEqual(9, statuses.count("already_exists"))
        self.assertEqual(1, len(server.mobile_daily_checkins))

        rows_for_day = [
            row
            for row in server.mobile_work_summary_records
            if row.get("ranger_id") == "rangeruser" and row.get("day_key") == "2026-03-20"
        ]
        self.assertEqual(1, len(rows_for_day))
        self.assertTrue(rows_for_day[0]["has_checkin"])

    def test_non_ranger_role_cannot_ingest_checkin(self):
        leader_headers = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.post(
            "/api/mobile/checkins",
            headers=leader_headers,
            json={},
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual({"detail": "Ranger role required"}, response.json())

    def test_checkin_requires_valid_bearer_token(self):
        missing = self.client.post("/api/mobile/checkins", json={})
        self.assertEqual(401, missing.status_code)
        self.assertEqual({"detail": "Invalid access token"}, missing.json())

        invalid = self.client.post(
            "/api/mobile/checkins",
            headers={"Authorization": "Bearer invalid"},
            json={},
        )
        self.assertEqual(401, invalid.status_code)
        self.assertEqual({"detail": "Invalid access token"}, invalid.json())

    def test_checkin_rejects_expired_access_token(self):
        ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")
        token = ranger_headers["Authorization"].split(" ", 1)[1]

        session = server.mobile_access_sessions[token]
        session["expires_at"] = datetime.now(timezone.utc) - timedelta(seconds=1)

        response = self.client.post(
            "/api/mobile/checkins",
            headers=ranger_headers,
            json={},
        )

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid access token"}, response.json())


if __name__ == "__main__":
    unittest.main()
