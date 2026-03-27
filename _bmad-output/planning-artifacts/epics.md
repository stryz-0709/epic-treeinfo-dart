---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/phase1-mobile-prd-input.md
  - _bmad-output/planning-artifacts/phase1-mobile-architecture-input.md
---

# EarthRanger - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for EarthRanger, decomposing the requirements from the PRD, UX Design (if present), and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

FR-SEC-001: Mobile app MUST NOT contain Supabase service-role key, ER credentials, or other privileged secrets.
FR-SEC-002: All mobile business data access MUST go through backend BFF APIs.
FR-AUTH-001: App MUST use production authentication flow (no hardcoded credentials).
FR-AUTH-002: Backend MUST issue/validate authenticated session/token before data endpoints are accessed.
FR-AUTH-003: Role claims (`leader`, `ranger`) MUST be enforced server-side for every protected endpoint.
FR-SEC-003: If direct mobile Supabase access is used for any limited case, only anon key + strict RLS is permitted.
FR-WM-001: System MUST display a calendar with per-day work summary.
FR-WM-002: System MUST display check-in indicator for days with confirmed check-in.
FR-WM-003: App-open check-in MUST be tied to authenticated user identity.
FR-WM-004: Backend MUST guarantee one effective check-in per user/day (`user_id + day_key` uniqueness).
FR-WM-005: Leader view MUST support ranger filter/drop-list.
FR-WM-006: Ranger view MUST show self records only.
FR-INC-001: System MUST display incidents from EarthRanger-backed sync data.
FR-INC-002: Ranger MUST see only incidents mapped to that ranger identity.
FR-INC-003: Leader MUST see all ranger incidents within authorized scope.
FR-INC-004: Incident creation/edit operations are not available in Phase 1.
FR-SCH-001: System MUST display day-to-ranger schedule assignments.
FR-SCH-002: Ranger MUST see only own schedule.
FR-SCH-003: Leader MUST be able to create/update schedules online.
FR-SCH-004: Schedule write actions MUST enforce role and payload validation on backend.
FR-SYNC-001: App MUST cache Work Management, Incident, and Schedule data for offline read.
FR-SYNC-002: Ranger check-in/stat actions MUST queue when offline.
FR-SYNC-003: Each queued write MUST include idempotency key (`user_id + action_type + day_key + client_uuid`).
FR-SYNC-004: Backend write endpoints MUST be idempotent and safe for repeated replay.
FR-SYNC-005: Queue MUST implement retry with exponential backoff + jitter.
FR-SYNC-006: App MUST show sync status (synced/pending/failed) to user.
FR-INT-001: EarthRanger polling MUST be server-side only.
FR-INT-002: EarthRanger sync MUST be incremental cursor-based (high-watermark/updated_since).
FR-INT-003: Mobile refresh endpoints SHOULD support conditional/incremental fetch patterns.
FR-INT-004: Ranger stats retention MUST keep at least 6 months of operational data.

### NonFunctional Requirements

NFR-SEC-001: No privileged credentials in distributed mobile artifacts.
NFR-SEC-002: Production cookies/tokens and session handling must be hardened (secure flags and revocation strategy).
NFR-SEC-003: CORS in production must be restricted to approved origins.
NFR-SEC-004: Webhook signature validation must be enforced in production (no empty-secret bypass).
NFR-REL-001: Daily check-in deduplication accuracy target: 100% for same user/day duplicates.
NFR-REL-002: Offline replay must tolerate duplicate submission and intermittent connectivity.
NFR-REL-003: APIs must return deterministic role-scoped results.
NFR-PERF-001: Team/ranger list and calendar queries should support pagination/filtering.
NFR-PERF-002: Server must avoid full-table scans for routine mobile list endpoints where feasible.
NFR-PERF-003: Sync endpoints should minimize payload via incremental updates.
NFR-MNT-001: Network/integration logic must be mockable for tests.
NFR-MNT-002: Mobile state and service layers must follow existing Provider/service boundaries.
NFR-MNT-003: Backend changes must preserve existing API compatibility where already consumed.

### Additional Requirements

