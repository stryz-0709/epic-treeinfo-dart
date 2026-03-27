# Story 3.3: Schedule Read and Leader Write APIs

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a leader or ranger,
I want schedule data to be role-scoped with leader-only write access,
so that assignments are managed correctly and safely.

## Acceptance Criteria

1. **Given** `GET /api/mobile/schedules`
   **When** called by ranger
   **Then** only self schedule entries are returned
   **And** other ranger entries are excluded.

2. **Given** `POST` or `PUT` schedule endpoints
   **When** called by leader
   **Then** schedule changes are validated and persisted
   **And** audit fields capture updater identity and timestamp.

3. **Given** schedule write request by non-leader user
   **When** authorization is evaluated
   **Then** the request is denied
   **And** a clear authorization error is returned.

## Tasks / Subtasks

- [x] Task 1: Strengthen role-scoped schedule read endpoint (AC: 1)
  - [x] Ensure ranger users receive self-only schedule rows with server-side scope enforcement.
  - [x] Support leader scope behavior for team view and ranger filter.
  - [x] Add filter support for schedule date range inputs where provided.

- [x] Task 2: Harden leader-only schedule writes with validation and audit fields (AC: 2, 3)
  - [x] Validate schedule write payload fields (`ranger_id`, `work_date`) with clear error responses.
  - [x] Persist/return audit metadata (`updated_by`, `updated_at`) on create and update operations.
  - [x] Preserve non-leader write denial via server-side role guard.

- [x] Task 3: Add automated backend regression tests (AC: 1, 2, 3)
  - [x] Add tests for ranger self-only reads and cross-ranger denial.
  - [x] Add tests for leader team-scope reads, ranger-filter reads, and date-range filters.
  - [x] Add tests for leader write validation/audit fields and non-leader authorization failures.

- [x] Task 4: Validate implementation and document evidence (AC: 1, 2, 3)
  - [x] Run full backend unit tests and confirm green.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-SCH-001`, `FR-SCH-002`, `FR-SCH-003`, and `FR-SCH-004`.
- Endpoint baseline: `GET /api/mobile/schedules?from=&to=&ranger_id=`, `POST /api/mobile/schedules`, `PUT /api/mobile/schedules/{schedule_id}`.
- Schedule writes must remain leader-only and include updater identity + timestamp audit fields.

### Architecture Compliance

- Keep role enforcement server-side with existing mobile bearer auth and leader guard dependencies.
- Keep implementation deterministic and testable with in-memory schedule records for Phase 1.
- Preserve API compatibility while extending scope/filter behavior and write validations.

### Testing Requirements

- Use deterministic test fixtures without external systems.
- Validate positive and negative role/authz paths.
- Validate payload and date-range validation behaviors.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 3, Story 3.3)]
- Architecture baseline: [Source: `_bmad-output/planning-artifacts/architecture.md` (Section 6.4)]
- Project rules: [Source: `_bmad-output/project-context.md` (server-side role enforcement + schedule scope rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `python -m unittest discover -s tests -p "test_mobile_schedules.py"` → pass (`Ran 5 tests`, `OK`)
- `python -m unittest discover -s tests` → pass (`Ran 42 tests`, `OK`)
- `python -m unittest discover -s app/tests -p "test_mobile_schedules.py" -v` → pass (`Ran 6 tests`, `OK`)
- `python -m unittest discover -s tests -p "test_mobile_schedules.py" -v` → pass (`Ran 7 tests`, `OK`)
- `python -m unittest discover -s tests -v` → pass (`Ran 100 tests`, `OK`)
- `python -m unittest discover -s tests -p "test_mobile_schedules.py" -v` → pass (`Ran 9 tests`, `OK`)
- `python -m unittest discover -s tests -v` → pass (`Ran 102 tests`, `OK`)
- Final adversarial review pass → `No actionable findings`; AC1/AC2/AC3 confirmed complete.

### Completion Notes List

- Hardened `GET /api/mobile/schedules` with server-side role scope parity: ranger self-only, leader team scope by default, optional leader ranger filter, and `from`/`to` date range validation.
- Added defensive schedule row normalization/filtering and consistent response metadata (`scope.team_scope`, `filters`).
- Hardened schedule create/update validation for required fields and ISO work-date format.
- Added schedule audit metadata on writes (`updated_by`, `updated_at`; `created_at` on create and preserved on update).
- Added schedule write payload hardening for note size (`note` max length 500 characters).
- Added Story 3.3 regression suite for scope enforcement, filters, validation, audit fields, and non-leader write denial.
- Added schedule concurrency safety with dedicated lock for write paths and read snapshot isolation.
- Added defensive audit timestamp fallback on reads for malformed legacy values without breaking response contracts.
- Added regression coverage for concurrent ID uniqueness, PUT empty `ranger_id` validation, whitespace-only note normalization, and malformed audit timestamp read behavior.
- Completed strict fix/test/re-review loop until no actionable findings remained.

### File List

- `app/src/server.py`
- `app/tests/test_mobile_schedules.py`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented Story 3.3 schedule API hardening (scope/filter/validation/audit), added regression tests, and moved story to review.
- 2026-03-20: Addressed critical review follow-ups (audit timestamp preservation on update, validation cleanup, note length guard) and reran Story 3.3 regression suite.
- 2026-03-23: Ran adversarial review, applied High→Medium→Low fixes (concurrency lock safety, read snapshot safety, explicit audit preservation), and reran targeted/full backend suites (`7/100` tests passing).
- 2026-03-23: Completed second fix/test/re-review pass (defensive audit fallback + additional regression cases), reran targeted/full backend suites (`9/102` tests passing), final adversarial review reported no actionable findings, and closed story as `done`.
