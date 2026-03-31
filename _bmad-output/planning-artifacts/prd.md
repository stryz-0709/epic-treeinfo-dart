---
stepsCompleted: []
inputDocuments:
  - _bmad-output/planning-artifacts/phase1-mobile-prd-input.md
  - _bmad-output/project-context.md
  - _bmad-output/planning-artifacts/full-method-kickoff-mobile.md
workflowType: "prd"
status: "draft-v1"
---

# Product Requirements Document - EarthRanger (Phase 1 Mobile)

**Author:** Admin  
**Date:** 2026-03-19

## 1. Product Overview

This PRD defines the Phase 1 mobile capability set for EarthRanger operations visibility, focused on:

1. Work Management (`Quản lí công việc`)
2. Incident Management (`Quản lí lâm phần`)
3. Schedule

Phase 1 is a **hybrid offline-capable release** with security-first architecture:

- Mobile app uses backend-for-frontend (BFF) APIs.
- Privileged keys stay on backend only.
- Offline cache + safe sync queue are included for ranger check-in/stat updates.

## 2. Goals and Success Outcomes

### 2.1 Business Goals

- Give leaders a reliable team-level view of ranger activity.
- Give rangers clear personal work/schedule/incident visibility.
- Reduce operational blind spots caused by connectivity gaps.
- Establish secure mobile architecture for future phases.

### 2.2 Success Metrics (Phase 1)

- ≥ 95% of daily ranger app opens create exactly one valid daily check-in record.
- 0 privileged keys present in mobile build assets or binaries.
- Leader can view scoped team summary and incidents only for authorized rangers with the same `region` and `team`.
- Ranger can only view self-scoped records.
- Offline queued ranger check-ins replay successfully when connectivity returns.

## 3. Scope

### 3.1 In Scope

#### F1 — Work Management Calendar

- Show per-day work summary in calendar view.
- Show a check-in/online indicator on days where check-in exists.
- Daily check-in trigger: authenticated app open.
- Ensure idempotent check-in behavior (max one record per user/day).
- Support time-range filtering (`from` ... `to`) for all summary views.
- For leader view, include ranger list/filter and ranger productivity metrics: patrol count, scheduled work count, completion percentage, total patrol distance, and event status breakdown.

#### F2 — Incident Management (`Quản lí lâm phần`)

- Show incidents/events created by ranger in the selected period.
- Data source is EarthRanger via backend sync/aggregation.
- Leaders can update incident status using controlled server-side transitions.
- Show solved incidents / total incidents and percentage in selected time range.
- Show event list fields: event type, status, priority, and note-presence indicator.
- Show attached files for each incident when available.

#### F3 — Schedule

- Show day-to-ranger assignment view.
- Leaders can create/update schedules (online-only in Phase 1).
- Rangers can view only own schedules.

#### F4 — Sync and Offline Foundation

- Device cache for Work Management, Incidents, Schedule.
- Offline queue for ranger check-in/stat updates only.
- Retry/backoff and visible sync status.

### 3.2 Out of Scope

- Incident/event creation and non-status incident content editing from this app.
- Leader offline schedule writes.
- Broad analytics redesign or deep historical BI dashboards.
- Direct EarthRanger polling from mobile clients.

## 4. Users and Roles

### 4.1 leader

- View ranger activity overview for authorized rangers in the same `region` and `team`.
- Filter/select ranger(s) from drop-list (same `region` + same `team` scope only).
- View incidents for authorized rangers in the same `region` and `team`.
- Create/update schedules only for authorized rangers in the same `region` and `team`.

### 4.2 ranger

- View own work/check-ins/schedule/incidents only.
- Cannot view or modify other ranger data.

## 5. Key User Flows

### 5.1 Ranger Daily Check-In Flow

1. Ranger opens app (authenticated session exists or login required).
2. App records local check-in intent and immediately updates local UI state.
3. If online: app sends check-in to backend endpoint.
4. If offline: app queues check-in with idempotency key and marks pending sync.
5. Backend deduplicates by user/day and confirms accepted/already-recorded.
6. App updates sync status and calendar indicator.

### 5.2 Leader Team Oversight Flow

1. Leader signs in.
2. Leader opens team Work Management dashboard/calendar.
3. Leader selects ranger from filter list limited to same-region/same-team scope.
4. Leader reviews ranger metrics (patrols, scheduled work, completion %, patrol distance, event status) and incident list by period.
5. Leader updates incident status when operations workflow requires.
6. Leader creates/updates schedule online.

### 5.3 Ranger Incident Visibility Flow

1. Ranger opens incident list screen.
2. App loads cached list first.
3. App refreshes from backend when online using incremental query parameters.
4. Ranger sees only self-scoped incidents.

## 6. Functional Requirements

### 6.1 Security and Authentication

