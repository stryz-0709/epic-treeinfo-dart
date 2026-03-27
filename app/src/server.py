"""
Unified FastAPI server — dashboard + API, all in one app.

Serves:
  - Dashboard UI (login, tree report, charts, map)
  - REST API for NFC app (/api/trees, /api/trees/{id}, /api/sync)

Production features:
  - Structured JSON logging with request ID tracking
  - bcrypt password hashing (auto-migrates from old SHA-256 hashes)
  - Rate limiting on login / API / sync
  - CORS middleware for NFC Android app

Usage:
    cd v2
    uvicorn src.server:app --reload --port 8000
"""

import hmac
import json
import logging
import os
import re
import secrets
from time import perf_counter
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from threading import RLock, Thread
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import bcrypt
from fastapi import FastAPI, Request, Form, Header, HTTPException, Depends, Query
from pydantic import BaseModel, Field
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from starlette.concurrency import run_in_threadpool
from starlette.middleware.base import BaseHTTPMiddleware

from src.config import get_settings
from src.logging_config import (
    setup_logging, request_id_var, generate_request_id, get_request_id,
)
from src.supabase_db import (
    ScheduleConflictError,
    ScheduleNotFoundError,
    ScheduleReadinessError,
    ScheduleRepositoryError,
    ScheduleValidationError,
    create_mobile_schedule,
    ensure_schedule_schema_ready,
    get_all_trees,
    get_mobile_schedule_item,
    get_schedule_preflight_cache,
    get_tree_by_id,
    get_tree_by_nfc,
    list_mobile_deleted_schedule_ids,
    list_mobile_schedule_items,
    link_nfc_to_tree,
    load_auth_users,
    replace_auth_users,
    soft_delete_mobile_schedule,
    update_mobile_schedule,
    validate_schedule_readiness_mode,
)
from src.earthranger import get_er_client
from src.models import db_row_to_dashboard, compute_stats, compute_alerts, compute_analytics, event_to_db_row
from src.sync import run_sync_cycle, run_loop
from src.retention import (
    execute_ranger_stats_retention,
    list_retention_runs,
    replay_retention_run,
)

log = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────
# LIFESPAN — start background sync on startup
# ─────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start the background sync thread when the server boots."""
    s = get_settings()

    # Configure logging BEFORE anything else
    setup_logging(level=s.log_level, json_output=s.log_json)

    # Fail fast on insecure production configuration
    s.validate_security_baseline()

    schedule_mode = validate_schedule_readiness_mode(is_production=s.is_production)
    if s.is_production and schedule_mode == "strict":
        ensure_schedule_schema_ready(force=True)
        log.info("Schedule schema preflight succeeded in strict production mode")
    else:
        log.info(
            "Schedule readiness mode '%s' active; request-path readiness gate enabled",
            schedule_mode,
        )

    log.info("Starting EarthRanger Tree Platform v%s", s.app_version)

    sync_thread = Thread(target=run_loop, daemon=True, name="sync-pipeline")
    sync_thread.start()
    log.info("Background sync started (every %d min)", s.sync_interval_minutes)
    yield
    log.info("Server shutting down")


# ─────────────────────────────────────────────────────────────
# RATE LIMITER
# ─────────────────────────────────────────────────────────────

limiter = Limiter(key_func=get_remote_address)


# ─────────────────────────────────────────────────────────────
# REQUEST ID MIDDLEWARE
# ─────────────────────────────────────────────────────────────

class RequestIDMiddleware(BaseHTTPMiddleware):
    """Attach a unique request ID to every request for log correlation."""

    async def dispatch(self, request: Request, call_next):
        incoming_request_id = request.headers.get("X-Request-ID")
        if incoming_request_id:
            incoming_request_id = incoming_request_id.strip()

        if (
            incoming_request_id
            and len(incoming_request_id) <= 128
            and re.fullmatch(r"[A-Za-z0-9._:-]+", incoming_request_id)
        ):
            rid = incoming_request_id
        else:
            rid = generate_request_id()

        token = request_id_var.set(rid)
        request.state.request_id = rid
        start = perf_counter()

        try:
            response = await call_next(request)
            duration = (perf_counter() - start) * 1000
            response.headers["X-Request-ID"] = rid

            # Log every request with structured fields
            log.info(
                "%s %s → %d (%.0fms)",
                request.method,
                request.url.path,
                response.status_code,
                duration,
                extra={
                    "event": "request_completed",
                    "method": request.method,
                    "path": str(request.url.path),
                    "status_code": response.status_code,
                    "duration_ms": round(duration, 1),
                    "client_ip": get_remote_address(request),
                    "request_id": rid,
                },
            )

            slow_threshold_ms = float(_s.effective_slow_request_warn_ms)
            if slow_threshold_ms <= 1 or duration >= slow_threshold_ms:
                log.warning(
                    "Slow request detected: %s %s (%.1fms)",
                    request.method,
                    request.url.path,
                    duration,
                    extra={
                        "event": "slow_request",
                        "method": request.method,
                        "path": str(request.url.path),
                        "status_code": response.status_code,
                        "duration_ms": round(duration, 1),
                        "slow_threshold_ms": slow_threshold_ms,
                        "client_ip": get_remote_address(request),
                        "request_id": rid,
                    },
                )
            return response
        except Exception:
            duration = (perf_counter() - start) * 1000
            log.exception(
                "%s %s → %d (%.0fms)",
                request.method,
                request.url.path,
                500,
                duration,
                extra={
                    "event": "request_failed",
                    "method": request.method,
                    "path": str(request.url.path),
                    "status_code": 500,
                    "duration_ms": round(duration, 1),
                    "client_ip": get_remote_address(request),
                    "request_id": rid,
                },
            )
            raise
        finally:
            request_id_var.reset(token)


# ─────────────────────────────────────────────────────────────
# APP
# ─────────────────────────────────────────────────────────────

_s = get_settings()

