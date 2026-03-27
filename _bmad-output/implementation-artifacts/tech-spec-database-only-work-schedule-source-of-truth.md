---
title: "Database-Only Work Schedule Source of Truth"
slug: "database-only-work-schedule-source-of-truth"
created: "2026-03-25"
status: "completed"
stepsCompleted: [1, 2, 3, 4]
tech_stack:
  - "Python 3.12"
  - "FastAPI"
  - "Supabase PostgreSQL"
  - "Dart / Flutter"
  - "http (Flutter client API layer)"
files_to_modify:
  - "app/src/server.py"
  - "app/src/supabase_db.py"
  - "app/deploy/supabase_schedule_setup.sql"
  - "app/tests/test_mobile_schedules.py"
  - "docs/SUPABASE_LOGIN_SETUP.md"
code_patterns:
  - "Role-scoped mobile endpoint handlers with dependency guards (require_mobile_auth/leader/admin)"
  - "Schedule filtering helpers in server.py (_build_mobile_schedule_items, _resolve_mobile_schedule_scope)"
  - "Supabase helper/repository style in supabase_db.py (table().select().insert().update().execute())"
  - "Response envelopes with items/scope/filters/pagination/directory expected by mobile provider"
  - "UTC timestamp handling with timezone-aware serialization"
test_patterns:
  - "Backend unittest + FastAPI TestClient integration style in app/tests/test_mobile_schedules.py"
  - "Role-based visibility and permission assertions with explicit HTTP detail checks"
  - "Deterministic sort/order assertions for schedule list responses"
  - "Transition tests from in-memory fixtures to database/repository-backed fixtures or mocks"
---

# Tech-Spec: Database-Only Work Schedule Source of Truth

**Created:** 2026-03-25

## Overview

### Problem Statement

The current mobile schedule APIs in `app/src/server.py` still depend on in-memory state (`mobile_schedule_records`) for create/read/update/delete flows. This causes non-durable schedule state, process-local inconsistency in multi-worker deployments, and mismatch risk with audit/compliance requirements. At the same time, Supabase schema and audit structures for schedules already exist in `app/deploy/supabase_schedule_setup.sql`.

### Solution

Move schedule read/write authority to Supabase only, using `public.schedules` as the single source of truth and `public.schedule_action_logs` as immutable history. Refactor backend schedule endpoints to call a dedicated data-access layer in `supabase_db.py`, preserving current API contract and role scoping while enforcing sort order by stable `username`.

### Scope

**In Scope:**

- Refactor `/api/mobile/schedules` GET/POST/PUT/DELETE to use Supabase-backed persistence only.
- Add schedule CRUD/query helper methods in `app/src/supabase_db.py`.
- Keep role-based access and scope enforcement (`leader`, `ranger`, `admin`) server-side.
- Ensure list sorting is deterministic and uses `work_date`, `username`, `schedule_id` (not `display_name`).
- Integrate with existing DB schema (`public.schedules`, `schedules_with_user_profile`, `schedule_action_logs`).
- Add/adjust backend tests to validate DB-only schedule behavior, permission scope, and ordering.
- Update operational docs for DB-only schedule source-of-truth behavior.
- Define cutover steps from in-memory runtime state to DB-only operations, including explicit no-backfill assumptions and operator checklist.
- Define rollback/contingency behavior that does not reintroduce in-memory write authority.
- Define explicit schedule API error, pagination, and soft-delete semantics to keep client behavior deterministic.

**Out of Scope:**

- Mobile UI redesign or new UX behavior beyond existing API contract.
- Direct mobile-to-Supabase privileged access.
- New caching layer introduction (Redis/in-memory read-through cache).
- Broader incident/work-management data model refactors.
- Changes to existing schedule SQL schema unless bug fixes are required during integration.

## Context for Development

### Codebase Patterns

- Current schedule endpoints in `app/src/server.py` are API-contract rich but in-memory-backed:
  - in-memory store: `mobile_schedule_records`
  - query helper: `_build_mobile_schedule_items(...)`
  - write endpoints: `POST/PUT/DELETE /api/mobile/schedules...`
- Role enforcement and scope validation are already centralized and must be preserved:
  - auth guards: `require_mobile_auth`, `require_mobile_leader`, `require_mobile_admin`
  - scope validators: `_resolve_mobile_schedule_scope`, `_validate_mobile_schedule_assignee_scope`
- Existing mobile response contract must remain stable for Flutter:
  - GET response shape includes `items`, `scope`, `filters`, `pagination`, `directory`
  - schedule item fields used by Flutter include `schedule_id`, `ranger_id`, `work_date`, `note`, `updated_by`, `created_at`, `updated_at`
