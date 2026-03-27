# Patrol + Events Dashboard Context (Targeted Fetch)

> Purpose: provide **only** the patrol/event_type/event_details information needed for this project’s Phase 1 mobile dashboard scope.
> 
> Scope alignment: `_bmad-output/project-context.md` rules for read-only incident consumption, role-scoped backend APIs, bounded pagination, and incremental sync.
> 
> Capture date: 2026-03-25

## What this project needs (minimal set)

For a patrol/events dashboard in this repo, the must-have data contracts are:

1. **Events/Incidents feed (read-only)** with incremental sync fields (`updated_since`, cursor/pagination, role scope).
2. **Event type catalog + schema** to interpret/validate `event_details` payload shape.
3. **Patrol list/detail** for operational context (segments, linked events, activity timeline).
4. **Patrol type + tracked-by catalogs** for stable labels/metadata and leader identity semantics.

## Key API semantics to keep straight

### Event vs event_type vs event_details

From EarthRanger Input Reports docs:

- `event` = shared/common report envelope.
- `event_type` = schema definition for that report type.
- `event_details` = report-specific JSON payload that must match the chosen event type schema.

References:
- https://sandbox.pamdas.org/api/v1.0/docs/api/activity.html
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/api/activity.rst.txt

### Event create/list details relevant to dashboards

From EarthRanger support API guide:

- List events: `GET /api/v1.0/activity/events/` supports filters (`state`, `event_type`, `since`, `until`, `updated_since`, bbox, includes, pagination).
- Single event: `GET /api/v1.0/activity/event/{id}/`.
- Create event requires at minimum: `event_type`, `time`, `location`.
- `event_details` is optional structurally but when present its keys/values must match event type schema.

Reference:
- https://support.earthranger.com/en_US/step-17-integrations-api-data-exports/earthranger-api

## Event type schema sync strategy (important)

## V1 (`/api/v1.0/activity/events/eventtypes`)

Recommended for offline/minimal checks:

- Use one list call as source of truth:
  - `GET /api/v1.0/activity/events/eventtypes?include_schema=true`
- Use `ETag` + `If-None-Match` for change detection.
- `updated_since` helps incremental sync, but choice-list updates may not bump `updated_at`; ETag remains the safer change detector.
- Per-type schema endpoint exists but has no ETag:
  - `GET /api/v1.0/activity/events/schema/eventtype/<eventtype_value>`
- General schema endpoint (`reported_by` use-cases) has ETag:
  - `GET /api/v1.0/activity/events/schema?format=json`

Reference:
- https://sandbox.pamdas.org/api/v1.0/docs/topics/eventtype-sync.html
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/topics/eventtype-sync.md.txt

## V2 (`/api/v2.0/activity/eventtypes`)

- List/detail support conditional GET via ETag, but **ETags are metadata-only** (do not fully cover rendered choice-list expansion changes).
- `include_schema=true` on list/detail returns **raw** schema.
- Rendered schema (choices expanded) requires:
  - `GET /api/v2.0/activity/eventtypes/schemas?pre_render=true` (no ETag)
  - `GET /api/v2.0/activity/eventtypes/<value>/schema?pre_render=true` (no ETag)
- If your UI correctness depends on rendered choice lists, do periodic forced refresh even when list ETag says 304.

Reference:
- https://sandbox.pamdas.org/api/v1.0/docs/topics/eventtype-sync.html
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/topics/eventtype-sync.md.txt

## Patrol sync strategy (important)

From Patrol Sync guidance:

- Conditional GET is supported for:
  - Patrol types list/detail (`/api/v1.0/activity/patrols/types` ...)
  - Tracked-by schema (`/api/v1.0/activity/patrols/trackedby`)
- Conditional GET is **not** supported for patrol instances/segments list/detail.
- For patrol instances, minimize transfer via:
  - `filter` with `date_range.lower/upper`
  - pagination
  - saved last sync window
- Web parity note: web UI currently supports one segment per patrol (API may allow multiple).

Reference:
- https://sandbox.pamdas.org/api/v1.0/docs/topics/patrol-sync.html
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/topics/patrol-sync.md.txt

## Dashboard field set (practical minimum)

### Event/incident list row

Minimum fields:

- `incident_id` / `er_event_id`
- `title`
- `status` (`new/active/resolved` mapped to app labels)
- `severity`/`priority`
- `occurred_at`
- `updated_at`
- `ranger_id` (for role scope)
- optional `event_type`, `event_category`, location summary

