---
stepsCompleted: [1, 2, 3, 4]
lastStep: 4
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/phase1-mobile-architecture-input.md
  - _bmad-output/project-context.md
  - _bmad-output/planning-artifacts/full-method-kickoff-mobile.md
workflowType: "architecture"
project_name: "EarthRanger"
user_name: "Admin"
date: "2026-03-19"
status: "draft-v1"
---

# Architecture Decision Document

## 1. Executive Summary

This document defines the Phase 1 architecture for EarthRanger mobile capabilities (Work Management, Incident Management read-only, Schedule) with a security-first and offline-capable design.

Primary architecture direction:

- Mobile app accesses data through backend BFF APIs.
- EarthRanger integration and polling are server-side only.
- Role enforcement is backend-enforced (`leader`, `ranger`).
- Ranger check-ins support offline queueing with idempotent replay.

## 2. Architecture Drivers and Constraints

### Drivers

1. Eliminate privileged credential exposure in mobile artifacts.
2. Ensure strict role-scoped access by backend policy.
3. Provide useful UX during intermittent network availability.
4. Respect EarthRanger rate limits and payload variability.
5. Keep implementation aligned with existing FastAPI + Flutter patterns.

### Constraints

- No service-role or ER credentials in mobile package/assets.
- Existing backend conventions must be preserved (`Depends(require_auth)`, rate limiting, request ID propagation, singleton config/clients).
- Incident ownership mapping fields from ER are not fully stable and must be handled defensively.

## 3. Finalized Phase 1 Decisions (Baseline)

### AD-01 — Access Boundary

**Decision:** Adopt BFF architecture (Mobile -> FastAPI -> Supabase/ER mirror).

**Rationale:** Centralizes authorization and secret handling while reducing client attack surface.

**Consequence:** Mobile service layer must be migrated to BFF endpoints before broad feature rollout.

### AD-02 — Authentication Model

**Decision:** Use backend-issued JWT/session model for Phase 1.

**Baseline parameters (configurable):**

- Access token TTL: 15 minutes
- Refresh/session TTL: 7 days
- Role claims embedded and validated server-side each request

**Rationale:** Keeps auth enforcement in one trust boundary and avoids client-side secret dependence.

### AD-03 — Authorization Model

**Decision:** Enforce role scope at backend query layer.

- `ranger`: self-only reads/writes within allowed actions
- `leader`: reads and schedule writes only for rangers with the same `region` and `team`

**Rationale:** UI-only scoping is insufficient for security and data correctness.

### AD-04 — Check-In Semantics

**Decision:** Daily check-in is triggered by authenticated app open and persisted server-side.

- Dedup key: `(user_id, day_key)`
- Client idempotency key: `(user_id, action_type, day_key, client_uuid)`
- Replay-safe response: `created` or `already_exists`

**Rationale:** Guarantees correctness under retries, reconnects, and duplicate submissions.

### AD-05 — Day-Boundary Policy

**Decision:** Use fixed project timezone `Asia/Ho_Chi_Minh` for day-key generation in Phase 1.

**Rationale:** Ensures report consistency across users/devices and prevents drift from device-local clock variance.

### AD-06 — Offline Write Scope

**Decision:** Offline queue allowed only for ranger check-in/stat writes in Phase 1.

- Leader schedule writes remain online-only
- Queue status exposed in UI: `synced`, `pending`, `failed`

**Rationale:** Limits conflict complexity while delivering meaningful offline value.

### AD-07 — ER Sync Strategy

**Decision:** Server-side incremental ER sync using cursor/high-watermark.

- No mobile fan-out polling against ER
- Configurable cadence + exponential backoff with jitter on throttling/errors

**Rationale:** Controls external API pressure and improves reliability.

### AD-08 — Schedule Source of Truth

**Decision:** Backend-managed schedule entity in Supabase/Postgres is canonical for Phase 1.

**Rationale:** Simplifies write validation, role enforcement, and mobile consistency.

### AD-09 — Incident Ownership Mapping

**Decision:** Use a mapping adapter with deterministic precedence and fallback.

**Baseline approach:**

1. Preferred identity fields (configurable precedence list)
2. If unresolved, classify as `unmapped` and exclude from ranger self-view until resolved
3. Log mapping misses for operations review

