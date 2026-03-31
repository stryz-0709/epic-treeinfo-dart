"""
Supabase client — all database operations in one place.
"""

from __future__ import annotations

import logging
import os
from datetime import date, datetime, timezone
from threading import RLock

from supabase import create_client, Client

from src.config import get_settings

log = logging.getLogger(__name__)

_client: Client | None = None
AUTH_USERS_TABLE = "app_users"
AUTH_USER_SELECT_FIELDS = "username,password_hash,role,display_name,region,team,position,phone,status,avatar_url"

SCHEDULES_TABLE = "schedules"
SCHEDULES_VIEW = "schedules_with_user_profile"
SCHEDULE_ACTION_LOGS_TABLE = "schedule_action_logs"
SCHEDULE_READINESS_MODE_ENV = "SCHEDULE_READINESS_MODE"
SCHEDULE_READINESS_MODE_STRICT = "strict"
SCHEDULE_READINESS_MODE_LAZY = "lazy"
SCHEDULE_MAX_QUERY_ROWS = 5000
SCHEDULE_PREFLIGHT_SUCCESS_RECHECK_SECONDS = 60
SCHEDULE_PREFLIGHT_FAILURE_RETRY_SECONDS = 5

_schedule_preflight_lock = RLock()
_schedule_preflight_cache: dict | None = None


class ScheduleRepositoryError(RuntimeError):
    """Base exception for schedule persistence/repository failures."""


class ScheduleReadinessError(ScheduleRepositoryError):
    """Raised when schedule schema readiness/preflight checks fail."""


class ScheduleConflictError(ScheduleRepositoryError):
    """Raised when schedule writes violate active-row uniqueness constraints."""


class ScheduleNotFoundError(ScheduleRepositoryError):
    """Raised when target schedule row is missing or already soft-deleted."""


class ScheduleValidationError(ScheduleRepositoryError):
    """Raised when write input fails DB-level validation/foreign-key checks."""


def _parse_cursor_iso(value: str | None) -> datetime | None:
    """Parse cursor text into UTC-aware datetime; return None for invalid values."""
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


def _is_unique_conflict_error(exc: Exception) -> bool:
    """Best-effort detection for duplicate/unique constraint conflicts."""
    status_code = getattr(exc, "status_code", None)
    if status_code is None:
        status_code = getattr(getattr(exc, "response", None), "status_code", None)
    if status_code == 409:
        return True

    message = str(exc).lower()
    markers = (
        "duplicate key",
        "unique constraint",
        "already exists",
    )
    return any(marker in message for marker in markers)


def _is_foreign_key_error(exc: Exception) -> bool:
    """Best-effort detection for FK/relationship violations."""
    status_code = getattr(exc, "status_code", None)
    if status_code is None:
        status_code = getattr(getattr(exc, "response", None), "status_code", None)

    message = str(exc).lower()
    if status_code == 400:
        if "foreign key" in message or "violates" in message:
            return True

    return (
        "foreign key" in message
        or "violates foreign key" in message
        or "unknown app_users.username" in message
        or "23503" in message
    )


def _normalize_schedule_username(value: str | None) -> str:
    """Normalize schedule identity key with trim + lowercase semantics."""
    return str(value or "").strip().lower()


def _normalize_schedule_note(value: str | None) -> str:
    """Normalize schedule note text before persistence."""
    return str(value or "").strip()


def _format_db_datetime(value: object) -> str | None:
    """Serialize DB datetime values as ISO strings, preserving malformed fallback text."""
    if value is None:
        return None

    if isinstance(value, datetime):
        parsed = value
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc).isoformat()

    raw = str(value).strip()
    if not raw:
        return None

    parsed = _parse_cursor_iso(raw)
    if parsed is None:
        return raw
    return parsed.isoformat()


def _schedule_row_to_api_item(row: dict) -> dict:
    """Map Supabase schedule row shape into mobile API payload fields."""
    return {
        "schedule_id": str(row.get("schedule_id") or ""),
        "ranger_id": _normalize_schedule_username(row.get("username")),
        "work_date": str(row.get("work_date") or "").strip(),
        "note": str(row.get("note") or ""),
        "updated_by": _normalize_schedule_username(row.get("updated_by_username")),
        "created_at": _format_db_datetime(row.get("created_at")),
        "updated_at": _format_db_datetime(row.get("updated_at")),
    }


