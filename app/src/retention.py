"""
Retention operations for ranger statistics lifecycle compliance.

This module provides:
- Retention execution with a minimum 6-month data window
- Structured/auditable run metadata (run_id, status, cutoff, correlation IDs)
- Failed-run discovery and replay support for operations
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timedelta, timezone
from threading import RLock
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from src.config import get_settings
from src.supabase_db import get_supabase

log = logging.getLogger("retention")

_MIN_RETENTION_DAYS = 183  # ~6 months minimum policy guardrail
_RETENTION_STATUS_VALUES = {"succeeded", "failed", "skipped"}

_retention_runs_lock = RLock()
_retention_runs: list[dict] = []


def _utcnow() -> datetime:
    """Return timezone-aware current UTC timestamp."""
    return datetime.now(timezone.utc)


def _normalize_optional_text(value: str | None) -> str | None:
    """Normalize optional text fields by trimming whitespace."""
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _coerce_utc(value: datetime | None) -> datetime:
    """Coerce optional datetime into UTC-aware datetime."""
    candidate = value or _utcnow()
    if candidate.tzinfo is None:
        candidate = candidate.replace(tzinfo=timezone.utc)
    return candidate.astimezone(timezone.utc)


def _retention_window_days(configured_days: int) -> int:
    """Return effective retention window in days, enforcing 6-month minimum."""
    safe_days = max(1, int(configured_days))
    return max(_MIN_RETENTION_DAYS, safe_days)


def get_retention_schedule_timezone() -> ZoneInfo | timezone:
    """Resolve retention scheduling timezone from settings with safe fallback."""
    timezone_name = _normalize_optional_text(get_settings().retention_schedule_timezone) or "Asia/Ho_Chi_Minh"
    try:
        return ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        log.warning(
            "Retention timezone '%s' not found; falling back to UTC",
            timezone_name,
        )
        return timezone.utc


def should_execute_scheduled_retention(
    now_local: datetime,
    *,
    schedule_hour: int,
    schedule_minute: int,
    last_attempt_day_key: str | None,
) -> bool:
    """Return True if the daily schedule is due and not yet attempted today."""
    if now_local.tzinfo is None:
        raise ValueError("now_local must be timezone-aware")

    safe_hour = min(23, max(0, int(schedule_hour)))
    safe_minute = min(59, max(0, int(schedule_minute)))

    if (now_local.hour, now_local.minute) < (safe_hour, safe_minute):
        return False

    today_key = now_local.date().isoformat()
    return today_key != str(last_attempt_day_key or "")


def _append_retention_run(run_record: dict) -> None:
    """Append run record in-memory with bounded history."""
    history_limit = max(1, int(get_settings().retention_audit_memory_limit))

    with _retention_runs_lock:
        _retention_runs.append(dict(run_record))
        if len(_retention_runs) > history_limit:
            del _retention_runs[: len(_retention_runs) - history_limit]


def _persist_retention_run(run_record: dict) -> None:
    """Best-effort persistence of retention run records to configured Supabase table."""
    settings = get_settings()
    audit_table = _normalize_optional_text(settings.retention_audit_table)
    if not audit_table:
        return

    payload = {
        "run_id": run_record.get("run_id"),
        "trigger": run_record.get("trigger"),
        "status": run_record.get("status"),
        "started_at": run_record.get("started_at"),
        "finished_at": run_record.get("finished_at"),
        "cutoff_day": run_record.get("cutoff_day"),
        "retention_days": run_record.get("retention_days"),
        "candidate_count": run_record.get("candidate_count", 0),
        "deleted_count": run_record.get("deleted_count", 0),
        "source_table": run_record.get("source_table"),
        "source_day_field": run_record.get("source_day_field"),
        "replay_of_run_id": run_record.get("replay_of_run_id"),
        "request_id": run_record.get("request_id"),
        "correlation_id": run_record.get("correlation_id"),
        "error": run_record.get("error"),
        "reason": run_record.get("reason"),
        "dry_run": bool(run_record.get("dry_run", False)),
    }

    try:
        get_supabase().table(audit_table).insert(payload).execute()
    except Exception as exc:  # pragma: no cover - best-effort persistence
        log.warning(
            "Failed to persist retention audit record: %s",
            exc,
            extra={
                "run_id": payload.get("run_id"),
                "audit_table": audit_table,
                "status": payload.get("status"),
            },
        )


def clear_retention_run_history() -> None:
    """Clear in-memory retention run history (primarily for deterministic tests)."""
    with _retention_runs_lock:
        _retention_runs.clear()


def list_retention_runs(status: str | None = None, limit: int = 50) -> list[dict]:
    """List retention runs from in-memory audit history (newest first)."""
    status_filter = _normalize_optional_text(status)
    if status_filter is not None:
        status_filter = status_filter.lower()
        if status_filter not in _RETENTION_STATUS_VALUES:
            raise ValueError(f"Invalid retention status filter: {status_filter}")

    safe_limit = max(1, min(int(limit), 500))

    with _retention_runs_lock:
        rows = list(reversed(_retention_runs))

    if status_filter is not None:
        rows = [row for row in rows if str(row.get("status") or "").lower() == status_filter]

    return rows[:safe_limit]


def get_retention_run(run_id: str) -> dict | None:
    """Return a specific retention run by run_id, if present in audit history."""
    wanted = _normalize_optional_text(run_id)
    if not wanted:
        return None

    with _retention_runs_lock:
        for row in reversed(_retention_runs):
            if str(row.get("run_id") or "") == wanted:
                return dict(row)

    return None


def _new_run_id() -> str:
    """Create a short deterministic-safe retention run identifier."""
    return f"ret-{secrets.token_hex(8)}"


def _resolve_correlation_id(
    correlation_id: str | None,
    request_id: str | None,
    run_id: str,
) -> str:
    """Resolve correlation id preference order for audit/log consistency."""
    explicit = _normalize_optional_text(correlation_id)
    if explicit:
        return explicit

    request = _normalize_optional_text(request_id)
    if request:
        return request

    return f"retcorr-{secrets.token_hex(8)}"


def record_retention_skip(
    *,
    reason: str,
    trigger: str = "scheduled",
    request_id: str | None = None,
    correlation_id: str | None = None,
    replay_of_run_id: str | None = None,
    now_utc: datetime | None = None,
) -> dict:
    """Record a skipped retention run as an auditable operation event."""
    started_at = _coerce_utc(now_utc)
    run_id = _new_run_id()
    normalized_request_id = _normalize_optional_text(request_id)
    normalized_replay_of_run_id = _normalize_optional_text(replay_of_run_id)
    resolved_correlation_id = _resolve_correlation_id(correlation_id, normalized_request_id, run_id)

    run_record = {
        "run_id": run_id,
        "trigger": trigger,
        "status": "skipped",
        "started_at": started_at.isoformat(),
        "finished_at": started_at.isoformat(),
        "cutoff_day": None,
        "retention_days": None,
        "candidate_count": 0,
        "deleted_count": 0,
        "source_table": _normalize_optional_text(get_settings().retention_source_table),
        "source_day_field": _normalize_optional_text(get_settings().retention_source_day_field),
        "replay_of_run_id": normalized_replay_of_run_id,
        "request_id": normalized_request_id,
        "correlation_id": resolved_correlation_id,
        "error": None,
        "reason": reason,
        "dry_run": False,
    }

    _append_retention_run(run_record)
    _persist_retention_run(run_record)

    log.warning(
        "Retention run skipped: %s",
        reason,
        extra={
            "run_id": run_id,
            "status": "skipped",
            "trigger": trigger,
            "request_id": normalized_request_id,
            "correlation_id": resolved_correlation_id,
            "reason": reason,
        },
    )

    return dict(run_record)


def execute_ranger_stats_retention(
    *,
    trigger: str = "manual",
    request_id: str | None = None,
    correlation_id: str | None = None,
    replay_of_run_id: str | None = None,
    now_utc: datetime | None = None,
    dry_run: bool = False,
) -> dict:
    """Execute ranger stats retention and return auditable run summary."""
    settings = get_settings()

    if not settings.retention_enabled:
        return record_retention_skip(
            reason="Retention disabled by configuration",
            trigger=trigger,
            request_id=request_id,
            correlation_id=correlation_id,
            replay_of_run_id=replay_of_run_id,
            now_utc=now_utc,
        )

    started_at = _coerce_utc(now_utc)
    run_id = _new_run_id()
    normalized_request_id = _normalize_optional_text(request_id)
    normalized_replay_of_run_id = _normalize_optional_text(replay_of_run_id)
    resolved_correlation_id = _resolve_correlation_id(correlation_id, normalized_request_id, run_id)

    source_table = _normalize_optional_text(settings.retention_source_table)
    source_day_field = _normalize_optional_text(settings.retention_source_day_field) or "day_key"

    retention_days = _retention_window_days(settings.retention_min_days)
    cutoff_day = (started_at - timedelta(days=retention_days)).date().isoformat()

    run_record = {
        "run_id": run_id,
        "trigger": trigger,
        "status": "failed",
        "started_at": started_at.isoformat(),
        "finished_at": started_at.isoformat(),
        "cutoff_day": cutoff_day,
        "retention_days": retention_days,
        "candidate_count": 0,
        "deleted_count": 0,
        "source_table": source_table,
        "source_day_field": source_day_field,
        "replay_of_run_id": normalized_replay_of_run_id,
        "request_id": normalized_request_id,
        "correlation_id": resolved_correlation_id,
        "error": None,
        "reason": None,
        "dry_run": bool(dry_run),
    }

    try:
        if not source_table:
            raise ValueError("Retention source table is not configured")

        select_result = (
            get_supabase()
            .table(source_table)
            .select(source_day_field)
            .lt(source_day_field, cutoff_day)
            .execute()
        )
        candidate_rows = select_result.data or []
        run_record["candidate_count"] = len(candidate_rows)

        if dry_run:
            deleted_count = 0
        else:
            delete_result = (
                get_supabase()
                .table(source_table)
                .delete()
                .lt(source_day_field, cutoff_day)
                .execute()
            )
            deleted_payload = getattr(delete_result, "data", None)
            if isinstance(deleted_payload, list):
                deleted_count = len(deleted_payload)
            else:
                # Supabase delete responses may omit row payloads depending on
                # server/client preferences; fall back to matched candidate count
                # so audit records remain operationally meaningful.
                deleted_count = run_record["candidate_count"]

        run_record["deleted_count"] = deleted_count
        run_record["status"] = "succeeded"
        run_record["finished_at"] = _utcnow().isoformat()

        log.info(
            "Retention run completed",
            extra={
                "run_id": run_id,
                "status": run_record["status"],
                "trigger": trigger,
                "request_id": normalized_request_id,
                "correlation_id": resolved_correlation_id,
                "cutoff_day": cutoff_day,
                "retention_days": retention_days,
                "candidate_count": run_record["candidate_count"],
                "deleted_count": deleted_count,
                "source_table": source_table,
                "source_day_field": source_day_field,
                "replay_of_run_id": normalized_replay_of_run_id,
                "dry_run": bool(dry_run),
            },
        )
    except Exception as exc:
        run_record["status"] = "failed"
        run_record["finished_at"] = _utcnow().isoformat()
        run_record["error"] = str(exc)

        log.error(
            "Retention run failed: %s",
            exc,
            extra={
                "run_id": run_id,
                "status": "failed",
                "trigger": trigger,
                "request_id": normalized_request_id,
                "correlation_id": resolved_correlation_id,
                "cutoff_day": cutoff_day,
                "retention_days": retention_days,
                "candidate_count": run_record["candidate_count"],
                "deleted_count": run_record["deleted_count"],
                "source_table": source_table,
                "source_day_field": source_day_field,
                "replay_of_run_id": normalized_replay_of_run_id,
                "dry_run": bool(dry_run),
            },
        )

    _append_retention_run(run_record)
    _persist_retention_run(run_record)
    return dict(run_record)


def replay_retention_run(
    failed_run_id: str,
    *,
    request_id: str | None = None,
    correlation_id: str | None = None,
    dry_run: bool = False,
    now_utc: datetime | None = None,
) -> dict:
    """Replay a previously failed retention run and preserve replay linkage."""
    target_id = _normalize_optional_text(failed_run_id)
    if not target_id:
        raise ValueError("failed_run_id is required")

    existing = get_retention_run(target_id)
    if not existing:
        raise LookupError(f"Retention run not found: {target_id}")

    if str(existing.get("status") or "").lower() != "failed":
        raise ValueError("Only failed retention runs can be replayed")

    return execute_ranger_stats_retention(
        trigger="replay",
        request_id=request_id,
        correlation_id=correlation_id,
        replay_of_run_id=target_id,
        now_utc=now_utc,
        dry_run=dry_run,
    )