- Existing Supabase schedule schema already supports database-only authority:
  - canonical table: `public.schedules`
  - profile-joined read model: `public.schedules_with_user_profile`
  - immutable audit history via trigger: `public.schedule_action_logs`
- Existing tests are currently coupled to in-memory globals and need conversion to DB/repository-backed behavior.

### Files to Reference

| File                                                                                             | Purpose                                                                                                                          |
| ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `app/src/server.py`                                                                              | Replace in-memory schedule reads/writes with Supabase-backed calls while preserving auth/role/scope behavior and response shape. |
| `app/src/supabase_db.py`                                                                         | Implement schedule repository functions (list/create/update/soft-delete + row mapping).                                          |
| `app/deploy/supabase_schedule_setup.sql`                                                         | Source of truth for schedule schema, profile sync trigger, audit log trigger, and active-row uniqueness constraints.             |
| `app/tests/test_mobile_schedules.py`                                                             | Existing regression suite currently built on in-memory state; primary test migration target.                                     |
| `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`                                 | Defines strict schedule payload parsing and required JSON fields for client compatibility.                                       |
| `mobile/epic-treeinfo-dart/lib/providers/schedule_provider.dart`                                 | Assumes deterministic ordering and stable scope/directory semantics from backend schedule APIs.                                  |
| `_bmad-output/implementation-artifacts/3-3-schedule-read-and-leader-write-apis.md`               | Baseline AC intent for scope, leader writes, and audit semantics.                                                                |
| `_bmad-output/implementation-artifacts/3-4-schedule-ux-for-ranger-view-and-leader-operations.md` | UX contract dependencies on schedule endpoint behavior.                                                                          |
| `docs/SUPABASE_LOGIN_SETUP.md`                                                                   | Deployment/setup docs that must reflect database-only schedule authority.                                                        |

### Technical Decisions

- **Single source of truth**: Only Supabase `public.schedules` is authoritative for schedule data.
- **API compatibility**: Preserve response envelope shape (`{"ok": true, ...}` and schedule fields used by mobile).
- **Identity/sorting key**: Use normalized `username` (trim + lowercase at API boundary) as canonical stable key; never sort by mutable `display_name`.
- **Lifecycle handling**: Respect soft-delete semantics (`deleted_at`) in reads and writes (DELETE endpoint should map to soft-delete behavior in DB).
- **Auditability**: Rely on DB trigger-based `schedule_action_logs` for immutable change history.
- **Security model**: Maintain backend-mediated access; no privileged direct client writes.
- **Error contract stability**: Preserve existing HTTP status + error detail expectations where tests/mobile depend on them.
- **Directory/scope stability**: Continue returning role-scoped `directory` and `scope` payloads so Flutter role UX remains unchanged.
- **Error payload contract**: Schedule APIs use FastAPI default error shape `{"detail": "..."}`. Status mappings are explicit: `400` (validation/filter format), `401` (invalid token), `403` (role/scope denial), `404` (missing schedule), `409` (duplicate active assignment conflict), `5xx` (unexpected backend/storage failure).
- **Timezone/date semantics**: `work_date` is a date-only field (`YYYY-MM-DD`) interpreted in project business-day policy (Asia/Ho_Chi_Minh) and persisted as SQL `date` without time-of-day conversion.
- **Soft-delete semantics**: Delete sets `deleted_at` and keeps audit history; active reads always filter `deleted_at is null`; repeated delete on already-deleted/nonexistent row returns `404`; restore/hard-purge are out of scope.
- **Delta filter semantics**: Active schedule items are filtered by `updated_at >= updated_since`; delete events since cursor are returned separately as tombstones so clients can reconcile removals without full refresh.
- **Concurrency policy**: Update/delete operations are atomic DB mutations on active rows (`schedule_id` + `deleted_at is null`); duplicate assignment conflicts are handled by DB uniqueness and mapped to HTTP `409`.
- **Active uniqueness semantics**: Enforce exactly one active schedule per `(work_date, username)` using `uq_schedules_active_assignment` (`WHERE deleted_at IS NULL`); soft-deleted historical rows do not block re-assignment.
- **Scope/directory generation rules**: Keep existing role behavior deterministic: ranger sees self-only scope and directory; leader sees ranger-assignable directory; admin-account leaders include leader+ranger directory entries as currently implemented.
- **Delete response source semantics**: `deleted_by` in API response is sourced from authenticated actor claims (`mobile_user.username`), not from storage row snapshots.
- **Pagination semantics**: `pagination.total` and `pagination.total_pages` are computed after applying role scope, date filters, `updated_since`, and active-row filter (`deleted_at is null`).
- **Pagination consistency model**: Offset pagination is allowed with explicit consistency semantics; server supports snapshot pinning (`snapshot_at`) so multi-page reads can remain deterministic under concurrent writes/deletes.
- **Delete actor coupling**: The actor reflected in API delete response must also be persisted as mutation/audit actor in storage for forensic consistency.
- **Preflight readiness gate**: Readiness is deployment-global in production: every worker must pass schedule-schema preflight before becoming ready to serve traffic; request-path fallback checks are only for non-production/local workflows.
- **Readiness mode configuration**: Runtime must use explicit `SCHEDULE_READINESS_MODE` with allowed values `strict` or `lazy`; default is `strict`; unknown/missing invalid values fail closed.
- **Readiness mode configuration**: Runtime must use explicit `SCHEDULE_READINESS_MODE` with allowed values `strict` or `lazy`; missing value defaults to `strict`; unknown/invalid values fail closed.
- **Readiness error exposure policy**: Client-facing readiness failure response is generic (`503`, stable `detail` + request correlation id); exact missing artifacts are logged server-side only.
- **Claim precedence policy**: `account_role` is authoritative for privilege enforcement (create/update/delete), while `role` is presentation scope (`leader`/`ranger`); conflicting claims invalidate session (`401`).