def _apply_is_null_filter(query, field_name: str):
    """Apply an IS NULL filter across supabase-py versions."""
    if hasattr(query, "is_"):
        return query.is_(field_name, "null")
    return query.eq(field_name, None)


def _apply_in_filter(query, field_name: str, values: list[str]):
    """Apply an IN (...) filter when supported by supabase-py version in use."""
    if not values:
        return query
    if hasattr(query, "in_"):
        return query.in_(field_name, values)
    return query


def _resolve_schedule_readiness_mode() -> str:
    """Resolve and validate schedule readiness mode from environment."""
    raw_mode = str(
        os.getenv(SCHEDULE_READINESS_MODE_ENV, SCHEDULE_READINESS_MODE_STRICT) or ""
    ).strip().lower()

    mode = raw_mode or SCHEDULE_READINESS_MODE_STRICT
    if mode in {SCHEDULE_READINESS_MODE_STRICT, SCHEDULE_READINESS_MODE_LAZY}:
        return mode

    raise ScheduleReadinessError(
        f"Invalid {SCHEDULE_READINESS_MODE_ENV}='{raw_mode}'. "
        f"Allowed values: '{SCHEDULE_READINESS_MODE_STRICT}', "
        f"'{SCHEDULE_READINESS_MODE_LAZY}'."
    )


def validate_schedule_readiness_mode(*, is_production: bool) -> str:
    """Validate readiness mode policy (production must run strict mode)."""
    mode = _resolve_schedule_readiness_mode()
    if is_production and mode != SCHEDULE_READINESS_MODE_STRICT:
        raise ScheduleReadinessError(
            "SCHEDULE_READINESS_MODE=lazy is not allowed in production. "
            "Use strict mode."
        )
    return mode


def _run_schedule_surface_checks() -> list[str]:
    """Validate required schedule DB artifacts can be queried."""
    failures: list[str] = []

    if not _is_supabase_configured():
        return ["Supabase configuration missing (SUPABASE_URL/SUPABASE_KEY)"]

    try:
        (
            get_supabase()
            .table(SCHEDULES_TABLE)
            .select(
                "schedule_id,work_date,username,note,created_by_username,"
                "updated_by_username,created_at,updated_at,deleted_at"
            )
            .limit(1)
            .execute()
        )
    except Exception as exc:
        failures.append(f"Required artifact unavailable: public.{SCHEDULES_TABLE} ({exc})")

    try:
        (
            get_supabase()
            .table(SCHEDULES_VIEW)
            .select(
                "schedule_id,work_date,username,note,created_at,updated_at,"
                "updated_by_username,deleted_at"
            )
            .limit(1)
            .execute()
        )
    except Exception as exc:
        failures.append(f"Required artifact unavailable: public.{SCHEDULES_VIEW} ({exc})")

    try:
        (
            get_supabase()
            .table(SCHEDULE_ACTION_LOGS_TABLE)
            .select("schedule_id,action_type,actor_username,action_timestamp")
            .limit(1)
            .execute()
        )
    except Exception as exc:
        failures.append(
            f"Required artifact unavailable: public.{SCHEDULE_ACTION_LOGS_TABLE} ({exc})"
        )

    return failures


