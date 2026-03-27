# Story 1.3: Server-Side Role Guard for Mobile Endpoints

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a security owner,
I want role and scope enforcement on every mobile endpoint,
so that ranger and leader data boundaries cannot be bypassed from the client.

## Acceptance Criteria

1. **Given** a ranger token
   **When** the user requests another ranger's data
   **Then** the backend denies the request
   **And** only self-scoped data is returned for ranger queries.

2. **Given** a leader token
   **When** the user requests team-scoped data
   **Then** the backend returns authorized team data
   **And** schedule write endpoints are allowed only for leader role.

## Tasks / Subtasks

- [x] Task 1: Add mobile bearer-token auth dependency and role guard primitives (AC: 1, 2)
  - [x] Parse and validate bearer access token from `Authorization` header.
  - [x] Reject missing/invalid/expired mobile access tokens with `401`.
  - [x] Add role guard helper(s) for leader-only endpoint protection.

- [x] Task 2: Add role-scoped mobile endpoints using guard primitives (AC: 1, 2)
  - [x] Add `GET /api/mobile/me` as authenticated identity/role proof endpoint.
  - [x] Add role-scoped read endpoint with `ranger_id` filter enforcement for ranger vs leader.
  - [x] Add leader-only schedule write endpoint guard and authorization errors for ranger tokens.

- [x] Task 3: Add automated regression tests for scope and role enforcement (AC: 1, 2)
  - [x] Add tests for missing/invalid bearer token rejection.
  - [x] Add tests verifying ranger requests for another ranger are denied.
  - [x] Add tests verifying ranger self-scope access works.
  - [x] Add tests verifying leader team-scope access works.
  - [x] Add tests verifying schedule write endpoint is leader-only.

- [x] Task 4: Validate implementation and document evidence (AC: 1, 2)
  - [x] Run full backend unit tests and confirm green.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

- [x] Review Follow-ups (AI)
  - [x] [AI-Review][Medium] Ignore malformed `day_key` rows in work-summary records so malformed source data cannot fail the whole role-scoped response.

## Dev Notes

### Technical Requirements

- This story implements `FR-AUTH-003`, `FR-WM-006`, `FR-INC-002`, and `FR-SCH-002` at guard/authorization level.
- Mobile endpoints must not rely on client-side role trust; all scope checks are server-side.
- Ranger scope is self-only; leader can request team-scoped data.

### Architecture Compliance

- Preserve BFF pattern and FastAPI conventions in `app/src/server.py`.
- Reuse existing mobile auth session stores from Stories 1.1/1.2.
- Keep existing dashboard auth/session (`/login`, cookie sessions) unchanged.
- Use existing rate-limiter and structured logging conventions.

### Testing Requirements

- Keep tests deterministic and local-only using temporary `users.json` fixtures.
- Reuse existing `TestClient` setup and no external dependencies.
- Validate both positive and negative authorization paths.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 1, Story 1.3)]
- Auth model baseline and contract: [Source: `_bmad-output/planning-artifacts/architecture.md` (Sections 3 AD-03, 6.1)]
- Project implementation rules: [Source: `_bmad-output/project-context.md` (Framework + Security + Testing rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests.test_mobile_work_management.MobileWorkManagementTests.test_malformed_day_key_rows_are_ignored -v` (expected red before fix: 1 failed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests.test_mobile_auth tests.test_mobile_work_management -v` (19 tests passed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (82 tests passed)

### Completion Notes List

- Added mobile bearer-token auth dependency (`require_mobile_auth`) with token parsing and invalid/expired token rejection.
- Added leader role guard dependency (`require_mobile_leader`) and reusable ranger-scope resolver for role-scoped query enforcement.
- Added guarded mobile endpoints: `GET /api/mobile/me`, `GET /api/mobile/work-management`, `GET /api/mobile/incidents`, `GET /api/mobile/schedules`, plus leader-only schedule writes (`POST/PUT /api/mobile/schedules`).
- Added deterministic in-memory schedule write storage for authorization guard validation.
- Added regression tests for missing/invalid/expired bearer token handling, ranger scope denial of cross-user reads, leader team-scope reads, and leader-only schedule writes.
- Adversarial review follow-up: hardened work-summary row parsing to ignore malformed persisted `day_key` values instead of failing the endpoint response.
- Added regression test proving malformed `day_key` rows are skipped safely.
- Completed strict review-test loop: targeted regressions and full backend regressions are green, and final adversarial pass has no actionable findings.

### File List

- `_bmad-output/implementation-artifacts/1-3-server-side-role-guard-for-mobile-endpoints.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `app/src/server.py`
- `app/tests/test_mobile_auth.py`
- `app/tests/test_mobile_work_management.py`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented server-side mobile role/scope guards with guarded endpoints and regression tests; moved story to review.
- 2026-03-23: Completed strict adversarial review loop, applied medium resilience fix for malformed work-summary rows, re-ran targeted/full regressions, and moved story to done.

## Senior Developer Review (AI)

- **Date:** 2026-03-23
- **Outcome:** Approve
- **Status impact:** Story moved from `review` to `done`

### Review Summary

- Pass 1 found one actionable Medium issue (malformed persisted `day_key` could fail role-scoped work summary responses); fix implemented with regression coverage.
- Targeted tests (`test_mobile_auth`, `test_mobile_work_management`) passed after fix.
- Full backend regression suite passed (`82` tests).
- Pass 2 adversarial review returned no actionable findings; acceptance criteria remain satisfied.
