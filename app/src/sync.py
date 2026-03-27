"""
Tree + incident sync pipeline — fetch EarthRanger events → upsert to Supabase.

Can run as:
  - One-shot:  python -m src.sync --once
  - Loop:      python -m src.sync               (default: every 60 min)
  - Custom:    python -m src.sync --interval 30

Also importable: the `run_sync_cycle()` function is used by the server
to trigger manual syncs via API.
"""

import argparse
import logging
import random
import signal
import sys
import time
import traceback
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from threading import RLock

import requests

from src.config import get_settings
from src.earthranger import get_er_client
from src.supabase_db import (
    get_sync_cursor,
    set_sync_cursor,
    upsert_incidents,
    upsert_trees,
)
from src.retention import (
    execute_ranger_stats_retention,
    record_retention_skip,
    get_retention_schedule_timezone,
    should_execute_scheduled_retention,
)
from src.models import (
    dedupe_events_by_tree_id,
    event_to_db_row,
    event_to_incident_row,
)

log = logging.getLogger("sync")
INCIDENT_SYNC_STREAM_NAME = "incidents"
INCIDENT_CURSOR_OVERLAP_SECONDS = 1


# ─────────────────────────────────────────────────────────────
# CORE SYNC
# ─────────────────────────────────────────────────────────────

def _parse_iso_datetime(value: str | None) -> datetime | None:
    """Parse ISO datetime text into UTC-aware datetime."""
    if value is None:
        return None

    raw = str(value).strip()
    if not raw:
        return None

    normalized = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _event_updated_at(ev: object) -> datetime | None:
    """Extract best-effort updated timestamp from raw EarthRanger event payload."""
    if not isinstance(ev, dict):
        return None

    return _parse_iso_datetime(
        str(ev.get("updated_at") or ev.get("time") or ev.get("created_at") or "")
    )


def _normalize_events_payload(payload: object) -> list[object]:
    """Normalize EarthRanger event payload wrappers into a flat list of events."""
    if payload is None:
        return []

    if isinstance(payload, list):
        return payload

    if isinstance(payload, tuple):
        return list(payload)

    if isinstance(payload, dict):
        direct_results = payload.get("results")
        if isinstance(direct_results, list):
            return direct_results

        data = payload.get("data")
        if isinstance(data, list):
            return data

        if isinstance(data, dict):
            nested_results = data.get("results")
            if isinstance(nested_results, list):
                return nested_results

        raise ValueError("EarthRanger events payload dict does not contain a list-like results field")

    raise TypeError(f"Unsupported EarthRanger events payload type: {type(payload).__name__}")


def _is_retryable_error(exc: Exception) -> bool:
    """Return True if sync error should be retried."""
    status_code = getattr(exc, "status_code", None)
    if status_code is None:
        status_code = getattr(getattr(exc, "response", None), "status_code", None)

    if status_code is not None:
        return status_code in {408, 409, 425, 429} or status_code >= 500

    if isinstance(exc, (requests.RequestException, TimeoutError, ConnectionError)):
        return True

    exc_type_name = exc.__class__.__name__.lower()
    if "timeout" in exc_type_name or "connection" in exc_type_name:
        return True

    return False


def _compute_retry_delay(attempt: int, base_delay_sec: int, max_delay_sec: int) -> float:
    """Compute bounded exponential backoff delay with jitter."""
    safe_base = max(base_delay_sec, 1)
    safe_max = max(max_delay_sec, safe_base)

    exponential_delay = min(safe_max, safe_base * (2 ** (attempt - 1)))
    jitter = random.uniform(0, max(0.001, exponential_delay * 0.25))
    return min(safe_max, exponential_delay + jitter)