app = FastAPI(
    title="EarthRanger Tree Platform",
    version=_s.app_version,
    lifespan=lifespan,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS — allow NFC app / external clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=_s.cors_origins,
    allow_credentials=_s.cors_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request ID tracking
app.add_middleware(RequestIDMiddleware)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(BASE_DIR)

templates = Jinja2Templates(directory=os.path.join(PROJECT_DIR, "templates"))

static_dir = os.path.join(PROJECT_DIR, "static")
os.makedirs(static_dir, exist_ok=True)
app.mount("/static", StaticFiles(directory=static_dir), name="static")


# ─────────────────────────────────────────────────────────────
# AUTH — bcrypt + session-based
# ─────────────────────────────────────────────────────────────

DEFAULT_USERS_FILE = os.path.join(PROJECT_DIR, "users.json")
USERS_FILE = DEFAULT_USERS_FILE
sessions: dict[str, dict] = {}
mobile_access_sessions: dict[str, dict] = {}
mobile_refresh_sessions: dict[str, dict] = {}
mobile_schedule_records: dict[str, dict] = {}
mobile_schedule_sequence = 0
mobile_work_summary_records: list[dict] = []
mobile_daily_checkins: dict[tuple[str, str], dict] = {}
mobile_incident_records: list[dict] = []
mobile_checkin_lock = RLock()
mobile_work_summary_lock = RLock()
mobile_schedule_lock = RLock()

SCHEDULE_SERVICE_UNAVAILABLE_DETAIL = "Schedule service unavailable"
ALLOWED_ROLE_ACCOUNT_ROLE_COMBINATIONS: set[tuple[str, str]] = {
    ("leader", "admin"),
    ("leader", "leader"),
    ("ranger", "ranger"),
}

PROJECT_TIMEZONE_NAME = "Asia/Ho_Chi_Minh"
try:
    PROJECT_TIMEZONE = ZoneInfo(PROJECT_TIMEZONE_NAME)
except ZoneInfoNotFoundError:
    # Fallback for environments without IANA timezone data.
    PROJECT_TIMEZONE = timezone(timedelta(hours=7), name=PROJECT_TIMEZONE_NAME)


class MobileLoginRequest(BaseModel):
    """Request payload for mobile login endpoint."""

    username: str = Field(max_length=128)
    password: str = Field(max_length=256)


class MobileRefreshRequest(BaseModel):
    """Request payload for mobile refresh endpoint."""

    refresh_token: str


class MobileLogoutRequest(BaseModel):
    """Request payload for mobile logout endpoint."""

    refresh_token: str


class MobileScheduleWriteRequest(BaseModel):
    """Request payload for mobile schedule write endpoints."""

    ranger_id: str
    work_date: str
    note: str = Field(default="", max_length=500)


class MobileCheckinRequest(BaseModel):
    """Request payload for mobile check-in ingest endpoint."""

    idempotency_key: str = ""
    client_time: str = ""
    timezone: str = ""
    app_version: str = ""


class RetentionRunRequest(BaseModel):
    """Request payload for manual retention run endpoint."""

    dry_run: bool = False


class RetentionReplayRequest(BaseModel):
    """Request payload for retention replay endpoint."""

    dry_run: bool = False


def _hash_pw(password: str) -> str:
    """Hash a password with bcrypt (salted, 12 rounds)."""
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()


def _verify_pw(password: str, stored_hash: str) -> bool:
    """
    Verify a password against a stored hash.
    Supports both bcrypt ($2b$...) and legacy SHA-256 (64-char hex).
    Auto-migrates SHA-256 → bcrypt on successful login.
    """
    # Legacy SHA-256 detection (64 hex chars, no $ prefix)
    if len(stored_hash) == 64 and not stored_hash.startswith("$"):
        import hashlib
        candidate_hash = hashlib.sha256(password.encode()).hexdigest()
        return hmac.compare_digest(candidate_hash, stored_hash)  # migration handled in login_submit

    # bcrypt verification
    try:
        return bcrypt.checkpw(password.encode(), stored_hash.encode())
    except Exception:
        return False


def _load_users_from_file() -> dict:
    if not os.path.exists(USERS_FILE):
        s = get_settings()
        default = {
            "admin": {
                "password": _hash_pw(s.default_admin_password),
                "role": "admin",
                "display_name": "Administrator",
            }
        }
        with open(USERS_FILE, "w", encoding="utf-8") as f:
            json.dump(default, f, indent=2)
        return default
    with open(USERS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def _save_users_to_file(users: dict) -> None:
    with open(USERS_FILE, "w", encoding="utf-8") as f:
        json.dump(users, f, indent=2, ensure_ascii=False)


def _is_forced_file_user_store() -> bool:
    """Return True when tests or runtime override USERS_FILE to a custom path."""
    return os.path.abspath(USERS_FILE) != os.path.abspath(DEFAULT_USERS_FILE)


def _load_users() -> dict:
    """Load users from Supabase auth store when available, otherwise fallback to local file."""
    if _is_forced_file_user_store():
        return _load_users_from_file()

    supabase_users = load_auth_users()
    if supabase_users is None:
        return _load_users_from_file()

    # Normal path: Supabase auth table contains account records.
    if supabase_users:
        return supabase_users

    # Bootstrap path: if Supabase auth table is empty, seed it from local users file once.
    local_users = _load_users_from_file()
    if local_users and replace_auth_users(local_users):
        log.info("Seeded Supabase auth user table from local users bootstrap file")
        return local_users

    return supabase_users


def _save_users(users: dict):
    """Persist users to Supabase auth store when available, otherwise local file."""
    if _is_forced_file_user_store():
        _save_users_to_file(users)
        return

    if replace_auth_users(users):
        return
    _save_users_to_file(users)


def _utcnow() -> datetime:
    """Return timezone-aware current UTC timestamp."""
    return datetime.now(timezone.utc)


def _normalize_mobile_role(user_role: str) -> str:
    """Map internal user roles to mobile contract role claims."""
    role = (user_role or "").strip().lower()
    if role in {"admin", "leader"}:
        return "leader"
    return "ranger"


def _normalize_account_role(user_role: str) -> str:
    """Normalize internal account roles for authorization policy decisions."""
    role = (user_role or "").strip().lower()
    if role == "viewer":
        return "ranger"
    if role in {"admin", "leader", "ranger"}:
        return role
    return "ranger"


def _assert_mobile_claim_combination(role: str, account_role: str) -> None:
    """Fail closed when role/account_role claims conflict with allowed combinations."""
    claim_pair = (role, account_role)
    if claim_pair in ALLOWED_ROLE_ACCOUNT_ROLE_COMBINATIONS:
        return
    raise HTTPException(status_code=401, detail="Invalid access token")


def _raise_schedule_service_unavailable(*, reason: str) -> None:
    """Raise a generic schedule-readiness outage response and log detailed cause server-side."""
    request_id = get_request_id()
    log.error(
        "Schedule service unavailable",
        extra={
            "event": "schedule_service_unavailable",
            "request_id": request_id,
            "reason": reason,
            "readiness_cache": get_schedule_preflight_cache(),
        },
    )
    raise HTTPException(status_code=503, detail=SCHEDULE_SERVICE_UNAVAILABLE_DETAIL)


def _ensure_schedule_service_ready() -> None:
    """Ensure schedule preflight gate is green before serving schedule endpoints."""
    try:
        ensure_schedule_schema_ready()
    except ScheduleReadinessError as exc:
        _raise_schedule_service_unavailable(reason=str(exc))


def _resolve_user_display_name(username: str, user_data: dict | None = None) -> str:
    """Resolve a human-readable display name for an account username."""
    normalized_username = str(username or "").strip()
    if not normalized_username:
        return ""

    normalized_user_data = user_data if isinstance(user_data, dict) else {}
    display_name = str(normalized_user_data.get("display_name") or "").strip()
    if display_name:
        return display_name

    users = _load_users()
    if isinstance(users, dict):
        lookup = users.get(normalized_username.lower()) or users.get(normalized_username)
        if isinstance(lookup, dict):
            fallback_display_name = str(lookup.get("display_name") or "").strip()
            if fallback_display_name:
                return fallback_display_name

    return normalized_username


def _cleanup_expired_mobile_sessions() -> None:
    """Remove expired mobile sessions and orphaned access tokens."""
    now = _utcnow()

    expired_refresh_tokens: list[str] = []
    for token, payload in list(mobile_refresh_sessions.items()):
        if not isinstance(payload, dict):
            expired_refresh_tokens.append(token)
            continue

        expires_at = payload.get("expires_at")
        if not isinstance(expires_at, datetime):
            expired_refresh_tokens.append(token)
            continue

        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)

        if expires_at <= now:
            expired_refresh_tokens.append(token)

    for token in expired_refresh_tokens:
        mobile_refresh_sessions.pop(token, None)

    expired_access_tokens: list[str] = []
    for token, payload in list(mobile_access_sessions.items()):
        if not isinstance(payload, dict):
            expired_access_tokens.append(token)
            continue

        expires_at = payload.get("expires_at")
        refresh_token = payload.get("refresh_token")

        if not isinstance(expires_at, datetime) or not isinstance(refresh_token, str) or not refresh_token:
            expired_access_tokens.append(token)
            continue

        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)

        if expires_at <= now or refresh_token not in mobile_refresh_sessions:
            expired_access_tokens.append(token)

    for token in expired_access_tokens:
        mobile_access_sessions.pop(token, None)


def _issue_mobile_tokens(username: str, user_data: dict) -> dict:
    """Issue access/refresh tokens for mobile clients."""
    s = get_settings()
    _cleanup_expired_mobile_sessions()

    now = _utcnow()
    refresh_expires_at = now + timedelta(days=s.mobile_refresh_token_ttl_days)

    refresh_token = secrets.token_urlsafe(48)
    account_role = _normalize_account_role(str(user_data.get("role", "viewer")))
    role = _normalize_mobile_role(account_role)
    display_name = _resolve_user_display_name(username, user_data)

    mobile_refresh_sessions[refresh_token] = {
        "username": username,
        "display_name": display_name,
        "role": role,
        "account_role": account_role,
        "issued_at": now,
        "expires_at": refresh_expires_at,
    }

    return _issue_mobile_access_token(
        username=username,
        role=role,
        account_role=account_role,
        refresh_token=refresh_token,
        display_name=display_name,
    )


def _issue_mobile_access_token(
    username: str,
    role: str,
    account_role: str,
    refresh_token: str,
    display_name: str | None = None,
) -> dict:
    """Issue a new mobile access token bound to an existing refresh token."""
    s = get_settings()
    now = _utcnow()
    access_expires_at = now + timedelta(minutes=s.mobile_access_token_ttl_minutes)
    access_token = secrets.token_urlsafe(32)
    resolved_display_name = str(display_name or "").strip() or _resolve_user_display_name(username)

    mobile_access_sessions[access_token] = {
        "username": username,
        "display_name": resolved_display_name,
        "role": role,
        "account_role": account_role,
        "issued_at": now,
        "expires_at": access_expires_at,
        "refresh_token": refresh_token,
    }

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": int((access_expires_at - now).total_seconds()),
        "role": role,
        "account_role": account_role,
        "username": username,
        "display_name": resolved_display_name,
    }


def _refresh_mobile_access_token(refresh_token: str) -> dict:
    """Refresh access token for a valid refresh/session token."""
    _cleanup_expired_mobile_sessions()

    refresh_session = mobile_refresh_sessions.get(refresh_token)
    if not refresh_session:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    username = str(refresh_session.get("username") or "").strip()
    role = str(refresh_session.get("role") or "").strip()
    account_role = _normalize_account_role(str(refresh_session.get("account_role") or role))
    display_name = str(refresh_session.get("display_name") or "").strip()
    if not display_name:
        display_name = _resolve_user_display_name(username)
        if display_name:
            refresh_session["display_name"] = display_name

    if not username or not role:
        mobile_refresh_sessions.pop(refresh_token, None)
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    stale_access_tokens = [
        token
        for token, payload in mobile_access_sessions.items()
        if payload["refresh_token"] == refresh_token
    ]
    for token in stale_access_tokens:
        mobile_access_sessions.pop(token, None)

    return _issue_mobile_access_token(
        username=username,
        role=role,
        account_role=account_role,
        refresh_token=refresh_token,
        display_name=display_name,
    )


