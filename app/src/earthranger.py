"""
EarthRanger API client — single implementation for all ER interactions.

Handles:
  - Event CRUD (create, read, update, list)
  - File attachments & notes
  - Event type resolution (v1 + v2)
  - Patrols
  - Pagination
"""

import logging
from typing import Any
from datetime import datetime, timezone

import requests

from src.config import get_settings

log = logging.getLogger(__name__)


class EarthRangerClient:
    """Unified EarthRanger REST client."""

    def __init__(self, domain: str | None = None, token: str | None = None):
        s = get_settings()
        self.domain = domain or s.earthranger_domain
        self.token = token or s.earthranger_token
        self.base = f"https://{self.domain}/api/v1.0"
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json",
        }
        self._uuid_cache: dict[str, str] = {}

    # ── low-level helpers ────────────────────────────────────

    def _get(self, path: str, params: dict | None = None, **kw) -> dict:
        url = f"{self.base}{path}" if path.startswith("/") else path
        resp = requests.get(url, headers=self.headers, params=params, timeout=30, **kw)
        resp.raise_for_status()
        return resp.json()

    def _post(self, path: str, json_data: dict | None = None, **kw) -> dict:
        url = f"{self.base}{path}"
        resp = requests.post(url, headers=self.headers, json=json_data, timeout=30, **kw)
        resp.raise_for_status()
        return resp.json()

    def _patch(self, path: str, json_data: dict | None = None, **kw) -> dict:
        url = f"{self.base}{path}"
        resp = requests.patch(url, headers=self.headers, json=json_data, timeout=30, **kw)
        resp.raise_for_status()
        return resp.json()

    def _delete(self, path: str, **kw) -> requests.Response:
        url = f"{self.base}{path}"
        resp = requests.delete(url, headers=self.headers, timeout=30, **kw)
        resp.raise_for_status()
        return resp

    # ── event types ──────────────────────────────────────────

    def list_event_types(self, version: str = "v2.0") -> list[dict]:
        """List all event types. Tries v2 first, falls back to v1."""
        url = f"https://{self.domain}/api/{version}/activity/eventtypes/"
        try:
            resp = requests.get(url, headers=self.headers, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            results = data if isinstance(data, list) else data.get("data", data.get("results", []))
            for t in results:
                if t.get("value") and t.get("id"):
                    self._uuid_cache[t["value"]] = t["id"]
            return results
        except Exception as e:
            log.warning("Failed to list %s event types: %s", version, e)
            return []

    def resolve_event_type_uuid(self, slug: str) -> str | None:
        """Resolve event type slug (e.g. 'tree_rep') to UUID."""
        if slug in self._uuid_cache:
            return self._uuid_cache[slug]
        # Load all types to populate cache
        for ver in ("v2.0", "v1.0"):
            self.list_event_types(ver)
            if slug in self._uuid_cache:
                return self._uuid_cache[slug]
        return None

    # ── events ───────────────────────────────────────────────

    def get_events(
        self,
        event_type: str | None = None,
        state: str | list[str] | None = None,
        page_size: int = 100,
        updated_since: datetime | None = None,
        **extra_params,
    ) -> list[dict]:
        """
        Fetch events with server-side filtering + pagination.

        Args:
            event_type: slug like 'tree_rep' (server-side filter if UUID resolved)
            state: 'new', 'active', 'resolved', or list of these
            page_size: results per page
            updated_since: ISO datetime filter
            **extra_params: additional query params
        """
        params: dict[str, Any] = {"page_size": page_size, **extra_params}

        if event_type:
            uuid = self.resolve_event_type_uuid(event_type)
            if uuid:
                params["event_type"] = uuid

        if state:
            if isinstance(state, list):
                params["state"] = ",".join(state)
            else:
                params["state"] = state

        if updated_since:
            params["updated_since"] = updated_since.isoformat()

        url: str | None = f"{self.base}/activity/events/"
        events: list[dict] = []

        while url:
            data = self._get(url, params=params)
            results_wrapper = data.get("data", data)
            results = results_wrapper.get("results", [])

            if event_type and "event_type" not in params:
                # Fallback: client-side filter when UUID not resolved
                results = [e for e in results if e.get("event_type") == event_type]

            events.extend(results)
            url = results_wrapper.get("next")
            params = {}  # next URL includes query params

        return events

    def get_event(self, event_id: str) -> dict:
        """Get a single event by ID."""
        data = self._get(f"/activity/event/{event_id}/")
        return data.get("data", data)

    def create_event(self, payload: dict) -> dict:
        """Create a new event/report."""
        data = self._post("/activity/events/", json_data=payload)
        return data.get("data", data)

    def update_event(self, event_id: str, payload: dict) -> dict:
        """Partially update an event."""
        data = self._patch(f"/activity/event/{event_id}/", json_data=payload)
        return data.get("data", data)

    # ── files ────────────────────────────────────────────────

    def get_event_files(self, event_id: str) -> list[dict]:
        data = self._get(f"/activity/event/{event_id}/files/")
        return data.get("data", data) if isinstance(data, dict) else data

    def upload_event_file(self, event_id: str, filepath: str, comment: str = "") -> dict:
        """Upload a file attachment to an event."""
        url = f"{self.base}/activity/event/{event_id}/files/"
        with open(filepath, "rb") as f:
            resp = requests.post(
                url,
                headers={"Authorization": f"Bearer {self.token}"},
                files={"filecontent.file": f},
                data={"comment": comment} if comment else {},
                timeout=60,
            )
        resp.raise_for_status()
        return resp.json()

    # ── notes ────────────────────────────────────────────────

    def get_event_notes(self, event_id: str) -> list[dict]:
        data = self._get(f"/activity/event/{event_id}/notes/")
        return data.get("data", data) if isinstance(data, dict) else data

    def add_event_note(self, event_id: str, text: str) -> dict:
        return self._post(f"/activity/event/{event_id}/notes/", json_data={"text": text})

    def update_event_note(self, event_id: str, note_id: str, text: str) -> dict:
        return self._patch(
            f"/activity/event/{event_id}/note/{note_id}/",
            json_data={"text": text},
        )

    def delete_event_note(self, event_id: str, note_id: str):
        return self._delete(f"/activity/event/{event_id}/note/{note_id}/")

    # ── relationships ────────────────────────────────────────

    def get_event_relationships(self, event_id: str) -> list[dict]:
        data = self._get(f"/activity/event/{event_id}/relationships/")
        return data.get("data", data) if isinstance(data, dict) else data

    def add_event_relationship(self, from_id: str, to_id: str, rel_type: str = "contains") -> dict:
        return self._post(
            f"/activity/event/{from_id}/relationships/{rel_type}/",
            json_data={"to_event_id": to_id},
        )

    # ── patrols ──────────────────────────────────────────────

    def get_patrols(self, **params) -> list[dict]:
        data = self._get("/activity/patrols/", params=params)
        results = data.get("data", data)
        return results.get("results", results) if isinstance(results, dict) else results

    # ── user info ────────────────────────────────────────────

    def get_me(self) -> dict:
        return self._get("/user/me/")

    # ── sources & subjects (for NFC integration) ─────────────

    def get_sources(self, **params) -> list[dict]:
        data = self._get("/sources/", params=params)
        results = data.get("data", data)
        return results.get("results", results) if isinstance(results, dict) else results

    def get_subjects(self, **params) -> list[dict]:
        data = self._get("/subjects/", params=params)
        results = data.get("data", data)
        return results.get("results", results) if isinstance(results, dict) else results


# ── Module-level convenience instance ────────────────────────

_client: EarthRangerClient | None = None


def get_er_client() -> EarthRangerClient:
    """Return a lazily-initialized singleton client."""
    global _client
    if _client is None:
        _client = EarthRangerClient()
    return _client