def _extract_retry_after_seconds(exc: Exception, max_delay_sec: int) -> float | None:
    """Extract retry delay from Retry-After header when provided by upstream."""
    response = getattr(exc, "response", None)
    headers = getattr(response, "headers", None)
    if not headers:
        return None

    retry_after_raw = headers.get("Retry-After") or headers.get("retry-after")
    if retry_after_raw is None:
        return None

    raw = str(retry_after_raw).strip()
    if not raw:
        return None

    try:
        delay_seconds = float(raw)
        if delay_seconds <= 0:
            return 0.0
        return min(float(max_delay_sec), delay_seconds)
    except ValueError:
        pass

    try:
        retry_at = parsedate_to_datetime(raw)
    except (TypeError, ValueError, IndexError, OverflowError):
        return None

    if retry_at.tzinfo is None:
        retry_at = retry_at.replace(tzinfo=timezone.utc)

    delta_seconds = (retry_at.astimezone(timezone.utc) - datetime.now(timezone.utc)).total_seconds()
    if delta_seconds <= 0:
        return 0.0
    return min(float(max_delay_sec), delta_seconds)


def _apply_cursor_overlap(anchor: datetime | None, overlap_seconds: int) -> datetime | None:
    """Apply overlap window safely, clamping at minimum UTC datetime."""
    if anchor is None:
        return None

    safe_overlap = max(0, int(overlap_seconds))
    if safe_overlap == 0:
        return anchor

    try:
        return anchor - timedelta(seconds=safe_overlap)
    except OverflowError:
        return datetime.min.replace(tzinfo=timezone.utc)


def _normalize_tree_event_payload(event: object) -> dict | None:
    """Normalize a single tree event payload; return None when shape is unrecoverably malformed."""
    if not isinstance(event, dict):
        return None

    event_details = event.get("event_details")
    if event_details is None:
        event_details = {}
    elif not isinstance(event_details, dict):
        return None

    location = event.get("location")
    if not isinstance(location, dict):
        location = {}

    updates = event.get("updates")
    if isinstance(updates, list):
        updates = [entry for entry in updates if isinstance(entry, dict)]
    else:
        updates = []

    normalized = dict(event)
    normalized["event_details"] = event_details
    normalized["location"] = location
    normalized["updates"] = updates
    return normalized


def _run_tree_sync_cycle() -> dict:
    """Execute existing tree sync with fixed-delay retries."""
    s = get_settings()
    er = get_er_client()
    max_retries = max(1, s.sync_max_retries)

    for attempt in range(1, max_retries + 1):
        try:
            log.info("── Tree sync cycle (attempt %d/%d) ──", attempt, max_retries)

            raw_events = er.get_events(event_type="tree_rep", page_size=100)
            events = _normalize_events_payload(raw_events)
            fetched = len(events)
            log.info("  Fetched %d tree_rep event(s)", fetched)

            valid_events: list[dict] = []
            dropped_count = 0
            for ev in events:
                normalized_event = _normalize_tree_event_payload(ev)
                if normalized_event is None:
                    dropped_count += 1
                    continue
                valid_events.append(normalized_event)

            if dropped_count > 0:
                log.warning("  Dropped %d malformed tree event(s)", dropped_count)

            events = dedupe_events_by_tree_id(valid_events)
            log.info("  %d unique tree(s) after dedup", len(events))

            if not events:
                log.info("  Nothing to sync for trees")
                return {"ok": True, "fetched": 0, "unique": 0, "upserted": 0, "error": None}

            rows: list[dict] = []
            row_drop_count = 0
            for ev in events:
                try:
                    rows.append(event_to_db_row(ev))
                except Exception:
                    row_drop_count += 1

            if row_drop_count > 0:
                log.warning("  Dropped %d malformed tree event(s) during row mapping", row_drop_count)

            if not rows:
                log.info("  Nothing to sync for trees after mapping")
                return {"ok": True, "fetched": fetched, "unique": 0, "upserted": 0, "error": None}

            count = upsert_trees(rows)
            log.info("  Upserted %d tree row(s) to Supabase", count)

            return {
                "ok": True,
                "fetched": fetched,
                "unique": len(events),
                "upserted": count,
                "error": None,
            }

        except Exception as exc:
            log.error("  Tree sync error: %s\n%s", exc, traceback.format_exc())
            if attempt < max_retries:
                log.info("  Retrying tree sync in %d s …", s.sync_retry_delay_sec)
                time.sleep(s.sync_retry_delay_sec)

    msg = f"Tree sync failed after {max_retries} attempts"
    log.error("── %s ──", msg)
    return {"ok": False, "fetched": 0, "unique": 0, "upserted": 0, "error": msg}


