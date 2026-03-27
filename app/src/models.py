"""
Shared data models and transformation helpers.

Single definition of how ER events map to Supabase rows / dashboard rows.
No more duplicated `build_rows()`.
"""

from datetime import datetime, timezone


# ─────────────────────────────────────────────────────────────
# ER event → Supabase row
# ─────────────────────────────────────────────────────────────

def event_to_db_row(ev: dict) -> dict:
    """Convert an EarthRanger tree_rep event to a Supabase `trees` table row."""
    loc = ev.get("location") or {}
    d = ev.get("event_details") or {}

    # tree_status can be a list ["good"] or a string
    raw_status = d.get("tree_status", [])
    if isinstance(raw_status, list):
        status = ", ".join(raw_status)
    else:
        status = str(raw_status)

    # Extract creator/updater from updates array if available
    updates = ev.get("updates", []) or []
    creator = ""
    updater = ""
    if updates:
        first = updates[-1] if updates else {}  # oldest
        last = updates[0] if updates else {}  # newest
        creator = (first.get("user", {}) or {}).get("username", "")
        updater = (last.get("user", {}) or {}).get("username", "")

    return {
        "event_id": ev.get("id", ""),
        "sn": str(ev.get("serial_number", "")),
        "tree_id": d.get("tree_id", ""),
        "tree_type": d.get("tree_type", ""),
        "age_years": d.get("tree_age"),
        "height_m": d.get("tree_height"),
        "diameter_cm": d.get("tree_diameter"),
        "foliage_m": d.get("tree_foliage"),
        "status": status,
        "latitude": loc.get("latitude"),
        "longitude": loc.get("longitude"),
        "event_state": ev.get("state", ""),
        "created_at": ev.get("time", ""),
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "creator": creator,
        "updater": updater,
        "last_reported": ev.get("updated_at", ""),
    }


def dedupe_events_by_tree_id(events: list[dict]) -> list[dict]:
    """Keep only the latest event per tree_id."""
    best: dict[str, dict] = {}
    for ev in events:
        tid = (ev.get("event_details") or {}).get("tree_id", "")
        if not tid:
            continue
        if tid not in best or ev.get("time", "") > best[tid].get("time", ""):
            best[tid] = ev
    return list(best.values())


def _to_utc_iso(value: str | None) -> str | None:
    """Normalize ISO datetime text to UTC ISO format; return None if invalid."""
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
    return parsed.astimezone(timezone.utc).isoformat()


def _extract_incident_ranger_id(ev: dict, details: dict) -> str | None:
    """Resolve ranger identity from an EarthRanger event using precedence fallbacks."""
    if not isinstance(ev, dict):
        return None

    if not isinstance(details, dict):
        details = {}

    candidates = (
        details.get("ranger_id"),
        details.get("ranger"),
        details.get("ranger_username"),
        details.get("ranger_user"),
        details.get("reported_by"),
        details.get("owner"),
        details.get("owner_id"),
        details.get("user_id"),
        details.get("subject_id"),
        ev.get("reported_by"),
        ev.get("owner"),
        ev.get("owner_id"),
        ev.get("user_id"),
    )

    for candidate in candidates:
        value = str(candidate or "").strip()
        if value:
            return value

    updates = ev.get("updates") or []
    if not isinstance(updates, list):
        updates = []

    for update in updates:
        if not isinstance(update, dict):
            continue

        user_obj = update.get("user")
        if not isinstance(user_obj, dict):
            continue

        value = str(user_obj.get("username") or "").strip()
        if value:
            return value

    return None


def event_to_incident_row(ev: dict) -> dict | None:
    """Convert an EarthRanger incident-style event to `incidents_mirror` row shape."""
    if not isinstance(ev, dict):
        return None

    event_id = str(ev.get("id") or "").strip()
    if not event_id:
        return None

    details_raw = ev.get("event_details")
    details = details_raw if isinstance(details_raw, dict) else {}

    updated_at = _to_utc_iso(
        str(ev.get("updated_at") or ev.get("time") or ev.get("created_at") or "")
    )
    if updated_at is None:
        return None

    occurred_at = _to_utc_iso(str(ev.get("time") or ev.get("created_at") or ""))
    occurred_at = occurred_at or updated_at

    ranger_id = _extract_incident_ranger_id(ev, details)
    mapping_status = "mapped" if ranger_id else "unmapped"

    incident_id = str(ev.get("serial_number") or event_id)
    title = str(details.get("title") or ev.get("title") or ev.get("event_type") or "Incident")
    status = str(ev.get("state") or details.get("status") or "open")
    severity = str(details.get("severity") or details.get("priority") or ev.get("priority") or "unknown")

    return {
        "er_event_id": event_id,
        "incident_id": incident_id,
        "ranger_id": ranger_id,
        "mapped_ranger_id": ranger_id,
        "mapping_status": mapping_status,
        "occurred_at": occurred_at,
        "updated_at": updated_at,
        "title": title,
        "status": status,
        "severity": severity,
        "payload_ref": f"er-event:{event_id}",
    }


# ─────────────────────────────────────────────────────────────
# Supabase row → dashboard-friendly dict
# ─────────────────────────────────────────────────────────────

STATUS_LABELS = {"good": "Tốt", "not_good": "Cần xử lý", "die": "Chết"}


def normalize_status(raw: str) -> str:
    """Normalize status string to one of: good, not_good, die."""
    s = (raw or "").strip().lower()
    if "good" in s and "not" not in s:
        return "good"
    if "not" in s or "xấu" in s or "cần" in s:
        return "not_good"
    if "die" in s or "chết" in s:
        return "die"
    return s or "good"


