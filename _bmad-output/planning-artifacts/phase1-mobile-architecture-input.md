# Phase 1 Mobile Architecture Input (from PRD)

Date: 2026-03-19
Project: EarthRanger
Prepared for: `bmad-create-architecture`

## 1) Source Artifacts Used

- `_bmad-output/planning-artifacts/prd.md`
- `_bmad-output/project-context.md`
- `_bmad-output/planning-artifacts/full-method-kickoff-mobile.md`

## 2) Architecture Goals to Satisfy

1. Security-first mobile architecture (no privileged keys in app package).
2. Role-correct data access (`leader`, `ranger`) enforced server-side.
3. Hybrid offline-capable behavior for Phase 1.
4. ER integration that is rate-limit-safe and server-mediated.
5. Reliable daily check-in semantics with idempotency.

## 3) Proposed Baseline Decisions (Recommended Defaults)

### AD-01 — Access Boundary

- Adopt **BFF pattern** for mobile:
  - Mobile -> FastAPI mobile endpoints -> Supabase + ER sync data.
- Do not allow mobile clients to call ER APIs directly.
- Keep Supabase service-role credentials server-side only.

### AD-02 — Authentication Strategy (Recommended)

- Use backend-managed auth/session for Phase 1:
  - `POST /api/mobile/auth/login`
  - short-lived access token + refresh/session strategy
  - role claims embedded and validated server-side per request
- Remove hardcoded mobile credentials entirely.

### AD-03 — Authorization Model

- Enforce scope in backend query layer (not UI filtering only):
  - `ranger`: self-only data
  - `leader`: team-level data + schedule write permissions
- Centralize role checks in reusable dependency/guard helpers.

### AD-04 — Check-In Semantics

- Trigger: authenticated app open.
- Backend dedup key: `(user_id, day_key)`.
- Client idempotency key for retries: `(user_id, action_type, day_key, client_uuid)`.
- Backend accepts replay safely and returns deterministic status (`created` or `already_exists`).

### AD-05 — Offline/Sync Scope

- Offline writes in Phase 1: ranger check-in/stat updates only.
- Leader schedule writes: online-only in Phase 1.
- Sync queue requirements:
  - durable local queue
  - exponential backoff + jitter
  - retry caps + dead-letter status
  - visible sync state in UI (`synced/pending/failed`)

### AD-06 — ER Data Ingestion

- Polling/sync from ER happens server-side only.
- Use incremental cursor/high-watermark (`updated_since`) strategy.
- Implement configurable cadence and adaptive backoff to respect rate limits.

## 4) Target Component Design

## 4.1 Mobile (Flutter)

- `providers/` = state orchestration + loading/error lifecycle
- `services/` = API client + auth/session + sync queue coordinator
- local store = structured cache for incidents/schedules/work-summary (SQLite/Hive/Isar class)
- sync engine = queue replay + network-awareness + conflict-safe retries

## 4.2 Backend (FastAPI)

- `mobile_auth` module: login/refresh/logout/me
- `mobile_work` module: check-in ingest + work summary queries
- `mobile_incidents` module: read-only incident feed endpoint
- `mobile_schedules` module: leader write endpoints + scoped reads
- `er_sync` worker: incremental incident sync + cursor state
- shared middleware/dependencies: auth, role guard, request-id, rate limits

## 4.3 Data/Storage

- Supabase/Postgres for persisted operational state.
- ER mirror tables/views for incident reads (read model for mobile).
- idempotency tracking table/log for replay-safe writes.
- retention jobs for 6-month stats policy.

## 5) API Contract Baseline (Architecture Draft)

### 5.1 Auth

- `POST /api/mobile/auth/login`
  - in: credentials
  - out: access token + refresh/session metadata + role
- `POST /api/mobile/auth/refresh`
  - in: refresh/session token
  - out: renewed access token
- `POST /api/mobile/auth/logout`
  - invalidates refresh/session
- `GET /api/mobile/me`
  - returns profile + role + scope

### 5.2 Work Management / Check-In

- `POST /api/mobile/checkins`
  - in: `{ idempotency_key, client_time, timezone, app_version }`
  - out: `{ status: created|already_exists, day_key, server_time }`
- `GET /api/mobile/work-management?from=&to=&ranger_id=`
  - role-scoped summaries + day indicators

### 5.3 Incidents (Read-only)

- `GET /api/mobile/incidents?from=&to=&updated_since=&ranger_id=`
  - paginated role-scoped incidents
  - includes sync metadata (`last_synced_at`, `has_more`)

### 5.4 Schedule

- `GET /api/mobile/schedules?from=&to=&ranger_id=`
- `POST /api/mobile/schedules` (leader only)
- `PUT /api/mobile/schedules/{schedule_id}` (leader only)

## 6) Security Controls (Must-Have)

1. Remove privileged secrets from mobile `.env` and assets.
2. Rotate service-role keys if prior exposure is possible.
3. Restrict CORS by environment (no wildcard production config).
4. Harden session/token policy (secure cookie/token handling, revocation path).
5. Enforce webhook signature secret in production.

## 7) Data Model Inputs for Architecture Phase

Minimum entities to finalize:

- `users` (id, role, team_scope)
- `daily_checkins` (user_id, day_key, first_checkin_at, source, idempotency_key)
- `schedules` (schedule_id, ranger_id, date, assigned_by, updated_at)
- `incidents_mirror` (er_event_id, ranger_identity_fields, occurred_at, payload_ref, updated_at)
- `sync_cursors` (stream_name, cursor_value, updated_at)
- `idempotency_log` (idempotency_key, endpoint, status, first_seen_at, last_seen_at)

## 8) Required Architecture Decisions to Lock

1. Final auth stack for Phase 1:
   - backend JWT/session (recommended), or
   - Supabase Auth + strict RLS boundary.
2. Day-boundary policy for check-in:
   - project timezone (recommended for reporting consistency), or
   - device-local timezone.
3. Exact ER incident ownership mapping fields.
4. Schedule source-of-truth ownership (existing vs new backend entity).
5. Queue retry ceilings and dead-letter behavior.

## 9) Implementation Order (Post-Architecture)

1. Security gate: key rotation + secret removal + BFF boundary enforcement.
2. Auth/session endpoints and role guard foundation.
3. Check-in endpoint with idempotency + work-summary read endpoint.
4. Incident read endpoint (backed by ER sync mirror).
5. Schedule read/write endpoints.
6. Mobile cache + queue skeleton and sync status UX.
7. Tests for scope enforcement, idempotency, and offline replay.

## 10) Definition of Architecture Ready

Architecture is ready for stories when all are true:

- Chosen auth model is explicit and documented.
- API contract v1 is approved per endpoint.
- Data model and idempotency mechanism are fixed.
- Offline queue policy and conflict behavior are fixed.
- Security gate checklist is accepted as release blocker.