- **FR-SEC-001**: Mobile app MUST NOT contain Supabase service-role key, ER credentials, or other privileged secrets.
- **FR-SEC-002**: All mobile business data access MUST go through backend BFF APIs.
- **FR-AUTH-001**: App MUST use production authentication flow (no hardcoded credentials).
- **FR-AUTH-002**: Backend MUST issue/validate authenticated session/token before data endpoints are accessed.
- **FR-AUTH-003**: Role claims (`leader`, `ranger`) MUST be enforced server-side for every protected endpoint.
- **FR-AUTH-004**: Leader permissions MUST apply only to rangers who share both `region` and `team` with that leader.
- **FR-SEC-003**: If direct mobile Supabase access is used for any limited case, only anon key + strict RLS is permitted.

### 6.2 Work Management

- **FR-WM-001**: System MUST display a calendar with per-day work summary.
- **FR-WM-002**: System MUST display check-in indicator for days with confirmed check-in.
- **FR-WM-003**: App-open check-in MUST be tied to authenticated user identity.
- **FR-WM-004**: Backend MUST guarantee one effective check-in per user/day (`user_id + day_key` uniqueness).
- **FR-WM-005**: Leader view MUST support ranger filter/drop-list constrained to same `region` and `team` scope.
- **FR-WM-006**: Ranger view MUST show self records only.
- **FR-WM-007**: Leader Work Management view MUST return ranger productivity metrics for selected time range: patrol count, scheduled work count, completion percentage, and total patrol distance.
- **FR-WM-008**: Work Management data MUST include event totals and event status breakdown for selected ranger/time range.
- **FR-WM-009**: Work Management endpoints MUST support explicit `from` and `to` range filtering.

### 6.3 Incident Management (`Quản lí lâm phần`)

- **FR-INC-001**: System MUST display incidents from EarthRanger-backed sync data.
- **FR-INC-002**: Ranger MUST see only incidents mapped to that ranger identity.
- **FR-INC-003**: Leader MUST see incidents only for authorized rangers in the same `region` and `team`.
- **FR-INC-004**: Leader MUST be able to update incident status through controlled server-side transitions.
- **FR-INC-005**: Incident list endpoints MUST support `from`, `to`, `status`, `event_type`, and `priority` filters.
- **FR-INC-006**: Incident list payload MUST expose note-presence information (`has_note`) for each event.
- **FR-INC-007**: System MUST return solved/total incident counts and solved percentage for selected time range.
- **FR-INC-008**: System MUST expose incident attachment listing for events that include files.
- **FR-INC-009**: Incident creation/deletion operations remain unavailable in Phase 1.

### 6.4 Schedule

- **FR-SCH-001**: System MUST display day-to-ranger schedule assignments.
- **FR-SCH-002**: Ranger MUST see only own schedule.
- **FR-SCH-003**: Leader MUST be able to create/update schedules online only for authorized rangers in the same `region` and `team`.
- **FR-SCH-004**: Schedule write actions MUST enforce role and payload validation on backend.

### 6.5 Offline and Sync

- **FR-SYNC-001**: App MUST cache Work Management, Incident, and Schedule data for offline read.
- **FR-SYNC-002**: Ranger check-in/stat actions MUST queue when offline.
- **FR-SYNC-003**: Each queued write MUST include idempotency key (`user_id + action_type + day_key + client_uuid`).
- **FR-SYNC-004**: Backend write endpoints MUST be idempotent and safe for repeated replay.
- **FR-SYNC-005**: Queue MUST implement retry with exponential backoff + jitter.
- **FR-SYNC-006**: App MUST show sync status (synced/pending/failed) to user.

### 6.6 Integration and Data Freshness

- **FR-INT-001**: EarthRanger polling MUST be server-side only.
- **FR-INT-002**: EarthRanger sync MUST be incremental cursor-based (high-watermark/updated_since).
- **FR-INT-003**: Mobile refresh endpoints SHOULD support conditional/incremental fetch patterns.
- **FR-INT-004**: Ranger stats retention MUST keep at least 6 months of operational data.

## 7. Non-Functional Requirements

### 7.1 Security

- **NFR-SEC-001**: No privileged credentials in distributed mobile artifacts.
- **NFR-SEC-002**: Production cookies/tokens and session handling must be hardened (secure flags and revocation strategy).
- **NFR-SEC-003**: CORS in production must be restricted to approved origins.
- **NFR-SEC-004**: Webhook signature validation must be enforced in production (no empty-secret bypass).

### 7.2 Reliability and Correctness

- **NFR-REL-001**: Daily check-in deduplication accuracy target: 100% for same user/day duplicates.
- **NFR-REL-002**: Offline replay must tolerate duplicate submission and intermittent connectivity.
- **NFR-REL-003**: APIs must return deterministic role-scoped results.

### 7.3 Performance

- **NFR-PERF-001**: Team/ranger list and calendar queries should support pagination/filtering.
- **NFR-PERF-002**: Server must avoid full-table scans for routine mobile list endpoints where feasible.
- **NFR-PERF-003**: Sync endpoints should minimize payload via incremental updates.

