"""Create an Event on EarthRanger via API."""

import os, sys, json, requests
from datetime import datetime, timezone

# ── CONFIG ──
DOMAIN = os.getenv("EARTHRANGER_DOMAIN", "epictech.pamdas.org")
TOKEN  = os.getenv("EARTHRANGER_TOKEN",  "Ct2JUbBzt0XB45jBSVkHgSvAYRECKRdt18DrXd6z")

BASE    = f"https://{DOMAIN}/api/v1.0"
HEADERS = {"Authorization": f"Bearer {TOKEN}", "Accept": "application/json", "Content-Type": "application/json"}


def create_event(event_type, title=None, priority=0, state="active",
                 lat=None, lon=None, event_time=None, event_details=None, notes=None):
    """POST a new event. Returns the created event dict."""
    payload = {
        "event_type": event_type,
        "priority": priority,
        "state": state,
        "time": (event_time or datetime.now(timezone.utc)).isoformat(),
    }
    if title:
        payload["title"] = title
    if lat is not None and lon is not None:
        payload["location"] = {"latitude": lat, "longitude": lon}
    if event_details:
        payload["event_details"] = event_details

    resp = requests.post(f"{BASE}/activity/events/", headers=HEADERS, json=payload, timeout=30)
    if not resp.ok:
        print(f"✗ Error {resp.status_code}: {resp.text}")
        resp.raise_for_status()

    event = resp.json().get("data", resp.json())

    if notes:
        for n in notes:
            requests.post(f"{BASE}/activity/event/{event['id']}/notes/",
                          headers=HEADERS, json={"text": n}, timeout=30)

    return event


# ── MAIN ──
if __name__ == "__main__":
    result = create_event(
        event_type="wildlife_sighting_rep",
        title="Python API Test – Wildlife Sighting",
        priority=200,
        state="active",
        lat=10.781045,
        lon=106.695180,
        notes=["Created via Python API script"],
    )

    print("✓ Event created!")
    print(f"  ID:       {result['id']}")
    print(f"  Serial:   {result['serial_number']}")
    print(f"  Title:    {result['title']}")
    print(f"  Time:     {result['time']}")
    print(f"  Location: {result['location']}")
    print(f"  URL:      https://{DOMAIN}/events/{result['id']}")

    sys.exit(1)
