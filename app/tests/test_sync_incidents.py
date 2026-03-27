"""Regression tests for Story 4.1 server-side incremental EarthRanger incident sync."""

from datetime import datetime, timezone
import unittest
from unittest.mock import MagicMock, patch

import requests

from src import sync


class _DummySettings:
    """Minimal settings stub for sync worker tests."""

    def __init__(
        self,
        sync_max_retries: int = 3,
        sync_retry_delay_sec: int = 2,
        sync_interval_minutes: int = 60,
    ):
        self.sync_max_retries = sync_max_retries
        self.sync_retry_delay_sec = sync_retry_delay_sec
        self.sync_interval_minutes = sync_interval_minutes


class IncidentSyncWorkerTests(unittest.TestCase):
    def test_runtime_cursor_read_error_returns_failed_cycle(self):
        er_client = MagicMock()

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", side_effect=RuntimeError("temporary db outage")),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertFalse(result["ok"])
        self.assertIn("Failed to load sync cursor", result["error"])
        er_client.get_events.assert_not_called()
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_tree_sync_drops_non_dict_events_without_crashing(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            "bad-tree-event",
            {
                "id": "tree-100",
                "time": "2026-03-20T00:00:00Z",
                "event_details": {"tree_id": "T-100"},
                "location": {"latitude": 10.0, "longitude": 106.0},
            },
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.upsert_trees", return_value=1) as upsert_mock,
        ):
            result = sync._run_tree_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(2, result["fetched"])
        self.assertEqual(1, result["unique"])
        self.assertEqual(1, result["upserted"])
        upsert_mock.assert_called_once()

    def test_tree_sync_accepts_results_wrapper_payload(self):
        er_client = MagicMock()
        er_client.get_events.return_value = {
            "results": [
                {
                    "id": "tree-200",
                    "time": "2026-03-20T01:00:00Z",
                    "event_details": {"tree_id": "T-200"},
                    "location": {"latitude": 10.1, "longitude": 106.1},
                }
            ]
        }

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.upsert_trees", return_value=1) as upsert_mock,
        ):
            result = sync._run_tree_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(1, result["fetched"])
        self.assertEqual(1, result["unique"])
        self.assertEqual(1, result["upserted"])
        upsert_mock.assert_called_once()

    def test_tree_sync_skips_malformed_nested_event_payloads(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "tree-bad-1",
                "time": "2026-03-20T00:00:00Z",
                "event_details": ["invalid-shape"],
                "location": {"latitude": 10.0, "longitude": 106.0},
            },
            {
                "id": "tree-good-1",
                "time": "2026-03-20T01:00:00Z",
                "event_details": {"tree_id": "T-201"},
                "location": {"latitude": 10.2, "longitude": 106.2},
            },
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.upsert_trees", return_value=1) as upsert_mock,
        ):
            result = sync._run_tree_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(2, result["fetched"])
        self.assertEqual(1, result["unique"])
        self.assertEqual(1, result["upserted"])
        upsert_mock.assert_called_once()

    def test_tree_sync_normalizes_malformed_location_and_updates(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "tree-good-2",
                "time": "2026-03-20T02:00:00Z",
                "event_details": {"tree_id": "T-202"},
                "location": "invalid-location-shape",
                "updates": "invalid-updates-shape",
            }
        ]

        captured_rows: list[dict] = []

        def _capture_rows(rows: list[dict]) -> int:
            captured_rows.extend(rows)
            return len(rows)

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.upsert_trees", side_effect=_capture_rows),
        ):
            result = sync._run_tree_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(1, result["fetched"])
        self.assertEqual(1, result["unique"])
        self.assertEqual(1, result["upserted"])
        self.assertEqual(1, len(captured_rows))
        self.assertEqual("T-202", captured_rows[0]["tree_id"])
        self.assertIsNone(captured_rows[0]["latitude"])
        self.assertIsNone(captured_rows[0]["longitude"])

    def test_run_loop_rejects_non_positive_interval(self):
        with patch("src.sync.get_settings", return_value=_DummySettings(sync_interval_minutes=0)):
            with self.assertRaises(ValueError):
                sync.run_loop()

    def test_run_loop_rejects_explicit_zero_interval_argument(self):
        with patch("src.sync.get_settings", return_value=_DummySettings(sync_interval_minutes=10)):
            with self.assertRaises(ValueError):
                sync.run_loop(0)

    def test_invalid_stored_cursor_fails_cycle_before_fetch(self):
        er_client = MagicMock()

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", side_effect=ValueError("invalid stored cursor")),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertFalse(result["ok"])
        self.assertEqual(0, result["fetched"])
        self.assertEqual(0, result["upserted"])
        self.assertIn("invalid stored cursor", result["error"])
        er_client.get_events.assert_not_called()
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_min_cursor_overlap_is_clamped_without_overflow(self):
        er_client = MagicMock()
        er_client.get_events.return_value = []

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value="0001-01-01T00:00:00+00:00"),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(0, result["fetched"])
        self.assertEqual(0, result["upserted"])
        call_kwargs = er_client.get_events.call_args.kwargs
        self.assertEqual("0001-01-01T00:00:00+00:00", call_kwargs["updated_since"].isoformat())
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_incremental_sync_uses_cursor_and_advances_high_watermark(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-1001",
                "updated_at": "2026-03-20T01:00:00Z",
                "time": "2026-03-20T00:30:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a", "severity": "high"},
            },
            {
                "id": "er-1002",
                "updated_at": "2026-03-20T03:00:00Z",
                "time": "2026-03-20T02:15:00Z",
                "state": "active",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-b", "severity": "medium"},
            },
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value="2026-03-20T00:00:00+00:00"),
            patch("src.sync.upsert_incidents", return_value=2) as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(2, result["fetched"])
        self.assertEqual(2, result["upserted"])

        call_kwargs = er_client.get_events.call_args.kwargs
        self.assertEqual("incident_rep", call_kwargs["event_type"])
        self.assertEqual(100, call_kwargs["page_size"])

        updated_since = call_kwargs["updated_since"]
        self.assertIsInstance(updated_since, datetime)
        self.assertEqual(
            "2026-03-19T23:59:59+00:00",
            updated_since.astimezone(timezone.utc).isoformat(),
        )

        upsert_rows = upsert_mock.call_args.args[0]
        self.assertEqual(2, len(upsert_rows))
        self.assertTrue(all("er_event_id" in row for row in upsert_rows))

        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T03:00:00+00:00")

    def test_retry_backoff_with_jitter_on_transient_errors(self):
        rate_limit_response = requests.Response()
        rate_limit_response.status_code = 429
        rate_limit_error = requests.HTTPError("rate limited")
        rate_limit_error.response = rate_limit_response

        er_client = MagicMock()
        er_client.get_events.side_effect = [
            rate_limit_error,
            requests.ConnectionError("temporary connection reset"),
            [
                {
                    "id": "er-2001",
                    "updated_at": "2026-03-20T04:00:00Z",
                    "time": "2026-03-20T03:00:00Z",
                    "state": "new",
                    "event_type": "incident_rep",
                    "event_details": {"ranger_id": "ranger-a"},
                }
            ],
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=4, sync_retry_delay_sec=2)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", return_value=1),
            patch("src.sync.set_sync_cursor"),
            patch("src.sync.random.uniform", side_effect=[0.5, 1.0]),
            patch("src.sync.time.sleep") as sleep_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(2, sleep_mock.call_count)

        first_delay = sleep_mock.call_args_list[0].args[0]
        second_delay = sleep_mock.call_args_list[1].args[0]
        self.assertAlmostEqual(2.5, first_delay)
        self.assertAlmostEqual(5.0, second_delay)

    def test_cursor_after_uses_persisted_cursor_value(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-2050",
                "updated_at": "2026-03-20T04:00:00Z",
                "time": "2026-03-20T03:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a"},
            }
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", side_effect=[None, None]),
            patch("src.sync.upsert_incidents", return_value=1),
            patch(
                "src.sync.set_sync_cursor",
                return_value={
                    "stream_name": "incidents",
                    "cursor_value": "2026-03-20T04:00:01+00:00",
                },
            ) as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual("2026-03-20T04:00:01+00:00", result["cursor_after"])
        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T04:00:00+00:00")

    def test_invalid_latest_cursor_is_treated_as_stale_during_write(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-2060",
                "updated_at": "2026-03-20T05:00:00Z",
                "time": "2026-03-20T04:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a"},
            }
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", side_effect=[None, ValueError("invalid latest cursor")]),
            patch("src.sync.upsert_incidents", return_value=1),
            patch(
                "src.sync.set_sync_cursor",
                return_value={"stream_name": "incidents", "cursor_value": "2026-03-20T05:00:00+00:00"},
            ) as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual("2026-03-20T05:00:00+00:00", result["cursor_after"])
        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T05:00:00+00:00")

    def test_retry_after_header_overrides_exponential_backoff(self):
        rate_limit_response = requests.Response()
        rate_limit_response.status_code = 429
        rate_limit_response.headers["Retry-After"] = "7"
        rate_limit_error = requests.HTTPError("rate limited")
        rate_limit_error.response = rate_limit_response

        er_client = MagicMock()
        er_client.get_events.side_effect = [
            rate_limit_error,
            [
                {
                    "id": "er-2099",
                    "updated_at": "2026-03-20T04:00:00Z",
                    "time": "2026-03-20T03:00:00Z",
                    "state": "new",
                    "event_type": "incident_rep",
                    "event_details": {"ranger_id": "ranger-a"},
                }
            ],
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=3, sync_retry_delay_sec=2)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", return_value=1),
            patch("src.sync.set_sync_cursor"),
            patch("src.sync.random.uniform") as jitter_mock,
            patch("src.sync.time.sleep") as sleep_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        sleep_mock.assert_called_once()
        self.assertAlmostEqual(7.0, sleep_mock.call_args.args[0])
        jitter_mock.assert_not_called()

    def test_invalid_retry_after_header_falls_back_to_exponential_backoff(self):
        rate_limit_response = requests.Response()
        rate_limit_response.status_code = 429
        rate_limit_response.headers["Retry-After"] = "invalid-delay"
        rate_limit_error = requests.HTTPError("rate limited")
        rate_limit_error.response = rate_limit_response

        er_client = MagicMock()
        er_client.get_events.side_effect = [
            rate_limit_error,
            [
                {
                    "id": "er-2100",
                    "updated_at": "2026-03-20T04:30:00Z",
                    "time": "2026-03-20T03:30:00Z",
                    "state": "new",
                    "event_type": "incident_rep",
                    "event_details": {"ranger_id": "ranger-a"},
                }
            ],
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=3, sync_retry_delay_sec=2)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", return_value=1),
            patch("src.sync.set_sync_cursor"),
            patch("src.sync.random.uniform", return_value=0.75) as jitter_mock,
            patch("src.sync.time.sleep") as sleep_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        sleep_mock.assert_called_once()
        self.assertAlmostEqual(2.75, sleep_mock.call_args.args[0])
        jitter_mock.assert_called_once()

    def test_non_retryable_incident_sync_error_fails_fast_without_sleep(self):
        er_client = MagicMock()
        er_client.get_events.side_effect = ValueError("malformed upstream query")

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=4, sync_retry_delay_sec=2)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
            patch("src.sync.time.sleep") as sleep_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertFalse(result["ok"])
        self.assertEqual(1, er_client.get_events.call_count)
        sleep_mock.assert_not_called()
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_no_new_events_does_not_advance_cursor(self):
        er_client = MagicMock()
        er_client.get_events.return_value = []

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value="2026-03-20T00:00:00+00:00"),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(0, result["fetched"])
        self.assertEqual(0, result["upserted"])
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_malformed_events_are_filtered_defensively(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-3001",
                "updated_at": "2026-03-20T05:00:00Z",
                "time": "2026-03-20T04:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a"},
            },
            {
                "updated_at": "2026-03-20T06:00:00Z",
                "time": "2026-03-20T06:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {},
            },
            {
                "id": "er-3003",
                "updated_at": "not-a-date",
                "time": "2026-03-20T06:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {},
            },
        ]

        captured_rows: list[dict] = []

        def _capture_rows(rows: list[dict]) -> int:
            captured_rows.extend(rows)
            return len(rows)

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", side_effect=_capture_rows),
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(3, result["fetched"])
        self.assertEqual(1, result["upserted"])
        self.assertEqual(1, len(captured_rows))
        self.assertEqual("er-3001", captured_rows[0]["er_event_id"])
        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T06:00:00+00:00")

    def test_malformed_top_level_payload_fails_instead_of_silent_success(self):
        er_client = MagicMock()
        er_client.get_events.return_value = {"unexpected": "payload-shape"}

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=1, sync_retry_delay_sec=1)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertFalse(result["ok"])
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_unparseable_batches_without_watermark_fail_cycle(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "",
                "updated_at": "not-a-date",
                "time": "also-not-a-date",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {},
            },
            "garbage-event-shape",
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertFalse(result["ok"])
        self.assertEqual(2, result["fetched"])
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_not_called()

    def test_duplicate_er_event_ids_are_deduplicated_before_upsert(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-4001",
                "updated_at": "2026-03-20T01:00:00Z",
                "time": "2026-03-20T00:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a", "severity": "low"},
            },
            {
                "id": "er-4001",
                "updated_at": "2026-03-20T02:00:00Z",
                "time": "2026-03-20T00:30:00Z",
                "state": "active",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a", "severity": "high"},
            },
        ]

        captured_rows: list[dict] = []

        def _capture_rows(rows: list[dict]) -> int:
            captured_rows.extend(rows)
            return len(rows)

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", side_effect=_capture_rows),
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(2, result["fetched"])
        self.assertEqual(1, result["upserted"])
        self.assertEqual(1, len(captured_rows))
        self.assertEqual("er-4001", captured_rows[0]["er_event_id"])
        self.assertEqual("high", captured_rows[0]["severity"])
        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T02:00:00+00:00")

    def test_non_dict_event_entries_are_ignored_without_crashing(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            "bad-event-shape",
            {
                "id": "er-5001",
                "updated_at": "2026-03-20T06:00:00Z",
                "time": "2026-03-20T05:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a"},
            },
            12345,
        ]

        captured_rows: list[dict] = []

        def _capture_rows(rows: list[dict]) -> int:
            captured_rows.extend(rows)
            return len(rows)

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", side_effect=_capture_rows),
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(3, result["fetched"])
        self.assertEqual(1, result["upserted"])
        self.assertEqual(1, len(captured_rows))
        self.assertEqual("er-5001", captured_rows[0]["er_event_id"])
        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T06:00:00+00:00")

    def test_all_invalid_rows_still_advance_cursor_from_source_timestamps(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "",
                "updated_at": "2026-03-20T07:00:00Z",
                "time": "2026-03-20T07:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {},
            },
            {
                "id": None,
                "updated_at": "2026-03-20T08:00:00Z",
                "time": "2026-03-20T08:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {},
            },
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents") as upsert_mock,
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual(2, result["fetched"])
        self.assertEqual(0, result["upserted"])
        upsert_mock.assert_not_called()
        set_cursor_mock.assert_called_once_with("incidents", "2026-03-20T08:00:00+00:00")

    def test_cursor_write_is_skipped_if_stream_already_advanced(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-7001",
                "updated_at": "2026-03-20T03:00:00Z",
                "time": "2026-03-20T02:00:00Z",
                "state": "active",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a"},
            }
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings()),
            patch("src.sync.get_er_client", return_value=er_client),
            patch(
                "src.sync.get_sync_cursor",
                side_effect=[
                    "2026-03-20T00:00:00+00:00",
                    "2026-03-20T05:00:00+00:00",
                ],
            ),
            patch("src.sync.upsert_incidents", return_value=1),
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])
        self.assertEqual("2026-03-20T05:00:00+00:00", result["cursor_after"])
        set_cursor_mock.assert_not_called()

    def test_cursor_is_not_advanced_when_upsert_fails(self):
        er_client = MagicMock()
        er_client.get_events.return_value = [
            {
                "id": "er-7101",
                "updated_at": "2026-03-20T09:00:00Z",
                "time": "2026-03-20T08:00:00Z",
                "state": "new",
                "event_type": "incident_rep",
                "event_details": {"ranger_id": "ranger-a"},
            }
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=1, sync_retry_delay_sec=1)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value="2026-03-20T07:00:00+00:00"),
            patch("src.sync.upsert_incidents", side_effect=RuntimeError("db unavailable")),
            patch("src.sync.set_sync_cursor") as set_cursor_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertFalse(result["ok"])
        set_cursor_mock.assert_not_called()

    def test_retry_logging_contains_traceable_sync_context(self):
        rate_limit_response = requests.Response()
        rate_limit_response.status_code = 429
        rate_limit_error = requests.HTTPError("rate limited")
        rate_limit_error.response = rate_limit_response

        er_client = MagicMock()
        er_client.get_events.side_effect = [
            rate_limit_error,
            [
                {
                    "id": "er-8001",
                    "updated_at": "2026-03-20T10:00:00Z",
                    "time": "2026-03-20T09:00:00Z",
                    "state": "active",
                    "event_type": "incident_rep",
                    "event_details": {"ranger_id": "ranger-a"},
                }
            ],
        ]

        with (
            patch("src.sync.get_settings", return_value=_DummySettings(sync_max_retries=2, sync_retry_delay_sec=2)),
            patch("src.sync.get_er_client", return_value=er_client),
            patch("src.sync.get_sync_cursor", return_value=None),
            patch("src.sync.upsert_incidents", return_value=1),
            patch("src.sync.set_sync_cursor"),
            patch("src.sync.random.uniform", return_value=0.5),
            patch("src.sync.time.sleep"),
            patch("src.sync.log") as log_mock,
        ):
            result = sync.run_incident_sync_cycle()

        self.assertTrue(result["ok"])

        error_extras = [
            call.kwargs.get("extra", {})
            for call in log_mock.error.call_args_list
            if isinstance(call.kwargs.get("extra", {}), dict)
        ]
        self.assertTrue(
            any(
                extra.get("stream_name") == "incidents"
                and extra.get("attempt") == 1
                and extra.get("retryable") is True
                for extra in error_extras
            )
        )

        retry_extras = [
            call.kwargs.get("extra", {})
            for call in log_mock.info.call_args_list
            if isinstance(call.kwargs.get("extra", {}), dict)
            and "retry_delay_sec" in call.kwargs.get("extra", {})
        ]
        self.assertTrue(retry_extras)
        self.assertEqual("incidents", retry_extras[0].get("stream_name"))
        self.assertEqual(1, retry_extras[0].get("attempt"))
        self.assertIn("retry_delay_sec", retry_extras[0])


if __name__ == "__main__":
    unittest.main()