### Event detail panel

Minimum sections:

- Identity + timing (`event_type`, serial/id, time, updated_at)
- `event_details` (rendered against schema)
- activity metadata (notes/files/related events as needed)
- map/location block

### Patrol list row

Minimum fields:

- `patrol_id`
- `title`
- `patrol_type` (display/icon from patrol type catalog)
- `state`
- `start_time`, `end_time`
- summary counts (`segments`, `events`)

### Patrol detail panel

Minimum sections:

- core patrol metadata (`objective`, `state`, timing)
- segment timeline (`scheduled_*`, `time_range`, leader)
- linked events timeline
- notes/files summary

## Mapping to this repository’s current backend contracts

### Existing mobile incident API shape (already in place)

`app/src/server.py` defines `GET /api/mobile/incidents` with:

- role scope (`leader` team-capable, `ranger` own scope)
- filters: `from`, `to`, `updated_since`, optional `ranger_id`
- pagination: `page/page_size` or `cursor`
- sync metadata: `sync.cursor`, `sync.has_more`, `sync.last_synced_at`

### Incident row normalization in this repo

`app/src/models.py` `event_to_incident_row(...)` maps ER events to mirror rows containing:

- `er_event_id`, `incident_id`, `ranger_id`, `mapping_status`
- `occurred_at`, `updated_at`
- `title`, `status`, `severity`, `payload_ref`

### Incremental cursor behavior already implemented

`app/src/sync.py` `run_incident_sync_cycle(...)`:

- calls ER events with `updated_since`
- applies small overlap window for safety
- deduplicates by `er_event_id`
- advances persisted cursor using best watermark (`updated_at`/source updated time)

### ER client capabilities already present

`app/src/earthranger.py` currently includes:

- events list/detail/create/update
- event type listing + slug→UUID resolution
- patrol list fetch

This is sufficient for Phase 1 read-only dashboard consumption without adding direct mobile→ER calls.

## UX references from EarthRanger Web docs (for dashboard parity)

- Event feed preview focuses on type icon, name/title, created time, event time, priority, jump-to-location.
- Event detail structure emphasizes: Event Details, Activity, History.
- Patrol detail emphasizes: state, objective, schedule/timing, tracks, and activity timeline containing events/notes/attachments.

References:
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/reports-incidents
- https://support.earthranger.com/en_US/step-5-tracking-devices-subjects-patrols/patrols-feed-web

## Recommended implementation posture for this project (now)

1. Keep mobile app consuming only backend endpoints (`/api/mobile/*`), not ER directly.
2. Keep incidents read-only in app (Phase 1 scope guardrail).
3. Use backend cursor + `updated_since` as primary incremental mechanism.
4. Cache event type/patrol type catalogs server-side with ETag-aware refresh where supported.
5. For any schema-driven event_details rendering, clearly separate:
   - fast path: raw schema cache
   - correctness path: periodic rendered-schema refresh (especially v2 choice-list sensitivity)

## Known gaps / auth-gated pieces

Some schema endpoints may return `401 Unauthorized` without proper tenant auth/session context. When that happens:

- rely on documented sync/topic guidance for contract decisions,
- and capture tenant-authenticated samples later in a secure environment.

## Source index (focused)

- https://support.earthranger.com/en_US/step-17-integrations-api-data-exports/earthranger-api
- https://support.earthranger.com/en_US/step-6-events-incidents-basics/reports-incidents
- https://support.earthranger.com/en_US/step-5-tracking-devices-subjects-patrols/patrols-feed-web
- https://sandbox.pamdas.org/api/v1.0/docs/topics/eventtype-sync.html
- https://sandbox.pamdas.org/api/v1.0/docs/topics/patrol-sync.html
- https://sandbox.pamdas.org/api/v1.0/docs/topics/api_primer.html
- https://sandbox.pamdas.org/api/v1.0/docs/api/activity.html
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/topics/eventtype-sync.md.txt
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/topics/patrol-sync.md.txt
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/topics/api_primer.md.txt
- https://sandbox.pamdas.org/api/v1.0/docs/_sources/api/activity.rst.txt
- Local alignment: `_bmad-output/project-context.md`, `app/src/server.py`, `app/src/models.py`, `app/src/earthranger.py`, `app/src/sync.py`
