"""
Structured JSON logging — production-grade log output.

Features:
  - JSON format (parseable by DigitalOcean / Datadog / any log aggregator)
  - Request ID tracking (correlate all logs for one HTTP request)
  - Timestamp in ISO-8601 UTC
  - Clean uvicorn access log integration

Usage:
    from src.logging_config import setup_logging
    setup_logging()  # call once at startup
"""

from __future__ import annotations

import logging
import sys
import uuid
from contextvars import ContextVar
from datetime import datetime, timezone

# ── Request ID context ───────────────────────────────────────
# Set per-request, available to all log statements in that request.
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")


def get_request_id() -> str:
    return request_id_var.get()


# ── JSON Formatter ───────────────────────────────────────────

class JSONFormatter(logging.Formatter):
    """Outputs each log record as a single JSON line."""

    _RESERVED_LOG_RECORD_ATTRS = set(logging.LogRecord(
        name="",
        level=0,
        pathname="",
        lineno=0,
        msg="",
        args=(),
        exc_info=None,
    ).__dict__.keys()) | {"message", "asctime"}

    @classmethod
    def _to_json_safe(cls, value, *, _seen: set[int] | None = None, _depth: int = 0):
        """Recursively coerce values into JSON-serializable primitives."""
        if _seen is None:
            _seen = set()

        if _depth >= 16:
            return "<max-depth>"

        if isinstance(value, (str, int, float, bool)) or value is None:
            return value

        if isinstance(value, dict):
            marker = id(value)
            if marker in _seen:
                return "<cycle>"

            _seen.add(marker)
            try:
                return {
                    str(key): cls._to_json_safe(val, _seen=_seen, _depth=_depth + 1)
                    for key, val in value.items()
                }
            finally:
                _seen.discard(marker)

        if isinstance(value, (list, tuple, set)):
            marker = id(value)
            if marker in _seen:
                return "<cycle>"

            _seen.add(marker)
            try:
                return [
                    cls._to_json_safe(item, _seen=_seen, _depth=_depth + 1)
                    for item in value
                ]
            finally:
                _seen.discard(marker)

        return str(value)

    def format(self, record: logging.LogRecord) -> str:
        import json

        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": request_id_var.get("-"),
        }

        # Include exception info if present
        if record.exc_info and record.exc_info[0] is not None:
            log_entry["exception"] = self.formatException(record.exc_info)

        # Include all custom extra fields attached to the log record.
        for key, value in record.__dict__.items():
            if key in self._RESERVED_LOG_RECORD_ATTRS or key.startswith("_"):
                continue
            if key in log_entry:
                continue

            log_entry[key] = self._to_json_safe(value)

        return json.dumps(log_entry, ensure_ascii=False, default=str)


# ── Plain Formatter (for local dev) ─────────────────────────

class DevFormatter(logging.Formatter):
    """Human-readable format for local development."""

    COLORS = {
        "DEBUG": "\033[36m",     # cyan
        "INFO": "\033[32m",      # green
        "WARNING": "\033[33m",   # yellow
        "ERROR": "\033[31m",     # red
        "CRITICAL": "\033[35m",  # magenta
    }
    RESET = "\033[0m"

    def format(self, record: logging.LogRecord) -> str:
        color = self.COLORS.get(record.levelname, "")
        rid = request_id_var.get("-")
        rid_short = rid[:8] if rid != "-" else "-"
        ts = datetime.now().strftime("%H:%M:%S")
        return (
            f"{color}{ts} {record.levelname:<7}{self.RESET} "
            f"[{rid_short}] {record.name}: {record.getMessage()}"
        )


# ── Setup ────────────────────────────────────────────────────

def setup_logging(level: str = "INFO", json_output: bool = True) -> None:
    """
    Configure root logger for the application.

    Args:
        level: Log level (DEBUG, INFO, WARNING, ERROR)
        json_output: True for production JSON, False for colorized dev output
    """
    root = logging.getLogger()
    root.setLevel(getattr(logging, level.upper(), logging.INFO))

    # Remove any existing handlers
    root.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter() if json_output else DevFormatter())
    root.addHandler(handler)

    # Quiet noisy third-party loggers
    for noisy in ("urllib3", "httpcore", "httpx", "hpack", "supabase", "gotrue", "postgrest"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    # Uvicorn access logs — let our formatter handle them
    logging.getLogger("uvicorn.access").handlers.clear()
    logging.getLogger("uvicorn.access").propagate = True
    logging.getLogger("uvicorn.error").handlers.clear()
    logging.getLogger("uvicorn.error").propagate = True


def generate_request_id() -> str:
    """Generate a short unique request ID."""
    return uuid.uuid4().hex[:12]