def _run_schedule_identity_checks() -> list[str]:
    """Validate canonical identity + duplicate-active invariants for strict readiness."""
    failures: list[str] = []

    try:
        app_users_result = get_supabase().table(AUTH_USERS_TABLE).select("username").execute()
    except Exception as exc:
        return [f"Unable to validate canonical usernames in public.{AUTH_USERS_TABLE} ({exc})"]

    app_user_rows = app_users_result.data or []
    non_canonical_app_users = [
        row for row in app_user_rows
        if _normalize_schedule_username(row.get("username"))
        and str(row.get("username") or "") != _normalize_schedule_username(row.get("username"))
    ]
    if non_canonical_app_users:
        failures.append(
            "Canonical username invariant failed: "
            f"{len(non_canonical_app_users)} non-canonical row(s) in public.{AUTH_USERS_TABLE}"
        )

    try:
        active_query = get_supabase().table(SCHEDULES_TABLE).select(
            "schedule_id,work_date,username,deleted_at"
        )
        active_query = _apply_is_null_filter(active_query, "deleted_at")
        active_rows_result = active_query.limit(SCHEDULE_MAX_QUERY_ROWS).execute()
    except Exception as exc:
        return [f"Unable to validate active schedule identity invariants ({exc})"]

    active_rows = active_rows_result.data or []

    non_canonical_schedule_rows = [
        row for row in active_rows
        if _normalize_schedule_username(row.get("username"))
        and str(row.get("username") or "") != _normalize_schedule_username(row.get("username"))
    ]
    if non_canonical_schedule_rows:
        failures.append(
            "Canonical username invariant failed: "
            f"{len(non_canonical_schedule_rows)} non-canonical active row(s) in public.{SCHEDULES_TABLE}"
        )

    duplicate_keys: dict[tuple[str, str], int] = {}
    for row in active_rows:
        normalized_username = _normalize_schedule_username(row.get("username"))
        work_date_value = str(row.get("work_date") or "").strip()
        if not normalized_username or not work_date_value:
            continue
        key = (work_date_value, normalized_username)
        duplicate_keys[key] = duplicate_keys.get(key, 0) + 1

    duplicate_count = sum(1 for count in duplicate_keys.values() if count > 1)
    if duplicate_count:
        failures.append(
            "Duplicate-active anomaly detected: "
            f"{duplicate_count} normalized (work_date,username) collision(s) in active schedules"
        )

    if len(active_rows) >= SCHEDULE_MAX_QUERY_ROWS:
        failures.append(
            "Schedule preflight identity scan reached safety row cap; "
            "increase SCHEDULE_MAX_QUERY_ROWS for strict readiness"
        )
        log.warning(
            "Schedule preflight scanned %d active rows and may be truncated; "
            "failing strict readiness until cap is increased.",
            SCHEDULE_MAX_QUERY_ROWS,
        )

    return failures


def run_schedule_schema_preflight() -> dict:
    """Run full schedule-schema readiness checks and return structured report."""
    mode = _resolve_schedule_readiness_mode()
    surface_failures = _run_schedule_surface_checks()

    identity_failures: list[str] = []
    if not surface_failures:
        identity_failures = _run_schedule_identity_checks()

    failures = [*surface_failures, *identity_failures]
    return {
        "ok": not failures,
        "mode": mode,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "failures": failures,
    }


def get_schedule_preflight_cache() -> dict | None:
    """Return the last schedule preflight cache snapshot."""
    return dict(_schedule_preflight_cache) if isinstance(_schedule_preflight_cache, dict) else None


def ensure_schedule_schema_ready(*, force: bool = False) -> None:
    """Ensure schedule schema is ready, raising fail-closed readiness errors when not ready."""
    global _schedule_preflight_cache

    with _schedule_preflight_lock:
        if not force and isinstance(_schedule_preflight_cache, dict):
            checked_at_raw = _schedule_preflight_cache.get("checked_at")
            checked_at = _parse_cursor_iso(str(checked_at_raw or ""))
            now = datetime.now(timezone.utc)

            if _schedule_preflight_cache.get("ok"):
                if (
                    checked_at is not None
                    and (now - checked_at).total_seconds() < SCHEDULE_PREFLIGHT_SUCCESS_RECHECK_SECONDS
                ):
                    return
            else:
                if (
                    checked_at is not None
                    and (now - checked_at).total_seconds() < SCHEDULE_PREFLIGHT_FAILURE_RETRY_SECONDS
                ):
                    failures = _schedule_preflight_cache.get("failures") or []
                    failure_message = "; ".join(str(item) for item in failures) or "unknown readiness failure"
                    raise ScheduleReadinessError(failure_message)

        report = run_schedule_schema_preflight()
        _schedule_preflight_cache = report

        if report["ok"]:
            return

        failures = report.get("failures") or []
        failure_message = "; ".join(str(item) for item in failures) or "unknown readiness failure"
        raise ScheduleReadinessError(failure_message)


def get_supabase() -> Client:
    """Return lazily-initialized Supabase client singleton."""
    global _client
    if _client is None:
        s = get_settings()
        _client = create_client(s.supabase_url, s.supabase_key)
    return _client


def _is_supabase_configured() -> bool:
    """Return True when Supabase URL/key are configured."""
    s = get_settings()
    return bool(str(s.supabase_url).strip() and str(s.supabase_key).strip())