### 7.4 Maintainability and Testability

- **NFR-MNT-001**: Network/integration logic must be mockable for tests.
- **NFR-MNT-002**: Mobile state and service layers must follow existing Provider/service boundaries.
- **NFR-MNT-003**: Backend changes must preserve existing API compatibility where already consumed.

## 8. Initial API Contract Targets (Architecture Input)

> Final contract details are finalized in architecture phase; this section defines required endpoints.

### 8.1 Auth and Session

- `POST /api/mobile/auth/login`
- `POST /api/mobile/auth/refresh`
- `POST /api/mobile/auth/logout`
- `GET /api/mobile/me`

### 8.2 Work Management (`Quản lí công việc`)

- `POST /api/mobile/checkins` (idempotent)
- `GET /api/mobile/work-management?from=&to=&ranger_id=&page=&page_size=`
- `GET /api/mobile/work-management/rangers?active=&query=&page=&page_size=` (leader only)
- `GET /api/mobile/work-management/summary?from=&to=&ranger_id=`

### 8.3 Incident Management (`Quản lí lâm phần`)

- `GET /api/mobile/incidents?from=&to=&updated_since=&ranger_id=&event_type=&status=&priority=&has_note=&page=&page_size=&cursor=`
- `GET /api/mobile/incidents/summary?from=&to=&ranger_id=`
- `GET /api/mobile/incidents/{incident_id}/attachments`
- `PATCH /api/mobile/incidents/{incident_id}/status` (leader only)

### 8.4 Schedule

- `GET /api/mobile/schedules?from=&to=&ranger_id=`
- `POST /api/mobile/schedules` (leader only)
- `PUT /api/mobile/schedules/{schedule_id}` (leader only)

## 9. Acceptance Criteria (Feature-Level)

### AC-F1 Work Management

- Calendar displays working day summary and check-in indicators.
- Reopening app multiple times same day does not create duplicate check-ins.
- Leader can filter by ranger within same `region` and `team`; ranger cannot view others.
- Leader sees patrol count, scheduled work count, completion %, total patrol distance, and event-status summary for selected range.

### AC-F2 Incident Management

- Ranger sees only self incidents for selected period.
- Leader sees incidents only for authorized rangers in the same `region` and `team`.
- Leader can update incident status via permitted transitions.
- Incident list includes event type, status, priority, note indicator, solved/total ratio %, and file attachment presence.
- No incident creation/deletion controls available in UI.

### AC-F3 Schedule

- Ranger can view own schedule entries by date.
- Leader can create/update schedule online only for authorized rangers in the same `region` and `team` and see updates reflected.
- Unauthorized schedule write attempts are rejected by backend.

### AC-F4 Offline/Sync

- Cached data is shown when offline.
- Offline ranger check-ins queue and replay on reconnect.
- Replay of same queued record does not create duplicate persisted check-ins.

## 10. Risks and Mitigations

- **Risk:** Privileged key leakage from prior mobile packaging.  
  **Mitigation:** Key rotation + backend-only secret policy before release.

- **Risk:** Role leakage via client-side filtering bugs.  
  **Mitigation:** Server-side scope enforcement for every endpoint.

- **Risk:** ER API rate limits and delayed incident freshness.  
  **Mitigation:** Centralized backend polling with backoff and incremental cursor sync.

- **Risk:** Data inconsistency under offline retries.  
  **Mitigation:** Idempotency keys + server dedup + client retry policy.

## 11. Dependencies

- Backend BFF endpoints and role enforcement implementation.
- EarthRanger integration mapping for ranger identity fields.
- Secure secret management and key rotation process.
- Mobile local storage and queue implementation.

## 12. Open Decisions (Must Be Resolved in Architecture)

1. Final auth model for Phase 1:
   - Backend-managed JWT/session, or
   - Supabase Auth + strict RLS + backend mediation boundary.
2. Check-in day-boundary policy:
   - device-local timezone vs fixed project timezone.
3. Canonical schedule source-of-truth entity and ownership.
4. Exact EarthRanger fields used for incident ownership mapping.
5. Offline queue limits and conflict-resolution policy for exceptional cases.

## 13. Delivery Gates

### Gate A — Security Baseline (must pass before broad feature rollout)

- Service-role key rotated if previously exposed.
- Privileged secrets removed from mobile package.
- Mobile reads/writes moved to backend BFF path.

### Gate B — Contract Readiness

- Auth/check-in/incidents/schedules API contract approved.
- Role-scoped data rules tested.

### Gate C — Sync Readiness

- Cache model validated.
- Offline replay + idempotency validated.
- Sync status UX validated.

## 14. Recommended Next Workflow

1. `bmad-create-architecture` using this PRD as source.
2. `bmad-check-implementation-readiness` after architecture artifact is complete.
3. Story pipeline:
   - `bmad-sprint-planning`
   - `bmad-create-story`
   - `bmad-dev-story`
   - `bmad-code-review`
