"""Get all tree_rep events from EarthRanger and display in a table."""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.er_utils import er

EVENT_TYPE = "tree_rep"


def get_events():
    return er.fetch_events(EVENT_TYPE)


def _user_display(user: dict) -> str:
    """Return 'First Last' or username from an updates[*].user dict."""
    if not user:
        return ""
    full = f"{user.get('first_name', '')} {user.get('last_name', '')}".strip()
    return full or user.get("username", "")


def print_table(events):
    """Print events as a formatted table."""
    rows = []
    for ev in events:
        loc, d = ev.get("location") or {}, ev.get("event_details") or {}
        status = ", ".join(d.get("tree_status", []))

        updates = ev.get("updates") or []
        # updates is newest-first; last entry is the creation record
        created_entry = next((u for u in reversed(updates) if u.get("type") == "add_event"), updates[-1] if updates else {})
        updated_entry = updates[0] if updates else {}
        created_by = _user_display(created_entry.get("user") or {})
        updated_by = _user_display(updated_entry.get("user") or {})

        rows.append([
            str(ev.get("serial_number", "")), d.get("tree_id", ""), d.get("tree_type", ""),
            str(d.get("tree_age", "")), d.get("tree_height", ""), d.get("tree_diameter", ""),
            d.get("tree_foliage", ""), status,
            str(loc.get("latitude", "")), str(loc.get("longitude", "")),
            ev.get("state", ""), ev.get("time", ""),
            created_by, updated_by,
        ])

    headers = ["SN", "Tree ID", "Loài Cây", "Tuổi", "Chiều cao", "Đường kính thân",
               "Độ rộng tán lá", "Tình trạng", "Latitude", "Longitude", "Trạng thái", "Time",
               "Created By", "Updated By"]
    widths = [max(len(h), *(len(str(r[i])) for r in rows)) for i, h in enumerate(headers)]
    fmt = " | ".join(f"{{:<{w}}}" for w in widths)
    sep = "-+-".join("-" * w for w in widths)

    print(fmt.format(*headers))
    print(sep)
    for r in rows:
        print(fmt.format(*r))


if __name__ == "__main__":
    events = get_events()
    print(f"Found {len(events)} '{EVENT_TYPE}' event(s)\n")
    if events:
        print_table(events)