def _logout_mobile_session(refresh_token: str) -> str | None:
    """Invalidate refresh token and linked access tokens; return username when successful."""
    _cleanup_expired_mobile_sessions()

    refresh_session = mobile_refresh_sessions.pop(refresh_token, None)
    if not refresh_session:
        return None

    username = str(refresh_session.get("username") or "").strip()

    stale_access_tokens = [
        token
        for token, payload in mobile_access_sessions.items()
        if payload["refresh_token"] == refresh_token
    ]
    for token in stale_access_tokens:
        mobile_access_sessions.pop(token, None)

    return username or None


def _extract_bearer_token(authorization: str | None) -> str | None:
    """Parse bearer token from Authorization header."""
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.strip().lower() != "bearer":
        return None
    parsed = token.strip()
    return parsed or None


def require_mobile_auth(authorization: Optional[str] = Header(None)) -> dict:
    """FastAPI dependency — validate mobile bearer token and return session."""
    _cleanup_expired_mobile_sessions()
    access_token = _extract_bearer_token(authorization)
    if not access_token:
        raise HTTPException(status_code=401, detail="Invalid access token")

    mobile_user = mobile_access_sessions.get(access_token)
    if not mobile_user:
        raise HTTPException(status_code=401, detail="Invalid access token")

    username = str(mobile_user.get("username") or "").strip()
    display_name = str(mobile_user.get("display_name") or "").strip()
    role = str(mobile_user.get("role") or "").strip().lower()
    account_role_raw = str(mobile_user.get("account_role") or "").strip().lower()
    user_data: dict = {}
    if account_role_raw:
        account_role = _normalize_account_role(account_role_raw)
    else:
        users = _load_users()
        user_data = users.get(username, {}) if isinstance(users, dict) else {}
        if not isinstance(user_data, dict):
            user_data = {}
        account_role = _normalize_account_role(str(user_data.get("role") or role))

    if not username or role not in {"leader", "ranger"}:
        mobile_access_sessions.pop(access_token, None)
        raise HTTPException(status_code=401, detail="Invalid access token")

    try:
        _assert_mobile_claim_combination(role, account_role)
    except HTTPException:
        mobile_access_sessions.pop(access_token, None)
        raise

    if not display_name:
        display_name = _resolve_user_display_name(username, user_data)

    return {
        **mobile_user,
        "username": username,
        "display_name": display_name,
        "role": role,
        "account_role": account_role,
    }


def require_mobile_leader(mobile_user: dict = Depends(require_mobile_auth)) -> dict:
    """FastAPI dependency — require leader role for mobile endpoint access."""
    if mobile_user.get("role") != "leader":
        raise HTTPException(status_code=403, detail="Leader role required")
    return mobile_user


def require_mobile_admin(mobile_user: dict = Depends(require_mobile_auth)) -> dict:
    """FastAPI dependency — require admin account role for mobile endpoint access."""
    account_role = _normalize_account_role(
        str(mobile_user.get("account_role") or mobile_user.get("role") or "")
    )
    if account_role != "admin":
        raise HTTPException(status_code=403, detail="Admin role required")
    return mobile_user


def require_mobile_ranger(mobile_user: dict = Depends(require_mobile_auth)) -> dict:
    """FastAPI dependency — require ranger role for mobile endpoint access."""
    if mobile_user.get("role") != "ranger":
        raise HTTPException(status_code=403, detail="Ranger role required")
    return mobile_user


def _resolve_mobile_ranger_scope(mobile_user: dict, ranger_id: str | None) -> str:
    """Resolve effective ranger scope from role and optional ranger filter."""
    username = mobile_user.get("username", "")
    requested_ranger_id = (ranger_id or "").strip()

    if mobile_user.get("role") == "leader":
        return requested_ranger_id or username

    if requested_ranger_id and requested_ranger_id != username:
        raise HTTPException(status_code=403, detail="Ranger scope violation")

    return username


def _next_mobile_schedule_id() -> str:
    """Generate a deterministic incrementing schedule ID for in-memory writes.

    Caller must hold ``mobile_schedule_lock``.
    """
    global mobile_schedule_sequence
    while True:
        mobile_schedule_sequence += 1
        candidate = f"sched-{mobile_schedule_sequence}"
        if candidate not in mobile_schedule_records:
            return candidate


def _parse_iso_day(value: str | None) -> date | None:
    """Parse an ISO day string (YYYY-MM-DD) to date."""
    if value is None:
        return None
    raw = value.strip()
    if not raw:
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid date format: '{value}' (expected YYYY-MM-DD)",
        ) from exc


def _safe_parse_row_day(value: str | None) -> date | None:
    """Parse row day defensively without raising on malformed source values."""
    if value is None:
        return None

    raw = value.strip()
    if not raw:
        return None

    try:
        return date.fromisoformat(raw)
    except ValueError:
        return None


def _parse_iso_datetime(value: str | None, field_name: str) -> datetime | None:
    """Parse an ISO datetime string to UTC-aware datetime."""
    if value is None:
        return None
    raw = value.strip()
    if not raw:
        return None

    normalized = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid datetime format for '{field_name}': '{value}'",
        ) from exc

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _parse_incident_cursor(value: str | None) -> int | None:
    """Parse incident sync cursor as a non-negative offset token."""
    if value is None:
        return None

    raw = value.strip()
    if not raw:
        return None

    if not raw.isdigit():
        raise HTTPException(status_code=400, detail="Invalid cursor format")

    return int(raw)


def _validate_mobile_date_window(
    from_day: date | None,
    to_day: date | None,
    *,
    endpoint_path: str,
) -> None:
    """Validate date range order and configured maximum query window."""
    if from_day and to_day and from_day > to_day:
        raise HTTPException(status_code=400, detail="Invalid date range: from must be <= to")

    if not (from_day and to_day):
        return

    max_window_days = get_settings().mobile_query_max_window_days
    window_days = (to_day - from_day).days + 1
    if window_days > max_window_days:
        detail = f"Date range exceeds maximum window of {max_window_days} day(s)"
        log.warning(
            "Rejected mobile request with oversized date window",
            extra={
                "event": "mobile_validation_failed",
                "path": endpoint_path,
                "reason": "date_window_exceeded",
                "window_days": window_days,
                "max_window_days": max_window_days,
            },
        )
        raise HTTPException(status_code=400, detail=detail)


def _validate_mobile_updated_since_lookback(
    updated_since: datetime | None,
    *,
    endpoint_path: str,
) -> None:
    """Reject stale incremental checkpoints that exceed configured lookback policy."""
    if updated_since is None:
        return

    max_age_days = get_settings().mobile_updated_since_max_age_days
    earliest_allowed = _utcnow() - timedelta(days=max_age_days)
    if updated_since < earliest_allowed:
        detail = f"updated_since is too old; maximum lookback is {max_age_days} day(s)"
        log.warning(
            "Rejected mobile request with stale incremental checkpoint",
            extra={
                "event": "mobile_validation_failed",
                "path": endpoint_path,
                "reason": "updated_since_too_old",
                "updated_since": updated_since.isoformat(),
                "earliest_allowed": earliest_allowed.isoformat(),
                "max_age_days": max_age_days,
            },
        )
        raise HTTPException(status_code=400, detail=detail)


def _validate_mobile_page_size(
    page_size: int,
    *,
    endpoint_path: str,
    max_page_size: int,
) -> None:
    """Enforce runtime-configurable page-size caps per endpoint family."""
    if page_size <= max_page_size:
        return

    detail = f"Invalid pagination: page_size exceeds maximum {max_page_size}"
    log.warning(
        "Rejected mobile request with oversized page_size",
        extra={
            "event": "mobile_validation_failed",
            "path": endpoint_path,
            "reason": "page_size_exceeded",
            "page_size": page_size,
            "max_page_size": max_page_size,
        },
    )
    raise HTTPException(status_code=400, detail=detail)


def _log_mobile_endpoint_summary(
    *,
    endpoint_path: str,
    mobile_user: dict,
    requested_ranger_id: str | None,
    effective_ranger_id: str | None,
    team_scope: bool,
    filters: dict,
    pagination: dict,
    item_count: int,
) -> None:
    """Emit structured endpoint summary logs for mobile API observability."""
    log.info(
        "Mobile endpoint summary: %s",
        endpoint_path,
        extra={
            "event": "mobile_endpoint_summary",
            "path": endpoint_path,
            "role": mobile_user.get("role"),
            "username": mobile_user.get("username"),
            "team_scope": team_scope,
            "requested_ranger_id": requested_ranger_id,
            "effective_ranger_id": effective_ranger_id,
            "filters": filters,
            "pagination": pagination,
            "page": pagination.get("page"),
            "page_size": pagination.get("page_size"),
            "total": pagination.get("total"),
            "item_count": item_count,
        },
    )


