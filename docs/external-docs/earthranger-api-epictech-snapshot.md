# EarthRanger API Snapshot (EpicTech Interactive Docs)

> Seed source: https://epictech.pamdas.org/api/v1.0/docs/interactive/  
> Supplemental source: https://support.earthranger.com/en_US/step-17-integrations-api-data-exports/earthranger-api  
> Capture date: 2026-03-25

## What was captured

- Interactive API index exposing EarthRanger API groups and endpoints
- Server status endpoint payload example
- Auth/token guidance from support docs
- Event, subject, observation, patrol, subject-group, and track API usage patterns
- v2 event-type management examples

## High-Level API Areas Seen in Interactive Docs

The interactive docs list broad endpoint groups including:

- Activity
- Analyzers
- Choices
- Core
- Mapping
- Observations
- Reports
- Sensors
- Accounts
- Schemas

Also seen:

- `/api/v1.0/docs/interactive/`
- `/api/v1.0/status/`

## Status Endpoint Snapshot

From `GET /api/v1.0/status/`:

- Example version: `release-2.134.1-1440`
- Flags in response included toggles like `event_search_enabled`, `alerts_enabled`, `patrol_enabled`, `events_enabled`, `subjects_enabled`, `analyzers_enabled`
- Environment/site info included timezone and tenant/site identifiers

## Authentication Notes (support article cross-reference)

- API requests require `Authorization: Bearer <token>`
- Token acquisition routes described:
  - Admin portal (long-lived token)
  - Support team request
- Example docs references from the support article include interactive and index docs on `sandbox.pamdas.org` and `er-client` on GitHub.

## Captured Endpoint Usage Patterns

### Events

- `GET /api/v1.0/activity/events/` with filtering, sorting, pagination
- `GET /api/v1.0/activity/event/{id}/`
- `POST /api/v1.0/activity/events/`
- `PATCH /api/v1.0/activity/event/{id}/`

Typical query/filter dimensions seen:

- `state`, `event_type`, `event_ids`, `event_category`
- `bbox`, `since`, `until`, `updated_since`
- `sort_by`, `page`, `page_size`
- include flags (`include_updates`, `include_notes`, `include_files`, `include_related_events`)

### Event Types (v2 examples in support API article)

- `GET /api/v2.0/activity/eventtypes/`
- `GET /api/v2.0/activity/eventtypes/{eventtype_value}/?include_schema=true`
- `POST /api/v2.0/activity/eventtypes/`
- `PATCH /api/v2.0/activity/eventtypes/{eventtype_value}/`
- `DELETE /api/v2.0/activity/eventtypes/{eventtype_value}/`

### Subjects

- `GET /api/v1.0/subjects/`
- `GET /api/v1.0/subject/{id}/`
- `POST /api/v1.0/subjects/`

### Observations

- `GET /api/v1.0/observations/`
- `POST /api/v1.0/observations/`

Observed behavior note: posting observations can auto-create source/subject when unknown source-provider/manufacturer combo appears.

### Subject Groups

- `GET /api/v1.0/subjectgroups/`
- `GET /api/v1.0/subjectgroup/{id}/subjects/`

### Patrols

- `GET /api/v1.0/activity/patrols/`
- `GET /api/v1.0/activity/patrol/{id}/`

### Subject Tracks

- `GET /api/v1.0/subject/{subject_id}/tracks/`

## Common API Conventions Seen

- Datetime format: ISO8601 with timezone
- Pagination pattern: `count`, `next`, `previous`, `results`
- Bounding box format: `west,south,east,north`
- Standard HTTP status/error semantics (`400`, `401`, `403`, `404`, `500`)

## Important linked resources discovered

- `https://github.com/PADAS/er-client`
- `https://github.com/PADAS/er-client/tree/main/docs/examples`
- `https://sandbox.pamdas.org/api/v1.0/docs/interactive/`
- `https://sandbox.pamdas.org/api/v1.0/docs/index.html`

## Capture limitations

- `https://epictech.pamdas.org/api/v1.0/api-schema/` could not be parsed by automated extraction.
- Interactive endpoint list is very large; this file captures representative structure and common operations rather than every route verbatim.

## URL Inventory (captured)

- https://epictech.pamdas.org/api/v1.0/docs/interactive/
- https://epictech.pamdas.org/api/v1.0/status/
- https://support.earthranger.com/en_US/step-17-integrations-api-data-exports/earthranger-api
- https://epictech.pamdas.org/api/v1.0/api-schema/ (parse failed)
