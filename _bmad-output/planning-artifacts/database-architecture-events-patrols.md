---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
inputDocuments:
  - _bmad-output/planning-artifacts/research/database-requirements-events-patrols.md
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/project-context.md
workflowType: "architecture"
project_name: "EarthRanger"
user_name: "Admin"
date: "2026-03-30"
status: "complete"
completedAt: "2026-03-30"
---

# Database Architecture Decision Document — Events & Patrols Analytics

## 1. Executive Summary

This document defines the **database architecture** for EarthRanger events/patrols analytics based on `database-requirements-events-patrols.md` (2026-03-30).

It establishes a durable, query-efficient, replay-safe model that:

- Persists full operational facts for events, patrols, segments, and track points
- Preserves raw payload snapshots for schema drift tolerance
- Enforces role scope at query layer (`admin`, `leader`, `ranger`)
- Supports incremental sync and monotonic cursors
- Enables daily/weekly analytics without historical re-ingest

This architecture is additive to the current codebase direction and keeps **`incidents_mirror`** + **`sync_cursors`** as canonical components.

## 2. Project Context Analysis

### Requirements Overview

Primary analytics outputs required for arbitrary time windows:

1. distance moved
2. event count
3. patrol time
4. event type/state distributions
5. role-scoped event/patrol listings
6. weekly productivity summaries

Key NFR drivers:

- Strong idempotency and replay safety
- Query performance with bounded windows/pagination
- Auditability (`request_id`, source timestamps, cursor state)
- Extensibility for ER schema variants (v1/v2 event type + patrol payload drift)
- Durability (no in-memory-only source of truth)

### Scale & Complexity Assessment

- **Primary domain:** Backend data platform for operational analytics
- **Complexity:** High (multi-source ingestion + role-scoped analytics + aggregates + retention)
- **Cross-cutting concerns:** identity normalization, cursor monotonicity, raw+normalized coexistence, geospatial distance quality, retention compliance

### Current-State Alignment

Current backend still has in-memory operational collections in `app/src/server.py` for mobile work/incident/check-in state. This architecture closes that gap by moving analytics facts and read paths to durable Postgres/Supabase tables.

## 3. Platform / Starter Evaluation (Database Track)

### Selected Foundation: Brownfield Supabase/Postgres Evolution

No re-scaffold is selected. This is an in-place architecture evolution on existing backend and Supabase patterns.

Rationale:

- Existing repository already uses Supabase/Postgres + `incidents_mirror` + `sync_cursors`
- Requirement asks for durable persistence, not framework replacement
- Fastest safe path is schema evolution + migration + read-path cutover

## 4. Core Architectural Decisions

### AD-DB-01 — Dual-Layer Persistence (Normalized + Raw)

Store both:

- **Normalized facts** for performant analytics
- **Raw payload snapshots** for schema drift, replay forensics, and future feature extraction

### AD-DB-02 — Canonical Existing Components Are Preserved

- Keep `incidents_mirror` as canonical event read/fact table (extend, not replace)
- Keep `sync_cursors` as canonical monotonic stream cursor registry

### AD-DB-03 — Identity and Scope Are Query-Layer Concerns

Role scope is enforced by backend query predicates/functions; UI filtering is non-authoritative.

### AD-DB-04 — UTC Storage + Project Day Boundary

- Persist all timestamps in UTC
- Convert UI range to UTC at query boundary
- Use `Asia/Ho_Chi_Minh` boundary for day-key aggregates

### AD-DB-05 — Incremental Ingestion with Strict Cursor Monotonicity

Per stream cursor value must never regress; idempotent upserts required for all ingest writes.

### AD-DB-06 — Geospatial Trackpoints Are First-Class Facts

Track points are mandatory persisted domain, not transient cache, to support distance analytics and future movement intelligence.

### AD-DB-07 — Aggregates Are Derived, Not Source of Truth

Daily aggregates accelerate dashboards; source of truth remains fact + raw layers.

## 5. Target Data Model (Table Model, Keys, Constraints)

## 5.1 Identity & Scope Domain

### `app_users` (existing; authoritative auth identity)

Required enhancement:

- add/rename to `team` (legacy `sub_region` renamed; required for leader-team scope enforcement in this module)