def _safe_parse_row_datetime(value: str | None) -> datetime | None:
    """Parse row datetime defensively without raising on malformed source values."""
    if value is None:
        return None

    raw = value.strip()
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


def _resolve_mobile_work_scope(mobile_user: dict, ranger_id: str | None) -> tuple[Optional[str], bool]:
    """Resolve effective work-management scope based on user role and ranger filter."""
    requested_ranger_id = (ranger_id or "").strip().lower() or None
    username = str(mobile_user.get("username") or "").strip()
    role = str(mobile_user.get("role") or "").strip().lower()

    # Auth/session claims are validated upstream by require_mobile_auth.
    # Keep this helper focused on scope resolution only.

    if role == "leader":
        # team scope when no specific ranger filter is provided
        return requested_ranger_id, requested_ranger_id is None

    if requested_ranger_id and requested_ranger_id != username:
        raise HTTPException(status_code=403, detail="Ranger scope violation")

    return username, False


def _build_mobile_schedule_directory(mobile_user: dict) -> list[dict]:
    """Build assignee directory for schedule UI based on account role visibility."""
    username = str(mobile_user.get("username") or "").strip().lower()
    account_role = _normalize_account_role(
        str(mobile_user.get("account_role") or mobile_user.get("role") or "ranger")
    )

    users = _load_users()
    directory_by_username: dict[str, dict] = {}

    if isinstance(users, dict):
        for raw_username, raw_user_data in users.items():
            candidate_username = str(raw_username or "").strip().lower()
            if not candidate_username:
                continue

            normalized_user_data = raw_user_data if isinstance(raw_user_data, dict) else {}
            candidate_role = _normalize_account_role(str(normalized_user_data.get("role") or "ranger"))

            if account_role == "admin":
                if candidate_role not in {"leader", "ranger"}:
                    continue
            elif account_role == "leader":
                if candidate_role != "ranger":
                    continue
            else:
                if candidate_username != username:
                    continue
                candidate_role = "ranger"

            display_name = str(normalized_user_data.get("display_name") or candidate_username).strip()
            if not display_name:
                display_name = candidate_username

            directory_by_username[candidate_username] = {
                "username": candidate_username,
                "display_name": display_name,
                "role": candidate_role,
            }

    if account_role == "ranger" and username and username not in directory_by_username:
        directory_by_username[username] = {
            "username": username,
            "display_name": username,
            "role": "ranger",
        }

    directory = list(directory_by_username.values())
    directory.sort(
        key=lambda item: (
            0 if item["role"] == "ranger" else 1,
            item["display_name"].lower(),
            item["username"],
        )
    )
    return directory


def _resolve_mobile_schedule_scope(
    mobile_user: dict,
    ranger_id: str | None,
    visible_user_ids: set[str],
) -> tuple[Optional[str], bool]:
    """Resolve effective schedule scope from account role and selected ranger filter."""
    username = str(mobile_user.get("username") or "").strip().lower()
    requested_ranger_id = (ranger_id or "").strip().lower() or None
    account_role = _normalize_account_role(
        str(mobile_user.get("account_role") or mobile_user.get("role") or "ranger")
    )

    if account_role == "ranger":
        if requested_ranger_id and requested_ranger_id != username:
            raise HTTPException(status_code=403, detail="Ranger scope violation")
        return username, False

    if requested_ranger_id:
        if requested_ranger_id not in visible_user_ids:
            raise HTTPException(status_code=403, detail="Schedule scope violation")
        return requested_ranger_id, False

    return None, True


def _validate_mobile_schedule_assignee_scope(mobile_user: dict, ranger_id: str) -> None:
    """Ensure schedule writes target assignees visible to current account role."""
    normalized_ranger_id = ranger_id.strip().lower()
    if not normalized_ranger_id:
        raise HTTPException(status_code=400, detail="ranger_id and work_date required")

    visible_user_ids = {
        item["username"]
        for item in _build_mobile_schedule_directory(mobile_user)
        if str(item.get("username") or "").strip()
    }
    if normalized_ranger_id not in visible_user_ids:
        raise HTTPException(status_code=403, detail="Schedule assignee not permitted")


def _coerce_checkin_flag(value: object) -> bool:
    """Coerce check-in indicator values into deterministic booleans."""
    if isinstance(value, bool):
        return value

    if isinstance(value, (int, float)):
        return value != 0

    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "y", "on", "confirmed"}:
            return True
        if normalized in {"false", "0", "no", "n", "off", "", "none", "null"}:
            return False

    return False


def _build_mobile_work_summary_items(
    mobile_user: dict,
    ranger_id: str | None,
    from_day: date | None,
    to_day: date | None,
) -> tuple[list[dict], Optional[str], bool]:
    """Build role-scoped, filtered work summary rows."""
    effective_ranger_id, team_scope = _resolve_mobile_work_scope(mobile_user, ranger_id)

    deduped_rows: dict[tuple[str, str], dict] = {}

    for row in list(mobile_work_summary_records):
        if not isinstance(row, dict):
            continue

        row_ranger_id = str(row.get("ranger_id") or "").strip()
        if not row_ranger_id:
            continue

        if effective_ranger_id is not None and row_ranger_id != effective_ranger_id:
            continue

        row_day_key = str(row.get("day_key") or "").strip()
        row_day = _safe_parse_row_day(row_day_key)
        if row_day is None:
            continue

        if from_day and row_day < from_day:
            continue
        if to_day and row_day > to_day:
            continue

        raw_has_checkin = row.get("has_checkin")
        if "has_checkin" in row and raw_has_checkin is not None:
            has_checkin = _coerce_checkin_flag(raw_has_checkin)
        else:
            has_checkin = _coerce_checkin_flag(row.get("checkin_confirmed", False))

        summary = row.get("summary")
        if not isinstance(summary, dict):
            summary = {}

        row_key = (row_ranger_id, row_day.isoformat())
        existing = deduped_rows.get(row_key)
        if existing:
            existing["has_checkin"] = existing["has_checkin"] or has_checkin
            if summary:
                merged_summary = dict(existing["summary"])
                merged_summary.update(summary)
                existing["summary"] = merged_summary
            continue

        deduped_rows[row_key] = {
            "ranger_id": row_ranger_id,
            "day_key": row_day.isoformat(),
            "has_checkin": has_checkin,
            "summary": dict(summary),
        }

    items = [
        {
            "ranger_id": item["ranger_id"],
            "day_key": item["day_key"],
            "has_checkin": item["has_checkin"],
            "checkin_indicator": "confirmed" if item["has_checkin"] else "none",
            "summary": item["summary"],
        }
        for item in deduped_rows.values()
    ]

    items.sort(key=lambda item: (item["ranger_id"], item["day_key"]))
    return items, effective_ranger_id, team_scope


def _build_mobile_incident_items(
    mobile_user: dict,
    ranger_id: str | None,
    from_day: date | None,
    to_day: date | None,
    updated_since: datetime | None,
) -> tuple[list[dict], Optional[str], bool]:
    """Build role-scoped, filtered incident rows from mirrored in-memory data."""
    effective_ranger_id, team_scope = _resolve_mobile_work_scope(mobile_user, ranger_id)

    items: list[dict] = []
    for row in list(mobile_incident_records):
        if not isinstance(row, dict):
            continue

        mapping_status = str(row.get("mapping_status") or "mapped").strip().lower()
        row_ranger_id = str(row.get("ranger_id") or row.get("mapped_ranger_id") or "").strip()
        incident_id = str(row.get("incident_id") or row.get("er_event_id") or "").strip()
        if not incident_id:
            continue

        if effective_ranger_id is not None and row_ranger_id != effective_ranger_id:
            continue

        # Ranger feeds must only include incidents mapped to the authenticated ranger identity.
        if mobile_user.get("role") == "ranger" and mapping_status != "mapped":
            continue

        occurred_at_raw = str(row.get("occurred_at") or "").strip()
        occurred_at = _safe_parse_row_datetime(occurred_at_raw)
        if from_day or to_day:
            if occurred_at is None:
                continue

            occurred_day = occurred_at.astimezone(PROJECT_TIMEZONE).date()
            if from_day and occurred_day < from_day:
                continue
            if to_day and occurred_day > to_day:
                continue

        updated_at_raw = str(row.get("updated_at") or occurred_at_raw).strip()
        updated_at = _safe_parse_row_datetime(updated_at_raw)
        if updated_since and updated_at is None:
            log.debug(
                "Skipping incident '%s' for updated_since filter due to missing/invalid updated_at",
                incident_id,
            )
            continue

        if updated_since and updated_at < updated_since:
            continue

        payload_ref = row.get("payload_ref")
        if payload_ref is not None:
            payload_ref = str(payload_ref)

        items.append(
            {
                "incident_id": incident_id,
                "er_event_id": str(row.get("er_event_id") or incident_id),
                "ranger_id": row_ranger_id or None,
                "mapping_status": mapping_status,
                "occurred_at": occurred_at.isoformat() if occurred_at else None,
                "updated_at": updated_at.isoformat() if updated_at else None,
                "title": str(row.get("title") or row.get("event_type") or "Incident"),
                "status": str(row.get("status") or "open"),
                "severity": str(row.get("severity") or "unknown"),
                "payload_ref": payload_ref,
            }
        )

    items.sort(
        key=lambda item: (item.get("updated_at") or "", item.get("incident_id") or ""),
        reverse=True,
    )
    return items, effective_ranger_id, team_scope


