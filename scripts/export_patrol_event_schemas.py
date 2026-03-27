from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "_bmad-output" / "planning-artifacts" / "research"
DATE_TAG = datetime.now(timezone.utc).strftime("%Y-%m-%d")

JSON_OUT = OUTPUT_DIR / f"patrol-events-schema-snapshot-{DATE_TAG}.json"
JSON_LATEST = OUTPUT_DIR / "patrol-events-schema-snapshot-latest.json"
MD_OUT = OUTPUT_DIR / f"patrol-events-schema-catalog-{DATE_TAG}.md"
MD_LATEST = OUTPUT_DIR / "patrol-events-schema-catalog-latest.md"


def read_env_file(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def read_create_event_defaults(path: Path) -> tuple[str | None, str | None]:
    if not path.exists():
        return None, None

    txt = path.read_text(encoding="utf-8", errors="ignore")
    dm = re.search(r'DOMAIN\s*=\s*os\.getenv\([^\)]*,\s*"([^"]+)"\)', txt)
    tm = re.search(r'TOKEN\s*=\s*os\.getenv\([^\)]*,\s*"([^"]+)"\)', txt)
    domain = dm.group(1) if dm else None
    token = tm.group(1) if tm else None
    return domain, token


def resolve_credentials() -> tuple[str, str]:
    env_file = read_env_file(ROOT / ".env")

    domain = (os.getenv("EARTHRANGER_DOMAIN") or env_file.get("EARTHRANGER_DOMAIN") or "").strip()
    token = (os.getenv("EARTHRANGER_TOKEN") or env_file.get("EARTHRANGER_TOKEN") or "").strip()

    if not domain or domain.startswith("__REPLACE") or not token or token.startswith("__REPLACE"):
        fallback_domain, fallback_token = read_create_event_defaults(ROOT / "scripts" / "create_event.py")
        if (not domain or domain.startswith("__REPLACE")) and fallback_domain:
            domain = fallback_domain
        if (not token or token.startswith("__REPLACE")) and fallback_token:
            token = fallback_token

    if not domain:
        domain = "epictech.pamdas.org"

    if not token:
        raise RuntimeError("No usable EarthRanger token found in env/.env.")

    return domain, token


def unwrap_data(payload: Any) -> Any:
    if isinstance(payload, dict) and "data" in payload:
        return payload.get("data")
    return payload


def extract_results(payload: Any) -> list[Any]:
    cur = unwrap_data(payload)
    if isinstance(cur, dict) and "results" in cur:
        cur = cur.get("results")
    if isinstance(cur, list):
        return cur
    return []


def extract_next(payload: Any) -> str | None:
    cur = unwrap_data(payload)
    if isinstance(cur, dict):
        next_url = cur.get("next")
        if isinstance(next_url, str) and next_url.strip():
            return next_url.strip()
    return None


def get_json(url: str, headers: dict[str, str], params: dict[str, Any] | None = None) -> Any:
    resp = requests.get(url, headers=headers, params=params, timeout=60)
    resp.raise_for_status()
    return resp.json()


def fetch_paginated(url: str, headers: dict[str, str], params: dict[str, Any] | None = None) -> list[Any]:
    results: list[Any] = []
    next_url: str | None = url
    next_params = dict(params or {})

    while next_url:
        payload = get_json(next_url, headers, next_params)
        results.extend(extract_results(payload))
        next_url = extract_next(payload)
        next_params = {}

    return results


def parse_schema(raw_schema: Any) -> dict[str, Any] | None:
    if isinstance(raw_schema, dict):
        return raw_schema
    if isinstance(raw_schema, str):
        try:
            parsed = json.loads(raw_schema)
            return parsed if isinstance(parsed, dict) else None
        except Exception:
            return None
    return None


def _extract_brace_block(source: str, open_brace_index: int) -> str:
    depth = 0
    in_str = False
    esc = False

    for idx in range(open_brace_index, len(source)):
        ch = source[idx]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue

        if ch == '"':
            in_str = True
            continue
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return source[open_brace_index : idx + 1]
    return ""


def _extract_top_level_object_keys(obj_block: str) -> list[str]:
    keys: list[str] = []
    depth = 0
    i = 0
    n = len(obj_block)
    in_str = False
    esc = False

    while i < n:
        ch = obj_block[i]

        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue

        if ch == '"':
            i += 1
            key_chars: list[str] = []
            esc2 = False
            while i < n:
                c2 = obj_block[i]
                if esc2:
                    key_chars.append(c2)
                    esc2 = False
                elif c2 == "\\":
                    esc2 = True
                elif c2 == '"':
                    break
                else:
                    key_chars.append(c2)
                i += 1

            key = "".join(key_chars)
            i += 1

            if depth == 1:
                j = i
                while j < n and obj_block[j].isspace():
                    j += 1
                if j < n and obj_block[j] == ':':
                    keys.append(key)
            continue

        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1

        i += 1

    return sorted(list(dict.fromkeys(keys)))


def extract_fields_from_raw_schema_string(raw_schema: str) -> tuple[list[str], list[str]]:
    if not raw_schema:
        return [], []

    schema_match = re.search(r'"schema"\s*:\s*\{', raw_schema)
    if schema_match:
        schema_open = raw_schema.find('{', schema_match.start())
        schema_block = _extract_brace_block(raw_schema, schema_open) if schema_open >= 0 else ""
        if schema_block:
            prop_match = re.search(r'"properties"\s*:\s*\{', schema_block)
            fields: list[str] = []
            if prop_match:
                prop_open = schema_block.find('{', prop_match.start())
                prop_block = _extract_brace_block(schema_block, prop_open) if prop_open >= 0 else ""
                fields = _extract_top_level_object_keys(prop_block) if prop_block else []

            req_match = re.search(r'"required"\s*:\s*\[(.*?)\]', schema_block, re.DOTALL)
            required: list[str] = []
            if req_match:
                required = sorted(re.findall(r'"([^"]+)"', req_match.group(1)))

            return fields, required

    json_match = re.search(r'"json"\s*:\s*\{', raw_schema)
    if json_match:
        json_open = raw_schema.find('{', json_match.start())
        json_block = _extract_brace_block(raw_schema, json_open) if json_open >= 0 else ""
        if json_block:
            prop_match = re.search(r'"properties"\s*:\s*\{', json_block)
            fields = []
            if prop_match:
                prop_open = json_block.find('{', prop_match.start())
                prop_block = _extract_brace_block(json_block, prop_open) if prop_open >= 0 else ""
                fields = _extract_top_level_object_keys(prop_block) if prop_block else []

            req_match = re.search(r'"required"\s*:\s*\[(.*?)\]', json_block, re.DOTALL)
            required = []
            if req_match:
                required = sorted(re.findall(r'"([^"]+)"', req_match.group(1)))

            return fields, required

    return [], []


def extract_schema_fields(raw_schema: Any) -> tuple[list[str], list[str], str]:
    parsed = parse_schema(raw_schema)

    if isinstance(parsed, dict):
        if isinstance(parsed.get("schema"), dict):
            schema_obj = parsed["schema"]
            props = schema_obj.get("properties") if isinstance(schema_obj.get("properties"), dict) else {}
            req = schema_obj.get("required") if isinstance(schema_obj.get("required"), list) else []
            return sorted(list(props.keys())), sorted(list(req)), "v1-schema"

        if isinstance(parsed.get("json"), dict):
            schema_obj = parsed["json"]
            props = schema_obj.get("properties") if isinstance(schema_obj.get("properties"), dict) else {}
            req = schema_obj.get("required") if isinstance(schema_obj.get("required"), list) else []
            return sorted(list(props.keys())), sorted(list(req)), "v2-json"

        props = parsed.get("properties") if isinstance(parsed.get("properties"), dict) else {}
        req = parsed.get("required") if isinstance(parsed.get("required"), list) else []
        if props:
            return sorted(list(props.keys())), sorted(list(req)), "direct-json-schema"

    if isinstance(raw_schema, str):
        fields, required = extract_fields_from_raw_schema_string(raw_schema)
        if fields:
            return fields, required, "raw-string-fallback"

    return [], [], "unknown"


def summarize_patrol_fields(patrols: list[Any]) -> dict[str, Any]:
    patrol_field_set: set[str] = set()
    segment_field_set: set[str] = set()
    tr_field_set: set[str] = set()
    leader_field_set: set[str] = set()
    start_field_set: set[str] = set()
    end_field_set: set[str] = set()

    for p in patrols:
        if not isinstance(p, dict):
            continue

        patrol_field_set.update(p.keys())

        segs = p.get("patrol_segments")
        if not isinstance(segs, list):
            continue

        for seg in segs:
            if not isinstance(seg, dict):
                continue

            segment_field_set.update(seg.keys())

            tr = seg.get("time_range")
            if isinstance(tr, dict):
                tr_field_set.update(tr.keys())

            leader = seg.get("leader")
            if isinstance(leader, dict):
                leader_field_set.update(leader.keys())

            sl = seg.get("start_location")
            if isinstance(sl, dict):
                start_field_set.update(sl.keys())

            el = seg.get("end_location")
            if isinstance(el, dict):
                end_field_set.update(el.keys())

    return {
        "patrol_fields": sorted(patrol_field_set),
        "segment_fields": sorted(segment_field_set),
        "segment_time_range_fields": sorted(tr_field_set),
        "segment_leader_fields": sorted(leader_field_set),
        "segment_start_location_fields": sorted(start_field_set),
        "segment_end_location_fields": sorted(end_field_set),
    }


def render_markdown(snapshot: dict[str, Any]) -> str:
    generated_at = snapshot.get("generated_at", "")
    domain = snapshot.get("source", {}).get("domain", "")

    lines: list[str] = []
    lines.append("# Patrol + Events Schema Snapshot")
    lines.append("")
    lines.append(f"- Generated at (UTC): `{generated_at}`")
    lines.append(f"- EarthRanger domain: `{domain}`")
    lines.append("")

    errors = snapshot.get("errors", [])
    lines.append("## Fetch status")
    lines.append("")
    if errors:
        lines.append("- ⚠️ Some fetch warnings/errors occurred:")
        for e in errors:
            lines.append(f"  - `{e}`")
    else:
        lines.append("- ✅ All configured schema fetches completed successfully.")
    lines.append("")

    ev = snapshot.get("event_types", {})
    v1_count = ev.get("v1", {}).get("count", 0)
    v2_count = ev.get("v2", {}).get("count", 0)
    lines.append("## Event type coverage")
    lines.append("")
    lines.append(f"- v1 event types: **{v1_count}**")
    lines.append(f"- v2 event types: **{v2_count}**")
    lines.append("")

    lines.append("## Event schema field catalog")
    lines.append("")
    lines.append("| Event Type | Version | Fields | Required | Parser |")
    lines.append("|---|---:|---:|---:|---|")

    for row in snapshot.get("event_schema_catalog", []):
        lines.append(
            f"| `{row.get('event_type','')}` | `{row.get('version','')}` | {row.get('field_count',0)} | {len(row.get('required_fields',[]))} | `{row.get('parser_mode','')}` |"
        )

    lines.append("")
    lines.append("## Patrol schema coverage")
    lines.append("")
    patrol = snapshot.get("patrol", {})
    lines.append(f"- Patrol types count: **{patrol.get('patrol_types',{}).get('count',0)}**")
    lines.append(f"- Patrol samples used for field inventory: **{patrol.get('instances',{}).get('sample_size',0)}**")
    lines.append("")

    inv = patrol.get("instances", {}).get("field_inventory", {})
    lines.append("### Patrol field inventory")
    lines.append("")
    for k in [
        "patrol_fields",
        "segment_fields",
        "segment_time_range_fields",
        "segment_leader_fields",
        "segment_start_location_fields",
        "segment_end_location_fields",
    ]:
        values = inv.get(k, [])
        lines.append(f"- **{k}** ({len(values)}): {', '.join(f'`{v}`' for v in values)}")

    lines.append("")
    lines.append("## Stored artifact files")
    lines.append("")
    lines.append("- `patrol-events-schema-snapshot-<date>.json` (full raw + normalized schema snapshot)")
    lines.append("- `patrol-events-schema-snapshot-latest.json` (rolling latest)")
    lines.append("- `patrol-events-schema-catalog-<date>.md` (human-readable summary)")
    lines.append("- `patrol-events-schema-catalog-latest.md` (rolling latest)")

    return "\n".join(lines) + "\n"


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    domain, token = resolve_credentials()
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    errors: list[str] = []

    snapshot: dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": {
            "domain": domain,
            "api_versions": ["v1.0", "v2.0"],
        },
        "event_types": {},
        "event_schema_catalog": [],
        "patrol": {},
        "errors": errors,
    }

    # Event types (v1/v2)
    for label, url in [
        ("v1", f"https://{domain}/api/v1.0/activity/events/eventtypes/"),
        ("v2", f"https://{domain}/api/v2.0/activity/eventtypes/"),
    ]:
        try:
            items = fetch_paginated(url, headers, params={"include_schema": "true", "page_size": 500})
        except Exception as exc:
            errors.append(f"eventtypes-{label}:EXC:{exc.__class__.__name__}")
            items = []

        normalized_items: list[dict[str, Any]] = []
        for item in items:
            if not isinstance(item, dict):
                continue

            schema_raw = item.get("schema")
            fields, required, mode = extract_schema_fields(schema_raw)

            normalized_items.append(
                {
                    **item,
                    "_schema_field_count": len(fields),
                    "_schema_fields": fields,
                    "_schema_required_fields": required,
                    "_schema_parser_mode": mode,
                }
            )

            event_type_value = str(item.get("value") or item.get("slug") or item.get("id") or "").strip()
            snapshot["event_schema_catalog"].append(
                {
                    "event_type": event_type_value,
                    "version": label,
                    "field_count": len(fields),
                    "fields": fields,
                    "required_fields": required,
                    "parser_mode": mode,
                }
            )

        normalized_items.sort(key=lambda x: str(x.get("value") or x.get("slug") or x.get("id") or ""))
        snapshot["event_types"][label] = {
            "count": len(normalized_items),
            "items": normalized_items,
        }

    snapshot["event_schema_catalog"].sort(key=lambda x: (x.get("version", ""), x.get("event_type", "")))

    # Patrol types
    try:
        patrol_types = fetch_paginated(
            f"https://{domain}/api/v1.0/activity/patrols/types/",
            headers,
            params={"page_size": 500},
        )
        patrol_types = [p for p in patrol_types if isinstance(p, dict)]
    except Exception as exc:
        errors.append(f"patrol-types:EXC:{exc.__class__.__name__}")
        patrol_types = []

    snapshot["patrol"]["patrol_types"] = {
        "count": len(patrol_types),
        "items": sorted(patrol_types, key=lambda x: str(x.get("value") or x.get("id") or "")),
    }

    # Patrol tracked-by schema
    try:
        trackedby = get_json(f"https://{domain}/api/v1.0/activity/patrols/trackedby/", headers)
    except Exception as exc:
        errors.append(f"patrol-trackedby:EXC:{exc.__class__.__name__}")
        trackedby = None

    snapshot["patrol"]["trackedby"] = trackedby

    # Patrol instances field inventory (sample-based)
    try:
        patrol_instances = extract_results(
            get_json(
                f"https://{domain}/api/v1.0/activity/patrols/",
                headers,
                params={"page_size": 200},
            )
        )
    except Exception as exc:
        errors.append(f"patrol-instances:EXC:{exc.__class__.__name__}")
        patrol_instances = []

    patrol_instances = [p for p in patrol_instances if isinstance(p, dict)]
    inventory = summarize_patrol_fields(patrol_instances)

    snapshot["patrol"]["instances"] = {
        "sample_size": len(patrol_instances),
        "field_inventory": inventory,
        "sample": patrol_instances,
    }

    # Persist files
    JSON_OUT.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")
    JSON_LATEST.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")

    md = render_markdown(snapshot)
    MD_OUT.write_text(md, encoding="utf-8")
    MD_LATEST.write_text(md, encoding="utf-8")

    print("Saved:")
    print(f"- {JSON_OUT}")
    print(f"- {JSON_LATEST}")
    print(f"- {MD_OUT}")
    print(f"- {MD_LATEST}")
    print(f"Event types: v1={snapshot.get('event_types',{}).get('v1',{}).get('count',0)}, v2={snapshot.get('event_types',{}).get('v2',{}).get('count',0)}")
    print(f"Patrol types: {snapshot.get('patrol',{}).get('patrol_types',{}).get('count',0)}")
    print(f"Patrol sample size: {snapshot.get('patrol',{}).get('instances',{}).get('sample_size',0)}")
    print(f"Errors: {len(errors)}")


if __name__ == "__main__":
    main()