### `ranger_identity` (new)

Purpose: canonical operational identity dimension used by analytics joins.

Key columns:

- `ranger_id text primary key`
- `display_name text not null`
- `account_role text null`
- `effective_mobile_role text null`
- `region text null`
- `team text null`
- `source text not null default 'app_users'`
- `created_at timestamptz not null default timezone('utc', now())`
- `updated_at timestamptz not null default timezone('utc', now())`

Constraints:

- `check (ranger_id = lower(trim(ranger_id)))`

## 5.2 Raw Payload Domain

### `er_raw_payloads` (new)

Purpose: durable raw snapshots for all event/patrol/segment/trackpoint ingest payloads.

Key columns:

- `payload_id uuid primary key default gen_random_uuid()`
- `stream_name text not null` (`incidents`, `patrols`, `trackpoints`, ...)
- `entity_type text not null` (`event`, `patrol`, `segment`, `trackpoint`)
- `source_entity_id text not null`
- `source_updated_at timestamptz null`
- `cursor_value text null`
- `request_id text null`
- `schema_variant text null`
- `payload jsonb not null`
- `synced_at timestamptz not null default timezone('utc', now())`

Constraints/index:

- unique composite for replay-safe write key:
  - `(stream_name, entity_type, source_entity_id, coalesce(source_updated_at, synced_at))`

## 5.3 Event Facts Domain

### `incidents_mirror` (existing; evolved)

This table becomes the full event fact model while preserving existing API compatibility.

Required columns (add where missing):

- `er_event_id text primary key`
- `incident_id text not null`
- `serial_number text null`
- `event_type_slug text not null`
- `event_type_uuid text null`
- `event_state text not null`
- `occurred_at timestamptz not null`
- `updated_at timestamptz not null`
- `ranger_id text null`
- `mapped_ranger_id text null`
- `mapping_status text not null` (`mapped|unmapped|partial`)
- `latitude double precision null`
- `longitude double precision null`
- `location geography(point, 4326) null` (if PostGIS enabled)
- `payload_ref text not null` (foreign-like reference to raw payload)
- `event_details jsonb null`
- `raw_payload jsonb null` (optional denormalized cache)
- `synced_at timestamptz not null default timezone('utc', now())`
- `source_cursor text null`
- `request_id text null`

Constraints:

- `check (mapping_status in ('mapped', 'unmapped', 'partial'))`
- lat/lng range guard (when present)

## 5.4 Patrol Facts Domain

### `patrols_mirror` (new)

- `patrol_id text primary key`
- `patrol_serial_number text null`
- `patrol_state text null`
- `patrol_type text null`
- `leader_ranger_id text null`
- `assignee_ranger_id text null`
- `title text null`
- `objective text null`
- `priority text null`
- `notes text null`
- `scheduled_start_at timestamptz null`
- `scheduled_end_at timestamptz null`
- `start_time timestamptz null`
- `end_time timestamptz null`
- `updated_at timestamptz not null`
- `payload_ref text not null`
- `raw_payload jsonb not null`
- `synced_at timestamptz not null default timezone('utc', now())`
- `source_cursor text null`
- `request_id text null`

### `patrol_segments_mirror` (new)

- `segment_id text primary key`
- `patrol_id text not null references patrols_mirror(patrol_id) on update cascade on delete cascade`
- `segment_patrol_type text null`
- `segment_leader_ranger_id text null`
- `segment_start_time timestamptz null`
- `segment_end_time timestamptz null`
- `start_latitude double precision null`
- `start_longitude double precision null`
- `end_latitude double precision null`
- `end_longitude double precision null`
- `segment_metadata jsonb null`
- `payload_ref text not null`
- `raw_payload jsonb not null`
- `updated_at timestamptz not null`
- `synced_at timestamptz not null default timezone('utc', now())`

### `patrol_segment_events` (new bridge)

- `segment_id text not null references patrol_segments_mirror(segment_id) on delete cascade`
- `er_event_id text not null references incidents_mirror(er_event_id) on delete cascade`
- `linked_at timestamptz not null default timezone('utc', now())`
- primary key `(segment_id, er_event_id)`

## 5.5 Trackpoint Domain (Mandatory)