def _build_mobile_schedule_items(
    mobile_user: dict,
    ranger_id: str | None,
    from_day: date | None,
    to_day: date | None,
    updated_since: datetime | None,
    snapshot_at: datetime,
) -> tuple[list[dict], Optional[str], bool, list[dict], list[str]]:
    """Build role-scoped, filtered schedule rows from Supabase schedule repository."""
    directory = _build_mobile_schedule_directory(mobile_user)
    visible_user_ids = {
        item["username"]
        for item in directory
        if str(item.get("username") or "").strip()
    }
    effective_ranger_id, team_scope = _resolve_mobile_schedule_scope(
        mobile_user,
        ranger_id,
        visible_user_ids,
    )

    items = list_mobile_schedule_items(
        effective_ranger_id=effective_ranger_id,
        visible_user_ids=visible_user_ids,
        from_day=from_day,
        to_day=to_day,
        updated_since=updated_since,
        snapshot_at=snapshot_at,
    )

    deleted_schedule_ids: list[str] = []
    if updated_since is not None:
        deleted_schedule_ids = list_mobile_deleted_schedule_ids(
            effective_ranger_id=effective_ranger_id,
            visible_user_ids=visible_user_ids,
            from_day=from_day,
            to_day=to_day,
            updated_since=updated_since,
            snapshot_at=snapshot_at,
        )

    return items, effective_ranger_id, team_scope, directory, deleted_schedule_ids


def _validate_mobile_schedule_write_payload(payload: MobileScheduleWriteRequest) -> tuple[str, date, str]:
    """Validate and normalize schedule write payload fields."""
    ranger_id = payload.ranger_id.strip().lower()
    work_date_raw = payload.work_date.strip()
    # Normalize note by trimming boundary whitespace before persistence.
    note = payload.note.strip()

    if not ranger_id or not work_date_raw:
        raise HTTPException(status_code=400, detail="ranger_id and work_date required")

    work_day = _parse_iso_day(work_date_raw)
    return ranger_id, work_day, note


def _compute_project_day_key(now_utc: datetime) -> str:
    """Compute day key in project timezone from UTC timestamp."""
    return now_utc.astimezone(PROJECT_TIMEZONE).date().isoformat()


def _upsert_work_summary_checkin(ranger_id: str, day_key: str) -> None:
    """Ensure work summary row has confirmed check-in indicator for ranger/day."""
    with mobile_work_summary_lock:
        for row in mobile_work_summary_records:
            if row.get("ranger_id") == ranger_id and row.get("day_key") == day_key:
                row["has_checkin"] = True
                row["checkin_confirmed"] = True
                if not isinstance(row.get("summary"), dict):
                    row["summary"] = {}
                return

        mobile_work_summary_records.append(
            {
                "ranger_id": ranger_id,
                "day_key": day_key,
                "has_checkin": True,
                "checkin_confirmed": True,
                "summary": {},
            }
        )


def _ingest_mobile_checkin(mobile_user: dict, payload: MobileCheckinRequest) -> dict:
    """Persist idempotent once-per-day check-in for authenticated ranger."""
    if mobile_user.get("role") != "ranger":
        raise HTTPException(status_code=403, detail="Ranger role required")

    user_id = str(mobile_user.get("username") or "").strip()
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid access token")

    with mobile_checkin_lock:
        server_time = _utcnow()
        day_key = _compute_project_day_key(server_time)
        checkin_key = (user_id, day_key)

        existing = mobile_daily_checkins.get(checkin_key)
        if existing:
            response = {
                "status": "already_exists",
                "user_id": user_id,
                "day_key": day_key,
                "server_time": existing["server_time"],
                "timezone": PROJECT_TIMEZONE_NAME,
                "idempotency_key": existing["idempotency_key"],
            }
        else:
            request_idempotency_key = payload.idempotency_key.strip()
            record = {
                "user_id": user_id,
                "day_key": day_key,
                "server_time": server_time.isoformat(),
                "timezone": PROJECT_TIMEZONE_NAME,
                "idempotency_key": request_idempotency_key or f"{user_id}:checkin:{day_key}",
                "client_time": payload.client_time.strip(),
                "client_timezone": payload.timezone.strip(),
                "app_version": payload.app_version.strip(),
            }

            mobile_daily_checkins[checkin_key] = record
            response = {
                "status": "created",
                "user_id": record["user_id"],
                "day_key": record["day_key"],
                "server_time": record["server_time"],
                "timezone": record["timezone"],
                "idempotency_key": record["idempotency_key"],
            }

        _upsert_work_summary_checkin(user_id, response["day_key"])

    log.info(
        "Mobile check-in ingest result status=%s user=%s day_key=%s",
        response["status"],
        user_id,
        response["day_key"],
        extra={
            "event": "mobile_checkin_ingest_result",
            "path": "/api/mobile/checkins",
            "username": user_id,
            "status": response["status"],
            "day_key": response["day_key"],
        },
    )
    return response


def get_current_user(request: Request) -> dict | None:
    token = request.cookies.get("session_token")
    if token and token in sessions:
        return sessions[token]
    return None


def require_auth(request: Request) -> dict:
    """FastAPI dependency — returns user or raises 401."""
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return user


def _require_admin_dashboard_user(user: dict) -> None:
    """Enforce admin role for dashboard/admin operations."""
    if user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin only")


# ─────────────────────────────────────────────────────────────
# ROUTES — Dashboard UI
# ─────────────────────────────────────────────────────────────

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if get_current_user(request):
        return RedirectResponse("/", status_code=302)
    return templates.TemplateResponse("login.html", {"request": request, "error": ""})


@app.post("/login")
@limiter.limit(lambda: get_settings().rate_limit_login)
async def login_submit(request: Request, username: str = Form(...), password: str = Form(...)):
    username = username.strip().lower()
    users = _load_users()
    user_data = users.get(username)
    if not user_data or not _verify_pw(password, user_data["password"]):
        log.warning("Failed login attempt for user '%s' from %s", username, get_remote_address(request))
        return templates.TemplateResponse("login.html", {
            "request": request,
            "error": "Sai tên đăng nhập hoặc mật khẩu",
        })

    # Auto-migrate legacy SHA-256 hash to bcrypt
    stored = user_data["password"]
    if len(stored) == 64 and not stored.startswith("$"):
        log.info("Migrating password hash for '%s' from SHA-256 to bcrypt", username)
        users[username]["password"] = _hash_pw(password)
        _save_users(users)

    token = secrets.token_urlsafe(32)
    sessions[token] = {
        "username": username,
        "role": user_data["role"],
        "display_name": user_data.get("display_name", username),
        "region": user_data.get("region"),
    }
    log.info("User '%s' logged in", username)
    response = RedirectResponse("/", status_code=302)
    response.set_cookie("session_token", token, httponly=True, samesite="lax", max_age=86400)
    return response


