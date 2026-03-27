# Story 3.1: Read-Only Incident API with Role Scope

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a leader or ranger,
I want incident data served from backend mirrored ER data,
so that incident visibility is reliable without direct ER mobile calls.

## Acceptance Criteria

1. **Given** an authenticated request to `GET /api/mobile/incidents`
   **When** the backend resolves role and query filters
   **Then** ranger users receive self incidents only
   **And** leader users receive authorized team incidents.

2. **Given** incident endpoints in Phase 1
   **When** clients inspect available actions
   **Then** create/edit operations are not exposed
   **And** read-only behavior is enforced server-side.

## Tasks / Subtasks

- [x] Task 1: Implement role-scoped incident read endpoint (AC: 1)
  - [x] Replace placeholder `GET /api/mobile/incidents` response with mirrored incident read-model payload.
  - [x] Enforce ranger self-only scope and leader team/ranger-filter scope server-side.
  - [x] Preserve authenticated-only access via mobile bearer token dependency.

- [x] Task 2: Add query filtering and response metadata (AC: 1)
  - [x] Add `from`, `to`, and `updated_since` query filtering support.
  - [x] Add pagination controls (`page`, `page_size`) with metadata.
  - [x] Add sync metadata (`cursor`, `has_more`, `last_synced_at`) for mobile consumption.

- [x] Task 3: Enforce read-only contract in Phase 1 (AC: 2)
  - [x] Keep only `GET /api/mobile/incidents` exposed for incident operations.
  - [x] Ensure create/edit incident actions are not available from this API surface.

- [x] Task 4: Add automated regression tests (AC: 1, 2)
  - [x] Add tests for ranger self scope and cross-ranger denial.
  - [x] Add tests for leader team scope and leader ranger filter behavior.
  - [x] Add tests for query filtering, pagination, and read-only endpoint behavior.

- [x] Task 5: Validate implementation and document evidence (AC: 1, 2)
  - [x] Run full backend unit tests and confirm green.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-INC-001`, `FR-INC-002`, `FR-INC-003`, and `FR-INC-004`.
- Endpoint contract target: `GET /api/mobile/incidents?from=&to=&updated_since=&ranger_id=&cursor=`.
- Ranger scope must return mapped self incidents only; leader scope must support team view and ranger filter.

### Architecture Compliance

- Keep role enforcement server-side via mobile bearer auth and scope helpers.
- Keep implementation deterministic/testable with in-memory mirrored incident records.
- Preserve read-only Phase 1 incident behavior by exposing only the GET endpoint.

### Testing Requirements

- Use deterministic in-memory incident fixtures.
- Validate both role scope and query filter behavior.
- Validate incident write/edit actions are not exposed.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 3, Story 3.1)]
- Architecture decision references: [Source: `_bmad-output/planning-artifacts/architecture.md` (Section 6.3)]
- Project rules: [Source: `_bmad-output/project-context.md` (Phase 1 incidents are read-only + role scope enforcement)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `python -m unittest discover -s tests -v` (first run interrupted due command timeout while suite was executing)
- `python -m unittest discover -s tests -v` (37 tests passed)
- `python -m unittest discover -s tests -p 'test_mobile_incidents.py' -v` (10 tests passed)
- `python -m unittest discover -s tests -v` (99 tests passed)

### Completion Notes List

- Replaced placeholder incidents endpoint with role-scoped read-model logic over in-memory `mobile_incident_records`.
- Added query filters for `from`, `to`, and `updated_since`, including validation and UTC-safe parsing.
- Added pagination metadata and sync metadata (`cursor`, `has_more`, `last_synced_at`) to support mobile incremental refresh patterns.
- Enforced ranger self-only incident visibility and preserved leader team/ranger-filter behavior server-side.
- Preserved read-only incident API surface for Phase 1 (no create/edit endpoint implementations).
- Added dedicated regression tests for incident scope, filter/pagination, and read-only behavior.
- Updated existing auth/work/check-in tests to clear incident in-memory state for deterministic isolation.
- Completed adversarial review hardening loop: pagination bounds, malformed mirrored row defenses, and normalized ranger scope metadata.
- Implemented deterministic cursor-based pagination semantics with validation for format/range/conflicting page+cursor inputs.
- Clarified sync checkpoint contract: `last_synced_at` is emitted only when `has_more` is false (full window drained), preventing premature checkpoint persistence.
- Added defensive debug logging for timestamp-less rows filtered by `updated_since`.
- Added extended regression coverage for malformed timestamps, cursor pagination flow, and invalid cursor inputs.
- Re-ran adversarial review after each fix cycle until no actionable findings remained.

### File List

- `_bmad-output/implementation-artifacts/3-1-read-only-incident-api-with-role-scope.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `app/src/server.py`
- `app/tests/test_mobile_incidents.py`
- `app/tests/test_mobile_auth.py`
- `app/tests/test_mobile_work_management.py`
- `app/tests/test_mobile_checkins.py`

## Change Log

- 2026-03-20: Story implemented with role-scoped incident read endpoint, filtering/pagination/sync metadata, and regression tests; moved to review.
- 2026-03-23: Completed strict adversarial hardening loop (High→Medium→Low), added cursor and sync-contract safety fixes, expanded incident regression tests, full suite green, and closed story as done.