**Rationale:** ER payload variability requires a defensive and auditable mapping layer.

### AD-10 — Retry and Dead-Letter Policy

**Decision:** Queue retry with exponential backoff.

- Initial delay: 5s
- Max delay: 15m
- Max attempts: 8
- After exhaustion: `failed` state with manual retry option

**Rationale:** Balances battery/network efficiency and delivery reliability.

## 4. Logical Architecture

### 4.1 Mobile App (Flutter)

Responsibilities:

- Present role-scoped views and sync status
- Cache read models locally
- Queue offline ranger writes
- Call BFF APIs only

Key boundaries:

- `providers/`: state + lifecycle (`loading/error/ready`)
- `services/`: API/auth/session/sync orchestration
- local persistence: structured store for incidents/schedules/work summaries and queue records

### 4.2 Backend API (FastAPI BFF)

Proposed modules:

- `mobile_auth`: login/refresh/logout/me
- `mobile_work`: check-in ingest + work summary reads
- `mobile_incidents`: read-only incident feed
- `mobile_schedules`: schedule reads/writes
- `er_sync`: ER ingest job + cursor state

Cross-cutting:

- `Depends(require_auth)` + role guard dependency
- existing request-id middleware
- endpoint rate limiting
- structured logging and auditable event IDs

### 4.3 Data and Integration Layer

- Supabase/Postgres as operational store
- ER incident mirror/read-model tables for mobile consumption
- idempotency log for replay-safe writes
- retention process for 6+ months of stats

## 5. Data Model v1 (Architecture Baseline)

1. `users`
   - `id`, `role`, `region`, `team`, `status`
2. `daily_checkins`
   - `id`, `user_id`, `day_key`, `first_checkin_at`, `source`, `idempotency_key`
   - unique index: `(user_id, day_key)`
3. `schedules`
   - `id`, `ranger_id`, `work_date`, `assigned_by`, `note`, `created_at`, `updated_at`
4. `incidents_mirror`
   - `er_event_id`, `occurred_at`, `updated_at`, `mapped_ranger_id`, `mapping_status`, `payload_ref`
5. `sync_cursors`
   - `stream_name`, `cursor_value`, `updated_at`
6. `idempotency_log`
   - `idempotency_key`, `endpoint`, `status`, `first_seen_at`, `last_seen_at`

## 6. API Contract v1 (Baseline)

### 6.1 Auth

- `POST /api/mobile/auth/login`
- `POST /api/mobile/auth/refresh`
- `POST /api/mobile/auth/logout`
- `GET /api/mobile/me`

### 6.2 Work Management / Check-In

- `POST /api/mobile/checkins`
  - input: `idempotency_key`, `client_time`, `timezone`, `app_version`
  - output: `status`, `day_key`, `server_time`
- `GET /api/mobile/work-management?from=&to=&ranger_id=`

### 6.3 Incidents (Read-only)

- `GET /api/mobile/incidents?from=&to=&updated_since=&ranger_id=&cursor=`

### 6.4 Schedule

- `GET /api/mobile/schedules?from=&to=&ranger_id=`
- `POST /api/mobile/schedules` (leader only)
- `PUT /api/mobile/schedules/{schedule_id}` (leader only)

### 6.5 Error Contract (Common)

- Standard JSON error payload with:
  - `code`
  - `message`
  - `request_id`
  - optional `details`

## 7. Security Architecture Controls

1. Remove privileged secrets from mobile app assets and build config.
2. Rotate service-role and related secrets before release if exposure is suspected.
3. Restrict CORS origins per environment; no production wildcard.
4. Harden token/session management and revocation path.
5. Require webhook secret verification in production mode.
6. Keep ER credentials strictly server-side.

## 8. Sync and Caching Design

### Read Path

- Cache-first render for incidents/schedules/work summary
- Background refresh from backend when online
- Incremental fetch via `updated_since`/cursor metadata

### Write Path (ranger check-ins)

- Offline enqueue when network unavailable
- Replay queue on reconnect/app resume
- Idempotent backend processing on each replay

### Conflict and Failure Handling

- Check-in conflicts resolve to existing daily record (no duplicate)
- Exhausted retries move record to `failed`
- User-facing manual retry for failed writes

## 9. Non-Functional Alignment