def run_incident_sync_cycle(stream_name: str = INCIDENT_SYNC_STREAM_NAME) -> dict:
    """Execute incremental incident sync using persisted high-watermark cursor."""
    s = get_settings()
    er = get_er_client()
    max_retries = max(1, s.sync_max_retries)
    try:
        cursor_before = get_sync_cursor(stream_name)
    except ValueError as exc:
        msg = str(exc)
        log.error("  %s", msg, extra={"stream_name": stream_name})
        return {
            "ok": False,
            "fetched": 0,
            "upserted": 0,
            "cursor_before": None,
            "cursor_after": None,
            "error": msg,
        }
    except Exception as exc:
        msg = f"Failed to load sync cursor for stream '{stream_name}': {exc}"
        log.error("  %s", msg, extra={"stream_name": stream_name})
        return {
            "ok": False,
            "fetched": 0,
            "upserted": 0,
            "cursor_before": None,
            "cursor_after": None,
            "error": msg,
        }

    cursor_anchor = _parse_iso_datetime(cursor_before)
    updated_since = _apply_cursor_overlap(cursor_anchor, INCIDENT_CURSOR_OVERLAP_SECONDS)

    max_delay_sec = max(s.sync_retry_delay_sec * 8, s.sync_retry_delay_sec)
    last_attempt = 0

    for attempt in range(1, max_retries + 1):
        last_attempt = attempt
        try:
            log.info(
                "── Incident sync cycle (attempt %d/%d) ──",
                attempt,
                max_retries,
                extra={
                    "stream_name": stream_name,
                    "attempt": attempt,
                    "max_attempts": max_retries,
                    "cursor_before": cursor_before,
                    "updated_since": updated_since.isoformat() if updated_since else None,
                },
            )

            raw_events = er.get_events(
                event_type="incident_rep",
                page_size=100,
                updated_since=updated_since,
            )
            events = _normalize_events_payload(raw_events)
            fetched = len(events)
            log.info(
                "  Fetched %d incident event(s)",
                fetched,
                extra={
                    "stream_name": stream_name,
                    "fetched_count": fetched,
                    "cursor_before": cursor_before,
                },
            )

            if not events:
                return {
                    "ok": True,
                    "fetched": 0,
                    "upserted": 0,
                    "cursor_before": cursor_before,
                    "cursor_after": cursor_before,
                    "error": None,
                }

            incident_rows_by_id: dict[str, dict] = {}
            latest_updated_at: datetime | None = None
            latest_source_updated_at: datetime | None = None
            for event in events:
                source_updated_at = _event_updated_at(event)
                if source_updated_at is not None:
                    if latest_source_updated_at is None or source_updated_at > latest_source_updated_at:
                        latest_source_updated_at = source_updated_at

                row = event_to_incident_row(event)
                if not row:
                    continue

                er_event_id = str(row.get("er_event_id") or "").strip()
                if not er_event_id:
                    continue

                existing_row = incident_rows_by_id.get(er_event_id)
                row_updated_at = _parse_iso_datetime(row.get("updated_at"))
                existing_updated_at = _parse_iso_datetime(existing_row.get("updated_at")) if existing_row else None

                if (
                    existing_row is None
                    or existing_updated_at is None
                    or (row_updated_at is not None and row_updated_at >= existing_updated_at)
                ):
                    incident_rows_by_id[er_event_id] = row

                if row_updated_at is None:
                    continue
                if latest_updated_at is None or row_updated_at > latest_updated_at:
                    latest_updated_at = row_updated_at

            incident_rows = list(incident_rows_by_id.values())
            upserted = upsert_incidents(incident_rows) if incident_rows else 0

            cursor_after = cursor_before
            watermark = latest_updated_at
            if latest_source_updated_at is not None and (
                watermark is None or latest_source_updated_at > watermark
            ):
                watermark = latest_source_updated_at

            if fetched > 0 and watermark is None:
                msg = "Incident sync fetched events but could not derive a valid cursor watermark"
                log.error(
                    "  %s",
                    msg,
                    extra={
                        "stream_name": stream_name,
                        "cursor_before": cursor_before,
                        "fetched_count": fetched,
                        "valid_row_count": len(incident_rows),
                    },
                )
                return {
                    "ok": False,
                    "fetched": fetched,
                    "upserted": upserted,
                    "cursor_before": cursor_before,
                    "cursor_after": cursor_before,
                    "error": msg,
                }

            if watermark is not None:
                candidate_cursor = watermark.isoformat()
                try:
                    latest_cursor = get_sync_cursor(stream_name)
                except ValueError as exc:
                    log.error(
                        "  %s",
                        exc,
                        extra={"stream_name": stream_name, "candidate_cursor": candidate_cursor},
                    )
                    latest_cursor = None
                latest_cursor_anchor = _parse_iso_datetime(latest_cursor)
                if latest_cursor_anchor is None or watermark > latest_cursor_anchor:
                    persisted = set_sync_cursor(stream_name, candidate_cursor)
                    if isinstance(persisted, dict):
                        persisted_value = str(persisted.get("cursor_value") or "").strip()
                        cursor_after = persisted_value or candidate_cursor
                    else:
                        cursor_after = candidate_cursor
                else:
                    cursor_after = latest_cursor

            log.info(
                "  Incident sync upserted %d row(s)",
                upserted,
                extra={
                    "stream_name": stream_name,
                    "cursor_before": cursor_before,
                    "cursor_after": cursor_after,
                    "fetched_count": fetched,
                    "valid_row_count": len(incident_rows),
                    "deduped_row_count": len(incident_rows_by_id),
                    "upserted_count": upserted,
                },
            )

            return {
                "ok": True,
                "fetched": fetched,
                "upserted": upserted,
                "cursor_before": cursor_before,
                "cursor_after": cursor_after,
                "error": None,
            }

        except Exception as exc:
            retryable = _is_retryable_error(exc)
            log.error(
                "  Incident sync error: %s\n%s",
                exc,
                traceback.format_exc(),
                extra={
                    "stream_name": stream_name,
                    "attempt": attempt,
                    "max_attempts": max_retries,
                    "retryable": retryable,
                },
            )

            if attempt >= max_retries or not retryable:
                break

            retry_after_delay = _extract_retry_after_seconds(exc, max_delay_sec=max_delay_sec)
            if retry_after_delay is not None:
                delay = retry_after_delay
            else:
                delay = _compute_retry_delay(
                    attempt=attempt,
                    base_delay_sec=s.sync_retry_delay_sec,
                    max_delay_sec=max_delay_sec,
                )
            log.info(
                "  Retrying incident sync in %.2f s …",
                delay,
                extra={
                    "stream_name": stream_name,
                    "attempt": attempt,
                    "retry_delay_sec": delay,
                    "retry_after_sec": retry_after_delay,
                },
            )
            time.sleep(delay)

    msg = f"Incident sync failed after {last_attempt} attempt(s)"
    log.error("── %s ──", msg, extra={"stream_name": stream_name, "cursor_before": cursor_before})
    return {
        "ok": False,
        "fetched": 0,
        "upserted": 0,
        "cursor_before": cursor_before,
        "cursor_after": cursor_before,
        "error": msg,
    }


