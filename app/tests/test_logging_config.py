"""Regression tests for structured JSON logging extras."""

from datetime import datetime, timezone
import json
import logging
import unittest

from src.logging_config import JSONFormatter


class JSONFormatterTests(unittest.TestCase):
    def test_json_formatter_preserves_custom_extra_fields(self):
        formatter = JSONFormatter()
        logger = logging.getLogger("sync.test")

        record = logger.makeRecord(
            name="sync.test",
            level=logging.INFO,
            fn=__file__,
            lno=42,
            msg="Incident sync retry",
            args=(),
            exc_info=None,
            extra={
                "stream_name": "incidents",
                "attempt": 2,
                "max_attempts": 4,
                "cursor_before": "2026-03-20T00:00:00+00:00",
                "retryable": True,
                "retry_delay_sec": 3.5,
                "stats": {"fetched": 10, "upserted": 9},
            },
        )

        payload = json.loads(formatter.format(record))

        self.assertEqual("incidents", payload["stream_name"])
        self.assertEqual(2, payload["attempt"])
        self.assertEqual(4, payload["max_attempts"])
        self.assertEqual("2026-03-20T00:00:00+00:00", payload["cursor_before"])
        self.assertTrue(payload["retryable"])
        self.assertEqual(3.5, payload["retry_delay_sec"])
        self.assertEqual({"fetched": 10, "upserted": 9}, payload["stats"])

    def test_json_formatter_handles_nested_non_serializable_values(self):
        formatter = JSONFormatter()
        logger = logging.getLogger("sync.test")

        record = logger.makeRecord(
            name="sync.test",
            level=logging.WARNING,
            fn=__file__,
            lno=90,
            msg="Nested payload",
            args=(),
            exc_info=None,
            extra={
                "stream_name": "incidents",
                "context": {
                    "occurred_at": datetime(2026, 3, 20, 12, 30, tzinfo=timezone.utc),
                    "labels": {"sync", "retry"},
                },
                "events": [
                    {
                        "id": "er-9001",
                        "seen_at": datetime(2026, 3, 20, 12, 31, tzinfo=timezone.utc),
                    }
                ],
            },
        )

        payload = json.loads(formatter.format(record))

        self.assertEqual("incidents", payload["stream_name"])
        self.assertIsInstance(payload["context"]["occurred_at"], str)
        self.assertIsInstance(payload["context"]["labels"], list)
        self.assertIsInstance(payload["events"][0]["seen_at"], str)

    def test_json_formatter_handles_cycle_in_extra_fields(self):
        formatter = JSONFormatter()
        logger = logging.getLogger("sync.test")

        cyc = {"name": "cycle"}
        cyc["self"] = cyc

        record = logger.makeRecord(
            name="sync.test",
            level=logging.ERROR,
            fn=__file__,
            lno=120,
            msg="Cycle payload",
            args=(),
            exc_info=None,
            extra={
                "stream_name": "incidents",
                "context": cyc,
            },
        )

        payload = json.loads(formatter.format(record))

        self.assertEqual("incidents", payload["stream_name"])
        self.assertEqual("<cycle>", payload["context"]["self"])


if __name__ == "__main__":
    unittest.main()
