# Database Requirements — Events & Patrols Analytics

- Date: 2026-03-27
- Last updated: 2026-03-30
- Project: EarthRanger
- Purpose: Define implementation-ready database requirements for event/patrol analytics before architecture design.

## 1) Context and objective

This module must support user-selected time-range analysis for ranger operations, including:

- Distance moved by ranger in a chosen period
- Number of events created by ranger
- Total patrol time in period
- Event-type breakdown in period
- Event/patrol listings scoped per ranger
- Weekly productivity/reporting summaries derived from the same persisted facts (AF-01 / AF-07 readiness)

## 2) Critical principle (must-have)

> **We will store ALL relevant patrol and event data for future needs**, including raw payload snapshots and ranger relocation history (track points), so new analytics can be computed later without re-ingesting historical data from source systems.

This includes both:

- Normalized tables for fast, reliable querying
- Raw JSON snapshots for schema drift tolerance and future feature extraction
- Durable database persistence as source of truth (not process-memory-only stores)

## 3) Functional requirements

### FR-01 Time-range analytics

System must support query filters:

- `from` timestamp
- `to` timestamp
- optional `ranger_id`
- optional role scope (`admin` global, `leader` team view, `ranger` self view)
- optional incremental/sync filters where needed (`updated_since`, cursor/page controls)

### FR-02 Distance moved

For any ranger and time window, system must compute total distance moved based on relocation/track points in chronological order.

### FR-03 Event count

System must return total number of events created by ranger in time window.

### FR-04 Event types

System must return grouped event-type counts (e.g., `tree_rep`, `incident_collection`, etc.) in time window.

### FR-05 Event status/state

System must support event status/state distribution queries in time window.

### FR-06 Patrol time

System must return patrol duration in time window, including partial-overlap handling when patrol intervals cross range boundaries.

### FR-07 Ranger-scoped listings

System must provide event and patrol listing endpoints/views scoped by role and ranger identity.

### FR-08 Incremental sync compatibility

Model must support cursor-based incremental updates and idempotent upserts.

### FR-09 Durability and replay safety

Operational analytics facts (events, patrols, trackpoints, check-in derived facts) must persist in durable tables and remain queryable across service restarts/redeployments.

### FR-10 Schema drift tolerance across ER variants

Ingestion must support EarthRanger payload variability (v1/v2 event type schemas, patrol shape changes) without breaking writes; unknown fields must be retained in raw snapshots.

### FR-11 Reporting and weekly-insight readiness

Data model must support weekly productivity and report-center queries without requiring re-sync of historical source data.

## 4) Non-functional requirements

### NFR-01 Data integrity

- Stable unique IDs for events/patrols/segments/trackpoints
- Idempotent upsert semantics
- Canonical ranger identity normalization

### NFR-02 Performance

- Bounded query windows and pagination support
- Indexes for time, ranger, type, status, and joins
- Optional daily aggregate layer for low-latency dashboards

### NFR-03 Auditability

- Preserve source timestamps and sync timestamps
- Keep source payload references/raw snapshots for traceability

### NFR-04 Extensibility

- New event types/fields must be ingested without schema breakage
- Raw payload retention required to support future analytics

### NFR-05 Observability

- Preserve `request_id`/correlation-friendly metadata for sync and analytics writes where available
- Preserve source update markers (`updated_at`, sync cursor checkpoints, `synced_at`) for operational traceability

### NFR-06 Scope correctness and security

- Role scoping must be enforceable at query layer, not UI layer
- Leader scope must align with team boundaries (same `region` + same `team` policy from project context)

## 5) Data domains to persist

## 5.1 Ranger identity

Required fields:

- `ranger_id` (canonical)
- `display_name`
- account role metadata where available (`account_role`, effective mobile role)
- organizational scope fields where available (`region`, `team`)

## 5.2 Event facts

Required fields:

- event identifiers (`er_event_id`, serial number)
- event type (`event_type_slug`, optional UUID mapping)
- event status/state
- occurrence and update timestamps
- creator/mapped ranger identity (`ranger_id`, `mapped_ranger_id`, `mapping_status`)
- location (lat/lng or geometry)
- sync metadata (`synced_at`, optional source cursor/checkpoint reference)
- payload reference (`payload_ref`) for audit joins
- raw payload snapshot (`event_details` + full payload)

## 5.3 Patrol facts

Required fields:

- patrol identifier
- patrol serial number where available
- patrol state/type
- leader and/or assignee identity
- schedule/start/end timestamps
- patrol metadata (`title`, `objective`, `priority`, `notes`)
- patrol updates/files metadata where available
- raw payload snapshot

## 5.4 Patrol segments

Required fields:

- segment identifier and patrol relation
- start/end location and time range
- segment patrol type
- segment leader
- linked events list/bridge where available
- segment update metadata where available

## 5.5 Ranger relocations / track points (mandatory)

Required fields:

- unique point id
- `ranger_id`
- `recorded_at`
- latitude/longitude (or geography point)
- optional telemetry (`speed`, `heading`, `accuracy`, `source`)

This domain is mandatory for distance analytics.

## 5.6 Sync and idempotency metadata

Required fields:

- sync stream identifier (`stream_name` or equivalent)
- monotonic cursor value/checkpoint
- checkpoint update timestamp
- idempotency key domain (ingest endpoint/action)
- first/last seen timestamps for replay forensics

## 6) Derived/aggregate requirements

System should support derived artifacts:

- `distance_moved_m` per ranger/day and ranger/time-range
- `patrol_time_sec` per ranger/day and ranger/time-range
- event count/type/state summaries
- weekly productivity summaries (self/team scope)
- report-ready aggregates for month/quarter/year windows

Recommended aggregate granularity:

- Daily per ranger (`agg_ranger_day`)
- Daily per ranger/event type (`agg_ranger_event_type_day`)

## 7) Query semantics and business rules

### BR-01 Timezone

- Persist timestamps in UTC
- Convert UI/local range to UTC at query boundary
- For day-based analytics keys, use fixed project timezone boundary `Asia/Ho_Chi_Minh` unless a later architecture decision changes policy

### BR-02 Interval overlap for patrol time

Patrol contribution in range is overlap of `[patrol_start, patrol_end]` with `[from, to]`.

### BR-03 Distance quality guardrails

- Ignore invalid points (null coords, malformed timestamps)
- Apply optional speed/jump thresholds to suppress GPS outliers

### BR-04 Role scope

- `ranger` sees own records only
- `leader` can view team scope and optionally filter to specific ranger, constrained by assigned `region + team`
- `admin` can view global scope where endpoint policy allows

### BR-05 Historical completeness

Do not delete historical event/patrol raw records needed for future analytics unless explicitly covered by retention and archival policy.

### BR-06 Cursor monotonicity

Incremental sync cursor/checkpoint values must be monotonic (never regress to older checkpoints).

### BR-07 Query bounds

Analytics and listing queries must enforce bounded date windows and page-size caps.

### BR-08 Ranger feed mapping policy

Ranger-scoped incident/event feeds should exclude unmapped records unless explicitly requested by privileged role.

## 8) Minimal indexing requirements

- Event table: indexes on `(occurred_at)`, `(ranger_id, occurred_at)`, `(mapped_ranger_id, occurred_at)`, `(event_type_slug, occurred_at)`, `(event_state, occurred_at)`
- Patrol table: indexes on `(start_time)`, `(leader_ranger_id, start_time)`, `(state, start_time)`
- Patrol segment table: indexes on `(patrol_id, segment_start_time)` and `(segment_leader_ranger_id, segment_start_time)`
- Trackpoint table: indexes on `(ranger_id, recorded_at)` and spatial index for geometry if PostGIS is used
- Incident mirror read indexes: `(mapped_ranger_id, updated_at)`, `(mapping_status, updated_at)`, `(event_type_slug, updated_at)`
- Sync cursor table: unique index on `(stream_name)`
- Idempotency log: unique index on `(idempotency_key, endpoint)` and lookup index on `(first_seen_at)`

## 9) Data retention and archival requirements

- Keep normalized operational data for analytics windows and reporting needs
- Keep raw snapshots for future schema evolution and reprocessing
- Ranger operational analytics retention must not be configured below 183 days (6-month floor)
- For high-volume track points, allow lifecycle policy (hot/warm/archive), but preserve ability to answer historical distance queries for required compliance period
- Retention/archival actions should remain auditable and replay-aware for operations

## 10) Acceptance criteria (for architecture + implementation)

- Can answer, for any ranger and arbitrary period, all of:
  1. distance moved
  2. number of events created
  3. patrol time spent
  4. event type breakdown
- Results are role-scoped correctly for `admin`, `leader` (team bounded), and `ranger` (self)
- Query latency remains acceptable under expected pagination/window limits
- Incremental sync updates do not create duplicate facts or regress cursors
- Data remains available after service restart/redeployment (no in-memory-only source-of-truth dependency)
- New event fields/types can be retained without breaking ingestion
- Mixed ER schema variants (v1/v2 event types + patrol payload variance) ingest successfully

## 11) Current-state alignment notes (2026-03-30)

To align architecture and implementation sequencing with current repository context:

- Existing mobile check-in and incident API paths still have process-memory usage in runtime; architecture/migrations must close this with durable table-backed reads/writes.
- `incidents_mirror` and `sync_cursors` are already part of the integration direction and should remain canonical components in the target model.
- Analytics/reporting requirements should be implemented on top of normalized facts + raw snapshots to keep future AF scope additive.

## 12) Handoff to architect

Use this requirements file as the source for database architecture design, including:

- table model (normalized + raw)
- constraints/keys
- indexing strategy
- aggregate strategy
- retention/archive strategy
- migration plan