## Implementation Plan

### Tasks

- [x] Task 1: Add schedule database access layer for read/write operations
  - File: `app/src/supabase_db.py`
  - Action: Implement schedule repository functions for list/create/update/soft-delete using existing Supabase query style (`table().select().insert().update().execute()`).
  - Notes: Include helper row mappers between DB schema (`username`, `work_date`, `created_by_*`, `updated_by_*`) and API payload fields (`ranger_id`, `work_date`, `updated_by`, timestamps). Normalize assignee identity (`trim().lower()`) before persistence/lookup, respect active-row semantics (`deleted_at is null`), and enforce deterministic ordering by `(work_date, username, schedule_id)`.

- [x] Task 2: Add schedule schema preflight validation
  - File: `app/src/supabase_db.py`
  - Action: Add a readiness check helper that validates required schedule artifacts (`public.schedules`, key columns, and required query surface) before schedule endpoints execute.
  - Notes: Use fail-closed semantics with deployment-wide readiness behavior: worker startup must fail if preflight fails in production, and request-path checks are fallback only for local/dev mode. Implement `SCHEDULE_READINESS_MODE` (`strict` default, `lazy` opt-in), reject invalid values, return generic client `503` with correlation id, and log exact missing artifacts server-side. Preflight MUST include canonical identity invariant checks (lowercase/trim conformance + duplicate-active anomaly checks).

- [x] Task 3: Replace schedule read path with Supabase-backed query composition
  - File: `app/src/server.py`
  - Action: Refactor schedule list assembly (`GET /api/mobile/schedules`) to use Supabase repository reads instead of `mobile_schedule_records`.
  - Notes: Preserve existing role guards and scope logic (`require_mobile_auth`, `_resolve_mobile_schedule_scope`). Keep required response envelope keys unchanged (`items`, `scope`, `filters`, `pagination`, `directory`) and add backward-compatible `sync` object for delta tombstones (`deleted_schedule_ids`) when `updated_since` is used.

- [x] Task 4: Replace schedule write/delete paths with Supabase-backed mutations
  - File: `app/src/server.py`
  - Action: Refactor `POST`, `PUT`, `DELETE /api/mobile/schedules...` to call repository functions and remove in-memory write authority.
  - Notes: Preserve leader/admin authorization behavior and validation responses. Map delete endpoint to soft-delete behavior in DB while retaining current external response (`{ "ok": true, "schedule_id": ..., "deleted_by": ... }`). `deleted_by` must be derived from authenticated actor claims and persisted consistently to mutation/audit actor fields. Soft-delete write-set must include `deleted_at`, `updated_at`, `updated_by_username`, and `updated_by_display_name`. Ensure duplicate assignment conflicts are mapped to `409` with safe `detail` message.

- [x] Task 5: Preserve mobile contract compatibility for schedule client/parser assumptions
  - File: `app/src/server.py`
  - Action: Ensure returned schedule item fields and scope metadata match current Flutter parser expectations.
  - Notes: Must continue returning stable field names consumed by `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart` and sorting behavior expected by `schedule_provider.dart`. Keep FastAPI error payload shape `{"detail": ...}` for compatibility. Implement explicit DB→API field mapping defined in this spec (including envelope/scope/directory/sync fields and actor/audit fields).

- [x] Task 6: Convert schedule backend regression tests from in-memory fixtures to DB/repository-backed behavior
  - File: `app/tests/test_mobile_schedules.py`
  - Action: Refactor tests to mock/inject Supabase repository responses (or test against isolated DB doubles) instead of direct `server.mobile_schedule_records` mutation.
  - Notes: Keep existing coverage intent: role scope, pagination, updated_since validation, write validation, permission denial, and schedule ordering assertions. Ensure fixture isolation and deterministic teardown between tests.

