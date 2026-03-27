"""Regression tests for Story 1.1/1.2 mobile backend auth endpoints."""

from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server


class MobileAuthLoginTests(unittest.TestCase):
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
            "leaderroleuser": {
                "password": server._hash_pw("plain-leader-password"),
                "role": "leader",
                "display_name": "Leader Role User",
            },
            "rangeruser": {
                "password": server._hash_pw("safe-ranger-password"),
                "role": "viewer",
                "display_name": "Ranger User",
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
        server.mobile_incident_records.clear()
        server.mobile_schedule_sequence = 0
        self.addCleanup(server.sessions.clear)
        self.addCleanup(server.mobile_access_sessions.clear)
        self.addCleanup(server.mobile_refresh_sessions.clear)
        self.addCleanup(server.mobile_schedule_records.clear)
        self.addCleanup(server.mobile_incident_records.clear)
        self.addCleanup(self._reset_mobile_schedule_sequence)

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    def _reset_mobile_schedule_sequence(self):
        server.mobile_schedule_sequence = 0

    def _restore_rate_limits(self):
        self.settings.rate_limit_login = self.original_rate_limit_login
        self.settings.rate_limit_api = self.original_rate_limit_api

    def _login_and_get_tokens(
        self,
        username: str = "leaderuser",
        password: str = "strong-password-123",
    ) -> dict:
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": username, "password": password},
        )
        self.assertEqual(200, response.status_code)
        return response.json()

    def _mobile_bearer_headers(
        self,
        username: str = "leaderuser",
        password: str = "strong-password-123",
    ) -> tuple[dict, dict]:
        login_payload = self._login_and_get_tokens(username=username, password=password)
        headers = {"Authorization": f"Bearer {login_payload['access_token']}"}
        return headers, login_payload

    def test_login_success_returns_tokens_and_leader_role_claim(self):
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "leaderuser", "password": "strong-password-123"},
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()

        self.assertEqual("bearer", payload["token_type"])
        self.assertEqual("leader", payload["role"])
        self.assertEqual("leaderuser", payload["username"])
        self.assertEqual("Leader User", payload["display_name"])
        self.assertIsInstance(payload["access_token"], str)
        self.assertIsInstance(payload["refresh_token"], str)
        self.assertGreater(payload["expires_in"], 0)

        self.assertNotIn("supabase_key", payload)
        self.assertNotIn("earthranger_token", payload)

        self.assertEqual(1, len(server.mobile_access_sessions))
        self.assertEqual(1, len(server.mobile_refresh_sessions))

    def test_login_maps_non_admin_role_to_ranger_claim(self):
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "rangeruser", "password": "safe-ranger-password"},
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual("ranger", payload["role"])

    def test_login_maps_explicit_leader_role_to_leader_claim(self):
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "leaderroleuser", "password": "plain-leader-password"},
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual("leader", payload["role"])

    def test_invalid_credentials_return_401_and_no_mobile_session(self):
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "leaderuser", "password": "wrong-password"},
        )

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid credentials"}, response.json())
        self.assertEqual({}, server.mobile_access_sessions)
        self.assertEqual({}, server.mobile_refresh_sessions)
        self.assertEqual({}, server.sessions)

    def test_login_rejects_overlong_credentials_and_creates_no_sessions(self):
        too_long_username = "u" * 129
        too_long_password = "p" * 257

        username_response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": too_long_username, "password": "ok"},
        )
        self.assertEqual(422, username_response.status_code)

        password_response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "leaderuser", "password": too_long_password},
        )
        self.assertEqual(422, password_response.status_code)

        self.assertEqual({}, server.mobile_access_sessions)
        self.assertEqual({}, server.mobile_refresh_sessions)
        self.assertEqual({}, server.sessions)

    def test_legacy_sha256_password_is_migrated_after_successful_mobile_login(self):
        users = json.loads(self.users_file.read_text(encoding="utf-8"))
        users["legacy"] = {
            "password": hashlib.sha256("legacy-pass".encode()).hexdigest(),
            "role": "viewer",
            "display_name": "Legacy User",
        }
        self.users_file.write_text(json.dumps(users, ensure_ascii=False, indent=2), encoding="utf-8")

        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "legacy", "password": "legacy-pass"},
        )

        self.assertEqual(200, response.status_code)

        updated_users = json.loads(self.users_file.read_text(encoding="utf-8"))
        self.assertTrue(updated_users["legacy"]["password"].startswith("$2"))

    def test_refresh_returns_new_access_token_and_preserves_role_claim(self):
        login_payload = self._login_and_get_tokens(username="rangeruser", password="safe-ranger-password")

        response = self.client.post(
            "/api/mobile/auth/refresh",
            json={"refresh_token": login_payload["refresh_token"]},
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()

        self.assertEqual("bearer", payload["token_type"])
        self.assertEqual("ranger", payload["role"])
        self.assertEqual("rangeruser", payload["username"])
        self.assertEqual("Ranger User", payload["display_name"])
        self.assertEqual(login_payload["refresh_token"], payload["refresh_token"])
        self.assertNotEqual(login_payload["access_token"], payload["access_token"])
        self.assertGreater(payload["expires_in"], 0)
        self.assertNotIn("supabase_key", payload)
        self.assertNotIn("earthranger_token", payload)
        self.assertEqual(1, len(server.mobile_refresh_sessions))
        self.assertEqual(1, len(server.mobile_access_sessions))

    def test_refresh_rejects_invalid_or_expired_refresh_token(self):
        invalid_response = self.client.post(
            "/api/mobile/auth/refresh",
            json={"refresh_token": "not-a-valid-token"},
        )
        self.assertEqual(401, invalid_response.status_code)
        self.assertEqual({"detail": "Invalid refresh token"}, invalid_response.json())

        login_payload = self._login_and_get_tokens()
        refresh_token = login_payload["refresh_token"]
        server.mobile_refresh_sessions[refresh_token]["expires_at"] = datetime.now(timezone.utc) - timedelta(seconds=1)

        expired_response = self.client.post(
            "/api/mobile/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        self.assertEqual(401, expired_response.status_code)
        self.assertEqual({"detail": "Invalid refresh token"}, expired_response.json())
        self.assertNotIn(refresh_token, server.mobile_refresh_sessions)

    def test_refresh_rejects_whitespace_only_token(self):
        response = self.client.post(
            "/api/mobile/auth/refresh",
            json={"refresh_token": "   "},
        )

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid refresh token"}, response.json())

    def test_refresh_rejects_malformed_refresh_session_payload(self):
        login_payload = self._login_and_get_tokens()
        refresh_token = login_payload["refresh_token"]
        server.mobile_refresh_sessions[refresh_token] = {
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=5),
        }

        response = self.client.post(
            "/api/mobile/auth/refresh",
            json={"refresh_token": refresh_token},
        )

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid refresh token"}, response.json())
        self.assertNotIn(refresh_token, server.mobile_refresh_sessions)

    def test_logout_invalidates_refresh_token_and_blocks_future_refresh(self):
        login_payload = self._login_and_get_tokens()
        refresh_token = login_payload["refresh_token"]

        logout_response = self.client.post(
            "/api/mobile/auth/logout",
            json={"refresh_token": refresh_token},
        )
        self.assertEqual(200, logout_response.status_code)
        self.assertEqual({"ok": True}, logout_response.json())
        self.assertNotIn(refresh_token, server.mobile_refresh_sessions)
        self.assertEqual({}, server.mobile_access_sessions)

        refresh_after_logout = self.client.post(
            "/api/mobile/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        self.assertEqual(401, refresh_after_logout.status_code)
        self.assertEqual({"detail": "Invalid refresh token"}, refresh_after_logout.json())

    def test_logout_rejects_whitespace_only_token(self):
        response = self.client.post(
            "/api/mobile/auth/logout",
            json={"refresh_token": "   "},
        )

        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid refresh token"}, response.json())

    def test_mobile_me_requires_valid_bearer_token(self):
        missing = self.client.get("/api/mobile/me")
        self.assertEqual(401, missing.status_code)
        self.assertEqual({"detail": "Invalid access token"}, missing.json())

        invalid = self.client.get("/api/mobile/me", headers={"Authorization": "Bearer invalid-token"})
        self.assertEqual(401, invalid.status_code)
        self.assertEqual({"detail": "Invalid access token"}, invalid.json())

        headers, login_payload = self._mobile_bearer_headers()
        server.mobile_access_sessions[login_payload["access_token"]]["expires_at"] = (
            datetime.now(timezone.utc) - timedelta(seconds=1)
        )
        expired = self.client.get("/api/mobile/me", headers=headers)
        self.assertEqual(401, expired.status_code)
        self.assertEqual({"detail": "Invalid access token"}, expired.json())

    def test_mobile_me_returns_username_display_name_and_role(self):
        headers, _ = self._mobile_bearer_headers(
            username="rangeruser",
            password="safe-ranger-password",
        )

        response = self.client.get("/api/mobile/me", headers=headers)
        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {
                "username": "rangeruser",
                "display_name": "Ranger User",
                "role": "ranger",
            },
            response.json(),
        )

    def test_ranger_scope_denies_other_ranger_and_allows_self_scope(self):
        headers, _ = self._mobile_bearer_headers(
            username="rangeruser",
            password="safe-ranger-password",
        )

        denied = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "leaderuser"},
            headers=headers,
        )
        self.assertEqual(403, denied.status_code)
        self.assertEqual({"detail": "Ranger scope violation"}, denied.json())

        allowed = self.client.get("/api/mobile/work-management", headers=headers)
        self.assertEqual(200, allowed.status_code)
        allowed_payload = allowed.json()
        self.assertEqual("ranger", allowed_payload["scope"]["role"])
        self.assertEqual("rangeruser", allowed_payload["scope"]["effective_ranger_id"])

    def test_leader_team_scope_read_and_schedule_write_authorization(self):
        leader_headers, _ = self._mobile_bearer_headers(
            username="leaderuser",
            password="strong-password-123",
        )
        ranger_headers, _ = self._mobile_bearer_headers(
            username="rangeruser",
            password="safe-ranger-password",
        )

        team_scope = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "rangeruser"},
            headers=leader_headers,
        )
        self.assertEqual(200, team_scope.status_code)
        self.assertEqual("rangeruser", team_scope.json()["scope"]["effective_ranger_id"])

        ranger_write = self.client.post(
            "/api/mobile/schedules",
            headers=ranger_headers,
            json={"ranger_id": "rangeruser", "work_date": "2026-03-20", "note": "ranger attempt"},
        )
        self.assertEqual(403, ranger_write.status_code)
        self.assertEqual({"detail": "Leader role required"}, ranger_write.json())

        with patch("src.server.ensure_schedule_schema_ready", return_value=None), patch(
            "src.server.create_mobile_schedule",
            return_value={
                "schedule_id": "auth-mock-1",
                "ranger_id": "rangeruser",
                "work_date": "2026-03-20",
                "note": "leader assignment",
                "updated_by": "leaderuser",
                "created_at": "2026-03-20T00:00:00+00:00",
                "updated_at": "2026-03-20T00:00:00+00:00",
            },
        ):
            leader_write = self.client.post(
                "/api/mobile/schedules",
                headers=leader_headers,
                json={"ranger_id": "rangeruser", "work_date": "2026-03-20", "note": "leader assignment"},
            )
        self.assertEqual(200, leader_write.status_code)
        leader_payload = leader_write.json()
        self.assertTrue(leader_payload["ok"])
        self.assertEqual("leaderuser", leader_payload["schedule"]["updated_by"])

    def test_explicit_leader_role_user_can_read_team_scope_and_write_schedule(self):
        leader_headers, _ = self._mobile_bearer_headers(
            username="leaderroleuser",
            password="plain-leader-password",
        )

        team_scope = self.client.get(
            "/api/mobile/work-management",
            params={"ranger_id": "rangeruser"},
            headers=leader_headers,
        )
        self.assertEqual(200, team_scope.status_code)
        self.assertEqual("rangeruser", team_scope.json()["scope"]["effective_ranger_id"])

        with patch("src.server.ensure_schedule_schema_ready", return_value=None), patch(
            "src.server.create_mobile_schedule",
            return_value={
                "schedule_id": "auth-mock-2",
                "ranger_id": "rangeruser",
                "work_date": "2026-03-21",
                "note": "leader role assignment",
                "updated_by": "leaderroleuser",
                "created_at": "2026-03-21T00:00:00+00:00",
                "updated_at": "2026-03-21T00:00:00+00:00",
            },
        ):
            leader_write = self.client.post(
                "/api/mobile/schedules",
                headers=leader_headers,
                json={"ranger_id": "rangeruser", "work_date": "2026-03-21", "note": "leader role assignment"},
            )
        self.assertEqual(200, leader_write.status_code)
        self.assertEqual("leaderroleuser", leader_write.json()["schedule"]["updated_by"])


if __name__ == "__main__":
    unittest.main()