- Performance: pagination/filtering and incremental payloads required for mobile endpoints.
- Reliability: deterministic role-scoped responses and replay-safe writes.
- Maintainability: keep existing backend/mobile module patterns and mockable service boundaries.
- Observability: preserve request IDs and structured logs for distributed troubleshooting.

## 10. Delivery Gates for Implementation Start

### Gate A — Security Baseline

- Secret removal from mobile complete
- Key rotation completed where needed
- BFF boundary enforced

### Gate B — Contract Readiness

- API contract v1 approved
- Role guard behavior verified by tests

### Gate C — Sync Readiness

- Queue semantics finalized and tested
- Cache + refresh behavior validated
- Sync status UX validated

## 11. Implementation Sequence (Approved Order)

1. Security hardening (secrets + key rotation + boundary).
2. Auth/session + role guard foundations.
3. Check-in ingest + work management reads.
4. Incident read endpoint over ER mirror.
5. Schedule read/write APIs.
6. Mobile cache + sync queue integration.
7. Test pass for authorization, idempotency, and offline replay.

## 12. Remaining Confirmation Items

1. Final ER incident identity precedence list (exact field names in production payloads).
2. Team-scope rules for leaders in multi-region edge cases.
3. Retention execution schedule (batch window + archival behavior).

## 13. Decision Addendum — Confirmation Item Resolution (2026-03-19)

This addendum closes Section 12 for Phase 1 planning readiness by explicitly resolving or deferring each confirmation item.

### Item 12.1 — ER incident identity precedence list

**Status:** Deferred with interim policy (accepted for Phase 1 start)

**Interim precedence policy:**

1. Use explicit ranger-assigned identity fields from ER payload when present.
2. If unavailable, use configured user-identity mapping adapter precedence.
3. If unresolved after mapping attempts, classify as `unmapped`, exclude from ranger self-view, and emit structured mapping-miss logs.

**Follow-up decision target:** finalize exact field names after production payload sampling in first implementation sprint.

### Item 12.2 — Team-scope rules for leaders in multi-region cases

**Status:** Resolved

**Decision:**

- Leader read/write scope is constrained to backend assignments where both `region` and `team` match the target ranger.
- Additional filters are additive (can narrow scope) and never broaden beyond assigned `region + team` scope.
- Cross-region access requires explicit backend-admin grant and is not implied by role alone.

### Item 12.3 — Retention execution schedule

**Status:** Resolved

**Decision:**

- Retention job runs daily at 01:30 `Asia/Ho_Chi_Minh`.
- Operational ranger stats are retained for a minimum of 6 months.
- Aggregation and cleanup runs are auditable via job execution logs and replay markers.

**Implementation note:** retention failures must emit actionable alerts and support replay.

---

This architecture draft is ready to feed `bmad-check-implementation-readiness` once the three confirmation items above are approved or explicitly deferred.

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
The requirement set is dominated by security-boundary and authorization correctness: no privileged secrets in mobile artifacts, backend-only access for business data, authenticated access before endpoint consumption, and strict role enforcement on all protected routes. Functional flows require robust daily check-in idempotency, role-scoped incident/schedule visibility, offline queue replay safety, and server-side incremental EarthRanger synchronization.

**Non-Functional Requirements:**
NFRs strongly shape architecture toward secure token/session handling (revocation strategy and hardened production config), deterministic role-scoped API behavior, retry-tolerant reliability under intermittent connectivity, bounded/paginated query patterns, and testable/mockable integration boundaries. Observability and request correlation are mandatory for operational troubleshooting.

**Scale & Complexity:**
EarthRanger Phase 1 combines mobile UX, backend authorization, and external integration into a tightly coupled reliability model. The architecture must handle token/session state, queue replay semantics, and role-safe data projections consistently across endpoints and runtimes.

- Primary domain: Mobile + backend BFF integration platform
- Complexity level: High
- Estimated architectural components: 11-13 major components (auth/session service, role guard layer, mobile APIs, sync worker, idempotency service, cache/queue subsystem, observability plane, retention/audit pipeline, and security governance controls)

### Technical Constraints & Dependencies