def load_auth_users() -> dict[str, dict] | None:
    """Load app auth users from Supabase.

    Returns:
        - dict keyed by username when table access succeeds
        - None when Supabase is not configured or auth table is unavailable
    """
    if not _is_supabase_configured():
        return None

    try:
        result = (
            get_supabase()
            .table(AUTH_USERS_TABLE)
            .select(AUTH_USER_SELECT_FIELDS)
            .execute()
        )
    except Exception:
        log.exception("Failed to load users from Supabase auth table '%s'", AUTH_USERS_TABLE)
        return None

    users: dict[str, dict] = {}
    for row in result.data or []:
        username = str(row.get("username") or "").strip().lower()
        if not username:
            continue

        role = str(row.get("role") or "ranger").strip().lower() or "ranger"
        password_hash = str(row.get("password_hash") or "").strip()

        # Invalid rows are skipped defensively.
        if not password_hash:
            continue

        user_data: dict[str, str] = {
            "password": password_hash,
            "role": role,
            "display_name": str(row.get("display_name") or username).strip() or username,
        }

        for field in ("region", "team", "position", "phone", "status", "avatar_url"):
            value = row.get(field)
            if value is not None:
                user_data[field] = str(value)

        users[username] = user_data

    return users


def replace_auth_users(users: dict[str, dict]) -> bool:
    """Replace Supabase auth user state with provided snapshot.

    Returns True when snapshot persistence succeeds; otherwise False.
    """
    if not _is_supabase_configured():
        return False

    try:
        table = get_supabase().table(AUTH_USERS_TABLE)
        existing_result = table.select("username").execute()
        existing_usernames = {
            str(row.get("username") or "").strip().lower()
            for row in (existing_result.data or [])
            if str(row.get("username") or "").strip()
        }

        now = datetime.now(timezone.utc).isoformat()
        upsert_rows: list[dict] = []
        for raw_username, raw_user in users.items():
            username = str(raw_username or "").strip().lower()
            if not username:
                continue

            password_hash = str(raw_user.get("password") or "").strip()
            if not password_hash:
                continue

            role = str(raw_user.get("role") or "ranger").strip().lower() or "ranger"
            row: dict[str, str] = {
                "username": username,
                "password_hash": password_hash,
                "role": role,
                "display_name": str(raw_user.get("display_name") or username).strip() or username,
                "updated_at": now,
            }

            for field in ("region", "team", "position", "phone", "status", "avatar_url"):
                value = raw_user.get(field)
                if value is not None:
                    row[field] = str(value)

            upsert_rows.append(row)

        if upsert_rows:
            table.upsert(upsert_rows, on_conflict="username").execute()

        desired_usernames = {row["username"] for row in upsert_rows}
        usernames_to_delete = sorted(existing_usernames - desired_usernames)
        for username in usernames_to_delete:
            table.delete().eq("username", username).execute()

        return True
    except Exception:
        log.exception("Failed to persist users to Supabase auth table '%s'", AUTH_USERS_TABLE)
        return False


# ─────────────────────────────────────────────────────────────
# SCHEDULES (mobile source-of-truth)
# ─────────────────────────────────────────────────────────────

def _load_active_schedule_row(schedule_id: str) -> dict | None:
    """Fetch active (non-soft-deleted) schedule row by ID."""
    normalized_schedule_id = str(schedule_id or "").strip()
    if not normalized_schedule_id:
        return None

    query = (
        get_supabase()
        .table(SCHEDULES_TABLE)
        .select(
            "schedule_id,work_date,username,note,updated_by_username,"
            "created_at,updated_at,deleted_at"
        )
        .eq("schedule_id", normalized_schedule_id)
    )
    query = _apply_is_null_filter(query, "deleted_at")

    try:
        result = query.maybe_single().execute()
    except Exception as exc:
        raise ScheduleRepositoryError("Failed to load active schedule") from exc
    return result.data


def get_mobile_schedule_item(*, schedule_id: str) -> dict:
    """Fetch one active schedule row by ID and map it to mobile API payload."""
    ensure_schedule_schema_ready()

    normalized_schedule_id = str(schedule_id or "").strip()
    if not normalized_schedule_id:
        raise ScheduleNotFoundError("Schedule not found")

    row = _load_active_schedule_row(normalized_schedule_id)
    if not row:
        raise ScheduleNotFoundError("Schedule not found")

    return _schedule_row_to_api_item(row)


