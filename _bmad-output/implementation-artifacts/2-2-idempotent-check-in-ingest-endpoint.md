# Story 2.2: Idempotent Check-In Ingest Endpoint

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a ranger,
I want app-open check-ins to be deduplicated by day,
so that my attendance is correct even with retries and repeated app opens.

## Acceptance Criteria

1. **Given** an authenticated ranger and a check-in request
   **When** `POST /api/mobile/checkins` is called
   **Then** the backend computes `day_key` using project timezone `Asia/Ho_Chi_Minh`
   **And** persists at most one effective check-in record per user/day.

2. **Given** a repeat submission for the same `user_id + day_key`
   **When** the request is processed
   **Then** the backend returns `already_exists`
   **And** no duplicate check-in row is created.

## Tasks / Subtasks

- [x] Task 1: Implement check-in ingest endpoint and project day-key computation (AC: 1)
  - [x] Add request model and route for `POST /api/mobile/checkins`.
  - [x] Compute `day_key` using project timezone `Asia/Ho_Chi_Minh` from server-side time.
  - [x] Restrict check-in ingest to authenticated ranger role.

- [x] Task 2: Enforce idempotent once-per-user/day persistence (AC: 1, 2)
  - [x] Persist check-in records with unique key semantics `(user_id, day_key)`.
  - [x] Return `created` for first check-in and `already_exists` for repeats on same day.
  - [x] Ensure repeated submissions do not create duplicate check-in rows.

- [x] Task 3: Integrate check-in indicator for work summary compatibility (AC: 1)
  - [x] Upsert/mark day-level check-in indicator in work summary data source.
  - [x] Preserve compatibility with existing `GET /api/mobile/work-management` summary contract.

- [x] Task 4: Add automated regression tests (AC: 1, 2)
  - [x] Add tests verifying day-key uses `Asia/Ho_Chi_Minh` boundary behavior.
  - [x] Add tests verifying first check-in creates record and repeat returns `already_exists`.
  - [x] Add tests verifying duplicate check-ins do not create extra rows.
  - [x] Add tests verifying non-ranger role cannot call check-in ingest.

- [x] Task 5: Validate implementation and document evidence (AC: 1, 2)
  - [x] Run full backend unit tests and confirm green.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-WM-003` and `FR-WM-004`.
- Day-key policy baseline is fixed project timezone `Asia/Ho_Chi_Minh`.
- Idempotency guarantee target is one effective check-in per `(user_id, day_key)`.

### Architecture Compliance

- Keep server-side auth/scope checks via existing mobile bearer token dependency.
- Keep implementation deterministic/in-memory for current backend baseline.
- Preserve existing work-management response shape and role enforcement.

### Testing Requirements

- Tests must be deterministic and avoid external services.
- Use fixed server timestamps (mock/patch) to verify timezone day-key behavior.
- Validate both positive and negative role/authz paths.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 2, Story 2.2)]
- Architecture decision references: [Source: `_bmad-output/planning-artifacts/architecture.md` (AD-04, AD-05)]
- Project rules: [Source: `_bmad-output/project-context.md` (check-in idempotency + server-side enforcement)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (initial run failed: check-in tests patched time made bearer tokens appear expired)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (33 tests passed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests.test_mobile_checkins -v` (targeted Story 2.2 suite: 7 tests passed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (full backend regression: 93 tests passed)
- Final adversarial review pass (Story 2.2 scope): PASS, no actionable findings.

### Completion Notes List

- Added `POST /api/mobile/checkins` with `MobileCheckinRequest` model and mobile bearer auth dependency.
- Implemented fixed project timezone day-key policy using `Asia/Ho_Chi_Minh` via zoneinfo with safe UTC+7 fallback.
- Added idempotent persistence store (`mobile_daily_checkins`) keyed by `(user_id, day_key)` returning `created`/`already_exists` semantics.
- Restricted check-in ingest to ranger role (`403 Ranger role required` for non-ranger access).
- Added work-summary compatibility upsert so check-in status appears in day summaries without duplicate rows.
- Added deterministic regression tests for timezone day-key boundary behavior, idempotent repeat behavior, duplicate prevention, non-ranger rejection, and token validation.
- Hardened check-in ingest critical section with explicit locking for concurrent idempotent writes and work-summary updates.
- Added `require_mobile_ranger` dependency for route-level role enforcement on `POST /api/mobile/checkins`.
- Expanded regression coverage with concurrency stress test, timezone boundary edge cases, and expired-access-token rejection.
- Completed adversarial review loop with final PASS and no actionable findings.

### File List

- `_bmad-output/implementation-artifacts/2-2-idempotent-check-in-ingest-endpoint.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `app/src/server.py`
- `app/tests/test_mobile_checkins.py`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented idempotent check-in ingest endpoint with project-timezone day key, work-summary integration, and regression tests; moved story to review.
- 2026-03-23: Applied adversarial-review hardening (concurrency lock scope + route-level ranger dependency), expanded targeted regression tests, reran full suite, and closed story as done.
