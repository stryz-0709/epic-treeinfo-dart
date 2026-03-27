"""Regression tests for Story 4.5 retention and compliance operations."""

from datetime import datetime, timezone
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import retention, server


class _DummyRetentionSettings:
    """Minimal settings stub for retention tests."""

    retention_enabled = True
    retention_schedule_timezone = "Asia/Ho_Chi_Minh"
    retention_schedule_hour_local = 1
    retention_schedule_minute_local = 30
    retention_min_days = 183
    retention_source_table = "daily_checkins"
    retention_source_day_field = "day_key"
    retention_audit_table = "retention_job_runs"
    retention_audit_memory_limit = 50


class _FakeResult:
    def __init__(self, data):
        self.data = data


class _FakeTable:
    """Tiny fluent query fake for retention tests."""

    def __init__(self, table_name: str, store: dict[str, list[dict]], fail_delete_tables: set[str]):
        self.table_name = table_name
        self.store = store
        self.fail_delete_tables = fail_delete_tables
        self._reset()

    def _reset(self):
        self._operation = None
        self._lt_key = None
        self._lt_value = None
        self._insert_payload = None

    def select(self, _fields: str):
        self._operation = "select"
        return self

    def delete(self):
        self._operation = "delete"
        return self

    def insert(self, payload: dict):
        self._operation = "insert"
        self._insert_payload = dict(payload)
        return self

    def lt(self, key: str, value: str):
        self._lt_key = key
        self._lt_value = value
        return self

    def execute(self):
        rows = self.store.setdefault(self.table_name, [])
        try:
            if self._operation == "select":
                filtered = [
                    dict(row)
                    for row in rows
                    if str(row.get(self._lt_key) or "") < str(self._lt_value)
                ]
                return _FakeResult(filtered)

            if self._operation == "delete":
                if self.table_name in self.fail_delete_tables:
                    raise RuntimeError("retention delete failed")

                matched = [
                    dict(row)
                    for row in rows
                    if str(row.get(self._lt_key) or "") < str(self._lt_value)
                ]
                self.store[self.table_name] = [
                    dict(row)
                    for row in rows
                    if str(row.get(self._lt_key) or "") >= str(self._lt_value)
                ]
                return _FakeResult(matched)

            if self._operation == "insert":
                rows.append(dict(self._insert_payload or {}))
                return _FakeResult([dict(self._insert_payload or {})])

            raise RuntimeError(f"Unsupported fake operation: {self._operation}")
        finally:
            self._reset()


class _FakeSupabaseClient:
    def __init__(self, store: dict[str, list[dict]], fail_delete_tables: set[str] | None = None):
        self.store = store
        self.fail_delete_tables = fail_delete_tables or set()

    def table(self, table_name: str):
        return _FakeTable(table_name, self.store, self.fail_delete_tables)