def list_mobile_schedule_items(
    *,
    effective_ranger_id: str | None,
    visible_user_ids: set[str] | None,
    from_day: date | None,
    to_day: date | None,
    updated_since: datetime | None,
    snapshot_at: datetime,
) -> list[dict]:
    """List active mobile schedule items from Supabase with deterministic ordering."""
    ensure_schedule_schema_ready()

    query = (
        get_supabase()
        .table(SCHEDULES_VIEW)
        .select(
            "schedule_id,work_date,username,note,updated_by_username,"
            "created_at,updated_at,deleted_at"
        )
    )

    normalized_scope_username = _normalize_schedule_username(effective_ranger_id)
    if normalized_scope_username:
        query = query.eq("username", normalized_scope_username)

    normalized_visible_user_ids = {
        _normalize_schedule_username(value)
        for value in (visible_user_ids or set())
        if _normalize_schedule_username(value)
    }
    if normalized_visible_user_ids:
        query = _apply_in_filter(query, "username", sorted(normalized_visible_user_ids))

    if from_day is not None:
        query = query.gte("work_date", from_day.isoformat())
    if to_day is not None:
        query = query.lte("work_date", to_day.isoformat())
    if updated_since is not None:
        query = query.gte("updated_at", updated_since.isoformat())

    query = query.lte("updated_at", snapshot_at.isoformat())
    query = _apply_is_null_filter(query, "deleted_at")

    try:
        result = query.limit(SCHEDULE_MAX_QUERY_ROWS).execute()
    except Exception as exc:
        raise ScheduleRepositoryError("Failed to list schedules") from exc

    rows = result.data or []
    if len(rows) >= SCHEDULE_MAX_QUERY_ROWS:
        raise ScheduleRepositoryError(
            "Schedule query reached safety row cap; narrow filters or increase SCHEDULE_MAX_QUERY_ROWS"
        )

    items: list[dict] = []
    for row in rows:
        if not isinstance(row, dict):
            continue

        mapped = _schedule_row_to_api_item(row)
        if normalized_visible_user_ids and mapped["ranger_id"] not in normalized_visible_user_ids:
            continue
        items.append(mapped)

    items.sort(key=lambda item: (item["work_date"], item["ranger_id"], item["schedule_id"]))
    return items


def list_mobile_deleted_schedule_ids(
    *,
    effective_ranger_id: str | None,
    visible_user_ids: set[str] | None,
    from_day: date | None,
    to_day: date | None,
    updated_since: datetime | None,
    snapshot_at: datetime,
) -> list[str]:
    """Return deterministic soft-delete tombstones for scoped incremental schedule sync."""
    if updated_since is None:
        return []

    ensure_schedule_schema_ready()

    query = (
        get_supabase()
        .table(SCHEDULES_TABLE)
        .select("schedule_id,username,work_date,updated_at,deleted_at")
        .gte("updated_at", updated_since.isoformat())
        .lte("updated_at", snapshot_at.isoformat())
    )

    normalized_scope_username = _normalize_schedule_username(effective_ranger_id)
    if normalized_scope_username:
        query = query.eq("username", normalized_scope_username)

    normalized_visible_user_ids = {
        _normalize_schedule_username(value)
        for value in (visible_user_ids or set())
        if _normalize_schedule_username(value)
    }
    if normalized_visible_user_ids:
        query = _apply_in_filter(query, "username", sorted(normalized_visible_user_ids))

    if from_day is not None:
        query = query.gte("work_date", from_day.isoformat())
    if to_day is not None:
        query = query.lte("work_date", to_day.isoformat())

    try:
        result = query.limit(SCHEDULE_MAX_QUERY_ROWS).execute()
    except Exception as exc:
        raise ScheduleRepositoryError("Failed to load schedule tombstones") from exc

    raw_rows = result.data or []
    if len(raw_rows) >= SCHEDULE_MAX_QUERY_ROWS:
        raise ScheduleRepositoryError(
            "Schedule tombstone query reached safety row cap; narrow filters or increase SCHEDULE_MAX_QUERY_ROWS"
        )

    rows: list[dict] = []
    for row in raw_rows:
        if not isinstance(row, dict):
            continue
        if row.get("deleted_at") in (None, ""):
            continue

        row_username = _normalize_schedule_username(row.get("username"))
        if normalized_visible_user_ids and row_username not in normalized_visible_user_ids:
            continue
        rows.append(row)

    tombstone_sort_rows: list[tuple[datetime, str]] = []
    dedup: set[str] = set()

    for row in rows:
        schedule_id = str(row.get("schedule_id") or "").strip()
        if not schedule_id or schedule_id in dedup:
            continue

        updated_at = _parse_cursor_iso(str(row.get("updated_at") or ""))
        if updated_at is None:
            continue

        dedup.add(schedule_id)
        tombstone_sort_rows.append((updated_at, schedule_id))

    tombstone_sort_rows.sort(key=lambda item: (item[0], item[1]))
    return [schedule_id for _, schedule_id in tombstone_sort_rows]