### `ranger_trackpoints` (new)

- `trackpoint_id text primary key`
- `ranger_id text not null`
- `recorded_at timestamptz not null`
- `latitude double precision not null`
- `longitude double precision not null`
- `location geography(point, 4326) null` (if PostGIS enabled)
- `speed_mps double precision null`
- `heading_deg double precision null`
- `accuracy_m double precision null`
- `source text null`
- `patrol_id text null references patrols_mirror(patrol_id) on update cascade on delete set null`
- `segment_id text null references patrol_segments_mirror(segment_id) on update cascade on delete set null`
- `payload_ref text not null`
- `raw_payload jsonb not null`
- `updated_at timestamptz null`
- `synced_at timestamptz not null default timezone('utc', now())`

Constraints:

- `check (latitude between -90 and 90)`
- `check (longitude between -180 and 180)`
- unique fallback de-dup key `(ranger_id, recorded_at, latitude, longitude, coalesce(source,''))`

## 5.6 Sync / Idempotency Domain

### `sync_cursors` (existing; strengthened)

- `stream_name text primary key`
- `cursor_value text not null`
- `updated_at timestamptz not null`
- optional `request_id text`

Policy:

- `set_sync_cursor` continues monotonic update semantics (never regress)

### `idempotency_log` (new or formalized)

- `idempotency_key text not null`
- `endpoint text not null`
- `request_hash text null`
- `status text not null`
- `first_seen_at timestamptz not null`
- `last_seen_at timestamptz not null`
- `request_id text null`
- primary key `(idempotency_key, endpoint)`

### `sync_run_audit` (new)

- `run_id text primary key`
- `stream_name text not null`
- `started_at timestamptz not null`
- `finished_at timestamptz null`
- `status text not null`
- `cursor_before text null`
- `cursor_after text null`
- `fetched_count int not null default 0`
- `upserted_count int not null default 0`
- `error text null`
- `request_id text null`

## 6. Indexing Strategy (Minimum Required + Added)

## 6.1 Required Minimum Indexes

### `incidents_mirror`

- `(occurred_at)`
- `(ranger_id, occurred_at)`
- `(mapped_ranger_id, occurred_at)`
- `(event_type_slug, occurred_at)`
- `(event_state, occurred_at)`
- `(mapped_ranger_id, updated_at)`
- `(mapping_status, updated_at)`
- `(event_type_slug, updated_at)`

### `patrols_mirror`

- `(start_time)`
- `(leader_ranger_id, start_time)`
- `(patrol_state, start_time)`

### `patrol_segments_mirror`

- `(patrol_id, segment_start_time)`
- `(segment_leader_ranger_id, segment_start_time)`

### `ranger_trackpoints`

- `(ranger_id, recorded_at)`
- spatial index on `location` (GiST), when PostGIS enabled

### `sync_cursors`

- unique `(stream_name)` (already canonical)

### `idempotency_log`

- unique `(idempotency_key, endpoint)`
- lookup `(first_seen_at)`

## 6.2 Supporting Indexes

- `er_raw_payloads(stream_name, source_entity_id, synced_at desc)`
- `patrol_segment_events(er_event_id)`
- `sync_run_audit(stream_name, started_at desc)`

## 7. Aggregate Strategy

## 7.1 Aggregate Tables

### `agg_ranger_day`

- `day_key date not null` (project TZ day boundary)
- `ranger_id text not null`
- `distance_moved_m double precision not null default 0`
- `patrol_time_sec bigint not null default 0`
- `events_created_count int not null default 0`
- `events_mapped_count int not null default 0`
- `events_unmapped_count int not null default 0`
- `event_state_open_count int not null default 0`
- `event_state_closed_count int not null default 0`
- `updated_at timestamptz not null default timezone('utc', now())`
- primary key `(day_key, ranger_id)`

### `agg_ranger_event_type_day`

- `day_key date not null`
- `ranger_id text not null`
- `event_type_slug text not null`
- `event_count int not null`
- `updated_at timestamptz not null default timezone('utc', now())`
- primary key `(day_key, ranger_id, event_type_slug)`

## 7.2 Derivation Rules

Distance moved from ordered track points per ranger in range:

$$
\text{distance\_moved\_m} = \sum_i \text{distance}(p_i, p_{i+1})
$$

with quality filters:

- drop invalid coordinate rows
- optional speed/jump outlier threshold

Patrol time overlap rule:

$$
\text{overlap\_sec} = \max\left(0,\ \min(\text{patrol\_end},\ \text{to}) - \max(\text{patrol\_start},\ \text{from})\right)
$$

(in SQL implemented via epoch extraction and boundary clipping).

## 7.3 Refresh Strategy

- Incremental aggregate refresh by impacted `(day_key, ranger_id)` after sync writes
- Nightly reconciliation job for drift repair
- Aggregates are recomputable from facts for audit correctness

## 8. Query Semantics & Security Boundaries

## 8.1 Scope Enforcement Contract

Backend query layer must always apply role predicate before expensive filters:

- `admin`: unrestricted (policy-allowed global)
- `leader`: only rows where ranger is in same `region + team`
- `ranger`: only own `ranger_id`

## 8.2 Ranger Feed Mapping Rule

For ranger role, incident/event listings must default to `mapping_status = 'mapped'`.

## 8.3 Query Bounds

All list/analytics endpoints must enforce:

- max date window (configurable)
- max page size (configurable)
- deterministic sort + cursor/page semantics

## 8.4 Timezone Semantics

- storage: UTC
- filter conversion: input range converted to UTC on boundary
- day-based grouping: `Asia/Ho_Chi_Minh`

## 9. Retention & Archival Strategy

## 9.1 Retention Policy

- Analytics operational floor: **183 days minimum** (hard guard)
- Keep normalized facts for required analytics windows
- Keep raw payload snapshots to support schema evolution and reprocessing

## 9.2 Trackpoint Volume Lifecycle

For `ranger_trackpoints`:

- hot: recent window (high query frequency)
- warm: medium-term storage
- archive: long-term compressed/partitioned storage

Archival must preserve ability to answer historical distance queries for compliance window.

## 9.3 Auditable Retention Operations

Retention/archival actions must be logged with:

- run id
- trigger (scheduled/manual/replay)
- cutoff
- deleted/archived counts
- correlation/request metadata

## 10. Implementation Patterns & Consistency Rules

## 10.1 Naming Conventions

- tables: `snake_case` plural for datasets (`ranger_trackpoints`, `patrols_mirror`)
- identifiers: stable external IDs retained as text (`er_event_id`, `patrol_id`)
- timestamps: suffix `_at`
- day keys: `day_key` for local-day aggregations

## 10.2 JSON & Payload Patterns

- Unknown source fields are never discarded; persist in `raw_payload`
- `payload_ref` must be written in normalized tables for traceability

## 10.3 Write Patterns

- all ingest writes are upsert/idempotent
- sync cursor update is monotonic only
- idempotency is enforced by unique key + audit timestamps

## 10.4 Read Patterns

- role scope first, then range filters, then pagination
- ranger feed defaults to mapped incidents only
- aggregate tables used for dashboards; detail endpoints use facts

## 10.5 Error/Observability Patterns

- include `request_id` in sync and analytics-write logs when available
- preserve `source_updated_at`, `synced_at`, `cursor_value`

## 11. Project Structure & Boundaries (Database Track)

```text
app/
├── deploy/
│   ├── supabase_auth_setup.sql
│   ├── supabase_schedule_setup.sql
│   └── sql/
│       └── analytics/
│           ├── 001_extensions_and_prereqs.sql
│           ├── 010_ranger_identity.sql
│           ├── 020_raw_payloads.sql
│           ├── 030_incidents_mirror_upgrade.sql
│           ├── 040_patrols_and_segments.sql
│           ├── 050_ranger_trackpoints.sql
│           ├── 060_sync_and_idempotency.sql
│           ├── 070_aggregates_daily.sql
│           ├── 080_views_and_scope_helpers.sql
│           └── 090_backfill_and_validation.sql
└── src/
    ├── supabase_db.py
    ├── sync.py
    ├── server.py
    └── analytics/
        ├── repositories.py
        ├── aggregation.py
        ├── scope.py
        └── quality_filters.py
```

Boundary decisions:

- DB DDL and migration scripts are isolated in `app/deploy/sql/analytics`
- API query-layer scope helpers are centralized (no per-endpoint ad-hoc scope logic)
- sync pipeline owns raw + fact ingest; API layer owns scoped reads

## 12. Migration Plan

## M0 — Preconditions

- enable required extensions (`pgcrypto`, optional `postgis`)
- backup/restore checkpoint
- verify canonical usernames in `app_users`

## M1 — Foundation Schema

Create:

- `ranger_identity`
- `er_raw_payloads`
- `patrols_mirror`
- `patrol_segments_mirror`
- `patrol_segment_events`
- `ranger_trackpoints`
- `idempotency_log` (if absent)
- `sync_run_audit`
- aggregates tables

## M2 — Evolve Existing Canonical Tables

Upgrade `incidents_mirror` and `sync_cursors` with required fields/constraints/indexes while preserving backward compatibility.

## M3 — Dual-Write Ingestion

- sync writes raw payload + fact tables in same cycle
- maintain existing read contracts during migration

## M4 — Backfill

- backfill historical incidents into evolved schema
- ingest available patrol/segment/trackpoint history
- reconstruct aggregates from facts

## M5 — Read Path Cutover

- replace in-memory operational reads with durable table-backed queries
- enforce role-scope predicates in query layer

## M6 — Validation Gates

- row-count reconciliation and cursor monotonicity checks
- no duplicate facts under replay
- acceptance queries pass for representative ranger/time windows

## M7 — Retention & Archival Activation

- enable lifecycle jobs and replay-auditable logs
- enforce 183-day floor guard

## 13. Requirements Coverage Validation

### FR Coverage Matrix

- **FR-01 Time-range analytics:** covered by fact tables + bounded range query contract
- **FR-02 Distance moved:** covered by `ranger_trackpoints` + distance derivation
- **FR-03 Event count:** covered by `incidents_mirror` and aggregates
- **FR-04 Event types:** covered by `event_type_slug` + `agg_ranger_event_type_day`
- **FR-05 Event status/state:** covered by `event_state` indexes + grouped queries
- **FR-06 Patrol time:** covered by patrol overlap computation on `patrols_mirror`
- **FR-07 Ranger-scoped listing:** covered by role-scope query-layer policy
- **FR-08 Incremental sync:** covered by `sync_cursors` monotonic updates + upserts
- **FR-09 Durability:** all analytics facts persisted in DB tables
- **FR-10 Schema drift tolerance:** `er_raw_payloads` + `raw_payload` retention
- **FR-11 Weekly/report readiness:** daily aggregates + recompute-capable facts

### NFR Coverage Summary

- Data integrity: PK/FK/unique constraints + canonical identity checks
- Performance: required indexes + bounded windows + aggregates
- Auditability: request/cursor/source timestamps + run audit tables
- Extensibility: raw JSON retention + additive columns
- Observability: request/correlation metadata in sync writes
- Scope correctness/security: query-layer role enforcement

## 14. Architecture Validation Results

### Coherence Validation

- No contradiction between existing canonical components and new model
- Migration path preserves current API compatibility while removing in-memory dependency for analytics facts
- Aggregate strategy remains derivable from persisted facts (no hidden business state)

### Gap Analysis

Critical:

1. `team` availability in identity source (renamed from `sub_region`) must be ensured for strict leader scope
2. trackpoint source endpoint contract must be finalized for reliable ingestion

Important:

1. decide whether PostGIS is enabled in target Supabase tier (for spatial performance)
2. finalize outlier threshold defaults for movement quality filtering

### Readiness Assessment

- **Overall Status:** READY FOR IMPLEMENTATION
- **Confidence:** High
- **First implementation priority:** execute M1 schema foundation + M2 `incidents_mirror` upgrade

## 15. Completion & Handoff

Architecture workflow for this database track is complete.

Next implementation handoff focus:

1. apply migration scripts (M0-M2)
2. implement dual-write ingest updates in `sync.py` + repository helpers
3. replace in-memory incident/work analytics reads with durable query paths
4. add aggregate refresh jobs + validation checks

This document is the architecture source of truth for events/patrols analytics persistence, indexing, retention, and migration sequencing.