class RetentionServiceTests(unittest.TestCase):
    def setUp(self):
        retention.clear_retention_run_history()
        self.addCleanup(retention.clear_retention_run_history)

    def test_execute_retention_purges_rows_older_than_cutoff_and_records_audit(self):
        store = {
            "daily_checkins": [
                {"id": "old-1", "day_key": "2025-01-10"},
                {"id": "fresh-1", "day_key": "2025-11-15"},
            ],
            "retention_job_runs": [],
        }
        fake_supabase = _FakeSupabaseClient(store)
        now_utc = datetime(2026, 3, 23, 3, 0, tzinfo=timezone.utc)

        with (
            patch("src.retention.get_settings", return_value=_DummyRetentionSettings()),
            patch("src.retention.get_supabase", return_value=fake_supabase),
        ):
            result = retention.execute_ranger_stats_retention(
                trigger="manual",
                request_id="req-001",
                correlation_id="corr-001",
                now_utc=now_utc,
            )

        self.assertEqual("succeeded", result["status"])
        self.assertEqual(1, result["candidate_count"])
        self.assertEqual(1, result["deleted_count"])
        self.assertEqual("req-001", result["request_id"])
        self.assertEqual("corr-001", result["correlation_id"])
        self.assertEqual("2025-11-15", store["daily_checkins"][0]["day_key"])
        self.assertEqual(1, len(store["retention_job_runs"]))

        audit_rows = retention.list_retention_runs(limit=10)
        self.assertEqual(1, len(audit_rows))
        self.assertEqual(result["run_id"], audit_rows[0]["run_id"])

    def test_failed_run_is_discoverable_and_replay_preserves_linkage(self):
        store = {
            "daily_checkins": [
                {"id": "old-1", "day_key": "2025-01-10"},
                {"id": "fresh-1", "day_key": "2025-11-15"},
            ],
            "retention_job_runs": [],
        }
        now_utc = datetime(2026, 3, 23, 3, 0, tzinfo=timezone.utc)

        with (
            patch("src.retention.get_settings", return_value=_DummyRetentionSettings()),
            patch(
                "src.retention.get_supabase",
                return_value=_FakeSupabaseClient(store, fail_delete_tables={"daily_checkins"}),
            ),
        ):
            failed = retention.execute_ranger_stats_retention(trigger="scheduled", now_utc=now_utc)

        self.assertEqual("failed", failed["status"])
        failed_rows = retention.list_retention_runs(status="failed")
        self.assertTrue(any(row["run_id"] == failed["run_id"] for row in failed_rows))

        with (
            patch("src.retention.get_settings", return_value=_DummyRetentionSettings()),
            patch("src.retention.get_supabase", return_value=_FakeSupabaseClient(store)),
        ):
            replayed = retention.replay_retention_run(
                failed["run_id"],
                request_id="req-replay-001",
                correlation_id="corr-replay-001",
                now_utc=now_utc,
            )

        self.assertEqual("succeeded", replayed["status"])
        self.assertEqual(failed["run_id"], replayed["replay_of_run_id"])
        self.assertEqual("req-replay-001", replayed["request_id"])
        self.assertEqual("corr-replay-001", replayed["correlation_id"])

    def test_scheduled_gating_runs_once_after_schedule_per_day(self):
        tz = retention.get_retention_schedule_timezone()

        before_schedule = datetime(2026, 3, 23, 1, 20, tzinfo=tz)
        after_schedule = datetime(2026, 3, 23, 1, 31, tzinfo=tz)

        self.assertFalse(
            retention.should_execute_scheduled_retention(
                before_schedule,
                schedule_hour=1,
                schedule_minute=30,
                last_attempt_day_key=None,
            )
        )

        self.assertTrue(
            retention.should_execute_scheduled_retention(
                after_schedule,
                schedule_hour=1,
                schedule_minute=30,
                last_attempt_day_key=None,
            )
        )

        self.assertFalse(
            retention.should_execute_scheduled_retention(
                after_schedule,
                schedule_hour=1,
                schedule_minute=30,
                last_attempt_day_key="2026-03-23",
            )
        )


class RetentionAdminApiTests(unittest.TestCase):
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
            "vieweruser": {
                "password": server._hash_pw("viewer-password-123"),
                "role": "viewer",
                "display_name": "Viewer User",
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
        self.original_rate_limit_api = self.settings.rate_limit_api
        self.original_rate_limit_sync = self.settings.rate_limit_sync
        self.settings.rate_limit_api = "1000/minute"
        self.settings.rate_limit_sync = "1000/minute"
        self.addCleanup(self._restore_rate_limits)

        server.sessions.clear()
        retention.clear_retention_run_history()
        self.addCleanup(server.sessions.clear)
        self.addCleanup(retention.clear_retention_run_history)

        server.sessions["admin-session"] = {
            "username": "adminuser",
            "role": "admin",
            "display_name": "Admin User",
        }
        server.sessions["viewer-session"] = {
            "username": "vieweruser",
            "role": "viewer",
            "display_name": "Viewer User",
        }

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    def _restore_rate_limits(self):
        self.settings.rate_limit_api = self.original_rate_limit_api
        self.settings.rate_limit_sync = self.original_rate_limit_sync

    def test_admin_can_list_failed_retention_runs(self):
        with patch(
            "src.server.list_retention_runs",
            return_value=[{"run_id": "ret-failed-001", "status": "failed"}],
        ) as list_mock:
            response = self.client.get(
                "/api/admin/retention/runs",
                params={"status": "failed", "limit": 20},
                cookies={"session_token": "admin-session"},
            )

        self.assertEqual(200, response.status_code)
        payload = response.json()
        self.assertEqual(1, len(payload["items"]))
        self.assertEqual("ret-failed-001", payload["items"][0]["run_id"])
        list_mock.assert_called_once_with(status="failed", limit=20)

    def test_non_admin_cannot_list_retention_runs(self):
        response = self.client.get(
            "/api/admin/retention/runs",
            cookies={"session_token": "viewer-session"},
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual({"detail": "Admin only"}, response.json())

    def test_replay_endpoint_propagates_not_found(self):
        with patch(
            "src.server.replay_retention_run",
            side_effect=LookupError("Retention run not found: ret-missing"),
        ):
            response = self.client.post(
                "/api/admin/retention/runs/ret-missing/replay",
                json={"dry_run": False},
                cookies={"session_token": "admin-session"},
            )

        self.assertEqual(404, response.status_code)
        self.assertEqual({"detail": "Retention run not found: ret-missing"}, response.json())


if __name__ == "__main__":
    unittest.main()