- [x] Task 7: Add database-specific edge-case tests for schedule constraints and error mapping
  - File: `app/tests/test_mobile_schedules.py`
  - Action: Add/adjust tests for duplicate active assignment, missing schedule update/delete, unknown assignee linkage, and DB exception-to-HTTP mapping.
  - Notes: Validate that DB constraint failures return clear API errors without leaking internal database details. Add tests for username normalization collisions, delta tombstones on soft-delete, and delete-response actor parity with persisted audit actor.

- [x] Task 8: Document cutover and rollback/contingency runbook
  - File: `docs/SUPABASE_LOGIN_SETUP.md`
  - Action: Add a release cutover checklist and rollback strategy for schedule storage migration.
  - Notes: Explicitly document no trusted backfill source from in-memory process state; require deployment inventory (running instances + version), verification window, DB health check, and objective rollback thresholds.

- [x] Task 9: Update setup/ops documentation for database-only schedule authority
  - File: `docs/SUPABASE_LOGIN_SETUP.md`
  - Action: Document that schedule endpoints no longer rely on in-memory persistence and require Supabase schedule schema deployment for runtime correctness.
  - Notes: Include operational implications for multi-worker consistency and restart durability.

- [x] Task 10: Enforce and validate canonical username invariants for schedule uniqueness
  - File: `app/deploy/supabase_schedule_setup.sql`
  - Action: Add SQL safety checks and (if needed) corrective migration steps so schedule identity used in uniqueness checks is canonical lowercase/trimmed before strict readiness can pass.
  - Notes: Ensure cutover includes explicit anomaly queries and remediation steps for case/whitespace collisions before enabling DB-only writes.

- [x] Task 11: Lock claim precedence and conflict handling in auth dependency
  - File: `app/src/server.py`
  - Action: Implement explicit `(role, account_role)` allowed-combination validation in `require_mobile_auth` and reject invalid claim combinations.
  - Notes: Keep admin-account leader combination valid while rejecting malformed/escalated claim pairs with `401`.

### Acceptance Criteria

