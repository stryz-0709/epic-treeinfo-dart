"""Unit tests for schedule repository safety-cap and preflight fail-closed behavior."""

from datetime import date, datetime, timezone
import unittest
from unittest.mock import patch

from src import supabase_db


class _FakeResult:
    def __init__(self, data):
        self.data = data


class _FakeTable:
    def __init__(self, rows):
        self._rows = rows
        self._limit = None
        self._maybe_single = False

    def select(self, _fields: str):
        return self

    def eq(self, _key: str, _value):
        return self

    def gte(self, _key: str, _value):
        return self

    def lte(self, _key: str, _value):
        return self

    def in_(self, _key: str, _values):
        return self

    def is_(self, _key: str, _value):
        return self

    def limit(self, value: int):
        self._limit = value
        return self

    def maybe_single(self):
        self._maybe_single = True
        return self

    def execute(self):
        rows = self._rows
        if isinstance(rows, dict):
            rows = [rows]
        elif rows is None:
            rows = []

        if self._limit is not None:
            rows = rows[: self._limit]

        if self._maybe_single:
            return _FakeResult(rows[0] if rows else None)

        return _FakeResult(rows)


class _FakeSupabaseClient:
    def __init__(self, tables: dict[str, list[dict] | dict | None]):
        self._tables = tables

    def table(self, name: str):
        if name not in self._tables:
            raise AssertionError(f"Unexpected table requested in test: {name}")
        return _FakeTable(self._tables[name])


class ScheduleRepositorySafetyTests(unittest.TestCase):
    def test_list_mobile_schedule_items_raises_when_result_hits_safety_cap(self):
        rows = [
            {
                "schedule_id": f"sched-{index}",
                "work_date": "2026-03-20",
                "username": "rangeruser",
                "note": "route",
                "updated_by_username": "leaderuser",
                "created_at": "2026-03-19T00:00:00+00:00",
                "updated_at": "2026-03-19T00:00:00+00:00",
                "deleted_at": None,
            }
            for index in range(3)
        ]
        client = _FakeSupabaseClient({supabase_db.SCHEDULES_VIEW: rows})

        with patch.object(supabase_db, "ensure_schedule_schema_ready", return_value=None), patch.object(
            supabase_db, "get_supabase", return_value=client
        ), patch.object(supabase_db, "SCHEDULE_MAX_QUERY_ROWS", 3):
            with self.assertRaises(supabase_db.ScheduleRepositoryError):
                supabase_db.list_mobile_schedule_items(
                    effective_ranger_id=None,
                    visible_user_ids={"rangeruser"},
                    from_day=date(2026, 3, 19),
                    to_day=date(2026, 3, 21),
                    updated_since=None,
                    snapshot_at=datetime(2026, 3, 25, tzinfo=timezone.utc),
                )

    def test_list_mobile_deleted_schedule_ids_raises_when_result_hits_safety_cap(self):
        rows = [
            {
                "schedule_id": f"sched-del-{index}",
                "username": "rangeruser",
                "work_date": "2026-03-20",
                "updated_at": "2026-03-24T00:00:00+00:00",
                "deleted_at": "2026-03-24T00:00:00+00:00",
            }
            for index in range(3)
        ]
        client = _FakeSupabaseClient({supabase_db.SCHEDULES_TABLE: rows})

        with patch.object(supabase_db, "ensure_schedule_schema_ready", return_value=None), patch.object(
            supabase_db, "get_supabase", return_value=client
        ), patch.object(supabase_db, "SCHEDULE_MAX_QUERY_ROWS", 3):
            with self.assertRaises(supabase_db.ScheduleRepositoryError):
                supabase_db.list_mobile_deleted_schedule_ids(
                    effective_ranger_id=None,
                    visible_user_ids={"rangeruser"},
                    from_day=date(2026, 3, 19),
                    to_day=date(2026, 3, 21),
                    updated_since=datetime(2026, 3, 20, tzinfo=timezone.utc),
                    snapshot_at=datetime(2026, 3, 25, tzinfo=timezone.utc),
                )

    def test_identity_preflight_fails_when_active_scan_hits_safety_cap(self):
        client = _FakeSupabaseClient(
            {
                supabase_db.AUTH_USERS_TABLE: [{"username": "rangeruser"}],
                supabase_db.SCHEDULES_TABLE: [
                    {
                        "schedule_id": "sched-1",
                        "work_date": "2026-03-20",
                        "username": "rangeruser",
                        "deleted_at": None,
                    },
                    {
                        "schedule_id": "sched-2",
                        "work_date": "2026-03-21",
                        "username": "rangeruser",
                        "deleted_at": None,
                    },
                ],
            }
        )

        with patch.object(supabase_db, "get_supabase", return_value=client), patch.object(
            supabase_db, "SCHEDULE_MAX_QUERY_ROWS", 2
        ):
            failures = supabase_db._run_schedule_identity_checks()

        self.assertTrue(any("reached safety row cap" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