- Architecture boundary: BFF pattern is mandatory (mobile -> FastAPI -> data/integrations); no direct ER access from mobile.
- Auth baseline: backend-issued access token + refresh/session model; role claims validated server-side per request.
- Day-boundary policy baseline: fixed project timezone `Asia/Ho_Chi_Minh` for check-in day key.
- Queue policy baseline: exponential backoff (initial 5s, max 15m), maximum 8 attempts, then failed/manual retry.
- ER sync model: server-side incremental sync with cursor/high-watermark and rate-limit-safe backoff.
- Schedule source-of-truth baseline: backend-managed schedule entity in Supabase/Postgres.
- Incident mapping baseline: deterministic field precedence with `unmapped` fallback handling and mapping-miss logging.
- Security controls: remove privileged mobile secrets, rotate keys if exposed, restrict production CORS, enforce webhook secret checks.
- Data model baseline includes `daily_checkins`, `schedules`, `incidents_mirror`, `sync_cursors`, and `idempotency_log` with uniqueness constraints.
- Delivery gates: security baseline, API contract readiness, and sync readiness must pass before broad implementation.

### UX Design Requirements

No standalone UX design document was found.

Derived UX requirements from PRD/Architecture:

UX-DR-001: Define calendar interaction behaviors for ranger and leader roles (date navigation, indicator legend, loading/empty/error states).
UX-DR-002: Define leader ranger-filter UX (drop-list behavior, default selection scope, no-data messaging).
UX-DR-003: Define incident list/detail display states including offline cache fallback and stale-data indicator.
UX-DR-004: Define schedule view and leader edit affordances with role-restricted actions and clear error messages.
UX-DR-005: Define sync status UI states (`synced`, `pending`, `failed`) and manual retry interaction for failed offline writes.

### FR Coverage Map

FR-SEC-001: Epic 1 - Secure Mobile Access & Role-Safe Authentication
FR-SEC-002: Epic 1 - Secure Mobile Access & Role-Safe Authentication
FR-AUTH-001: Epic 1 - Secure Mobile Access & Role-Safe Authentication
FR-AUTH-002: Epic 1 - Secure Mobile Access & Role-Safe Authentication
FR-AUTH-003: Epic 1 - Secure Mobile Access & Role-Safe Authentication
FR-SEC-003: Epic 1 - Secure Mobile Access & Role-Safe Authentication
FR-WM-001: Epic 2 - Ranger Work Management Calendar & Daily Check-In
FR-WM-002: Epic 2 - Ranger Work Management Calendar & Daily Check-In
FR-WM-003: Epic 2 - Ranger Work Management Calendar & Daily Check-In
FR-WM-004: Epic 2 - Ranger Work Management Calendar & Daily Check-In
FR-WM-005: Epic 2 - Ranger Work Management Calendar & Daily Check-In
FR-WM-006: Epic 2 - Ranger Work Management Calendar & Daily Check-In
FR-INC-001: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-INC-002: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-INC-003: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-INC-004: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-SCH-001: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-SCH-002: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-SCH-003: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-SCH-004: Epic 3 - Incident Visibility & Leader Schedule Operations
FR-SYNC-001: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-SYNC-002: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-SYNC-003: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-SYNC-004: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-SYNC-005: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-SYNC-006: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-INT-001: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-INT-002: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-INT-003: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations
FR-INT-004: Epic 4 - Offline Sync Reliability & EarthRanger Data Operations

## Epic List

### Epic 1: Secure Mobile Access & Role-Safe Authentication

Deliver a secure sign-in/session foundation so leaders and rangers can access only the data and actions they are authorized to use.
**FRs covered:** FR-SEC-001, FR-SEC-002, FR-AUTH-001, FR-AUTH-002, FR-AUTH-003, FR-SEC-003

### Epic 2: Ranger Work Management Calendar & Daily Check-In

Enable role-aware Work Management calendar views and reliable once-per-day check-in behavior so ranger activity is visible and accurate.
**FRs covered:** FR-WM-001, FR-WM-002, FR-WM-003, FR-WM-004, FR-WM-005, FR-WM-006

### Epic 3: Incident Visibility & Leader Schedule Operations

Deliver incident visibility and schedule workflows so rangers can track personal operations and leaders can plan team assignments.
**FRs covered:** FR-INC-001, FR-INC-002, FR-INC-003, FR-INC-004, FR-SCH-001, FR-SCH-002, FR-SCH-003, FR-SCH-004

### Epic 4: Offline Sync Reliability & EarthRanger Data Operations

Provide robust offline sync and backend integration behavior so data remains consistent, resilient, and timely under variable connectivity.
**FRs covered:** FR-SYNC-001, FR-SYNC-002, FR-SYNC-003, FR-SYNC-004, FR-SYNC-005, FR-SYNC-006, FR-INT-001, FR-INT-002, FR-INT-003, FR-INT-004

