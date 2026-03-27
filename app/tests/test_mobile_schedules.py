"""Regression tests for DB-backed mobile schedules read/write endpoints."""

from datetime import date, datetime, timezone
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from src import server
from src.supabase_db import (
    ScheduleConflictError,
    ScheduleNotFoundError,
    ScheduleReadinessError,
)


LEADER_PASSWORD_HASH = server._hash_pw("strong-password-123")
FIELD_LEADER_PASSWORD_HASH = server._hash_pw("field-leader-password")
RANGER_PASSWORD_HASH = server._hash_pw("safe-ranger-password")
OTHER_RANGER_PASSWORD_HASH = server._hash_pw("another-ranger-password")


def _iso_to_datetime(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


class _FakeScheduleRepository:
    """In-memory repository double that mimics DB-backed schedule behavior."""

    def __init__(self, rows: list[dict]):
        self._rows: dict[str, dict] = {}
        self._sequence = 100
        self._now_sequence = 0
        self.readiness_error: str | None = None

        for row in rows:
            normalized = self._normalize_row(row)
            self._rows[normalized["schedule_id"]] = normalized

    @staticmethod
    def _normalize_username(value: str | None) -> str:
        return str(value or "").strip().lower()

    @staticmethod
    def _normalize_note(value: str | None) -> str:
        return str(value or "").strip()

    def _next_now_iso(self) -> str:
        self._now_sequence += 1
        return datetime(2026, 3, 25, 0, 0, self._now_sequence, tzinfo=timezone.utc).isoformat()

    def _normalize_row(self, row: dict) -> dict:
        return {
            "schedule_id": str(row.get("schedule_id") or "").strip(),
            "ranger_id": self._normalize_username(row.get("ranger_id") or row.get("username")),
            "work_date": str(row.get("work_date") or "").strip(),
            "note": str(row.get("note") or ""),
            "updated_by": self._normalize_username(row.get("updated_by") or row.get("updated_by_username")),
            "created_at": str(row.get("created_at") or self._next_now_iso()).strip(),
            "updated_at": str(row.get("updated_at") or self._next_now_iso()).strip(),
            "deleted_at": row.get("deleted_at"),
        }

    @staticmethod
    def _to_api_item(row: dict) -> dict:
        return {
            "schedule_id": row["schedule_id"],
            "ranger_id": row["ranger_id"],
            "work_date": row["work_date"],
            "note": row["note"],
            "updated_by": row["updated_by"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    @staticmethod
    def _row_work_day(row: dict) -> date:
        return date.fromisoformat(str(row.get("work_date") or ""))

    @staticmethod
    def _row_updated_at(row: dict) -> datetime:
        return _iso_to_datetime(str(row.get("updated_at") or ""))

    def preflight_cache(self) -> dict:
        if self.readiness_error:
            return {"ok": False, "failures": [self.readiness_error]}
        return {"ok": True, "failures": []}

    def ensure_ready(self, force: bool = False):
        _ = force
        if self.readiness_error:
            raise ScheduleReadinessError(self.readiness_error)

    def seed_schedule(
        self,
        *,
        schedule_id: str,
        ranger_id: str,
        work_date: str,
        note: str,
        updated_by: str,
        created_at: str,
        updated_at: str,
        deleted_at: str | None = None,
    ) -> None:
        self._rows[schedule_id] = self._normalize_row(
            {
                "schedule_id": schedule_id,
                "ranger_id": ranger_id,
                "work_date": work_date,
                "note": note,
                "updated_by": updated_by,
                "created_at": created_at,
                "updated_at": updated_at,
                "deleted_at": deleted_at,
            }
        )

    def get_row(self, schedule_id: str) -> dict | None:
        row = self._rows.get(schedule_id)
        return dict(row) if isinstance(row, dict) else None

    def get_item(self, *, schedule_id: str) -> dict:
        self.ensure_ready()

        normalized_schedule_id = str(schedule_id or "").strip()
        row = self._rows.get(normalized_schedule_id)
        if not row or row.get("deleted_at") not in (None, ""):
            raise ScheduleNotFoundError("Schedule not found")

        return self._to_api_item(row)

    def _has_active_conflict(self, *, work_date: str, ranger_id: str, ignore_schedule_id: str | None = None) -> bool:
        for row in self._rows.values():
            if row.get("deleted_at") not in (None, ""):
                continue
            if ignore_schedule_id and row.get("schedule_id") == ignore_schedule_id:
                continue
            if row.get("work_date") == work_date and row.get("ranger_id") == ranger_id:
                return True
        return False

    def list_items(
        self,
        *,
        effective_ranger_id: str | None,
        visible_user_ids: set[str] | None,
        from_day: date | None,
        to_day: date | None,
        updated_since: datetime | None,
        snapshot_at: datetime,
    ) -> list[dict]:
        self.ensure_ready()

        normalized_scope = self._normalize_username(effective_ranger_id)
        normalized_visible = {
            self._normalize_username(item)
            for item in (visible_user_ids or set())
            if self._normalize_username(item)
        }

        items: list[dict] = []
        for row in self._rows.values():
            if row.get("deleted_at") not in (None, ""):
                continue

            ranger_id = self._normalize_username(row.get("ranger_id"))
            if normalized_scope and ranger_id != normalized_scope:
                continue
            if normalized_visible and ranger_id not in normalized_visible:
                continue

            row_day = self._row_work_day(row)
            if from_day and row_day < from_day:
                continue
            if to_day and row_day > to_day:
                continue

            updated_at = self._row_updated_at(row)
            if updated_since and updated_at < updated_since:
                continue
            if updated_at > snapshot_at:
                continue

            items.append(self._to_api_item(row))

        items.sort(key=lambda item: (item["work_date"], item["ranger_id"], item["schedule_id"]))
        return items

    def list_deleted_ids(
        self,
        *,
        effective_ranger_id: str | None,
        visible_user_ids: set[str] | None,
        from_day: date | None,
        to_day: date | None,
        updated_since: datetime | None,
        snapshot_at: datetime,
    ) -> list[str]:
        self.ensure_ready()

        if updated_since is None:
            return []

        normalized_scope = self._normalize_username(effective_ranger_id)
        normalized_visible = {
            self._normalize_username(item)
            for item in (visible_user_ids or set())
            if self._normalize_username(item)
        }

        deleted_rows: list[tuple[datetime, str]] = []
        seen_ids: set[str] = set()
        for row in self._rows.values():
            if row.get("deleted_at") in (None, ""):
                continue

            ranger_id = self._normalize_username(row.get("ranger_id"))
            if normalized_scope and ranger_id != normalized_scope:
                continue
            if normalized_visible and ranger_id not in normalized_visible:
                continue

            row_day = self._row_work_day(row)
            if from_day and row_day < from_day:
                continue
            if to_day and row_day > to_day:
                continue

            updated_at = self._row_updated_at(row)
            if updated_at < updated_since or updated_at > snapshot_at:
                continue

            schedule_id = str(row.get("schedule_id") or "").strip()
            if not schedule_id or schedule_id in seen_ids:
                continue
            seen_ids.add(schedule_id)
            deleted_rows.append((updated_at, schedule_id))

        deleted_rows.sort(key=lambda item: (item[0], item[1]))
        return [schedule_id for _, schedule_id in deleted_rows]

    def create(
        self,
        *,
        ranger_id: str,
        work_day: date,
        note: str,
        actor_username: str,
        actor_display_name: str,
    ) -> dict:
        self.ensure_ready()
        _ = actor_display_name

        normalized_ranger_id = self._normalize_username(ranger_id)
        normalized_actor = self._normalize_username(actor_username)
        work_date = work_day.isoformat()

        if self._has_active_conflict(work_date=work_date, ranger_id=normalized_ranger_id):
            raise ScheduleConflictError(
                "duplicate key value violates unique constraint uq_schedules_active_assignment"
            )

        self._sequence += 1
        schedule_id = f"db-{self._sequence}"
        now_iso = self._next_now_iso()

        row = {
            "schedule_id": schedule_id,
            "ranger_id": normalized_ranger_id,
            "work_date": work_date,
            "note": self._normalize_note(note),
            "updated_by": normalized_actor,
            "created_at": now_iso,
            "updated_at": now_iso,
            "deleted_at": None,
        }
        self._rows[schedule_id] = row
        return self._to_api_item(row)

    def update(
        self,
        *,
        schedule_id: str,
        ranger_id: str,
        work_day: date,
        note: str,
        actor_username: str,
        actor_display_name: str,
    ) -> dict:
        self.ensure_ready()
        _ = actor_display_name

        normalized_schedule_id = str(schedule_id or "").strip()
        row = self._rows.get(normalized_schedule_id)
        if not row or row.get("deleted_at") not in (None, ""):
            raise ScheduleNotFoundError("Schedule not found")

        normalized_ranger_id = self._normalize_username(ranger_id)
        work_date = work_day.isoformat()
        if self._has_active_conflict(
            work_date=work_date,
            ranger_id=normalized_ranger_id,
            ignore_schedule_id=normalized_schedule_id,
        ):
            raise ScheduleConflictError(
                "duplicate key value violates unique constraint uq_schedules_active_assignment"
            )

        row["ranger_id"] = normalized_ranger_id
        row["work_date"] = work_date
        row["note"] = self._normalize_note(note)
        row["updated_by"] = self._normalize_username(actor_username)
        row["updated_at"] = self._next_now_iso()
        self._rows[normalized_schedule_id] = row
        return self._to_api_item(row)

    def soft_delete(
        self,
        *,
        schedule_id: str,
        actor_username: str,
        actor_display_name: str,
    ) -> dict:
        self.ensure_ready()
        _ = actor_display_name

        normalized_schedule_id = str(schedule_id or "").strip()
        row = self._rows.get(normalized_schedule_id)
        if not row or row.get("deleted_at") not in (None, ""):
            raise ScheduleNotFoundError("Schedule not found")

        now_iso = self._next_now_iso()
        row["deleted_at"] = now_iso
        row["updated_at"] = now_iso
        row["updated_by"] = self._normalize_username(actor_username)
        self._rows[normalized_schedule_id] = row

        return {
            "schedule_id": normalized_schedule_id,
            "deleted_at": now_iso,
            "updated_by": row["updated_by"],
        }


class MobileScheduleTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.users_file = Path(self.temp_dir.name) / "users.json"

        users = {
            "leaderuser": {
                "password": LEADER_PASSWORD_HASH,
                "role": "admin",
                "display_name": "Leader User",
            },
            "fieldleader": {
                "password": FIELD_LEADER_PASSWORD_HASH,
                "role": "leader",
                "display_name": "Field Leader",
            },
            "rangeruser": {
                "password": RANGER_PASSWORD_HASH,
                "role": "viewer",
                "display_name": "Ranger User",
            },
            "otherranger": {
                "password": OTHER_RANGER_PASSWORD_HASH,
                "role": "viewer",
                "display_name": "Other Ranger",
            },
        }
        self.users_file.write_text(json.dumps(users, ensure_ascii=False, indent=2), encoding="utf-8")

        seed_rows = [
            {
                "schedule_id": "seed-1",
                "ranger_id": "rangeruser",
                "work_date": "2026-03-19",
                "note": "Morning route",
                "updated_by": "leaderuser",
                "created_at": "2026-03-18T10:00:00+00:00",
                "updated_at": "2026-03-18T10:00:00+00:00",
            },
            {
                "schedule_id": "seed-2",
                "ranger_id": "rangeruser",
                "work_date": "2026-03-21",
                "note": "Night route",
                "updated_by": "leaderuser",
                "created_at": "2026-03-20T10:00:00+00:00",
                "updated_at": "2026-03-20T10:00:00+00:00",
            },
            {
                "schedule_id": "seed-3",
                "ranger_id": "otherranger",
                "work_date": "2026-03-20",
                "note": "Bridge watch",
                "updated_by": "leaderuser",
                "created_at": "2026-03-19T10:00:00+00:00",
                "updated_at": "2026-03-19T10:00:00+00:00",
            },
            {
                "schedule_id": "seed-4",
                "ranger_id": "otherranger",
                "work_date": "2026-03-22",
                "note": "Camera sweep",
                "updated_by": "leaderuser",
                "created_at": "2026-03-21T10:00:00+00:00",
                "updated_at": "2026-03-21T10:00:00+00:00",
            },
        ]
        self.repo = _FakeScheduleRepository(seed_rows)

        self.users_patch = patch("src.server.USERS_FILE", str(self.users_file))
        self.run_loop_patch = patch("src.server.run_loop", lambda: None)
        self.schedule_patches = [
            patch("src.server.ensure_schedule_schema_ready", side_effect=self.repo.ensure_ready),
            patch("src.server.get_schedule_preflight_cache", side_effect=self.repo.preflight_cache),
            patch("src.server.list_mobile_schedule_items", side_effect=self.repo.list_items),
            patch("src.server.list_mobile_deleted_schedule_ids", side_effect=self.repo.list_deleted_ids),
            patch("src.server.get_mobile_schedule_item", side_effect=self.repo.get_item),
            patch("src.server.create_mobile_schedule", side_effect=self.repo.create),
            patch("src.server.update_mobile_schedule", side_effect=self.repo.update),
            patch("src.server.soft_delete_mobile_schedule", side_effect=self.repo.soft_delete),
        ]

        self.users_patch.start()
        self.run_loop_patch.start()
        for patcher in self.schedule_patches:
            patcher.start()

        self.addCleanup(self.users_patch.stop)
        self.addCleanup(self.run_loop_patch.stop)
        for patcher in reversed(self.schedule_patches):
            self.addCleanup(patcher.stop)

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

    def _login(self, username: str, password: str) -> dict:
        response = self.client.post(
            "/api/mobile/auth/login",
            json={"username": username, "password": password},
        )
        self.assertEqual(200, response.status_code)
        return response.json()

    def _login_headers(self, username: str, password: str) -> tuple[dict, dict]:
        tokens = self._login(username, password)
        return {"Authorization": f"Bearer {tokens['access_token']}"}, tokens

    def _assert_iso_datetime(self, value: str):
        self.assertIsInstance(value, str)
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        self.assertIsNotNone(parsed)

    def test_ranger_self_scope_and_cross_ranger_denial(self):
        headers, _ = self._login_headers("rangeruser", "safe-ranger-password")

        denied = self.client.get(
            "/api/mobile/schedules",
            params={"ranger_id": "otherranger"},
            headers=headers,
        )
        self.assertEqual(403, denied.status_code)
        self.assertEqual({"detail": "Ranger scope violation"}, denied.json())

        allowed = self.client.get("/api/mobile/schedules", headers=headers)
        self.assertEqual(200, allowed.status_code)
        payload = allowed.json()

        self.assertEqual("ranger", payload["scope"]["role"])
        self.assertFalse(payload["scope"]["team_scope"])
        self.assertEqual("rangeruser", payload["scope"]["effective_ranger_id"])
        self.assertEqual(2, len(payload["items"]))
        self.assertTrue(all(item["ranger_id"] == "rangeruser" for item in payload["items"]))

    def test_leader_team_scope_ranger_filter_and_date_filters(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        team_scope = self.client.get("/api/mobile/schedules", headers=headers)
        self.assertEqual(200, team_scope.status_code)
        team_payload = team_scope.json()

        self.assertEqual("leader", team_payload["scope"]["role"])
        self.assertTrue(team_payload["scope"]["team_scope"])
        self.assertIsNone(team_payload["scope"]["effective_ranger_id"])
        self.assertEqual(4, len(team_payload["items"]))

        filtered = self.client.get(
            "/api/mobile/schedules",
            params={"ranger_id": "otherranger"},
            headers=headers,
        )
        self.assertEqual(200, filtered.status_code)
        filtered_payload = filtered.json()

        self.assertFalse(filtered_payload["scope"]["team_scope"])
        self.assertEqual("otherranger", filtered_payload["scope"]["effective_ranger_id"])
        self.assertEqual(2, len(filtered_payload["items"]))

        ranged = self.client.get(
            "/api/mobile/schedules",
            params={"from": "2026-03-20", "to": "2026-03-21"},
            headers=headers,
        )
        self.assertEqual(200, ranged.status_code)
        ranged_payload = ranged.json()

        self.assertEqual("2026-03-20", ranged_payload["filters"]["from"])
        self.assertEqual("2026-03-21", ranged_payload["filters"]["to"])
        self.assertEqual(2, len(ranged_payload["items"]))

    def test_schedule_requested_ranger_id_echo_is_normalized(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/schedules",
            params={"ranger_id": "  OTHERranger  "},
            headers=headers,
        )

        self.assertEqual(200, response.status_code)
        payload = response.json()

        self.assertEqual("otherranger", payload["scope"]["requested_ranger_id"])
        self.assertEqual("otherranger", payload["scope"]["effective_ranger_id"])

    def test_admin_scope_can_view_leader_and_ranger_assignments(self):
        self.repo.seed_schedule(
            schedule_id="seed-leader",
            ranger_id="fieldleader",
            work_date="2026-03-23",
            note="Leader planning shift",
            updated_by="leaderuser",
            created_at="2026-03-22T10:00:00+00:00",
            updated_at="2026-03-22T10:00:00+00:00",
        )

        headers, _ = self._login_headers("leaderuser", "strong-password-123")
        response = self.client.get("/api/mobile/schedules", headers=headers)
        self.assertEqual(200, response.status_code)

        payload = response.json()
        self.assertEqual("admin", payload["scope"]["account_role"])
        self.assertTrue(any(item["ranger_id"] == "fieldleader" for item in payload["items"]))

        directory = {item["username"]: item for item in payload["directory"]}
        self.assertEqual("leader", directory["fieldleader"]["role"])
        self.assertEqual("ranger", directory["rangeruser"]["role"])

    def test_leader_scope_excludes_leader_rows_and_denies_leader_assignment(self):
        self.repo.seed_schedule(
            schedule_id="seed-leader",
            ranger_id="fieldleader",
            work_date="2026-03-23",
            note="Leader planning shift",
            updated_by="leaderuser",
            created_at="2026-03-22T10:00:00+00:00",
            updated_at="2026-03-22T10:00:00+00:00",
        )

        headers, _ = self._login_headers("fieldleader", "field-leader-password")

        response = self.client.get("/api/mobile/schedules", headers=headers)
        self.assertEqual(200, response.status_code)
        payload = response.json()

        self.assertEqual("leader", payload["scope"]["account_role"])
        self.assertTrue(all(item["ranger_id"] != "fieldleader" for item in payload["items"]))

        denied_filter = self.client.get(
            "/api/mobile/schedules",
            params={"ranger_id": "fieldleader"},
            headers=headers,
        )
        self.assertEqual(403, denied_filter.status_code)
        self.assertEqual({"detail": "Schedule scope violation"}, denied_filter.json())

        denied_assignment = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={"ranger_id": "fieldleader", "work_date": "2026-03-25", "note": "assign leader"},
        )
        self.assertEqual(403, denied_assignment.status_code)
        self.assertEqual({"detail": "Schedule assignee not permitted"}, denied_assignment.json())

    def test_non_admin_leader_cannot_update_leader_assigned_schedule(self):
        self.repo.seed_schedule(
            schedule_id="seed-leader-update",
            ranger_id="fieldleader",
            work_date="2026-03-28",
            note="Leader shift",
            updated_by="leaderuser",
            created_at="2026-03-27T10:00:00+00:00",
            updated_at="2026-03-27T10:00:00+00:00",
        )

        headers, _ = self._login_headers("fieldleader", "field-leader-password")
        response = self.client.put(
            "/api/mobile/schedules/seed-leader-update",
            headers=headers,
            json={"ranger_id": "rangeruser", "work_date": "2026-03-29", "note": "Retarget"},
        )

        self.assertEqual(403, response.status_code)
        self.assertEqual({"detail": "Schedule assignee not permitted"}, response.json())

    def test_schedule_read_invalid_date_range_returns_400(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/schedules",
            params={"from": "2026-03-22", "to": "2026-03-20"},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual({"detail": "Invalid date range: from must be <= to"}, response.json())

    def test_schedule_read_pagination_metadata_and_bounds(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        first_page = self.client.get(
            "/api/mobile/schedules",
            params={"page": 1, "page_size": 2},
            headers=headers,
        )
        self.assertEqual(200, first_page.status_code)
        first_payload = first_page.json()

        self.assertEqual(2, len(first_payload["items"]))
        self.assertEqual(1, first_payload["pagination"]["page"])
        self.assertEqual(2, first_payload["pagination"]["page_size"])
        self.assertEqual(4, first_payload["pagination"]["total"])
        self.assertEqual(2, first_payload["pagination"]["total_pages"])

        response = self.client.get(
            "/api/mobile/schedules",
            params={"page": 3, "page_size": 2},
            headers=headers,
        )
        self.assertEqual(400, response.status_code)
        self.assertEqual({"detail": "Invalid pagination: page exceeds total_pages"}, response.json())

    def test_updated_since_sync_tombstones_are_present_and_stable_with_snapshot(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        deleted = self.client.delete("/api/mobile/schedules/seed-1", headers=headers)
        self.assertEqual(200, deleted.status_code)

        first_page = self.client.get(
            "/api/mobile/schedules",
            params={"updated_since": "2026-03-17T00:00:00Z", "page": 1, "page_size": 1},
            headers=headers,
        )
        self.assertEqual(200, first_page.status_code)
        first_payload = first_page.json()

        self.assertIn("sync", first_payload)
        self.assertIn("deleted_schedule_ids", first_payload["sync"])
        self.assertIn("seed-1", first_payload["sync"]["deleted_schedule_ids"])

        pinned_snapshot = first_payload["filters"]["snapshot_at"]
        second_page = self.client.get(
            "/api/mobile/schedules",
            params={
                "updated_since": "2026-03-17T00:00:00Z",
                "snapshot_at": pinned_snapshot,
                "page": 2,
                "page_size": 1,
            },
            headers=headers,
        )
        self.assertEqual(200, second_page.status_code)
        second_payload = second_page.json()

        self.assertEqual(
            first_payload["sync"]["deleted_schedule_ids"],
            second_payload["sync"]["deleted_schedule_ids"],
        )

    def test_schedule_read_invalid_snapshot_at_returns_400(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/schedules",
            params={"snapshot_at": "not-a-datetime"},
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertIn("Invalid datetime format", response.json()["detail"])

    def test_schedule_read_snapshot_must_be_after_updated_since(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.get(
            "/api/mobile/schedules",
            params={
                "updated_since": "2026-03-22T00:00:00Z",
                "snapshot_at": "2026-03-21T00:00:00Z",
            },
            headers=headers,
        )

        self.assertEqual(400, response.status_code)
        self.assertEqual({"detail": "Invalid snapshot_at: must be >= updated_since"}, response.json())

    def test_leader_write_validation_and_audit_fields(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        missing_required = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={"ranger_id": "", "work_date": "2026-03-25", "note": "test"},
        )
        self.assertEqual(400, missing_required.status_code)
        self.assertEqual({"detail": "ranger_id and work_date required"}, missing_required.json())

        invalid_date = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={"ranger_id": "rangeruser", "work_date": "2026/03/25", "note": "test"},
        )
        self.assertEqual(400, invalid_date.status_code)
        self.assertIn("Invalid date format", invalid_date.json()["detail"])

        created = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={"ranger_id": " rangeruser ", "work_date": "2026-03-25", "note": " night patrol "},
        )
        self.assertEqual(200, created.status_code)
        schedule = created.json()["schedule"]

        self.assertEqual("rangeruser", schedule["ranger_id"])
        self.assertEqual("night patrol", schedule["note"])
        self.assertEqual("leaderuser", schedule["updated_by"])
        self._assert_iso_datetime(schedule["created_at"])
        self._assert_iso_datetime(schedule["updated_at"])

        updated = self.client.put(
            f"/api/mobile/schedules/{schedule['schedule_id']}",
            headers=headers,
            json={"ranger_id": "otherranger", "work_date": "2026-03-26", "note": "updated route"},
        )
        self.assertEqual(200, updated.status_code)
        updated_schedule = updated.json()["schedule"]

        self.assertEqual("otherranger", updated_schedule["ranger_id"])
        self.assertEqual("updated route", updated_schedule["note"])
        self.assertEqual(schedule["created_at"], updated_schedule["created_at"])

    def test_schedule_conflict_maps_to_safe_409(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={"ranger_id": "rangeruser", "work_date": "2026-03-19", "note": "duplicate"},
        )

        self.assertEqual(409, response.status_code)
        self.assertEqual({"detail": "Duplicate active schedule assignment"}, response.json())

    def test_update_and_delete_missing_schedule_map_to_404(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        update_missing = self.client.put(
            "/api/mobile/schedules/missing-id",
            headers=headers,
            json={"ranger_id": "rangeruser", "work_date": "2026-03-26", "note": "updated route"},
        )
        self.assertEqual(404, update_missing.status_code)
        self.assertEqual({"detail": "Schedule not found"}, update_missing.json())

        delete_missing = self.client.delete("/api/mobile/schedules/missing-id", headers=headers)
        self.assertEqual(404, delete_missing.status_code)
        self.assertEqual({"detail": "Schedule not found"}, delete_missing.json())

    def test_admin_soft_delete_persists_actor_and_response_actor_matches(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        deleted = self.client.delete("/api/mobile/schedules/seed-1", headers=headers)
        self.assertEqual(200, deleted.status_code)
        payload = deleted.json()

        self.assertTrue(payload["ok"])
        self.assertEqual("seed-1", payload["schedule_id"])
        self.assertEqual("leaderuser", payload["deleted_by"])

        persisted = self.repo.get_row("seed-1")
        self.assertIsNotNone(persisted)
        self.assertEqual("leaderuser", persisted["updated_by"])
        self.assertIsNotNone(persisted["deleted_at"])

    def test_non_admin_cannot_delete_schedule(self):
        leader_headers, _ = self._login_headers("fieldleader", "field-leader-password")
        leader_denied = self.client.delete("/api/mobile/schedules/seed-1", headers=leader_headers)
        self.assertEqual(403, leader_denied.status_code)
        self.assertEqual({"detail": "Admin role required"}, leader_denied.json())

        ranger_headers, _ = self._login_headers("rangeruser", "safe-ranger-password")
        ranger_denied = self.client.delete("/api/mobile/schedules/seed-1", headers=ranger_headers)
        self.assertEqual(403, ranger_denied.status_code)
        self.assertEqual({"detail": "Admin role required"}, ranger_denied.json())

    def test_non_leader_schedule_writes_are_denied(self):
        headers, _ = self._login_headers("rangeruser", "safe-ranger-password")

        create_response = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={"ranger_id": "rangeruser", "work_date": "2026-03-25", "note": "attempt"},
        )
        self.assertEqual(403, create_response.status_code)
        self.assertEqual({"detail": "Leader role required"}, create_response.json())

        update_response = self.client.put(
            "/api/mobile/schedules/seed-1",
            headers=headers,
            json={"ranger_id": "rangeruser", "work_date": "2026-03-26", "note": "attempt"},
        )
        self.assertEqual(403, update_response.status_code)
        self.assertEqual({"detail": "Leader role required"}, update_response.json())

    def test_schedule_write_note_length_limit(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={
                "ranger_id": "rangeruser",
                "work_date": "2026-03-25",
                "note": "x" * 501,
            },
        )

        self.assertEqual(422, response.status_code)
        payload = response.json()
        self.assertIn("detail", payload)
        self.assertTrue(
            any("at most 500" in str(item.get("msg", "")).lower() for item in payload["detail"])
        )

    def test_schedule_write_whitespace_only_note_is_normalized(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")

        response = self.client.post(
            "/api/mobile/schedules",
            headers=headers,
            json={
                "ranger_id": "rangeruser",
                "work_date": "2026-03-25",
                "note": "   ",
            },
        )

        self.assertEqual(200, response.status_code)
        self.assertEqual("", response.json()["schedule"]["note"])

    def test_schedule_readiness_failure_returns_generic_503_without_internal_details(self):
        headers, _ = self._login_headers("leaderuser", "strong-password-123")
        self.repo.readiness_error = "Required artifact unavailable: public.schedules (relation missing)"

        response = self.client.get("/api/mobile/schedules", headers=headers)
        self.assertEqual(503, response.status_code)
        payload = response.json()

        self.assertEqual({"detail": "Schedule service unavailable"}, payload)
        self.assertNotIn("relation missing", json.dumps(payload))

    def test_invalid_role_account_role_claim_combination_returns_401(self):
        headers, login_payload = self._login_headers("leaderuser", "strong-password-123")
        access_token = login_payload["access_token"]

        server.mobile_access_sessions[access_token]["role"] = "leader"
        server.mobile_access_sessions[access_token]["account_role"] = "ranger"

        response = self.client.get("/api/mobile/schedules", headers=headers)
        self.assertEqual(401, response.status_code)
        self.assertEqual({"detail": "Invalid access token"}, response.json())


if __name__ == "__main__":
    unittest.main()