def create_mobile_schedule(
    *,
    ranger_id: str,
    work_day: date,
    note: str,
    actor_username: str,
    actor_display_name: str,
) -> dict:
    """Persist a new active schedule row and return API-mapped payload."""
    ensure_schedule_schema_ready()

    normalized_ranger_id = _normalize_schedule_username(ranger_id)
    normalized_actor_username = _normalize_schedule_username(actor_username)
    if not normalized_ranger_id:
        raise ScheduleValidationError("ranger_id and work_date required")
    if not normalized_actor_username:
        raise ScheduleValidationError("Invalid schedule actor identity")

    normalized_actor_display_name = str(actor_display_name or "").strip() or normalized_actor_username

    payload = {
        "work_date": work_day.isoformat(),
        "username": normalized_ranger_id,
        "note": _normalize_schedule_note(note),
        "created_by_username": normalized_actor_username,
        "created_by_display_name": normalized_actor_display_name,
        "updated_by_username": normalized_actor_username,
        "updated_by_display_name": normalized_actor_display_name,
    }

    try:
        result = get_supabase().table(SCHEDULES_TABLE).insert(payload).execute()
    except Exception as exc:
        if _is_unique_conflict_error(exc):
            raise ScheduleConflictError("Duplicate active schedule assignment") from exc
        if _is_foreign_key_error(exc):
            raise ScheduleValidationError("Schedule assignee not found") from exc
        raise ScheduleRepositoryError("Failed to create schedule") from exc

    rows = result.data or []
    if not rows:
        raise ScheduleRepositoryError("Schedule create returned no row")

    return _schedule_row_to_api_item(rows[0])