## Epic 1: Secure Mobile Access & Role-Safe Authentication

Deliver a secure sign-in/session foundation so leaders and rangers can access only the data and actions they are authorized to use.

### Story 1.1: Backend Login with Role Claims

As a ranger or leader,
I want to sign in through backend authentication,
So that my session and role are trusted by server-side authorization.

**Implements:** FR-SEC-002, FR-AUTH-001, FR-AUTH-002, FR-AUTH-003

**Acceptance Criteria:**

1.  **Given** valid user credentials
    **When** the client calls `POST /api/mobile/auth/login`
    **Then** the backend returns a valid access token, refresh/session token, and role claim
    **And** no privileged service credentials are returned in the response.

2.  **Given** invalid credentials
    **When** the client calls `POST /api/mobile/auth/login`
    **Then** the backend returns an authentication error
    **And** no session is created.

### Story 1.2: Secure Session Refresh and Logout

As an authenticated mobile user,
I want secure session refresh and logout behavior,
So that I can continue safely without re-login churn and terminate sessions when needed.

**Implements:** FR-AUTH-002, FR-AUTH-003

**Acceptance Criteria:**

1.  **Given** an expired access token and valid refresh/session token
    **When** the client calls `POST /api/mobile/auth/refresh`
    **Then** the backend issues a new access token
    **And** preserves role scope claims.

2.  **Given** an authenticated session
    **When** the client calls `POST /api/mobile/auth/logout`
    **Then** the refresh/session token is invalidated
    **And** subsequent refresh attempts fail.

### Story 1.3: Server-Side Role Guard for Mobile Endpoints

As a security owner,
I want role and scope enforcement on every mobile endpoint,
So that ranger and leader data boundaries cannot be bypassed from the client.

**Implements:** FR-AUTH-003, FR-WM-006, FR-INC-002, FR-SCH-002

**Acceptance Criteria:**

1.  **Given** a ranger token
    **When** the user requests another ranger's data
    **Then** the backend denies the request
    **And** only self-scoped data is returned for ranger queries.

2.  **Given** a leader token
    **When** the user requests team-scoped data
    **Then** the backend returns authorized team data
    **And** schedule write endpoints are allowed only for leader role.

### Story 1.4: Secret Hygiene and Production Security Baseline

As a platform security owner,
I want privileged secrets removed from mobile builds and hardened backend security defaults,
So that release artifacts and runtime policies meet Phase 1 security requirements.

**Implements:** FR-SEC-001, FR-SEC-003

**Acceptance Criteria:**

1.  **Given** a production mobile build
    **When** build assets are inspected
    **Then** no Supabase service-role key or ER credentials are present
    **And** only approved non-privileged configuration is packaged.

2.  **Given** backend startup in production mode
    **When** security configuration is validated
    **Then** wildcard CORS is rejected
    **And** webhook secret enforcement is active.

## Epic 2: Ranger Work Management Calendar & Daily Check-In

Enable role-aware Work Management calendar views and reliable once-per-day check-in behavior so ranger activity is visible and accurate.

### Story 2.1: Work Management Summary API for Calendar Views

As a leader or ranger,
I want a role-scoped Work Management summary endpoint,
So that the mobile app can render per-day check-in indicators accurately.

**Implements:** FR-WM-001, FR-WM-002, FR-WM-005, FR-WM-006

**Acceptance Criteria:**

1.  **Given** a date range and authenticated user
    **When** the client calls `GET /api/mobile/work-management`
    **Then** the backend returns per-day summary data with check-in indicator fields
    **And** the response is scoped to user role and ranger filter rules.

2.  **Given** large result sets
    **When** queries are executed
    **Then** pagination/filtering controls are supported
    **And** response time remains within defined service expectations.

### Story 2.2: Idempotent Check-In Ingest Endpoint

As a ranger,
I want app-open check-ins to be deduplicated by day,
So that my attendance is correct even with retries and repeated app opens.

**Implements:** FR-WM-003, FR-WM-004

**Acceptance Criteria:**

1.  **Given** an authenticated ranger and a check-in request
    **When** `POST /api/mobile/checkins` is called
    **Then** the backend computes `day_key` using project timezone `Asia/Ho_Chi_Minh`
    **And** persists at most one effective check-in record per user/day.

2.  **Given** a repeat submission for the same `user_id + day_key`
    **When** the request is processed
    **Then** the backend returns `already_exists`
    **And** no duplicate check-in row is created.

### Story 2.3: Mobile App-Open Check-In Trigger

