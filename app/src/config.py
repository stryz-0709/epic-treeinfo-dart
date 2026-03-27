"""
Application settings — single source of truth for all configuration.

Loads from environment variables (or .env file). No secrets in code.
"""

import os
from pathlib import Path
from functools import lru_cache
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    """All configuration loaded from env vars / .env file."""

    model_config = SettingsConfigDict(
        env_file=os.getenv("ENV_FILE", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # ── Project paths ────────────────────────────────────────
    base_dir: Path = Field(default_factory=lambda: Path(__file__).resolve().parent.parent)

    # ── EarthRanger ──────────────────────────────────────────
    earthranger_domain: str = "epictech.pamdas.org"
    earthranger_token: str = ""

    @property
    def earthranger_base_url(self) -> str:
        return f"https://{self.earthranger_domain}/api/v1.0"

    @property
    def earthranger_headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.earthranger_token}",
            "Accept": "application/json",
        }

    # ── Supabase ─────────────────────────────────────────────
    supabase_url: str = ""
    supabase_key: str = ""

    # ── Dashboard auth ───────────────────────────────────────
    session_secret: str = "change-me"
    default_admin_password: str = "admin123"

    # ── Mobile auth ──────────────────────────────────────────
    mobile_access_token_ttl_minutes: int = 15
    mobile_refresh_token_ttl_days: int = 7

    # ── Mobile API performance guardrails ───────────────────
    mobile_work_management_max_page_size: int = 366
    mobile_incidents_max_page_size: int = 200
    mobile_schedules_max_page_size: int = 500
    mobile_query_max_window_days: int = 366
    mobile_updated_since_max_age_days: int = 3650
    mobile_slow_request_warn_ms: int = 1200
    # Legacy alias kept for compatibility with existing observability tests.
    request_slow_threshold_ms: float | None = None

    # ── Runtime environment ──────────────────────────────────
    environment: str = "development"

    _allowed_environments: set[str] = {
        "dev",
        "development",
        "staging",
        "test",
        "prod",
        "production",
    }

    _weak_session_secret_values: set[str] = {
        "",
        "change-me",
        "changeme",
        "default",
        "secret",
        "password",
        "admin123",
    }

    # ── Zalo ─────────────────────────────────────────────────
    zalo_enabled: bool = True
    zalo_group_id: str = ""
    zalo_app_id: str = ""
    zalo_secret_key: str = ""
    zalo_sheet_url: str = ""
    zalo_sheet_tab: str = "APIKeys"
    zalo_get_oa_url: str = "https://openapi.zalo.me/v2.0/oa/getoa"
    zalo_refresh_url: str = "https://oauth.zaloapp.com/v4/oa/access_token"
    zalo_service_account_file: str = "service-account.json"

    # ── Sync pipeline ────────────────────────────────────────
    sync_interval_minutes: int = 60
    sync_max_retries: int = 3
    sync_retry_delay_sec: int = 30

    # ── Retention & compliance operations ───────────────────
    retention_enabled: bool = True
    retention_schedule_timezone: str = "Asia/Ho_Chi_Minh"
    retention_schedule_hour_local: int = 1
    retention_schedule_minute_local: int = 30
    retention_min_days: int = 183
    retention_source_table: str = "daily_checkins"
    retention_source_day_field: str = "day_key"
    retention_audit_table: str = "retention_job_runs"
    retention_audit_memory_limit: int = 500

    # ── Alert filtering ──────────────────────────────────────
    alert_event_types: list[str] = Field(default_factory=list)
    alert_event_categories: list[str] = Field(default_factory=lambda: ["security"])
    alert_states: list[str] = Field(default_factory=lambda: ["new", "active"])
    alert_min_priority: int = 0
    alert_lookback_hours: int = 1

    # ── Server ───────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "info"
    log_json: bool = True  # False for colorized dev output

    # ── CORS (for NFC app / external clients) ────────────────
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])
    cors_allow_credentials: bool = True

    # ── Rate limiting ────────────────────────────────────────
    rate_limit_login: str = "5/minute"     # max login attempts
    rate_limit_api: str = "60/minute"      # general API calls
    rate_limit_sync: str = "2/minute"      # manual sync trigger

    # ── Version ──────────────────────────────────────────────
    app_version: str = "2.1.0"

    @property
    def normalized_environment(self) -> str:
        """Return normalized environment token for policy checks."""
        return self.environment.strip().lower()

    @property
    def is_production(self) -> bool:
        """Return True when running in production mode."""
        return self.normalized_environment in {"prod", "production"}

    def _has_wildcard_cors_origin(self) -> bool:
        """Return True if CORS origins include wildcard."""
        return any(origin.strip() == "*" for origin in self.cors_origins)

    @property
    def effective_slow_request_warn_ms(self) -> float:
        """Return effective slow-request warning threshold in milliseconds."""
        if self.request_slow_threshold_ms is not None:
            return float(self.request_slow_threshold_ms)
        return float(self.mobile_slow_request_warn_ms)

    def validate_security_baseline(self) -> None:
        """Validate production-only security guardrails.

        In production:
        - wildcard CORS origins are forbidden
        - session secret must not use default placeholder
        """
        if self.normalized_environment not in self._allowed_environments:
            raise ValueError(
                "Invalid ENVIRONMENT configuration: expected one of "
                f"{sorted(self._allowed_environments)}."
            )

        if not (0 <= self.retention_schedule_hour_local <= 23):
            raise ValueError(
                "Invalid retention schedule configuration: RETENTION_SCHEDULE_HOUR_LOCAL "
                "must be between 0 and 23."
            )

        if not (0 <= self.retention_schedule_minute_local <= 59):
            raise ValueError(
                "Invalid retention schedule configuration: RETENTION_SCHEDULE_MINUTE_LOCAL "
                "must be between 0 and 59."
            )

        if not (1 <= self.retention_audit_memory_limit <= 10_000):
            raise ValueError(
                "Invalid retention audit configuration: RETENTION_AUDIT_MEMORY_LIMIT "
                "must be between 1 and 10000."
            )

        if not (1 <= self.mobile_work_management_max_page_size <= 10_000):
            raise ValueError(
                "Invalid mobile API pagination configuration: "
                "MOBILE_WORK_MANAGEMENT_MAX_PAGE_SIZE must be between 1 and 10000."
            )

        if not (1 <= self.mobile_incidents_max_page_size <= 10_000):
            raise ValueError(
                "Invalid mobile API pagination configuration: "
                "MOBILE_INCIDENTS_MAX_PAGE_SIZE must be between 1 and 10000."
            )

        if not (1 <= self.mobile_schedules_max_page_size <= 10_000):
            raise ValueError(
                "Invalid mobile API pagination configuration: "
                "MOBILE_SCHEDULES_MAX_PAGE_SIZE must be between 1 and 10000."
            )

        if not (1 <= self.mobile_query_max_window_days <= 36500):
            raise ValueError(
                "Invalid mobile API query window configuration: "
                "MOBILE_QUERY_MAX_WINDOW_DAYS must be between 1 and 36500."
            )

        if not (1 <= self.mobile_updated_since_max_age_days <= 36500):
            raise ValueError(
                "Invalid mobile API incremental lookback configuration: "
                "MOBILE_UPDATED_SINCE_MAX_AGE_DAYS must be between 1 and 36500."
            )

        if self.mobile_slow_request_warn_ms < 0:
            raise ValueError(
                "Invalid mobile API observability configuration: "
                "MOBILE_SLOW_REQUEST_WARN_MS must be >= 0."
            )

        if self.request_slow_threshold_ms is not None and self.request_slow_threshold_ms <= 0:
            raise ValueError(
                "Invalid observability configuration: REQUEST_SLOW_THRESHOLD_MS must be > 0 "
                "when provided."
            )

        timezone_name = self.retention_schedule_timezone.strip() or "Asia/Ho_Chi_Minh"
        try:
            ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError(
                "Invalid retention schedule configuration: RETENTION_SCHEDULE_TIMEZONE "
                f"'{timezone_name}' is not a recognized IANA timezone."
            ) from exc

        if not self.is_production:
            return

        if self._has_wildcard_cors_origin():
            raise ValueError(
                "Invalid production CORS configuration: wildcard origin '*' is not allowed."
            )

        session_secret = self.session_secret.strip()
        if (
            session_secret.lower() in self._weak_session_secret_values
            or len(session_secret) < 32
        ):
            raise ValueError(
                "Invalid production session configuration: SESSION_SECRET must be at "
                "least 32 characters and not a default/weak value."
            )


@lru_cache
def get_settings() -> Settings:
    """Return cached settings singleton."""
    return Settings()