- [ ] AC 1: Given a valid leader request to create a schedule, when `POST /api/mobile/schedules` is called, then the schedule is persisted in `public.schedules` and returned with API-compatible fields.
- [ ] AC 2: Given the API process restarts (or requests are served by different workers), when `GET /api/mobile/schedules` is called, then previously created schedules are still returned because persistence is database-backed.
- [ ] AC 3: Given a ranger-authenticated user, when `GET /api/mobile/schedules` is called, then only self-scoped schedule rows are returned and cross-ranger scope requests are denied.
- [ ] AC 4: Given a leader-authenticated user, when `GET /api/mobile/schedules` is called without `ranger_id`, then team-scoped rows allowed by server-side role policy are returned with existing `scope` and `directory` metadata.
- [ ] AC 5: Given repeated list queries across the same filter window, when schedules are returned, then ordering is deterministic by `work_date`, `username`, `schedule_id` (not `display_name`).
- [ ] AC 6: Given a valid leader update request for an existing schedule, when `PUT /api/mobile/schedules/{schedule_id}` is called, then the row is updated in Supabase and subsequent reads reflect the change.
- [ ] AC 7: Given an admin delete request for an existing schedule, when `DELETE /api/mobile/schedules/{schedule_id}` is called, then the schedule is soft-deleted and excluded from active list responses.
- [ ] AC 8: Given a non-leader create/update request or non-admin delete request, when authorization is evaluated, then the request is rejected with the same role error semantics currently used by the API.
- [ ] AC 9: Given invalid schedule write input (missing `ranger_id`, malformed `work_date`, out-of-scope assignee), when write endpoints are called, then clear 4xx validation errors are returned and no database mutation occurs.
- [ ] AC 10: Given duplicate active assignment input for the same `(work_date, username)`, when persistence is attempted, then API error handling returns a safe conflict response and avoids inconsistent state.
- [ ] AC 11: Given schedule schema artifacts are missing or incomplete, when schedule endpoints are called, then backend returns generic `503` service-unavailable error with correlation id and logs clearly identify missing prerequisites.
- [ ] AC 12: Given a deleted schedule row, when list endpoint is queried with or without `updated_since`, then deleted rows are excluded from active response items and delete behavior remains idempotent from API perspective (`404` on repeated delete).
- [ ] AC 13: Given a DB uniqueness/constraint conflict or missing row update/delete, when API maps storage errors, then HTTP status and `detail` payload follow explicit contract (`409` conflict, `404` missing row, no internal SQL leakage).
- [ ] AC 14: Given release cutover to DB-only schedule authority, when deployment checklist is executed, then operators have documented validation and rollback/contingency steps before and after enabling schedule writes.
- [ ] AC 15: Given concurrent first-requests arrive before schema readiness state is known, when preflight executes, then exactly one synchronized readiness check decision is applied and no request bypasses the fail-closed gate.
- [ ] AC 16: Given successful delete request, when API returns response, then `deleted_by` equals authenticated actor username and does not depend on mutable storage snapshot fields.
- [ ] AC 17: Given a soft-deleted schedule exists for `(work_date, username)`, when a new active schedule for the same key is created, then create succeeds unless another active row exists.
- [ ] AC 18: Given production deployment with multiple workers, when any worker fails schedule-schema preflight, then it does not become ready to serve traffic and schedule endpoints are not partially available across workers.
- [ ] AC 19: Given schema readiness failure, when schedule endpoint responds, then client receives generic `503` detail and correlation id while exact missing artifacts appear only in server logs.
- [ ] AC 20: Given create/update/delete with mixed-case or whitespace `ranger_id`, when request is processed, then identity is normalized (`trim+lower`) and uniqueness checks behave consistently.
- [ ] AC 21: Given delete succeeds, when audit rows are inspected, then response `deleted_by` matches persisted actor fields used for schedule mutation/audit trail.
- [ ] AC 22: Given `updated_since` is provided, when soft-delete actions occurred after cursor, then response includes tombstone IDs (`sync.deleted_schedule_ids`) for scoped reconciliation.
- [ ] AC 23: Given non-admin leader account, when targeting own leader username for schedule filter/create/update, then scope/assignee rules deny those operations per policy.
- [ ] AC 24: Given cutover execution, when go/no-go is evaluated, then objective thresholds (instance version parity, smoke matrix pass, error-rate guardrail) determine promotion or rollback.
- [ ] AC 25: Given runtime starts with `SCHEDULE_READINESS_MODE` unset, then mode defaults to `strict`; given mode is invalid, startup fails closed.
- [ ] AC 26: Given `role` and `account_role` claims conflict, when authorization is evaluated, then request is rejected with `401` and does not proceed.
- [ ] AC 27: Given `updated_since` + pagination are used, when responses share same `snapshot_at`, then `sync.deleted_schedule_ids` is deterministic, deduplicated, and stable across pages.
- [ ] AC 28: Given production runtime sets `SCHEDULE_READINESS_MODE=lazy`, when service starts, then startup fails closed.
- [ ] AC 29: Given pre-cutover normalization audit finds non-canonical usernames or duplicate-active anomalies, when go/no-go is evaluated, then cutover is blocked until remediation brings audit counts to zero.
- [ ] AC 30: Given valid claim combinations (`leader/admin`, `leader/leader`, `ranger/ranger`), when auth is evaluated, then access proceeds by policy; all other combinations are rejected with `401`.

## Additional Context

### Dependencies

- Runtime Supabase connectivity configured via `SUPABASE_URL` and `SUPABASE_KEY`.
- Existing schedule schema migration applied: `app/deploy/supabase_schedule_setup.sql`.
- Existing auth/user profile schema available: `app/deploy/supabase_auth_setup.sql` and `public.app_users`.
- Backend Supabase singleton client and table query style in `app/src/supabase_db.py`.
- Mobile client contract dependency: schedule payload parsing in `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`.

### API Contract Clarifications

- **Error payload**: FastAPI default `{ "detail": "..." }`.
- **Error status mapping**:
  - `400`: invalid date range/format, malformed filters, invalid write payload
  - `401`: invalid/expired access token
  - `403`: role/scope denial
  - `404`: schedule not found (including repeated delete)
  - `409`: duplicate active assignment conflict `(work_date, username)`
  - `503`: schedule service temporarily unavailable (readiness/maintenance)
  - `5xx`: unexpected storage/runtime errors
- **Readiness failure payload policy**:
  - Client `detail` is generic and stable (e.g., `Schedule service unavailable`).
  - Include canonical `X-Request-ID` response header (and optional mirrored `request_id` field).
  - Exact missing DB artifacts are emitted to structured logs only.
- **Pagination response shape**:
  - `pagination.page` (1-based)
  - `pagination.page_size`
  - `pagination.total`
  - `pagination.total_pages`
- **Pagination semantics**:
  - `total` and `total_pages` are calculated after all filters are applied: scope, `from/to`, `updated_since`, and active-row filter (`deleted_at is null`).
  - Input bounds: `page >= 1`; `1 <= page_size <= min(500, mobile_schedules_max_page_size)`.
  - Out-of-range page (`page > max(total_pages, 1)`) returns `400` with stable `detail` message.
  - When `snapshot_at` is omitted, server generates UTC `snapshot_at` at request start and returns it in `filters.snapshot_at`.
  - Invalid `snapshot_at` format returns `400`.
  - For deterministic multi-page reads under concurrent changes, clients pin `snapshot_at`; server applies `updated_at <= snapshot_at` to subsequent pages.
