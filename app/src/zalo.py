"""
Zalo notification service — single module for all Zalo interactions.

Handles:
  - Token management (fetch from Google Sheet, validate, refresh)
  - Sending messages to Zalo group
  - Alert formatting (Vietnamese)
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import gspread
import requests
from google.oauth2.service_account import Credentials

from src.config import get_settings

log = logging.getLogger(__name__)


class ZaloTokenError(Exception):
    """Raised when Zalo token operations fail."""
    pass


# ─────────────────────────────────────────────────────────────
# TOKEN MANAGEMENT
# ─────────────────────────────────────────────────────────────

class ZaloTokenManager:
    """Manages Zalo OA access tokens via Google Sheet storage."""

    def __init__(self):
        s = get_settings()
        self.sheet_url = s.zalo_sheet_url
        self.sheet_tab = s.zalo_sheet_tab
        self.get_oa_url = s.zalo_get_oa_url
        self.refresh_url = s.zalo_refresh_url
        self.app_id = s.zalo_app_id
        self.secret_key = s.zalo_secret_key
        self.service_account_file = s.zalo_service_account_file
        # Resolve service account path relative to project root
        self._sa_path = str(s.base_dir / self.service_account_file)
        self._cached_token: str | None = None

    def _get_sheet_client(self):
        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ]
        creds = Credentials.from_service_account_file(self._sa_path, scopes=scopes)
        return gspread.authorize(creds)

    def _fetch_from_sheet(self) -> tuple[str, str, str, str]:
        """Fetch tokens + credentials from Google Sheet row 2."""
        if not self.sheet_url:
            raise ZaloTokenError("ZALO_SHEET_URL not configured")

        try:
            client = self._get_sheet_client()
            sheet_id = self.sheet_url.split("/d/")[1].split("/")[0]
            ws = client.open_by_key(sheet_id).worksheet(self.sheet_tab)
            row = ws.row_values(2)
            if not row or len(row) < 5:
                raise ZaloTokenError("Sheet row 2 missing expected columns")
            access_token = row[0]
            refresh_token = row[1]
            app_id = row[3] if len(row) > 3 and row[3] else self.app_id
            secret_key = row[4] if len(row) > 4 and row[4] else self.secret_key
            return access_token, refresh_token, app_id, secret_key
        except gspread.exceptions.SpreadsheetNotFound:
            raise ZaloTokenError("Spreadsheet not found — check URL and permissions")
        except gspread.exceptions.WorksheetNotFound:
            raise ZaloTokenError(f"Worksheet '{self.sheet_tab}' not found")
        except ZaloTokenError:
            raise
        except Exception as e:
            raise ZaloTokenError(f"Failed to fetch tokens from sheet: {e}") from e

    def _check_token(self, access_token: str) -> bool:
        """Validate access token against Zalo OA API."""
        try:
            resp = requests.get(
                self.get_oa_url,
                headers={"access_token": access_token},
                timeout=30,
            )
            return resp.ok and resp.json().get("error", -1) == 0
        except Exception:
            return False

    def _refresh_token(self, app_id: str, secret_key: str, refresh_token: str) -> tuple[str, str]:
        """Refresh the access token, returning (new_access, new_refresh)."""
        resp = requests.post(
            self.refresh_url,
            headers={
                "secret_key": secret_key,
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={
                "refresh_token": refresh_token,
                "app_id": app_id,
                "grant_type": "refresh_token",
            },
            timeout=30,
        )
        if not resp.ok:
            raise ZaloTokenError(f"Refresh HTTP {resp.status_code}: {resp.text}")
        data = resp.json()
        if not (data.get("access_token") and data.get("refresh_token")):
            raise ZaloTokenError(f"Refresh response missing tokens: {data}")
        return data["access_token"], data["refresh_token"]

    def _update_sheet(self, access_token: str, refresh_token: str):
        """Write refreshed tokens back to Google Sheet."""
        try:
            client = self._get_sheet_client()
            sheet_id = self.sheet_url.split("/d/")[1].split("/")[0]
            ws = client.open_by_key(sheet_id).worksheet(self.sheet_tab)
            ws.update_cell(2, 1, access_token)
            ws.update_cell(2, 2, refresh_token)
            ws.update_cell(2, 6, int(time.time()))
            log.info("Zalo tokens updated in Google Sheet")
        except Exception as e:
            log.error("Failed to update sheet with new tokens: %s", e)

    def get_access_token(self) -> str:
        """Get a valid Zalo access token (fetch → validate → refresh if needed)."""
        access_token, refresh_token, app_id, secret_key = self._fetch_from_sheet()

        if self._check_token(access_token):
            self._cached_token = access_token
            return access_token

        log.info("Zalo access token expired — refreshing…")
        new_access, new_refresh = self._refresh_token(app_id, secret_key, refresh_token)
        self._update_sheet(new_access, new_refresh)
        self._cached_token = new_access
        return new_access


# ─────────────────────────────────────────────────────────────
# ALERT FORMATTING
# ─────────────────────────────────────────────────────────────

def format_er_alert(event: dict) -> str:
    """Format an EarthRanger event into a Vietnamese alert message."""
    title = event.get("title", "Alert")
    event_type = event.get("event_type", "unknown")
    state = event.get("state", "unknown")

    # Time
    time_str = event.get("time", "")
    if time_str:
        try:
            dt = datetime.fromisoformat(time_str.replace("Z", "+00:00"))
            time_formatted = dt.strftime("%Y-%m-%d %H:%M")
        except Exception:
            time_formatted = time_str
    else:
        time_formatted = "N/A"

    # Location
    location = event.get("location", {}) or {}
    lat = location.get("latitude", "N/A")
    lon = location.get("longitude", "N/A")

    # Priority
    priority = event.get("priority", 0)
    if priority >= 300:
        priority_label = "🔴 Cao"
    elif priority >= 100:
        priority_label = "🟡 Trung bình"
    else:
        priority_label = "🟢 Thấp"

    # Details
    details = event.get("event_details", {}) or {}
    details_lines = [f"  • {k}: {v}" for k, v in details.items() if v]
    details_str = "\n" + "\n".join(details_lines[:5]) if details_lines else ""

    # Reporter
    reported_by = event.get("reported_by", {}) or {}
    reporter = reported_by.get("username", "N/A") if reported_by else "N/A"

    return (
        f"🚨 CẢNH BÁO EARTHRANGER\n\n"
        f"📍 {title}\n"
        f"📋 Loại: {event_type}\n"
        f"⚡ Trạng thái: {state.upper()}\n"
        f"🎯 Ưu tiên: {priority_label}\n"
        f"🕐 Thời gian: {time_formatted}\n"
        f"📌 Vị trí: {lat}, {lon}\n"
        f"👤 Báo cáo bởi: {reporter}{details_str}"
    )


def format_camera_alert(camera_id: int, object_class: str, direction: str | None = None,
                         image_url: str | None = None) -> str:
    """Format a camera detection alert."""
    labels = {
        "person": "Người", "car": "Ô tô", "motorbike": "Xe máy",
        "truck": "Xe tải", "cow": "Bò",
    }
    label = labels.get(object_class, object_class)
    dir_text = f" ({direction})" if direction else ""
    msg = (
        f"📹 PHÁT HIỆN TỪ CAMERA\n\n"
        f"📷 Camera: {camera_id}\n"
        f"🔍 Đối tượng: {label}{dir_text}\n"
        f"🕐 {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC"
    )
    if image_url:
        msg += f"\n🖼️ Ảnh: {image_url}"
    return msg


# ─────────────────────────────────────────────────────────────
# ALERT FILTER
# ─────────────────────────────────────────────────────────────

def should_notify(event: dict) -> bool:
    """Check if an event passes the alert filter rules."""
    s = get_settings()

    if event.get("priority", 0) < s.alert_min_priority:
        return False

    if s.alert_event_types:
        if event.get("event_type", "") not in s.alert_event_types:
            return False

    if s.alert_event_categories:
        cat = event.get("event_category", {})
        cat_val = cat.get("value", "") if isinstance(cat, dict) else ""
        if cat_val not in s.alert_event_categories:
            return False

    if s.alert_states:
        if event.get("state", "") not in s.alert_states:
            return False

    return True


# ─────────────────────────────────────────────────────────────
# SEND MESSAGE
# ─────────────────────────────────────────────────────────────

_token_manager: ZaloTokenManager | None = None


def _get_token_manager() -> ZaloTokenManager:
    global _token_manager
    if _token_manager is None:
        _token_manager = ZaloTokenManager()
    return _token_manager


def send_to_zalo_group(message: str) -> bool:
    """Send a text message to the configured Zalo group. Returns True on success."""
    s = get_settings()
    if not s.zalo_enabled:
        log.info("Zalo notifications disabled")
        return False

    group_id = s.zalo_group_id
    if not group_id:
        log.error("ZALO_GROUP_ID not configured")
        return False

    try:
        access_token = _get_token_manager().get_access_token()
        resp = requests.post(
            "https://openapi.zalo.me/v3.0/oa/group/message",
            headers={
                "access_token": access_token,
                "Content-Type": "application/json",
            },
            json={
                "recipient": {"group_id": group_id},
                "message": {"text": message},
            },
            timeout=10,
        )
        if resp.status_code == 200 and resp.json().get("error", -1) == 0:
            log.info("Message sent to Zalo group")
            return True
        log.error("Zalo API error: %s", resp.text)
        return False
    except ZaloTokenError as e:
        log.error("Zalo token error: %s", e)
        return False
    except Exception as e:
        log.error("Error sending to Zalo: %s", e)
        return False