As a ranger,
I want check-in to happen automatically on authenticated app open,
So that I do not need a separate manual attendance action.

**Implements:** FR-WM-003, FR-WM-004

**Acceptance Criteria:**

1.  **Given** a ranger with valid session
    **When** the app enters foreground on a new day
    **Then** the client submits a check-in request automatically
    **And** updates the local day indicator from the server response.

2.  **Given** the same day and repeated app opens
    **When** check-in is triggered again
    **Then** the UI remains stable
    **And** no duplicate daily check-in appears.

### Story 2.4: Work Management Calendar UX by Role

As a leader or ranger,
I want a clear Work Management calendar UI with role-appropriate controls,
So that I can quickly understand check-in coverage.

**Implements:** FR-WM-001, FR-WM-002, FR-WM-005, FR-WM-006

**Acceptance Criteria:**

1.  **Given** a leader user
    **When** opening Work Management
    **Then** a ranger filter/drop-list is available
    **And** the selected ranger/team scope is reflected in calendar data.

2.  **Given** a ranger user
    **When** opening Work Management
    **Then** only self calendar data is shown
    **And** no controls for viewing other rangers are displayed.

3.  **Given** loading, empty, or error states
    **When** the calendar screen renders
    **Then** clear UX states are shown
    **And** they align with UX-DR-001 and UX-DR-002.

## Epic 3: Incident Visibility & Leader Schedule Operations

Deliver incident visibility and schedule workflows so rangers can track personal operations and leaders can plan team assignments.

### Story 3.1: Read-Only Incident API with Role Scope

As a leader or ranger,
I want incident data served from backend mirrored ER data,
So that incident visibility is reliable without direct ER mobile calls.

**Implements:** FR-INC-001, FR-INC-002, FR-INC-003, FR-INC-004

**Acceptance Criteria:**

1.  **Given** an authenticated request to `GET /api/mobile/incidents`
    **When** the backend resolves role and query filters
    **Then** ranger users receive self incidents only
    **And** leader users receive authorized team incidents.

2.  **Given** incident endpoints in Phase 1
    **When** clients inspect available actions
    **Then** create/edit operations are not exposed
    **And** read-only behavior is enforced server-side.

### Story 3.2: Incident List UX with Operational States

As a ranger or leader,
I want incident lists to show meaningful data and state feedback,
So that I can act on incident context even with stale or partial refreshes.

**Implements:** FR-INC-001, FR-INC-002, FR-INC-003

**Acceptance Criteria:**

1.  **Given** incident data returned by API
    **When** the incident list screen renders
    **Then** records reflect role scope correctly
    **And** no cross-ranger leakage appears for ranger users.

2.  **Given** empty, loading, stale, or refresh-error conditions
    **When** the screen updates
    **Then** clear UX state messaging is shown
    **And** behavior aligns with UX-DR-003.

### Story 3.3: Schedule Read and Leader Write APIs

As a leader or ranger,
I want schedule data to be role-scoped with leader-only write access,
So that assignments are managed correctly and safely.

**Implements:** FR-SCH-001, FR-SCH-002, FR-SCH-003, FR-SCH-004

**Acceptance Criteria:**

1.  **Given** `GET /api/mobile/schedules`
    **When** called by ranger
    **Then** only self schedule entries are returned
    **And** other ranger entries are excluded.

2.  **Given** `POST` or `PUT` schedule endpoints
    **When** called by leader
    **Then** schedule changes are validated and persisted
    **And** audit fields capture updater identity and timestamp.

3.  **Given** schedule write request by non-leader user
    **When** authorization is evaluated
    **Then** the request is denied
    **And** a clear authorization error is returned.

### Story 3.4: Schedule UX for Ranger View and Leader Operations

As a ranger or leader,
I want schedule screens tailored to my role,
So that I can view or manage assignments with minimal confusion.

**Implements:** FR-SCH-001, FR-SCH-002, FR-SCH-003

**Acceptance Criteria:**

1.  **Given** a ranger user
    **When** opening schedule screen
    **Then** schedule entries are visible in read-only mode
    **And** edit controls are hidden.

2.  **Given** a leader user
    **When** creating or editing schedule entries online
    **Then** the UI validates required fields and server errors
    **And** successful changes refresh visible schedule data.

3.  **Given** UX design requirements for schedule states
    **When** schedule UI is implemented
    **Then** role actions, empty states, and error messages align with UX-DR-004.

## Epic 4: Offline Sync Reliability & EarthRanger Data Operations