- **Sorting contract**: ascending `(work_date, username, schedule_id)`.
- **Delete response contract**:
  - Success payload remains `{ "ok": true, "schedule_id": "...", "deleted_by": "..." }`.
  - `deleted_by` source is authenticated actor claim (`mobile_user.username`).
  - Delete mutation must persist same actor identity to storage actor/audit fields by writing `updated_by_username` + `updated_by_display_name` in same soft-delete mutation.
- **Date/time parsing semantics**:
  - `work_date` accepts only strict `YYYY-MM-DD` date strings; datetime/timezone strings are rejected as `400`.
  - `updated_since` accepts ISO datetime with or without timezone; server normalizes to UTC for comparison.
  - Naive `updated_since` values are interpreted as UTC to match existing parser behavior.
  - Date filter operators are inclusive: `from <= work_date <= to`.
  - Delta comparator for active items is inclusive: `updated_at >= updated_since`.
- **Active uniqueness contract**:
  - API normalizes identity input with `trim+lower` before read/write operations.
  - Active uniqueness key is `(work_date, username)` for rows where `deleted_at is null`.
  - DB uniqueness enforcement MUST use normalized identity semantics; preflight MUST verify canonical-lowercase identity invariants and fail readiness if violations are detected.
  - Cutover MUST run normalization audit/remediation and require zero anomalies before enabling strict readiness.
  - Conflict path maps to `409` with safe `detail` (no raw SQL text leakage).
- **Delta tombstone contract**:
  - Tombstone source is soft-deleted rows in `public.schedules` where `deleted_at is not null` and `updated_at` is within delta window (`updated_since <= updated_at <= snapshot_at`) after scope filters.
  - When `updated_since` is supplied, response includes `sync.deleted_schedule_ids` (array of `schedule_id`) scoped to caller visibility.
  - `sync.deleted_schedule_ids` is deduplicated, sorted by `(updated_at, schedule_id)`, and deterministic for a fixed `snapshot_at`.
  - For all pages sharing the same `snapshot_at`, server returns the same full-window `sync.deleted_schedule_ids` list to avoid page-loss ambiguity.
  - `sync.deleted_schedule_ids` is additive/backward-compatible and defaults to `[]` when no matching delete actions exist.

### DB ↔ API Field Mapping Contract

| API Surface                                 | API Field     | DB Source                                                      | Notes                            |
| ------------------------------------------- | ------------- | -------------------------------------------------------------- | -------------------------------- |
| List/Create/Update response `schedule` item | `schedule_id` | `schedules.schedule_id`                                        | UUID string                      |
| List/Create/Update response `schedule` item | `ranger_id`   | `schedules.username`                                           | Canonical identity key           |
| List/Create/Update response `schedule` item | `work_date`   | `schedules.work_date`                                          | Serialized as `YYYY-MM-DD`       |
| List/Create/Update response `schedule` item | `note`        | `schedules.note`                                               | Trimmed at API boundary          |
| List/Create/Update response `schedule` item | `updated_by`  | `schedules.updated_by_username`                                | Actor username for last mutation |
| List/Create/Update response `schedule` item | `created_at`  | `schedules.created_at`                                         | ISO-8601 UTC string              |
| List/Create/Update response `schedule` item | `updated_at`  | `schedules.updated_at`                                         | ISO-8601 UTC string              |
| Delete response                             | `schedule_id` | Request path parameter (validated against existing active row) | Must match soft-deleted row key  |
| Delete response                             | `deleted_by`  | Authenticated actor (`mobile_user.username`)                   | Not sourced from DB snapshot     |

### Envelope, Scope, Filters, Directory, Sync Contract