def run_sync_cycle() -> dict:
    """
    Execute one full sync cycle for trees and incidents.

    Returns a summary dict:
        {
            "ok": True/False,
            "fetched": int,
            "unique": int,
            "upserted": int,
            "error": str|None,
            "incidents": { ... }
        }
    """
    cycle_started_at = datetime.now(timezone.utc)
    tree_result = _run_tree_sync_cycle()
    incident_result = run_incident_sync_cycle()
    cycle_duration_ms = (datetime.now(timezone.utc) - cycle_started_at).total_seconds() * 1000

    errors = [
        tree_result.get("error"),
        incident_result.get("error"),
    ]
    errors = [err for err in errors if err]

    result = {
        "ok": tree_result.get("ok", False) and incident_result.get("ok", False),
        "fetched": tree_result.get("fetched", 0),
        "unique": tree_result.get("unique", 0),
        "upserted": tree_result.get("upserted", 0),
        "error": "; ".join(errors) if errors else None,
        "incidents": incident_result,
    }

    log.info(
        "Sync cycle completed",
        extra={
            "cycle_ok": result["ok"],
            "duration_ms": round(cycle_duration_ms, 1),
            "tree_fetched": result["fetched"],
            "tree_unique": result["unique"],
            "tree_upserted": result["upserted"],
            "incident_fetched": incident_result.get("fetched", 0),
            "incident_upserted": incident_result.get("upserted", 0),
            "error": result["error"],
        },
    )

    return result