- Backend is the sole trust boundary for privileged keys and EarthRanger integration.
- Existing FastAPI conventions must be preserved (`Depends(require_auth)`, rate limits, request ID propagation, structured logging).
- Offline support is required but constrained: ranger check-in/stat writes only; leader schedule writes remain online-only.
- Daily check-in semantics require deterministic day-key policy and server-side deduplication.
- Integration must tolerate EarthRanger payload variability and rate limiting via incremental cursor sync and backoff.
- Existing implementation context already enforces security baselines (no mobile secret leakage, production secret hardening, and revocation expectations).

### Cross-Cutting Concerns Identified

- Token/session lifecycle architecture (issue, validate, refresh, revoke, rotate)
- Secret classification and storage policy by environment and purpose
- Role-based authorization and scope isolation at API and query layers
- Idempotency and replay safety for offline and retry-heavy paths
- Observability for auth and sync flows (correlation IDs, audit events, anomaly detection)
- Production security guardrails (CORS restrictions, webhook secret enforcement, key rotation drills)

## Starter Template Evaluation

### Primary Technology Domain

**Brownfield mobile + backend BFF platform** based on project requirements and current implementation baseline:

- Backend API: FastAPI + Uvicorn + Supabase integration
- Mobile app: Flutter client consuming BFF endpoints
- Security boundary: backend-only privileged credentials and EarthRanger integration

### Starter Options Considered

1. **Brownfield continuation (in-place hardening)** — preserve existing FastAPI/Flutter architecture and implement token governance controls directly in current modules.
2. **FastAPI full-stack starter (latest release observed: 0.10.0)** — modern starter ecosystem, but introduces significant framework and structure drift versus current production codebase.
3. **Flutter fresh scaffold paths (`flutter create` and Very Good CLI, latest release observed: v1.1.0)** — useful for new apps/modules, but not aligned with current integrated backend/mobile repository state.

### Selected Starter: Brownfield Continuation (No Re-Scaffold)

**Rationale for Selection:**

- Token lifecycle, storage boundaries, revocation, and rotation policy are **governance/security architecture** tasks, not greenfield scaffolding tasks.
- Existing project already has validated structure, security guardrails, and implementation artifacts; replacing foundation now would increase risk and delay hardening outcomes.
- Brownfield continuation preserves operational continuity while allowing immediate enforcement of token-purpose separation and rotation policy.

**Initialization Command:**

```bash
# No new project scaffold selected.
# Continue in-place within the current EarthRanger repository.
```

**Architectural Decisions Provided by Selected Foundation:**

**Language & Runtime:**

- Python backend runtime with FastAPI service conventions
- Flutter/Dart mobile runtime for client UX and offline queue behavior

**Styling Solution:**

- Existing mobile UI patterns retained (no new starter-imposed design system)

**Build Tooling:**

- Existing backend/mobile build and deployment paths retained
- No disruptive build-system migration introduced at this stage

**Testing Framework:**

- Existing repository testing strategy remains authoritative for implementation stories

**Code Organization:**

- Preserve current module boundaries (`mobile_auth`, `mobile_work`, `mobile_incidents`, `mobile_schedules`, sync jobs)
- Apply token-governance changes incrementally inside established architecture

**Development Experience:**

- Fastest path for secure delivery: harden current code instead of replatforming
- Keeps team context and artifacts compatible with approved phase planning

**Version Validation Notes (web-verified during starter research):**

- FastAPI latest stable observed: **0.135.2**
- Uvicorn latest stable observed: **0.42.0**
- FastAPI full-stack template active and maintained (latest release observed: **0.10.0**)
- Very Good CLI active and maintained (latest release observed: **v1.1.0**)

**Note:** Implementation should start with in-place architecture hardening stories rather than repository re-scaffolding.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**

- Classify tokens/secrets by purpose and environment (no shared long-lived catch-all token usage).
- Persist mobile auth session state in durable storage for production reliability/auditability (in-memory-only state is insufficient for restart/failover scenarios).
- Enforce refresh-token rotation and reuse detection.
- Define explicit revocation paths (single-session, user-wide, and incident-wide).
- Keep privileged credentials in backend-only secret boundaries.

**Important Decisions (Shape Architecture):**

- Audit logging model for token issue/refresh/revoke/rotate events.
- Runbook-driven scheduled and emergency key/token rotation process.
- Mobile secure storage and refresh retry behavior standardization.

