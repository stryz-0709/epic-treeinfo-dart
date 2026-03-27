"""Regression tests for admin account provisioning and role assignment."""

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server


class AdminUserAccountTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.users_file = Path(self.temp_dir.name) / "users.json"

        users = {
            "adminuser": {
                "password": server._hash_pw("admin-password-123"),
                "role": "admin",
                "display_name": "Admin User",
            },
            "legacyviewer": {
                "password": server._hash_pw("viewer-password-123"),
                "role": "viewer",
                "display_name": "Legacy Viewer",
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
        self.addCleanup(server.sessions.clear)
        self.addCleanup(server.mobile_access_sessions.clear)
        self.addCleanup(server.mobile_refresh_sessions.clear)

        server.sessions["admin-session"] = {
            "username": "adminuser",
            "role": "admin",
            "display_name": "Admin User",
        }
        server.sessions["viewer-session"] = {
            "username": "legacyviewer",
            "role": "viewer",
            "display_name": "Legacy Viewer",
        }

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    def _restore_rate_limits(self):
        self.settings.rate_limit_login = self.original_rate_limit_login
        self.settings.rate_limit_api = self.original_rate_limit_api

    @staticmethod
    def _admin_cookies() -> dict:
        return {"session_token": "admin-session"}

    @staticmethod
    def _viewer_cookies() -> dict:
        return {"session_token": "viewer-session"}

    def test_admin_can_create_leader_account_and_login_with_assigned_password(self):
        create_response = self.client.post(
            "/api/users",
            cookies=self._admin_cookies(),
            json={
                "username": "leader.new",
                "password": "assigned-pass-123",
                "role": "leader",
                "display_name": "Leader New",
            },
        )

        self.assertEqual(200, create_response.status_code)
        self.assertEqual({"ok": True, "username": "leader.new"}, create_response.json())

        login_response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "leader.new", "password": "assigned-pass-123"},
        )
        self.assertEqual(200, login_response.status_code)
        self.assertEqual("leader", login_response.json()["role"])

    def test_admin_can_create_ranger_account_and_login_with_assigned_password(self):
        create_response = self.client.post(
            "/api/users",
            cookies=self._admin_cookies(),
            json={
                "username": "ranger.new",
                "password": "assigned-ranger-123",
                "role": "ranger",
                "display_name": "Ranger New",
            },
        )

        self.assertEqual(200, create_response.status_code)
        self.assertEqual({"ok": True, "username": "ranger.new"}, create_response.json())

        login_response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": "ranger.new", "password": "assigned-ranger-123"},
        )
        self.assertEqual(200, login_response.status_code)
        self.assertEqual("ranger", login_response.json()["role"])

    def test_admin_create_maps_legacy_viewer_alias_to_ranger(self):
        create_response = self.client.post(
            "/api/users",
            cookies=self._admin_cookies(),
            json={
                "username": "legacy.alias",
                "password": "assigned-legacy-123",
                "role": "viewer",
                "display_name": "Legacy Alias",
            },
        )

        self.assertEqual(200, create_response.status_code)

        users = json.loads(self.users_file.read_text(encoding="utf-8"))
        self.assertEqual("ranger", users["legacy.alias"]["role"])

    def test_api_users_normalizes_legacy_viewer_role_to_ranger(self):
        response = self.client.get(
            "/api/users",
            cookies=self._admin_cookies(),
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        role_by_username = {item["username"]: item["role"] for item in payload["users"]}
        self.assertEqual("ranger", role_by_username["legacyviewer"])

    def test_non_admin_cannot_create_user_accounts(self):
        response = self.client.post(
            "/api/users",
            cookies=self._viewer_cookies(),
            json={
                "username": "blocked.user",
                "password": "assigned-pass-123",
                "role": "leader",
            },
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual({"detail": "Admin only"}, response.json())


if __name__ == "__main__":
    unittest.main()