def db_row_to_dashboard(r: dict) -> dict:
    """Convert a Supabase `trees` row to a dashboard-friendly dict."""
    images = []
    img_field = r.get("image_urls") or ""
    if img_field:
        images = [u.strip() for u in img_field.split(",") if u.strip()]

    return {
        "tree_id": r.get("tree_id", ""),
        "species": r.get("tree_type", ""),
        "age": r.get("age_years") or 0,
        "height": r.get("height_m") or "",
        "diameter": r.get("diameter_cm") or "",
        "canopy": r.get("foliage_m") or "",
        "status": normalize_status(r.get("status", "")),
        "lat": r.get("latitude") or 0,
        "lng": r.get("longitude") or 0,
        "images": images,
        "created_at": r.get("created_at") or "",
        "created_by": r.get("creator") or "",
        "updated_at": r.get("last_reported") or "",
        "updated_by": r.get("updater") or "",
        "sn": r.get("sn") or "",
        "event_id": r.get("event_id") or "",
        "event_state": r.get("event_state") or "",
        "synced_at": r.get("synced_at") or "",
    }


def compute_stats(rows: list[dict]) -> dict:
    """Compute dashboard statistics from a list of dashboard rows."""
    total = len(rows)
    species = list(set(r["species"] for r in rows if r["species"]))
    good = sum(1 for r in rows if r["status"] == "good")
    not_good = sum(1 for r in rows if r["status"] == "not_good")
    die = sum(1 for r in rows if r["status"] == "die")
    ages = [r["age"] for r in rows if r["age"]]
    avg_age = round(sum(ages) / len(ages), 1) if ages else 0
    good_pct = round(good / total * 100) if total else 0

    return {
        "total": total,
        "species_count": len(species),
        "species_list": sorted(species),
        "good": good,
        "good_pct": good_pct,
        "not_good": not_good,
        "die": die,
        "avg_age": avg_age,
    }


def compute_alerts(rows: list[dict]) -> list[dict]:
    """Generate prioritized alert items from tree data."""
    alerts = []
    for r in rows:
        if r["status"] == "die":
            alerts.append({
                "tree_id": r["tree_id"],
                "species": r["species"],
                "status": r["status"],
                "priority": "critical",
                "message": f"Cây {r['tree_id']} ({r['species']}) đã chết — cần xử lý/thay thế",
                "lat": r["lat"],
                "lng": r["lng"],
            })
        elif r["status"] == "not_good":
            alerts.append({
                "tree_id": r["tree_id"],
                "species": r["species"],
                "status": r["status"],
                "priority": "warning",
                "message": f"Cây {r['tree_id']} ({r['species']}) sức khỏe kém — cần kiểm tra",
                "lat": r["lat"],
                "lng": r["lng"],
            })
    alerts.sort(key=lambda a: (0 if a["priority"] == "critical" else 1, a["tree_id"]))
    return alerts


def compute_analytics(rows: list[dict]) -> dict:
    """Compute advanced analytics for tree manager."""
    from collections import defaultdict

    heights = [float(r["height"]) for r in rows if r["height"]]
    diameters = [float(r["diameter"]) for r in rows if r["diameter"]]
    canopies = [float(r["canopy"]) for r in rows if r["canopy"]]

    # Species health breakdown
    species_health = defaultdict(lambda: {"good": 0, "not_good": 0, "die": 0, "total": 0})
    for r in rows:
        sp = r["species"] or "Unknown"
        species_health[sp][r["status"]] = species_health[sp].get(r["status"], 0) + 1
        species_health[sp]["total"] += 1

    # Height distribution buckets
    height_buckets = defaultdict(int)
    for h in heights:
        bucket = f"{int(h)}-{int(h)+1}m"
        height_buckets[bucket] += 1

    # Diameter distribution buckets
    diameter_buckets = defaultdict(int)
    for d in diameters:
        bucket_start = int(d // 10) * 10
        bucket = f"{bucket_start}-{bucket_start+10}cm"
        diameter_buckets[bucket] += 1

    # Recent activity (trees updated in last 30 days)
    now = datetime.now(timezone.utc)
    recent = []
    for r in rows:
        if r["updated_at"]:
            try:
                updated = datetime.fromisoformat(r["updated_at"].replace("Z", "+00:00"))
                if (now - updated).days <= 30:
                    recent.append({
                        "tree_id": r["tree_id"],
                        "species": r["species"],
                        "status": r["status"],
                        "updated_at": r["updated_at"],
                        "updated_by": r["updated_by"],
                        "days_ago": (now - updated).days,
                    })
            except (ValueError, TypeError):
                pass
    recent.sort(key=lambda x: x.get("updated_at", ""), reverse=True)

    return {
        "height": {
            "min": round(min(heights), 1) if heights else 0,
            "max": round(max(heights), 1) if heights else 0,
            "avg": round(sum(heights) / len(heights), 1) if heights else 0,
            "distribution": dict(sorted(height_buckets.items())),
        },
        "diameter": {
            "min": round(min(diameters), 1) if diameters else 0,
            "max": round(max(diameters), 1) if diameters else 0,
            "avg": round(sum(diameters) / len(diameters), 1) if diameters else 0,
            "distribution": dict(sorted(diameter_buckets.items())),
        },
        "canopy": {
            "min": round(min(canopies), 1) if canopies else 0,
            "max": round(max(canopies), 1) if canopies else 0,
            "avg": round(sum(canopies) / len(canopies), 1) if canopies else 0,
            "total_coverage": round(sum(canopies), 1) if canopies else 0,
        },
        "species_health": dict(species_health),
        "recent_activity": recent[:20],
    }