**Deferred Decisions (Post-MVP):**

- External IdP/OIDC federation.
- Hardware-backed key custody and automated key lifecycle platform integration.

### Data Architecture

**Session/Token Persistence Model:**

- Introduce durable auth/session tables in Supabase/Postgres:
  - `auth_refresh_sessions`
  - `auth_access_sessions` (or equivalent access-session index)
  - `auth_revocation_events`
  - `auth_secret_rotation_audit`
- Persist token fingerprints/hashes and metadata only; never store plaintext bearer tokens.
- Track lineage fields (`replaced_by`, `revoked_at`, `revoked_reason`) to support forensic and incident operations.

**Validation & Retention:**

- Access token validation remains short-lived and fast.
- Refresh-session records must support cleanup policy and replay/reuse detection history.
- Retention windows for auth audit data must be long enough for incident response and compliance review.

### Authentication & Security

**Token Classes by Purpose:**

1. `ER_INTEGRATION_TOKEN` (backend-only machine-to-machine credential)
2. `MOBILE_ACCESS_TOKEN` (short-lived bearer for API access)
3. `MOBILE_REFRESH_TOKEN` (session continuity token)
4. `SESSION_SECRET` (server-side signing/session protection)
5. `WEBHOOK_SECRET` (inbound webhook signature verification)

**Lifecycle Policy:**

- Access token TTL remains short-lived (baseline: 15 minutes).
- Refresh token TTL remains bounded (baseline: 7 days) with rotation on every successful refresh.
- Refresh token reuse detection triggers immediate revocation of the associated session family.

**Storage Boundary Policy:**

- Privileged credentials are backend-runtime only.
- Mobile clients must never embed privileged service tokens/secrets.
- Environment separation is mandatory (`dev`, `staging`, `prod`) with distinct secret sets.

**Revocation Policy:**

- User logout revokes the submitted refresh token and all linked active access tokens.
- Security event handling supports user-wide revocation and incident-wide emergency revocation.
- Revocation actions emit structured audit events with request correlation IDs.

**Rotation Policy:**

- Scheduled rotation target:
  - ER integration token: rotate at fixed cadence (recommended maximum 90 days)
  - Session/webhook secrets: rotate at fixed cadence (recommended maximum 90 days)
- Immediate emergency rotation when exposure is suspected.

### API & Communication Patterns

**Auth Endpoints (retained and hardened):**

- `POST /api/mobile/auth/login`
- `POST /api/mobile/auth/refresh`
- `POST /api/mobile/auth/logout`
- `GET /api/mobile/me`

**Contract Rules:**

- Refresh returns a fresh access token and rotated refresh token.
- Logout revokes refresh token lineage for that session.
- Auth failures return consistent 401 payloads with request correlation.
- Rate limits remain enabled on auth routes.

### Frontend Architecture

**Client Token Handling:**

- Keep access token memory-first where possible.
- Store refresh token only in platform secure storage.
- On refresh reuse/invalid token response, clear local auth state and force re-authentication.

**Offline Interaction:**

- Offline queue behavior remains decoupled from privileged secrets.
- Queue replay must tolerate expired access token by invoking refresh flow first.

### Infrastructure & Deployment

**Environment Security Controls:**

- Development may use local `.env` during active development.
- Staging/production must use managed runtime secret distribution and strict environment isolation.

**Observability Requirements:**

- Mandatory auth event telemetry for login success/failure, refresh success/failure, revoke, and rotation actions.
- Preserve request ID propagation across auth workflows.

**Version Validation Notes (web-verified):**

- FastAPI: **0.135.2** (released Mar 23, 2026)
- Uvicorn: **0.42.0** (released Mar 16, 2026)

### Decision Impact Analysis

**Implementation Sequence:**

1. Add durable session/token persistence schema and migration.
2. Refactor auth issue/refresh/logout to durable session model.
3. Implement refresh-token rotation + reuse detection safeguards.
4. Add admin/security revocation controls and audit events.
5. Implement scheduled + emergency rotation runbooks and checks.

**Cross-Component Dependencies:**

- Mobile refresh/logout behavior depends on backend refresh rotation and revocation semantics.
- Incident response process depends on complete audit and revocation coverage.
- Secret hygiene controls in CI/release checks depend on stable token classification and environment policy.