@app.post("/api/mobile/auth/login")
@limiter.limit(lambda: get_settings().rate_limit_login)
async def api_mobile_login(request: Request, payload: MobileLoginRequest):
    """Authenticate mobile user and return short-lived access + refresh tokens."""
    username = payload.username.strip().lower()
    password = payload.password

    users = _load_users()
    user_data = users.get(username)

    if not username or not password or not user_data:
        log.warning(
            "Failed mobile login attempt for user '%s' from %s",
            username or "<empty>",
            get_remote_address(request),
            extra={
                "event": "mobile_auth_login_failed",
                "path": "/api/mobile/auth/login",
                "username": username or None,
                "client_ip": get_remote_address(request),
                "reason": "invalid_credentials_or_user_missing",
            },
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    stored_hash = user_data.get("password", "")
    if not _verify_pw(password, stored_hash):
        log.warning(
            "Failed mobile login attempt for user '%s' from %s",
            username,
            get_remote_address(request),
            extra={
                "event": "mobile_auth_login_failed",
                "path": "/api/mobile/auth/login",
                "username": username,
                "client_ip": get_remote_address(request),
                "reason": "invalid_password",
            },
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # Auto-migrate legacy SHA-256 hash to bcrypt
    if len(stored_hash) == 64 and not stored_hash.startswith("$"):
        log.info("Migrating mobile login password hash for '%s' from SHA-256 to bcrypt", username)
        users[username]["password"] = _hash_pw(password)
        _save_users(users)
        user_data = users[username]

    tokens = _issue_mobile_tokens(username, user_data)
    log.info(
        "Mobile user '%s' authenticated with role '%s'",
        username,
        tokens["role"],
        extra={
            "event": "mobile_auth_login_succeeded",
            "path": "/api/mobile/auth/login",
            "username": username,
            "role": tokens["role"],
        },
    )
    return tokens


@app.post("/api/mobile/auth/refresh")
@limiter.limit(lambda: get_settings().rate_limit_login)
async def api_mobile_refresh(request: Request, payload: MobileRefreshRequest):
    """Issue a new access token from a valid mobile refresh/session token."""
    refresh_token = payload.refresh_token.strip()
    if not refresh_token:
        log.warning(
            "Failed mobile refresh attempt with empty token from %s",
            get_remote_address(request),
            extra={
                "event": "mobile_auth_refresh_failed",
                "path": "/api/mobile/auth/refresh",
                "client_ip": get_remote_address(request),
                "reason": "empty_refresh_token",
            },
        )
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    tokens = _refresh_mobile_access_token(refresh_token)
    log.info(
        "Mobile session refreshed with role '%s'",
        tokens["role"],
        extra={
            "event": "mobile_auth_refresh_succeeded",
            "path": "/api/mobile/auth/refresh",
            "role": tokens["role"],
        },
    )
    return tokens


@app.post("/api/mobile/auth/logout")
@limiter.limit(lambda: get_settings().rate_limit_login)
async def api_mobile_logout(request: Request, payload: MobileLogoutRequest):
    """Invalidate an authenticated mobile refresh/session token."""
    refresh_token = payload.refresh_token.strip()
    if not refresh_token:
        log.warning(
            "Failed mobile logout attempt with empty token from %s",
            get_remote_address(request),
            extra={
                "event": "mobile_auth_logout_failed",
                "path": "/api/mobile/auth/logout",
                "client_ip": get_remote_address(request),
                "reason": "empty_refresh_token",
            },
        )
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    logged_out_username = _logout_mobile_session(refresh_token)
    if not logged_out_username:
        log.warning(
            "Failed mobile logout attempt with invalid token from %s",
            get_remote_address(request),
            extra={
                "event": "mobile_auth_logout_failed",
                "path": "/api/mobile/auth/logout",
                "client_ip": get_remote_address(request),
                "reason": "invalid_refresh_token",
            },
        )
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    log.info(
        "Mobile user '%s' logged out",
        logged_out_username,
        extra={
            "event": "mobile_auth_logout_succeeded",
            "path": "/api/mobile/auth/logout",
            "username": logged_out_username,
        },
    )
    return {"ok": True}


@app.get("/api/mobile/me")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_me(request: Request, mobile_user: dict = Depends(require_mobile_auth)):
    """Return authenticated mobile identity and role claims."""
    return {
        "username": mobile_user["username"],
        "display_name": mobile_user.get("display_name") or mobile_user["username"],
        "role": mobile_user["role"],
    }


@app.get("/api/mobile/work-management")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_work_management(
    request: Request,
    from_day_raw: Optional[str] = Query(None, alias="from"),
    to_day_raw: Optional[str] = Query(None, alias="to"),
    ranger_id: Optional[str] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(31, ge=1, le=366),
    mobile_user: dict = Depends(require_mobile_auth),
):
    """Role-scoped work management summary endpoint for calendar views."""
    requested_ranger_id = (ranger_id or "").strip() or None
    from_day = _parse_iso_day(from_day_raw)
    to_day = _parse_iso_day(to_day_raw)
    _validate_mobile_date_window(
        from_day,
        to_day,
        endpoint_path="/api/mobile/work-management",
    )
    _validate_mobile_page_size(
        page_size,
        endpoint_path="/api/mobile/work-management",
        max_page_size=get_settings().mobile_work_management_max_page_size,
    )

    all_items, effective_ranger_id, team_scope = _build_mobile_work_summary_items(
        mobile_user=mobile_user,
        ranger_id=requested_ranger_id,
        from_day=from_day,
        to_day=to_day,
    )

    total = len(all_items)
    total_pages = 1 if total == 0 else ((total - 1) // page_size) + 1
    max_page = max(total_pages, 1)

    if page > max_page:
        raise HTTPException(status_code=400, detail="Invalid pagination: page exceeds total_pages")

    start = (page - 1) * page_size
    end = start + page_size
    paged_items = all_items[start:end]

    filters_payload = {
        "from": from_day.isoformat() if from_day else None,
        "to": to_day.isoformat() if to_day else None,
    }
    pagination_payload = {
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
    }

    _log_mobile_endpoint_summary(
        endpoint_path="/api/mobile/work-management",
        mobile_user=mobile_user,
        requested_ranger_id=requested_ranger_id,
        effective_ranger_id=effective_ranger_id,
        team_scope=team_scope,
        filters=filters_payload,
        pagination=pagination_payload,
        item_count=len(paged_items),
    )

    return {
        "items": paged_items,
        "scope": {
            "role": mobile_user["role"],
            "team_scope": team_scope,
            "requested_ranger_id": requested_ranger_id,
            "effective_ranger_id": effective_ranger_id,
        },
        "filters": filters_payload,
        "pagination": pagination_payload,
    }


@app.get("/api/mobile/incidents")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_incidents(
    request: Request,
    from_day_raw: Optional[str] = Query(None, alias="from"),
    to_day_raw: Optional[str] = Query(None, alias="to"),
    updated_since_raw: Optional[str] = Query(None, alias="updated_since"),
    ranger_id: Optional[str] = None,
    cursor: Optional[str] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    mobile_user: dict = Depends(require_mobile_auth),
):
    """Role-scoped read-only incidents endpoint for mobile clients."""
    from_day = _parse_iso_day(from_day_raw)
    to_day = _parse_iso_day(to_day_raw)
    _validate_mobile_date_window(
        from_day,
        to_day,
        endpoint_path="/api/mobile/incidents",
    )

    requested_ranger_id = (ranger_id or "").strip() or None
    updated_since = _parse_iso_datetime(updated_since_raw, "updated_since")
    _validate_mobile_updated_since_lookback(
        updated_since,
        endpoint_path="/api/mobile/incidents",
    )

    _validate_mobile_page_size(
        page_size,
        endpoint_path="/api/mobile/incidents",
        max_page_size=get_settings().mobile_incidents_max_page_size,
    )

    cursor_offset = _parse_incident_cursor(cursor)

    all_items, effective_ranger_id, team_scope = _build_mobile_incident_items(
        mobile_user=mobile_user,
        ranger_id=requested_ranger_id,
        from_day=from_day,
        to_day=to_day,
        updated_since=updated_since,
    )

    total = len(all_items)
    total_pages = 0 if total == 0 else ((total - 1) // page_size) + 1
    max_page = max(total_pages, 1)

    if cursor_offset is not None:
        if page != 1:
            raise HTTPException(status_code=400, detail="Invalid pagination: provide either page or cursor")

        if cursor_offset < 0 or (total == 0 and cursor_offset > 0) or (total > 0 and cursor_offset >= total):
            raise HTTPException(status_code=400, detail="Invalid cursor: offset out of range")

        start = cursor_offset
        page = (start // page_size) + 1
    else:
        if page > max_page:
            raise HTTPException(status_code=400, detail="Invalid pagination: page exceeds total_pages")
        start = (page - 1) * page_size

    end = start + page_size
    paged_items = all_items[start:end]

    has_more = page < total_pages if total_pages else False
    overall_latest_synced_at = next((item["updated_at"] for item in all_items if item.get("updated_at")), None)
    # Emit incremental checkpoint only when the current pagination window has been fully drained.
    last_synced_at = None if has_more else overall_latest_synced_at
    next_cursor = str(end) if end < total else None

    filters_payload = {
        "from": from_day.isoformat() if from_day else None,
        "to": to_day.isoformat() if to_day else None,
        "updated_since": updated_since.isoformat() if updated_since else None,
    }
    pagination_payload = {
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
    }

    _log_mobile_endpoint_summary(
        endpoint_path="/api/mobile/incidents",
        mobile_user=mobile_user,
        requested_ranger_id=requested_ranger_id,
        effective_ranger_id=effective_ranger_id,
        team_scope=team_scope,
        filters=filters_payload,
        pagination=pagination_payload,
        item_count=len(paged_items),
    )

    return {
        "items": paged_items,
        "scope": {
            "role": mobile_user["role"],
            "team_scope": team_scope,
            "requested_ranger_id": requested_ranger_id,
            "effective_ranger_id": effective_ranger_id,
        },
        "filters": filters_payload,
        "pagination": pagination_payload,
        "sync": {
            "cursor": next_cursor,
            "has_more": has_more,
            "last_synced_at": last_synced_at,
        },
    }


@app.post("/api/mobile/checkins")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_checkins(
    request: Request,
    payload: MobileCheckinRequest,
    mobile_user: dict = Depends(require_mobile_ranger),
):
    """Idempotent ranger check-in ingest endpoint."""
    return _ingest_mobile_checkin(mobile_user, payload)


@app.get("/api/mobile/schedules")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_schedules(
    request: Request,
    from_day_raw: Optional[str] = Query(None, alias="from"),
    to_day_raw: Optional[str] = Query(None, alias="to"),
    updated_since_raw: Optional[str] = Query(None, alias="updated_since"),
    snapshot_at_raw: Optional[str] = Query(None, alias="snapshot_at"),
    ranger_id: Optional[str] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=500),
    mobile_user: dict = Depends(require_mobile_auth),
):
    """Role-scoped schedule read endpoint for mobile clients."""
    from_day = _parse_iso_day(from_day_raw)
    to_day = _parse_iso_day(to_day_raw)
    updated_since = _parse_iso_datetime(updated_since_raw, "updated_since")
    snapshot_at = _parse_iso_datetime(snapshot_at_raw, "snapshot_at")
    if snapshot_at is None:
        snapshot_at = _utcnow()

    now_utc = _utcnow()
    if snapshot_at > now_utc + timedelta(minutes=5):
        raise HTTPException(status_code=400, detail="Invalid snapshot_at: cannot be in the future")

    snapshot_max_age_days = get_settings().mobile_updated_since_max_age_days
    if snapshot_at < now_utc - timedelta(days=snapshot_max_age_days):
        raise HTTPException(
            status_code=400,
            detail=f"snapshot_at is too old; maximum lookback is {snapshot_max_age_days} day(s)",
        )

    if updated_since and snapshot_at < updated_since:
        raise HTTPException(status_code=400, detail="Invalid snapshot_at: must be >= updated_since")

    _validate_mobile_updated_since_lookback(
        updated_since,
        endpoint_path="/api/mobile/schedules",
    )

    requested_ranger_id = (ranger_id or "").strip().lower() or None
    _validate_mobile_date_window(
        from_day,
        to_day,
        endpoint_path="/api/mobile/schedules",
    )
    _validate_mobile_page_size(
        page_size,
        endpoint_path="/api/mobile/schedules",
        max_page_size=get_settings().mobile_schedules_max_page_size,
    )

    # Both leader and ranger roles can read; role scope is enforced server-side per row.
    _ensure_schedule_service_ready()
    try:
        items, effective_ranger_id, team_scope, directory, deleted_schedule_ids = _build_mobile_schedule_items(
            mobile_user=mobile_user,
            ranger_id=requested_ranger_id,
            from_day=from_day,
            to_day=to_day,
            updated_since=updated_since,
            snapshot_at=snapshot_at,
        )
    except ScheduleReadinessError as exc:
        _raise_schedule_service_unavailable(reason=str(exc))
    except ScheduleRepositoryError:
        log.exception("Failed to read mobile schedules from repository")
        raise HTTPException(status_code=500, detail="Schedule persistence failure")

    total = len(items)
    total_pages = 0 if total == 0 else ((total - 1) // page_size) + 1
    max_page = max(total_pages, 1)

    if page > max_page:
        raise HTTPException(status_code=400, detail="Invalid pagination: page exceeds total_pages")

    start = (page - 1) * page_size
    end = start + page_size
    paged_items = items[start:end]

    filters_payload = {
        "from": from_day.isoformat() if from_day else None,
        "to": to_day.isoformat() if to_day else None,
        "updated_since": updated_since.isoformat() if updated_since else None,
        "snapshot_at": snapshot_at.isoformat(),
    }
    pagination_payload = {
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
    }

    _log_mobile_endpoint_summary(
        endpoint_path="/api/mobile/schedules",
        mobile_user=mobile_user,
        requested_ranger_id=requested_ranger_id,
        effective_ranger_id=effective_ranger_id,
        team_scope=team_scope,
        filters=filters_payload,
        pagination=pagination_payload,
        item_count=len(paged_items),
    )

    response_payload = {
        "items": paged_items,
        "scope": {
            "role": mobile_user["role"],
            "account_role": mobile_user.get("account_role"),
            "team_scope": team_scope,
            "requested_ranger_id": requested_ranger_id,
            "effective_ranger_id": effective_ranger_id,
        },
        "filters": filters_payload,
        "pagination": pagination_payload,
        "directory": directory,
    }

    if updated_since is not None:
        response_payload["sync"] = {
            "deleted_schedule_ids": deleted_schedule_ids,
        }

    return response_payload


@app.post("/api/mobile/schedules")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_create_schedule(
    request: Request,
    payload: MobileScheduleWriteRequest,
    mobile_user: dict = Depends(require_mobile_leader),
):
    """Leader-only mobile schedule create endpoint."""
    ranger_id, work_day, note = _validate_mobile_schedule_write_payload(payload)
    _validate_mobile_schedule_assignee_scope(mobile_user, ranger_id)

    _ensure_schedule_service_ready()
    actor_username = str(mobile_user.get("username") or "").strip().lower()
    actor_display_name = str(mobile_user.get("display_name") or actor_username).strip() or actor_username

    try:
        schedule = create_mobile_schedule(
            ranger_id=ranger_id,
            work_day=work_day,
            note=note,
            actor_username=actor_username,
            actor_display_name=actor_display_name,
        )
    except ScheduleReadinessError as exc:
        _raise_schedule_service_unavailable(reason=str(exc))
    except ScheduleConflictError:
        raise HTTPException(status_code=409, detail="Duplicate active schedule assignment")
    except ScheduleValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except ScheduleRepositoryError:
        log.exception("Failed to create mobile schedule")
        raise HTTPException(status_code=500, detail="Schedule persistence failure")

    return {"ok": True, "schedule": schedule}


@app.put("/api/mobile/schedules/{schedule_id}")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_update_schedule(
    request: Request,
    schedule_id: str,
    payload: MobileScheduleWriteRequest,
    mobile_user: dict = Depends(require_mobile_leader),
):
    """Leader-only mobile schedule update endpoint."""
    ranger_id, work_day, note = _validate_mobile_schedule_write_payload(payload)

    _ensure_schedule_service_ready()
    actor_username = str(mobile_user.get("username") or "").strip().lower()
    actor_display_name = str(mobile_user.get("display_name") or actor_username).strip() or actor_username

    try:
        existing_schedule = get_mobile_schedule_item(schedule_id=schedule_id)
        _validate_mobile_schedule_assignee_scope(
            mobile_user,
            str(existing_schedule.get("ranger_id") or ""),
        )
        _validate_mobile_schedule_assignee_scope(mobile_user, ranger_id)
        schedule = update_mobile_schedule(
            schedule_id=schedule_id,
            ranger_id=ranger_id,
            work_day=work_day,
            note=note,
            actor_username=actor_username,
            actor_display_name=actor_display_name,
        )
    except ScheduleReadinessError as exc:
        _raise_schedule_service_unavailable(reason=str(exc))
    except ScheduleNotFoundError:
        raise HTTPException(status_code=404, detail="Schedule not found")
    except ScheduleConflictError:
        raise HTTPException(status_code=409, detail="Duplicate active schedule assignment")
    except ScheduleValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except ScheduleRepositoryError:
        log.exception("Failed to update mobile schedule")
        raise HTTPException(status_code=500, detail="Schedule persistence failure")

    return {"ok": True, "schedule": schedule}


@app.delete("/api/mobile/schedules/{schedule_id}")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_mobile_delete_schedule(
    request: Request,
    schedule_id: str,
    mobile_user: dict = Depends(require_mobile_admin),
):
    """Admin-only mobile schedule delete endpoint."""
    _ensure_schedule_service_ready()

    actor_username = str(mobile_user.get("username") or "").strip().lower()
    actor_display_name = str(mobile_user.get("display_name") or actor_username).strip() or actor_username

    try:
        soft_delete_mobile_schedule(
            schedule_id=schedule_id,
            actor_username=actor_username,
            actor_display_name=actor_display_name,
        )
    except ScheduleReadinessError as exc:
        _raise_schedule_service_unavailable(reason=str(exc))
    except ScheduleNotFoundError:
        raise HTTPException(status_code=404, detail="Schedule not found")
    except ScheduleRepositoryError:
        log.exception("Failed to delete mobile schedule")
        raise HTTPException(status_code=500, detail="Schedule persistence failure")

    return {
        "ok": True,
        "schedule_id": schedule_id,
        "deleted_by": actor_username,
    }


@app.get("/logout")
async def logout(request: Request):
    token = request.cookies.get("session_token")
    if token and token in sessions:
        del sessions[token]
    resp = RedirectResponse("/login", status_code=302)
    resp.delete_cookie("session_token")
    return resp


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    user = get_current_user(request)
    if not user:
        return RedirectResponse("/login", status_code=302)
    return templates.TemplateResponse("index.html", {"request": request, "user": user})


# ─────────────────────────────────────────────────────────────
# ROUTES — Data API (for dashboard + NFC app)
# ─────────────────────────────────────────────────────────────

@app.get("/api/trees")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_trees(request: Request):
    """All trees with stats. Used by dashboard and NFC app."""
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    records = get_all_trees()
    rows = [db_row_to_dashboard(r) for r in records]

    # Region-based filtering: non-admin users see only their region
    user_region = user.get("region") if user else None
    if user_region and user.get("role") != "admin":
        rows = [r for r in rows if r.get("region") == user_region]

    stats = compute_stats(rows)
    alerts = compute_alerts(rows)
    analytics = compute_analytics(rows)
    return {"trees": rows, "stats": stats, "alerts": alerts, "analytics": analytics}


@app.get("/api/trees/{tree_id}")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_tree_detail(request: Request, tree_id: str, user: dict = Depends(require_auth)):
    """Get a single tree. Used by NFC app after scanning."""
    tree = get_tree_by_id(tree_id)
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return {"tree": db_row_to_dashboard(tree)}


@app.get("/api/nfc/{nfc_uid}")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_nfc_lookup(request: Request, nfc_uid: str, user: dict = Depends(require_auth)):
    """Look up a tree by NFC card UID."""
    tree = get_tree_by_nfc(nfc_uid)
    if not tree:
        raise HTTPException(status_code=404, detail="NFC card not linked to any tree")
    return {"tree": db_row_to_dashboard(tree)}


@app.post("/api/nfc/link")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_nfc_link(request: Request, user: dict = Depends(require_auth)):
    """Link an NFC card to a tree."""
    body = await request.json()
    nfc_uid = body.get("nfc_uid")
    tree_id = body.get("tree_id")
    if not nfc_uid or not tree_id:
        raise HTTPException(status_code=400, detail="nfc_uid and tree_id required")
    result = link_nfc_to_tree(nfc_uid, tree_id, assigned_by=user["username"])
    return {"ok": True, "data": result}


@app.post("/api/sync")
@limiter.limit(lambda: get_settings().rate_limit_sync)
async def api_trigger_sync(request: Request, user: dict = Depends(require_auth)):
    """Manually trigger an ER → Supabase sync cycle."""
    _require_admin_dashboard_user(user)
    log.info(
        "Manual sync triggered by '%s'",
        user["username"],
        extra={
            "event": "sync_manual_triggered",
            "path": "/api/sync",
            "username": user["username"],
            "request_id": get_request_id(),
        },
    )
    result = run_sync_cycle()
    log.info(
        "Manual sync completed for '%s'",
        user["username"],
        extra={
            "event": "sync_manual_completed",
            "path": "/api/sync",
            "username": user["username"],
            "request_id": get_request_id(),
            "ok": result.get("ok"),
            "error": result.get("error"),
            "incident_ok": (result.get("incidents") or {}).get("ok"),
        },
    )
    return result


@app.get("/api/admin/retention/runs")
@limiter.limit(lambda: get_settings().rate_limit_api)
async def api_list_retention_runs(
    request: Request,
    status: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    user: dict = Depends(require_auth),
):
    """List retention run records for operator troubleshooting."""
    _require_admin_dashboard_user(user)

    status_filter = (status or "").strip().lower() or None
    try:
        items = list_retention_runs(status=status_filter, limit=limit)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "items": items,
        "request_id": get_request_id(),
    }


@app.post("/api/admin/retention/run")
@limiter.limit(lambda: get_settings().rate_limit_sync)
async def api_run_retention(
    request: Request,
    payload: RetentionRunRequest,
    user: dict = Depends(require_auth),
):
    """Manually execute retention run for ranger stats data lifecycle controls."""
    _require_admin_dashboard_user(user)

    request_id = get_request_id()
    correlation_id = f"retention-manual-{request_id}"
    run_result = await run_in_threadpool(
        execute_ranger_stats_retention,
        trigger="manual",
        request_id=request_id,
        correlation_id=correlation_id,
        dry_run=payload.dry_run,
    )

    response_payload = {
        "ok": run_result.get("status") == "succeeded",
        "run": run_result,
        "request_id": request_id,
    }
    return response_payload


@app.post("/api/admin/retention/runs/{run_id}/replay")
@limiter.limit(lambda: get_settings().rate_limit_sync)
async def api_replay_retention_run(
    request: Request,
    run_id: str,
    payload: RetentionReplayRequest,
    user: dict = Depends(require_auth),
):
    """Replay a failed retention run and preserve replay lineage."""
    _require_admin_dashboard_user(user)

    request_id = get_request_id()
    correlation_id = f"retention-replay-{request_id}"

    try:
        replay_result = await run_in_threadpool(
            replay_retention_run,
            run_id,
            request_id=request_id,
            correlation_id=correlation_id,
            dry_run=payload.dry_run,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    response_payload = {
        "ok": replay_result.get("status") == "succeeded",
        "run": replay_result,
        "request_id": request_id,
    }
    return response_payload


# ─────────────────────────────────────────────────────────────
# HEALTH
# ─────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    s = get_settings()
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": s.app_version,
    }


# ─────────────────────────────────────────────────────────────
# ROUTES — User management (admin only)
# ─────────────────────────────────────────────────────────────

@app.get("/api/users")
async def api_list_users(request: Request, user: dict = Depends(require_auth)):
    """List all users (admin only). Passwords are excluded."""
    if user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
    users = _load_users()
    serialized_users: list[dict] = []
    for uname, udata in users.items():
        role = str(udata.get("role") or "ranger").strip().lower() or "ranger"
        if role == "viewer":
            role = "ranger"

        serialized_users.append(
            {
                "username": uname,
                "role": role,
                "display_name": udata.get("display_name", uname),
            }
        )

    return {
        "users": serialized_users
    }


@app.post("/api/users")
async def api_create_user(request: Request, user: dict = Depends(require_auth)):
    """Create a new user account (admin only)."""
    if user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
    body = await request.json()

    raw_username = body.get("username", "")
    raw_password = body.get("password", "")
    username = raw_username.strip().lower() if isinstance(raw_username, str) else ""
    password = raw_password if isinstance(raw_password, str) else ""
    display_name_raw = body.get("display_name", "")
    display_name = display_name_raw.strip() if isinstance(display_name_raw, str) else ""
    raw_role = body.get("role", "ranger")
    role_input = raw_role.strip().lower() if isinstance(raw_role, str) else ""
    if role_input == "viewer":
        role_input = "ranger"

    if not username or not password:
        raise HTTPException(status_code=400, detail="username and password required")
    if len(username) < 3:
        raise HTTPException(status_code=400, detail="Username must be at least 3 characters")
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    # Admin provisioning in this endpoint is intentionally restricted to field roles.
    if role_input not in ("leader", "ranger"):
        raise HTTPException(status_code=400, detail="Role must be 'leader' or 'ranger'")

    users = _load_users()
    if username in users:
        raise HTTPException(status_code=409, detail="User already exists")

    user_record: dict[str, str] = {
        "password": _hash_pw(password),
        "role": role_input,
        "display_name": display_name or username,
    }

    for optional_field in ("region", "position", "phone"):
        raw_value = body.get(optional_field)
        if raw_value is None:
            continue
        normalized = str(raw_value).strip()
        if normalized:
            user_record[optional_field] = normalized

    users[username] = user_record
    _save_users(users)
    log.info("User '%s' created by '%s'", username, user["username"])
    return {"ok": True, "username": username}


@app.delete("/api/users/{username}")
async def api_delete_user(request: Request, username: str, user: dict = Depends(require_auth)):
    """Delete a user (admin only). Cannot delete yourself."""
    username = username.strip().lower()
    if user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin only")

    requester_username = str(user.get("username") or "").strip().lower()
    if username == requester_username:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")

    users = _load_users()
    if username not in users:
        raise HTTPException(status_code=404, detail="User not found")
    del users[username]
    _save_users(users)
    # Remove active sessions for deleted user
    to_remove = [t for t, s in sessions.items() if str(s.get("username") or "").strip().lower() == username]
    for t in to_remove:
        del sessions[t]

    refresh_to_remove = [
        t
        for t, s in mobile_refresh_sessions.items()
        if str(s.get("username") or "").strip().lower() == username
    ]
    for t in refresh_to_remove:
        del mobile_refresh_sessions[t]

    access_to_remove = [
        t
        for t, s in mobile_access_sessions.items()
        if str(s.get("username") or "").strip().lower() == username
    ]
    for t in access_to_remove:
        del mobile_access_sessions[t]

    log.info("User '%s' deleted by '%s'", username, user["username"])
    return {"ok": True}
