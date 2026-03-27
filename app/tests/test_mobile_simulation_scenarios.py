"""Simulation-style regression tests for mobile API and sync resilience scenarios.

These tests intentionally use table-driven / scenario-based patterns to verify:
- duplicate same-day check-in replay behavior,
- ranger cross-scope access denial,
- leader team-scope filtering,
- stale updated_since rejection,
- transient EarthRanger rate-limit/backoff recovery.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import MagicMock, patch

import requests
from fastapi.testclient import TestClient

from src import server, sync


class _DummySyncSettings:
    """Minimal settings stub for sync retry simulations."""

    def __init__(
        self,
        sync_max_retries: int = 4,
        sync_retry_delay_sec: int = 2,
        sync_interval_minutes: int = 60,
    ):
        self.sync_max_retries = sync_max_retries
        self.sync_retry_delay_sec = sync_retry_delay_sec
        self.sync_interval_minutes = sync_interval_minutes


def _build_rate_limit_error(retry_after: str | None = None) -> requests.HTTPError:
    """Build a requests.HTTPError with optional 429 Retry-After header."""
    response = requests.Response()
    response.status_code = 429
    if retry_after is not None:
        response.headers["Retry-After"] = retry_after

    error = requests.HTTPError("rate limited")
    error.response = response
    return error


def _incident_event(event_id: str, updated_at: str) -> dict:
    """Return a minimal valid incident event payload for sync mapping."""
    return {
        "id": event_id,
        "updated_at": updated_at,
        "time": updated_at,
        "state": "active",
        "event_type": "incident_rep",
        "event_details": {"ranger_id": "rangeruser"},
    }


class MobileScenarioSimulationTests(unittest.TestCase):
    """Scenario-based simulations for role-scoped mobile APIs."""

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
                    "day_key": "2026-03-19",
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
                "sched-1": {
                    "schedule_id": "sched-1",
                    "ranger_id": "rangeruser",
                    "work_date": "2026-03-19",
                    "note": "Morning route",
                    "updated_by": "leaderuser",
                    "created_at": "2026-03-19T01:00:00+00:00",
                    "updated_at": "2026-03-19T01:00:00+00:00",
                },
                "sched-2": {
                    "schedule_id": "sched-2",
                    "ranger_id": "otherranger",
                    "work_date": "2026-03-20",
                    "note": "Evening route",
                    "updated_by": "leaderuser",
                    "created_at": "2026-03-20T01:00:00+00:00",
                    "updated_at": "2026-03-20T01:00:00+00:00",
                },
            }
        )

        self.schedule_repo_patches = [
            patch("src.server.ensure_schedule_schema_ready", return_value=None),
            patch("src.server.get_schedule_preflight_cache", return_value={"ok": True, "failures": []}),
            patch("src.server.list_mobile_schedule_items", side_effect=self._fake_schedule_list_items),
            patch("src.server.list_mobile_deleted_schedule_ids", side_effect=self._fake_schedule_list_deleted_ids),
        ]
        for patcher in self.schedule_repo_patches:
            patcher.start()
        for patcher in reversed(self.schedule_repo_patches):
            self.addCleanup(patcher.stop)

        self.client = TestClient(server.app)
        self.addCleanup(self.client.close)

    @staticmethod
    def _parse_iso_day(value: str | None) -> date | None:
        raw = str(value or "").strip()
        if not raw:
            return None
        return date.fromisoformat(raw)

    @staticmethod
    def _parse_iso_dt(value: str | None) -> datetime | None:
        raw = str(value or "").strip()
        if not raw:
            return None
        normalized = raw.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)

    def _fake_schedule_list_items(
        self,
        *,
        effective_ranger_id: str | None,
        visible_user_ids: set[str] | None,
        from_day: date | None,
        to_day: date | None,
        updated_since: datetime | None,
        snapshot_at: datetime,
    ) -> list[dict]:
        normalized_scope = str(effective_ranger_id or "").strip().lower()
        normalized_visible = {
            str(item or "").strip().lower()
            for item in (visible_user_ids or set())
            if str(item or "").strip()
        }

        items: list[dict] = []
        for row in server.mobile_schedule_records.values():
            ranger_id = str(row.get("ranger_id") or "").strip().lower()
            if not ranger_id:
                continue
            if normalized_scope and ranger_id != normalized_scope:
                continue
            if normalized_visible and ranger_id not in normalized_visible:
                continue

            row_day = self._parse_iso_day(row.get("work_date"))
            if row_day is None:
                continue
            if from_day and row_day < from_day:
                continue
            if to_day and row_day > to_day:
                continue

            updated_at = self._parse_iso_dt(row.get("updated_at"))
            if updated_since and (updated_at is None or updated_at < updated_since):
                continue
            if updated_at and updated_at > snapshot_at:
                continue

            items.append(
                {
                    "schedule_id": str(row.get("schedule_id") or ""),
                    "ranger_id": ranger_id,
                    "work_date": row_day.isoformat(),
                    "note": str(row.get("note") or ""),
                    "updated_by": str(row.get("updated_by") or "").strip().lower() or None,
                    "created_at": str(row.get("created_at") or "").strip() or None,
                    "updated_at": str(row.get("updated_at") or "").strip() or None,
                }
            )

        items.sort(key=lambda item: (item["work_date"], item["ranger_id"], item["schedule_id"]))
        return items

    def _fake_schedule_list_deleted_ids(
        self,
        *,
        effective_ranger_id: str | None,
        visible_user_ids: set[str] | None,
        from_day: date | None,
        to_day: date | None,
        updated_since: datetime | None,
        snapshot_at: datetime,
    ) -> list[str]:
        _ = (effective_ranger_id, visible_user_ids, from_day, to_day, updated_since, snapshot_at)
        return []

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

    def test_duplicate_same_day_checkin_replay_table(self):
        ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")
        fixed_now_utc = datetime(2026, 3, 20, 1, 0, tzinfo=timezone.utc)

        scenarios = [
            {"idempotency_key": "replay-client-key", "expected_status": "created", "expected_rows": 1},
            {
                "idempotency_key": "replay-client-key",
                "expected_status": "already_exists",
                "expected_rows": 1,
            },
            {
                "idempotency_key": "another-client-key-same-day",
                "expected_status": "already_exists",
                "expected_rows": 1,
            },
        ]

        with patch("src.server._utcnow", return_value=fixed_now_utc):
            for scenario in scenarios:
                with self.subTest(scenario=scenario):
                    response = self.client.post(
                        "/api/mobile/checkins",
                        headers=ranger_headers,
                        json={"idempotency_key": scenario["idempotency_key"]},
                    )

                    self.assertEqual(200, response.status_code)
                    payload = response.json()
                    self.assertEqual(scenario["expected_status"], payload["status"])
                    self.assertEqual("2026-03-20", payload["day_key"])
                    self.assertEqual("rangeruser", payload["user_id"])
                    self.assertEqual(scenario["expected_rows"], len(server.mobile_daily_checkins))

        rows_for_day = [
            row
            for row in server.mobile_work_summary_records
            if row.get("ranger_id") == "rangeruser" and row.get("day_key") == "2026-03-20"
        ]
        self.assertEqual(1, len(rows_for_day))
        self.assertTrue(rows_for_day[0]["has_checkin"])

    def test_ranger_cross_scope_access_denial_table(self):
        ranger_headers = self._login_headers("rangeruser", "safe-ranger-password")
        scenarios = [
            {"endpoint": "/api/mobile/work-management", "params": {"ranger_id": "otherranger"}},
            {"endpoint": "/api/mobile/incidents", "params": {"ranger_id": "otherranger"}},
            {"endpoint": "/api/mobile/schedules", "params": {"ranger_id": "otherranger"}},
        ]

        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                response = self.client.get(
                    scenario["endpoint"],
                    params=scenario["params"],
                    headers=ranger_headers,
                )
                self.assertEqual(403, response.status_code)
                self.assertEqual({"detail": "Ranger scope violation"}, response.json())

    def test_leader_team_scope_filtering_table(self):
        leader_headers = self._login_headers("leaderuser", "strong-password-123")

        scenarios = [
            {
                "endpoint": "/api/mobile/work-management",
                "team_total": 2,
                "filtered_total": 1,
            },
            {
                "endpoint": "/api/mobile/incidents",
                "team_total": 2,
                "filtered_total": 1,
            },
            {
                "endpoint": "/api/mobile/schedules",
                "team_total": 2,
                "filtered_total": 1,
            },
        ]

        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                team_scope = self.client.get(scenario["endpoint"], headers=leader_headers)
                self.assertEqual(200, team_scope.status_code)
                team_payload = team_scope.json()

                self.assertTrue(team_payload["scope"]["team_scope"])
                self.assertIsNone(team_payload["scope"]["effective_ranger_id"])
                self.assertEqual(scenario["team_total"], team_payload["pagination"]["total"])

                filtered = self.client.get(
                    scenario["endpoint"],
                    params={"ranger_id": " otherranger "},
                    headers=leader_headers,
                )
                self.assertEqual(200, filtered.status_code)
                filtered_payload = filtered.json()

                self.assertFalse(filtered_payload["scope"]["team_scope"])
                self.assertEqual("otherranger", filtered_payload["scope"]["effective_ranger_id"])
                self.assertEqual(scenario["filtered_total"], filtered_payload["pagination"]["total"])
                self.assertTrue(
                    all(item.get("ranger_id") == "otherranger" for item in filtered_payload["items"])
                )

    def test_stale_updated_since_rejection_table(self):
        leader_headers = self._login_headers("leaderuser", "strong-password-123")

        max_age_days = int(self.settings.mobile_updated_since_max_age_days)
        current_now = server._utcnow()
        stale_values = [
            (current_now - timedelta(days=max_age_days + 1)).isoformat().replace("+00:00", "Z"),
            (current_now - timedelta(days=max_age_days, seconds=1)).isoformat().replace("+00:00", "Z"),
        ]

        scenarios = [
            {"endpoint": "/api/mobile/incidents"},
            {"endpoint": "/api/mobile/schedules"},
        ]

        for scenario in scenarios:
            for stale_updated_since in stale_values:
                with self.subTest(endpoint=scenario["endpoint"], updated_since=stale_updated_since):
                    response = self.client.get(
                        scenario["endpoint"],
                        params={"updated_since": stale_updated_since},
                        headers=leader_headers,
                    )
                    self.assertEqual(400, response.status_code)
                    self.assertIn("updated_since is too old", response.json()["detail"])


class SyncBackoffRecoverySimulationTests(unittest.TestCase):
    """Scenario-based simulations for transient EarthRanger backoff recovery."""

    def test_transient_earthranger_rate_limit_backoff_recovery_table(self):
        scenarios = [
            {
                "name": "retry_after_header_precedence",
                "side_effects": [
                    _build_rate_limit_error(retry_after="7"),
                    [_incident_event("er-9001", "2026-03-20T04:00:00Z")],
                ],
                "jitter_values": [0.25],
                "expected_sleep_delays": [7.0],
                "expected_jitter_calls": 0,
            },
            {
                "name": "exponential_jitter_then_recovery",
                "side_effects": [
                    _build_rate_limit_error(),
                    requests.ConnectionError("temporary connection reset"),
                    [_incident_event("er-9002", "2026-03-20T05:00:00Z")],
                ],
                "jitter_values": [0.5, 1.0],
                "expected_sleep_delays": [2.5, 5.0],
                "expected_jitter_calls": 2,
            },
        ]

        for scenario in scenarios:
            with self.subTest(name=scenario["name"]):
                er_client = MagicMock()
                er_client.get_events.side_effect = scenario["side_effects"]

                with (
                    patch(
                        "src.sync.get_settings",
                        return_value=_DummySyncSettings(sync_max_retries=4, sync_retry_delay_sec=2),
                    ),
                    patch("src.sync.get_er_client", return_value=er_client),
                    patch("src.sync.get_sync_cursor", return_value=None),
                    patch("src.sync.upsert_incidents", return_value=1),
                    patch("src.sync.set_sync_cursor"),
                    patch("src.sync.random.uniform", side_effect=scenario["jitter_values"]) as jitter_mock,
                    patch("src.sync.time.sleep") as sleep_mock,
                ):
                    result = sync.run_incident_sync_cycle()

                self.assertTrue(result["ok"])
                self.assertEqual(
                    len(scenario["expected_sleep_delays"]),
                    sleep_mock.call_count,
                )

                actual_delays = [call.args[0] for call in sleep_mock.call_args_list]
                for idx, expected_delay in enumerate(scenario["expected_sleep_delays"]):
                    self.assertAlmostEqual(expected_delay, actual_delays[idx], places=6)

                self.assertEqual(scenario["expected_jitter_calls"], jitter_mock.call_count)


if __name__ == "__main__":
    unittest.main()