Provide robust offline sync and backend integration behavior so data remains consistent, resilient, and timely under variable connectivity.

### Story 4.1: Server-Side Incremental EarthRanger Sync Worker

As an operations platform,
I want incidents synchronized from EarthRanger using incremental cursors,
So that incident visibility remains up to date without exceeding rate limits.

**Implements:** FR-INT-001, FR-INT-002

**Acceptance Criteria:**

1.  **Given** configured ER integration credentials on backend
    **When** sync job runs
    **Then** it requests updates using `updated_since`/high-watermark cursor
    **And** stores cursor state for next run.

2.  **Given** rate-limit or transient ER failures
    **When** sync retries are executed
    **Then** exponential backoff with jitter is applied
    **And** errors are logged with traceable context.

### Story 4.2: Mobile Cache-First Read Models

As a mobile user,
I want cached Work Management, Incident, and Schedule data available offline,
So that I can continue reading operational context during connectivity loss.

**Implements:** FR-SYNC-001, FR-INT-003

**Acceptance Criteria:**

1.  **Given** previously synced data
    **When** device is offline
    **Then** calendar, incident, and schedule screens render cached records
    **And** show stale/offline indicators where applicable.

2.  **Given** network reconnect
    **When** refresh is triggered
    **Then** incremental updates are fetched and merged
    **And** cache is updated without duplicating records.

### Story 4.3: Offline Queue and Idempotent Replay for Ranger Writes

As a ranger,
I want offline check-in/stat actions queued and replayed safely,
So that my attendance records remain correct after reconnect.

**Implements:** FR-SYNC-002, FR-SYNC-003, FR-SYNC-004, FR-SYNC-005

**Acceptance Criteria:**

1.  **Given** offline state during check-in/stat action
    **When** action is captured
    **Then** queue item is saved with idempotency key format `user_id + action_type + day_key + client_uuid`
    **And** item is marked pending.

2.  **Given** reconnect and replay cycle
    **When** queued items are submitted
    **Then** backend idempotency guarantees prevent duplicates
    **And** retries follow configured backoff policy (initial 5s, max 15m, max 8 attempts).

### Story 4.4: Sync Status UX and Manual Retry Flow

As a mobile user,
I want visible sync status and retry controls,
So that I understand whether my offline actions are safely persisted.

**Implements:** FR-SYNC-006

**Acceptance Criteria:**

1.  **Given** queued actions in mixed states
    **When** sync status UI renders
    **Then** each action is shown as `synced`, `pending`, or `failed`
    **And** status transitions are reflected in near real time.

2.  **Given** failed queued actions
    **When** user selects retry
    **Then** replay is re-attempted with current connectivity context
    **And** UX behavior aligns with UX-DR-005.

### Story 4.5: Retention and Compliance Operations

As a product and operations team,
I want retention controls implemented for ranger statistics,
So that Phase 1 meets data-lifecycle requirements and remains auditable.

**Implements:** FR-INT-004

**Acceptance Criteria:**

1.  **Given** operational data lifecycle requirements
    **When** retention jobs execute
    **Then** ranger stats data is retained for at least 6 months
    **And** aggregation/cleanup behavior is auditable.

2.  **Given** retention jobs are deployed
    **When** a scheduled run fails or is skipped
    **Then** the failure is logged with request/job correlation metadata
    **And** operators can identify and replay the failed retention run.

### Story 4.6: Performance and Observability Hardening

As a platform owner,
I want mobile-facing endpoints optimized and observable,
So that performance remains stable and production troubleshooting is fast.

**Implements:** NFR-PERF-001, NFR-PERF-002, NFR-PERF-003, NFR-MNT-001

**Acceptance Criteria:**

1.  **Given** mobile list and summary endpoints
    **When** requests are processed under normal load
    **Then** pagination/filtering and incremental payload practices are applied
    **And** endpoints avoid unnecessary full-table scans.

2.  **Given** API requests across auth, work-management, incidents, schedules, and sync flows
    **When** logs and traces are reviewed
    **Then** request IDs and structured log fields support end-to-end correlation
    **And** key error/performance events are visible for operations monitoring.

## Final Validation Summary

- ✅ Every FR in Requirements Inventory maps to an epic and to at least one story.
- ✅ Story flow is sequential with no forward dependencies inside epics.
- ✅ Epics are user-value oriented (not technical-layer milestones).
- ✅ UX-derived requirements (UX-DR-001..005) are covered by story acceptance criteria.
- ✅ No unresolved template placeholders remain.
