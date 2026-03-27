"""Unit tests for sync cursor persistence semantics in supabase_db."""

import unittest
from unittest.mock import patch

from src import supabase_db


class _FakeResult:
    def __init__(self, data):
        self.data = data


class _FakeSyncCursorTable:
    def __init__(self, store: dict, insert_side_effect=None, force_update_noop: bool = False):
        self.store = store
        self.insert_side_effect = insert_side_effect
        self.force_update_noop = force_update_noop
        self._reset()

    def _reset(self):
        self._op = None
        self._payload = None
        self._filters = {}
        self._is_filters = {}
        self._select_fields = None

    def select(self, fields: str):
        self._op = "select"
        self._select_fields = fields
        return self

    def update(self, payload: dict):
        self._op = "update"
        self._payload = payload
        return self

    def insert(self, payload: dict):
        self._op = "insert"
        self._payload = payload
        return self

    def eq(self, key: str, value):
        self._filters[key] = value
        return self

    def is_(self, key: str, value):
        self._is_filters[key] = value
        return self

    def maybe_single(self):
        return self

    def execute(self):
        try:
            if self._op == "select":
                stream_name = self._filters.get("stream_name")
                row = self.store.get(stream_name)
                if not row:
                    return _FakeResult(None)

                fields = [f.strip() for f in str(self._select_fields or "").split(",") if f.strip()]
                if not fields:
                    return _FakeResult(dict(row))
                return _FakeResult({field: row.get(field) for field in fields})

            if self._op == "update":
                stream_name = self._filters.get("stream_name")
                row = self.store.get(stream_name)
                if not row:
                    return _FakeResult([])

                if "cursor_value" in self._filters and str(row.get("cursor_value")) != str(self._filters["cursor_value"]):
                    return _FakeResult([])

                if "cursor_value" in self._is_filters:
                    expected = str(self._is_filters["cursor_value"]).strip().lower()
                    if expected == "null" and row.get("cursor_value") is not None:
                        return _FakeResult([])

                if self.force_update_noop:
                    return _FakeResult([])

                row.update(self._payload or {})
                self.store[stream_name] = row
                return _FakeResult([dict(row)])

            if self._op == "insert":
                if callable(self.insert_side_effect):
                    effect = self.insert_side_effect
                    self.insert_side_effect = None
                    maybe_exc = effect(self._payload, self.store)
                    if isinstance(maybe_exc, Exception):
                        raise maybe_exc

                stream_name = str((self._payload or {}).get("stream_name") or "")
                if stream_name in self.store:
                    raise RuntimeError("duplicate key value violates unique constraint")

                self.store[stream_name] = dict(self._payload or {})
                return _FakeResult([dict(self.store[stream_name])])

            raise RuntimeError(f"Unsupported fake operation: {self._op}")
        finally:
            self._reset()


class _FakeSupabaseClient:
    def __init__(self, table: _FakeSyncCursorTable):
        self._table = table

    def table(self, name: str):
        if name != "sync_cursors":
            raise AssertionError(f"Unexpected table requested in test: {name}")
        return self._table


class SyncCursorPersistenceTests(unittest.TestCase):
    def test_get_sync_cursor_raises_on_invalid_stored_value(self):
        store = {
            "incidents": {
                "stream_name": "incidents",
                "cursor_value": "not-a-date",
                "updated_at": "2026-03-20T00:00:00+00:00",
            }
        }
        table = _FakeSyncCursorTable(store)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            with self.assertRaises(ValueError):
                supabase_db.get_sync_cursor("incidents")

    def test_set_sync_cursor_updates_newer_candidate(self):
        store = {
            "incidents": {
                "stream_name": "incidents",
                "cursor_value": "2026-03-20T01:00:00Z",
                "updated_at": "2026-03-20T01:00:00+00:00",
            }
        }
        table = _FakeSyncCursorTable(store)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            result = supabase_db.set_sync_cursor("incidents", "2026-03-20T02:00:00+00:00")

        self.assertEqual("2026-03-20T02:00:00+00:00", result["cursor_value"])
        self.assertEqual("2026-03-20T02:00:00+00:00", store["incidents"]["cursor_value"])

    def test_set_sync_cursor_updates_existing_null_cursor(self):
        store = {
            "incidents": {
                "stream_name": "incidents",
                "cursor_value": None,
                "updated_at": "2026-03-20T00:00:00+00:00",
            }
        }
        table = _FakeSyncCursorTable(store)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            result = supabase_db.set_sync_cursor("incidents", "2026-03-20T02:00:00+00:00")

        self.assertEqual("2026-03-20T02:00:00+00:00", result["cursor_value"])
        self.assertEqual("2026-03-20T02:00:00+00:00", store["incidents"]["cursor_value"])

    def test_set_sync_cursor_updates_existing_empty_string_cursor(self):
        store = {
            "incidents": {
                "stream_name": "incidents",
                "cursor_value": "",
                "updated_at": "2026-03-20T00:00:00+00:00",
            }
        }
        table = _FakeSyncCursorTable(store)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            result = supabase_db.set_sync_cursor("incidents", "2026-03-20T02:00:00+00:00")

        self.assertEqual("2026-03-20T02:00:00+00:00", result["cursor_value"])
        self.assertEqual("2026-03-20T02:00:00+00:00", store["incidents"]["cursor_value"])

    def test_set_sync_cursor_rejects_non_conflict_insert_errors(self):
        store = {}

        def _non_conflict_failure(_payload, _store):
            return RuntimeError("database network unavailable")

        table = _FakeSyncCursorTable(store, insert_side_effect=_non_conflict_failure)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            with self.assertRaises(RuntimeError):
                supabase_db.set_sync_cursor("incidents", "2026-03-20T02:00:00+00:00")

        self.assertFalse(store)

    def test_set_sync_cursor_handles_insert_race_with_newer_existing_value(self):
        store = {}

        def _race_insert(payload, current_store):
            current_store[payload["stream_name"]] = {
                "stream_name": payload["stream_name"],
                "cursor_value": "2026-03-20T05:00:00+00:00",
                "updated_at": "2026-03-20T05:00:00+00:00",
            }
            return RuntimeError("duplicate key value violates unique constraint")

        table = _FakeSyncCursorTable(store, insert_side_effect=_race_insert)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            result = supabase_db.set_sync_cursor("incidents", "2026-03-20T04:00:00+00:00")

        self.assertEqual("2026-03-20T05:00:00+00:00", result["cursor_value"])
        self.assertEqual("2026-03-20T05:00:00+00:00", store["incidents"]["cursor_value"])

    def test_set_sync_cursor_raises_if_contention_keeps_cursor_older_than_candidate(self):
        store = {
            "incidents": {
                "stream_name": "incidents",
                "cursor_value": "2026-03-20T01:00:00+00:00",
                "updated_at": "2026-03-20T01:00:00+00:00",
            }
        }
        table = _FakeSyncCursorTable(store, force_update_noop=True)

        with patch("src.supabase_db.get_supabase", return_value=_FakeSupabaseClient(table)):
            with self.assertRaises(RuntimeError):
                supabase_db.set_sync_cursor("incidents", "2026-03-20T02:00:00+00:00")


if __name__ == "__main__":
    unittest.main()