| Surface       | Field                  | Type                  | Nullability                           | Rules                                                |
| ------------- | ---------------------- | --------------------- | ------------------------------------- | ---------------------------------------------------- |
| `scope`       | `role`                 | string                | non-null                              | `leader` or `ranger` (mobile contract role)          |
| `scope`       | `account_role`         | string                | nullable                              | normalized internal role (`admin`,`leader`,`ranger`) |
| `scope`       | `team_scope`           | boolean               | non-null                              | true only when effective scope is team-level         |
| `scope`       | `requested_ranger_id`  | string                | nullable                              | echo of normalized request filter                    |
| `scope`       | `effective_ranger_id`  | string                | nullable                              | null for team scope, username for scoped reads       |
| `filters`     | `from`                 | string (`YYYY-MM-DD`) | nullable                              | inclusive lower bound                                |
| `filters`     | `to`                   | string (`YYYY-MM-DD`) | nullable                              | inclusive upper bound                                |
| `filters`     | `updated_since`        | string (ISO-8601 UTC) | nullable                              | normalized cursor used in query                      |
| `filters`     | `snapshot_at`          | string (ISO-8601 UTC) | nullable                              | fixed snapshot bound for paged consistency           |
| `pagination`  | `page`                 | integer               | non-null                              | `>= 1`                                               |
| `pagination`  | `page_size`            | integer               | non-null                              | configured bounds                                    |
| `pagination`  | `total`                | integer               | non-null                              | post-filter count                                    |
| `pagination`  | `total_pages`          | integer               | non-null                              | derived from total/page_size                         |
| `directory[]` | `username`             | string                | non-null                              | normalized username                                  |
| `directory[]` | `display_name`         | string                | non-null                              | display label                                        |
| `directory[]` | `role`                 | string                | non-null                              | `leader` or `ranger`                                 |
| `sync`        | `deleted_schedule_ids` | array[string]         | non-null when `updated_since` present | tombstones for scoped deletions                      |

Directory sort order remains deterministic: ranger entries first, then by `display_name.lower()`, then `username`.

Allowed claim combinations for auth/session validation:

- (`role=leader`, `account_role=admin`) — valid admin-account leader
- (`role=leader`, `account_role=leader`) — valid leader
- (`role=ranger`, `account_role=ranger`) — valid ranger
- Any other combination — invalid token/session (`401`)

### Scope and Directory Resolution Rules

- Ranger account: effective scope is self-only; directory includes self.
- Leader account: team-scope default when no `ranger_id`; directory includes assignable ranger users.
- Admin-account leader: directory includes leader + ranger entries per current behavior.
- Non-admin leader self-target policy: leader usernames are not assignable targets for create/update, and `ranger_id` filter for self-leader username is denied.

| Account Role         | Read `/api/mobile/schedules`                   | Create/Update  | Delete         | Allowed `ranger_id` target set |
| -------------------- | ---------------------------------------------- | -------------- | -------------- | ------------------------------ |
| ranger               | Self-only                                      | Denied (`403`) | Denied (`403`) | Self only                      |
| leader (non-admin)   | Team ranger scope only                         | Allowed        | Denied (`403`) | Ranger accounts only           |
| admin-account leader | Team scope including leader+ranger assignments | Allowed        | Allowed        | Leader + ranger accounts       |

Endpoint-level clarification:

- `GET /api/mobile/schedules`: non-admin leader can list team ranger schedules; explicit `ranger_id` equal to own leader username is denied.
- `POST /api/mobile/schedules`: non-admin leader can create only for ranger targets.
- `PUT /api/mobile/schedules/{id}`: non-admin leader can retarget/update only to ranger targets.
- `DELETE /api/mobile/schedules/{id}`: admin-account leader only.

### Schema Readiness Gate Semantics

- Production mode uses deployment-global readiness behavior:
  - Every worker runs schedule-schema preflight during startup.
  - Worker fails startup/readiness if preflight fails (no traffic should be routed to failed worker).
  - Orchestrator readiness must gate on the same preflight status.
- Runtime mode selection:
  - `SCHEDULE_READINESS_MODE=strict` (default): startup preflight required; failures block readiness.
  - `SCHEDULE_READINESS_MODE=lazy` (non-production only): allow startup and enforce request-path preflight gate.
  - Invalid/unknown mode values fail closed during startup.
- Local/dev mode may use lazy first-request preflight with process-local lock to avoid duplicate checks.
- Retry policy for non-ready state (local/dev fallback): exponential backoff with jitter, max recheck interval 60s.
- Client error contract on readiness failure is generic `503` with correlation id; logs include concrete missing artifacts.
- No schedule read/write path is allowed to continue when readiness is unresolved.

### Cutover and Rollback Strategy

- **Cutover assumptions**:
  - In-memory schedule runtime state is not a reliable migration source.
  - Any required historical schedule seed must come from external operator source, not process memory.
- **Cutover checklist**:
  1. Inventory all running API instances and ensure release version alignment (no mixed in-memory writer version remains).
  2. Announce schedule-write maintenance window and freeze deployment churn.
  3. Apply `app/deploy/supabase_schedule_setup.sql` in target environment.
  4. Run canonical identity audit queries (`app_users` + `schedules`) for case/whitespace anomalies and duplicate-active risk.
  5. If audit fails, execute remediation (normalize identities + resolve collisions) and re-run audit until zero anomalies.
  6. Run schema readiness verification and confirm `uq_schedules_active_assignment` exists.
  7. Deploy DB-backed backend build to all workers.
  8. Validate GET/POST/PUT/DELETE schedule smoke tests.
  9. Validate role matrix behavior (ranger deny write, leader deny delete unless admin-account leader).
  10. Confirm multi-worker consistency by repeating read after process restart.
  11. Close maintenance window only after health + audit-log checks pass.