# ─────────────────────────────────────────────────────────────
# LOOP SCHEDULER
# ─────────────────────────────────────────────────────────────

_shutdown = False
_last_retention_attempt_day_key: str | None = None
_retention_schedule_lock = RLock()


def _handle_signal(sig, frame):
    global _shutdown
    _shutdown = True
    log.info("Shutdown signal received")


def _run_scheduled_retention_if_due() -> None:
    """Run daily retention job once schedule time is reached in local policy timezone."""
    global _last_retention_attempt_day_key

    with _retention_schedule_lock:
        settings = get_settings()
        schedule_timezone = get_retention_schedule_timezone()
        now_local = datetime.now(schedule_timezone)
        today_key = now_local.date().isoformat()

        if not should_execute_scheduled_retention(
            now_local,
            schedule_hour=settings.retention_schedule_hour_local,
            schedule_minute=settings.retention_schedule_minute_local,
            last_attempt_day_key=_last_retention_attempt_day_key,
        ):
            return

        correlation_id = f"retention-scheduled-{today_key}"
        if not settings.retention_enabled:
            result = record_retention_skip(
                reason="Retention disabled by configuration",
                trigger="scheduled",
                correlation_id=correlation_id,
            )
            _last_retention_attempt_day_key = today_key
            log.warning(
                "Scheduled retention skipped",
                extra={
                    "run_id": result.get("run_id"),
                    "status": result.get("status"),
                    "trigger": result.get("trigger"),
                    "correlation_id": result.get("correlation_id"),
                    "reason": result.get("reason"),
                },
            )
            return

        result = execute_ranger_stats_retention(
            trigger="scheduled",
            correlation_id=correlation_id,
        )
        _last_retention_attempt_day_key = today_key

        if result.get("status") != "succeeded":
            log.warning(
                "Scheduled retention run finished with non-success status",
                extra={
                    "run_id": result.get("run_id"),
                    "status": result.get("status"),
                    "trigger": result.get("trigger"),
                    "correlation_id": result.get("correlation_id"),
                    "error": result.get("error"),
                },
            )


def run_loop(interval_min: int | None = None):
    """Run sync in a loop. Blocks until Ctrl+C or SIGTERM."""
    s = get_settings()
    interval = s.sync_interval_minutes if interval_min is None else interval_min
    if interval < 1:
        raise ValueError(f"sync interval must be >= 1 minute, got {interval}")

    interval_sec = interval * 60

    import threading
    if threading.current_thread() is threading.main_thread():
        signal.signal(signal.SIGINT, _handle_signal)
        signal.signal(signal.SIGTERM, _handle_signal)

    log.info("Sync pipeline started — interval %d min (Ctrl+C to stop)", interval)

    while not _shutdown:
        run_sync_cycle()
        _run_scheduled_retention_if_due()
        if _shutdown:
            break
        log.info("Next sync in %d min …", interval)
        for _ in range(interval_sec):
            if _shutdown:
                break
            time.sleep(1)

    log.info("Pipeline stopped")


# ─────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────

def main():
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] %(levelname)-7s %(name)s — %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    parser = argparse.ArgumentParser(description="EarthRanger → Supabase tree sync")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    parser.add_argument("--interval", type=int, default=None, help="Minutes between syncs")
    args = parser.parse_args()

    if args.once:
        result = run_sync_cycle()
        sys.exit(0 if result["ok"] else 1)
    else:
        run_loop(args.interval)


if __name__ == "__main__":
    main()