def update_mobile_schedule(
    *,
    schedule_id: str,
    ranger_id: str,
    work_day: date,
    note: str,
    actor_username: str,
    actor_display_name: str,
) -> dict:
    """Update active schedule row and return API-mapped payload."""
    ensure_schedule_schema_ready()

    normalized_schedule_id = str(schedule_id or "").strip()
    normalized_ranger_id = _normalize_schedule_username(ranger_id)
    normalized_actor_username = _normalize_schedule_username(actor_username)
    if not normalized_schedule_id:
        raise ScheduleNotFoundError("Schedule not found")
    if not normalized_ranger_id:
        raise ScheduleValidationError("ranger_id and work_date required")
    if not normalized_actor_username:
        raise ScheduleValidationError("Invalid schedule actor identity")

    existing = _load_active_schedule_row(normalized_schedule_id)
    if not existing:
        raise ScheduleNotFoundError("Schedule not found")

    normalized_actor_display_name = str(actor_display_name or "").strip() or normalized_actor_username

    payload = {
        "work_date": work_day.isoformat(),
        "username": normalized_ranger_id,
        "note": _normalize_schedule_note(note),
        "updated_by_username": normalized_actor_username,
        "updated_by_display_name": normalized_actor_display_name,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        update_query = (
            get_supabase()
            .table(SCHEDULES_TABLE)
            .update(payload)
            .eq("schedule_id", normalized_schedule_id)
        )
        update_query = _apply_is_null_filter(update_query, "deleted_at")
        update_result = update_query.execute()
    except Exception as exc:
        if _is_unique_conflict_error(exc):
            raise ScheduleConflictError("Duplicate active schedule assignment") from exc
        if _is_foreign_key_error(exc):
            raise ScheduleValidationError("Schedule assignee not found") from exc
        raise ScheduleRepositoryError("Failed to update schedule") from exc

    updated_rows = update_result.data or []
    if updated_rows:
        return _schedule_row_to_api_item(updated_rows[0])

    updated = _load_active_schedule_row(normalized_schedule_id)
    if not updated:
        raise ScheduleNotFoundError("Schedule not found")
    return _schedule_row_to_api_item(updated)


def soft_delete_mobile_schedule(
    *,
    schedule_id: str,
    actor_username: str,
    actor_display_name: str,
) -> dict:
    """Soft-delete active schedule row and persist actor identity in mutation fields."""
    ensure_schedule_schema_ready()

    normalized_schedule_id = str(schedule_id or "").strip()
    normalized_actor_username = _normalize_schedule_username(actor_username)
    if not normalized_schedule_id:
        raise ScheduleNotFoundError("Schedule not found")
    if not normalized_actor_username:
        raise ScheduleValidationError("Invalid schedule actor identity")

    existing = _load_active_schedule_row(normalized_schedule_id)
    if not existing:
        raise ScheduleNotFoundError("Schedule not found")

    normalized_actor_display_name = str(actor_display_name or "").strip() or normalized_actor_username
    now_iso = datetime.now(timezone.utc).isoformat()

    payload = {
        "deleted_at": now_iso,
        "updated_at": now_iso,
        "updated_by_username": normalized_actor_username,
        "updated_by_display_name": normalized_actor_display_name,
    }

    try:
        update_query = (
            get_supabase()
            .table(SCHEDULES_TABLE)
            .update(payload)
            .eq("schedule_id", normalized_schedule_id)
        )
        update_query = _apply_is_null_filter(update_query, "deleted_at")
        update_result = update_query.execute()
    except Exception as exc:
        raise ScheduleRepositoryError("Failed to delete schedule") from exc

    updated_rows = update_result.data or []
    if not updated_rows:
        raise ScheduleNotFoundError("Schedule not found")

    return {
        "schedule_id": normalized_schedule_id,
        "deleted_at": now_iso,
        "updated_by": normalized_actor_username,
    }


# ─────────────────────────────────────────────────────────────
# TREES
# ─────────────────────────────────────────────────────────────

def upsert_trees(rows: list[dict]) -> int:
    """
    Insert or update tree records.  Deduplicates on `tree_id`.

    Returns count of upserted rows.
    """
    now = datetime.now(timezone.utc).isoformat()
    for row in rows:
        row["synced_at"] = now

    result = (
        get_supabase()
        .table("trees")
        .upsert(rows, on_conflict="tree_id")
        .execute()
    )
    return len(result.data) if result.data else 0


def upsert_incidents(rows: list[dict]) -> int:
    """Insert or update incident mirror records by stable EarthRanger event ID."""
    if not rows:
        return 0

    now = datetime.now(timezone.utc).isoformat()
    payload: list[dict] = []
    for row in rows:
        normalized = dict(row)
        normalized["synced_at"] = now
        payload.append(normalized)

    result = (
        get_supabase()
        .table("incidents_mirror")
        .upsert(payload, on_conflict="er_event_id")
        .execute()
    )
    return len(result.data) if result.data else 0


def get_sync_cursor(stream_name: str) -> str | None:
    """Fetch stored high-watermark cursor value for a named sync stream."""
    result = (
        get_supabase()
        .table("sync_cursors")
        .select("cursor_value")
        .eq("stream_name", stream_name)
        .maybe_single()
        .execute()
    )

    if not result.data:
        return None

    cursor_raw = str(result.data.get("cursor_value") or "").strip()
    if not cursor_raw:
        return None

    parsed = _parse_cursor_iso(cursor_raw)
    if parsed is None:
        raise ValueError(
            f"Stored cursor for stream '{stream_name}' is invalid ISO datetime: {cursor_raw!r}"
        )
    return parsed.isoformat()


def set_sync_cursor(stream_name: str, cursor_value: str) -> dict:
    """Persist cursor monotonically, never regressing to an older value."""
    candidate = _parse_cursor_iso(cursor_value)
    if candidate is None:
        raise ValueError(f"Invalid cursor_value for stream '{stream_name}': {cursor_value!r}")

    candidate_value = candidate.isoformat()
    now = datetime.now(timezone.utc).isoformat()
    table = get_supabase().table("sync_cursors")

    for _ in range(4):
        existing_result = (
            table
            .select("cursor_value")
            .eq("stream_name", stream_name)
            .maybe_single()
            .execute()
        )
        existing_data = existing_result.data
        row_exists = existing_data is not None
        existing_data = existing_data or {}
        existing_value = existing_data.get("cursor_value")
        existing_raw = str(existing_value or "").strip()

        if row_exists and existing_raw:
            existing_dt = _parse_cursor_iso(existing_raw)
            if existing_dt is None:
                raise ValueError(
                    f"Stored cursor for stream '{stream_name}' is invalid ISO datetime: {existing_raw!r}"
                )

            if existing_dt >= candidate:
                return {
                    "stream_name": stream_name,
                    "cursor_value": existing_dt.isoformat(),
                    "updated_at": now,
                }

            update_result = (
                table
                .update({"cursor_value": candidate_value, "updated_at": now})
                .eq("stream_name", stream_name)
                .eq("cursor_value", existing_raw)
                .execute()
            )
            if update_result.data:
                return update_result.data[0]

            # Another writer updated the row between read and write; retry.
            continue

        if row_exists and not existing_raw:
            null_filtered_update = (
                table
                .update({"cursor_value": candidate_value, "updated_at": now})
                .eq("stream_name", stream_name)
            )
            if existing_value is None:
                if hasattr(null_filtered_update, "is_"):
                    null_filtered_update = null_filtered_update.is_("cursor_value", "null")
                else:
                    null_filtered_update = null_filtered_update.eq("cursor_value", None)
            else:
                null_filtered_update = null_filtered_update.eq("cursor_value", existing_value)

            update_null_result = null_filtered_update.execute()
            if update_null_result.data:
                return update_null_result.data[0]

            # Another writer changed this row between read and write; retry.
            continue

        record = {
            "stream_name": stream_name,
            "cursor_value": candidate_value,
            "updated_at": now,
        }
        try:
            insert_result = table.insert(record).execute()
            if insert_result.data:
                return insert_result.data[0]
        except Exception as exc:
            if not _is_unique_conflict_error(exc):
                raise

            # Insert race: row was created concurrently, retry from top.
            continue

    final_cursor = get_sync_cursor(stream_name)
    final_dt = _parse_cursor_iso(final_cursor)
    if final_dt is None:
        raise RuntimeError(f"Unable to persist cursor for stream '{stream_name}'")
    if final_dt < candidate:
        raise RuntimeError(
            f"Unable to advance cursor for stream '{stream_name}' to {candidate_value}; "
            f"final stored cursor remained at {final_dt.isoformat()}"
        )

    return {
        "stream_name": stream_name,
        "cursor_value": final_dt.isoformat(),
        "updated_at": now,
    }


def get_all_trees() -> list[dict]:
    """Fetch every row from the trees table."""
    result = get_supabase().table("trees").select("*").execute()
    return result.data or []


def get_tree_by_id(tree_id: str) -> dict | None:
    """Fetch a single tree by its tree_id."""
    result = (
        get_supabase()
        .table("trees")
        .select("*")
        .eq("tree_id", tree_id)
        .maybe_single()
        .execute()
    )
    return result.data


# ─────────────────────────────────────────────────────────────
# NFC CARDS (for future NFC app integration)
# ─────────────────────────────────────────────────────────────

def get_tree_by_nfc(nfc_uid: str) -> dict | None:
    """Look up a tree by its NFC card UID."""
    result = (
        get_supabase()
        .table("nfc_cards")
        .select("tree_id")
        .eq("nfc_uid", nfc_uid)
        .maybe_single()
        .execute()
    )
    if not result.data:
        return None
    return get_tree_by_id(result.data["tree_id"])


def link_nfc_to_tree(nfc_uid: str, tree_id: str, assigned_by: str = "") -> dict:
    """Assign an NFC card to a tree."""
    result = (
        get_supabase()
        .table("nfc_cards")
        .upsert(
            {"nfc_uid": nfc_uid, "tree_id": tree_id, "assigned_by": assigned_by},
            on_conflict="nfc_uid",
        )
        .execute()
    )
    return result.data[0] if result.data else {}