- **Go/No-Go thresholds**:
  - Instance parity: `100%` active instances report target build/version (no mixed writer versions).
  - Normalization guardrail: canonical identity anomaly count `= 0` and duplicate-active anomaly count `= 0`.
  - Smoke matrix: required schedule smoke suite pass rate `100%`.
  - Error guardrail during 15-minute observation: schedule endpoint `5xx/503 < 1%` and auth/scope regression checks all pass.
  - Conflict guardrail: `409` rate remains within expected operational baseline (no sustained abnormal spike).
- **Rollback/contingency**:
  - Do not revert to in-memory authority.
  - If DB schedule operations fail, move schedule writes to temporary maintenance mode (documented `503` behavior) and redeploy last known good DB-backed build after remediation.
  - Rollback triggers: failed instance parity, failed smoke matrix, readiness-gate failures, or breach of error/conflict guardrails.

### Testing Strategy

- Unit/integration-style backend tests in `app/tests/test_mobile_schedules.py` using `unittest` + `TestClient` with deterministic fixtures.
- Replace in-memory global mutation setup with repository-level mocks/doubles for Supabase read/write operations.
- Verify read-path contract stability (`items/scope/filters/pagination/directory`) and field-level compatibility for Flutter parser.
- Verify authorization gates and scope violations preserve existing HTTP status/detail behavior.
- Verify sorting contract and pagination behavior remain stable after DB migration.
- Add explicit tests for DB edge cases: duplicate active assignment conflict, missing schedule update/delete, and unknown assignee linkage handling.
- Run targeted schedule suite and full backend suite to catch regression impact on adjacent mobile endpoints.
- Add contract tests for explicit error status/detail mapping and pagination field presence.
- Add tests for schema-readiness failure path and contingency behavior.
- Add tests for strict `work_date` parsing and timezone-normalized `updated_since` handling.
- Add tests for role/account-role matrix edge cases to prevent auth/scope drift.
- Add tests for delta tombstones (`sync.deleted_schedule_ids`) and client reconciliation behavior after soft-delete.
- Add tests for `snapshot_at` pinned pagination consistency under concurrent create/update/delete events.
- Add tests verifying generic readiness `503` payload versus detailed server-side logs.

### Canonical Identity Audit (Pre-Cutover Required)

Run and require zero-result anomalies before enabling DB-only writes:

- `app_users` canonical check: usernames with `username != lower(trim(username))`
- `schedules` canonical check: active rows with `username != lower(trim(username))`
- duplicate-active check by normalized identity: collisions on `(work_date, lower(trim(username)))` where `deleted_at is null`

If any query returns rows, cutover remains blocked until remediation completes and audits re-pass.

### Adjacent Regression Matrix

Validate adjacent mobile APIs to ensure schedule migration does not regress shared auth/envelope behavior:

| Endpoint Family               | Regression Focus                                            |
| ----------------------------- | ----------------------------------------------------------- |
| `/api/mobile/auth/*`          | token/session continuity, unchanged error semantics         |
| `/api/mobile/me`              | role/account-role claims remain consistent                  |
| `/api/mobile/work-management` | shared pagination/error contract unaffected                 |
| `/api/mobile/incidents`       | shared `updated_since` parsing/lookback behavior unaffected |

Minimum regression gate: targeted schedule suite + full backend suite + matrix spot checks above must pass before release sign-off.

### Notes

- High-risk migration area: preserving exact API payload semantics while changing storage backend.
- Risk mitigation: keep scope/validation logic in API layer and only replace persistence mechanism.
- Do not regress project rule that `username` is canonical identity/sort key; `display_name` remains display-only.
- Optional future enhancement (out of scope): add non-authoritative read caching after DB-only baseline is stable and fully tested.
- Concurrency baseline for this change is deterministic DB atomic operations + uniqueness constraints; optimistic revision tokens can be evaluated in a later story if conflict frequency increases.

## Review Notes

- Adversarial review completed (12 findings surfaced).
- Auto-fix pass applied for repository filtering efficiency, readiness cache recheck behavior, and schedule snapshot guardrails.
- Remaining lower-confidence/intentional-policy findings acknowledged and tracked for future hardening.
- Validation evidence:
  - `python -m unittest tests/test_mobile_schedules.py`
  - `python -m unittest tests/test_mobile_auth.py`
  - `python -m unittest tests/test_mobile_performance_observability.py`
  - `python -m unittest tests/test_mobile_simulation_scenarios.py`
  - Consolidated run: 45 tests passed.
