# Story 4.5: Retention and Compliance Operations

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a product and operations team,
I want retention controls implemented for ranger statistics,
so that Phase 1 meets data-lifecycle requirements and remains auditable.

## Acceptance Criteria

1. **Given** operational data lifecycle requirements
   **When** retention jobs execute
   **Then** ranger stats data is retained for at least 6 months
   **And** aggregation/cleanup behavior is auditable.

2. **Given** retention jobs are deployed
   **When** a scheduled run fails or is skipped
   **Then** the failure is logged with request/job correlation metadata
   **And** operators can identify and replay the failed retention run.

## Tasks / Subtasks

- [x] Task 1: Add backend retention execution service for ranger operational stats (AC: 1)
  - [x] Implement a dedicated retention module in `app/src/` that computes a cutoff window of at least 6 months and executes cleanup against configured ranger-stats storage.
  - [x] Keep retention behavior configuration-driven (enabled flag, schedule, source table/field, retention window) via `get_settings()`.
  - [x] Ensure retention execution returns deterministic summary data (`run_id`, `status`, `cutoff_day`, `deleted_count`, `error`) for auditability and operations use.

- [x] Task 2: Add auditable retention run records with replay markers (AC: 1, 2)
  - [x] Record each retention run with structured metadata: `run_id`, `trigger`, `status`, `started_at`, `finished_at`, `cutoff_day`, and `request/job correlation ids`.
  - [x] Include replay linkage (`replay_of_run_id`) for manual reruns so operators can trace remediation lineage.
  - [x] Persist audit records in-process (for runtime visibility) and maintain compatibility with Supabase-backed persistence where configured.

- [x] Task 3: Integrate scheduled retention execution into backend loop with skip/failure visibility (AC: 1, 2)
  - [x] Trigger retention once per day at architecture-approved schedule (01:30 `Asia/Ho_Chi_Minh`) while preserving existing sync loop behavior.
  - [x] Emit explicit structured logs for `succeeded`, `failed`, and `skipped` outcomes with correlation metadata.
  - [x] Ensure scheduler logic is idempotent per day (no duplicate executions for same window).

- [x] Task 4: Add operator APIs to identify failed runs and replay retention safely (AC: 2)
  - [x] Provide admin-only endpoint(s) to list retention runs with status filtering (especially `failed`).
  - [x] Provide admin-only replay endpoint that re-executes retention for a failed run and records `replay_of_run_id` linkage.
  - [x] Return response payloads with enough metadata for operational troubleshooting (`run_id`, `status`, `request_id`, replay context).

- [x] Task 5: Add deterministic automated tests for retention and replay flow (AC: 1, 2)
  - [x] Add unit tests for retention service success/failure paths, including cutoff computation and audit recording.
  - [x] Add tests for daily scheduler gating and replay marker behavior.
  - [x] Add API tests for admin failed-run listing and replay trigger behavior.
  - [x] Re-run targeted backend tests then full backend regression suite.

## Dev Notes

### Technical Requirements

- Implements `FR-INT-004` and architecture addendum Item 12.3.
- Retention must enforce at least 6-month operational data window for ranger stats.
- Retention execution must be auditable and replay-friendly.

### Architecture Compliance

- Keep BFF and server-side operations boundary intact (no mobile-side retention logic).
- Reuse existing settings/logging/sync conventions (`get_settings`, structured logging, request/job correlation fields).
- Preserve existing sync worker reliability characteristics; retention must not destabilize incident/tree sync flow.

### Library and Framework Requirements

- Use existing Python/FastAPI modules only; avoid adding new dependencies for scheduling or time handling.
- Keep timezone handling UTC-aware for persisted timestamps, with explicit `Asia/Ho_Chi_Minh` schedule interpretation.
- Keep logging compatible with `src.logging_config.JSONFormatter` extras.

### File Structure Requirements

- Primary implementation targets:
  - `app/src/config.py`
  - `app/src/sync.py`
  - `app/src/server.py`
  - `app/src/retention.py` (new)
- Test targets:
  - `app/tests/test_retention_operations.py` (new)
  - Existing sync/logging test files only if needed for minimal coverage adjustments.

### Previous Story Intelligence

- Story 4.1 already established resilient sync worker patterns (retryability, structured logging, cursor safety); reuse this operational style for retention runs.
- Story 4.3/4.4 expanded mobile sync-state and replay semantics; for 4.5, reuse the same observability mindset (deterministic status + replay context), but keep implementation server-side.
- Existing backend tests rely on deterministic mocks and in-memory stubs; follow that same approach for retention tests.

### Testing Requirements

- Tests must be deterministic and mock-only (no live Supabase/EarthRanger required).
- Validate success/failure/skip + replay branches explicitly.
- Validate correlation metadata appears in run results/log context and API responses.

### Implementation Guardrails

- Do **not** reduce retention below 6 months.
- Do **not** introduce destructive cleanup without auditable run records.
- Do **not** require new secrets or break existing auth/session paths.
- Do **not** alter Phase 1 role/access behavior for existing mobile endpoints.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 4, Story 4.5)]
- PRD requirement: [Source: `_bmad-output/planning-artifacts/prd.md` (Section 6.6 FR-INT-004)]
- Architecture retention decision: [Source: `_bmad-output/planning-artifacts/architecture.md` (Section 13, Item 12.3)]
- Project guardrails: [Source: `_bmad-output/project-context.md` (Data Sync, Retention Rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- Targeted backend sweep: `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests.test_retention_operations tests.test_sync_incidents tests.test_secret_hygiene_prod_security -v` from `app/` (pass, 45 tests).
- Retention-focused rerun after hardening: `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests.test_retention_operations -v` from `app/` (pass, 6 tests).
- Full backend regression: `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -p "test_*.py"` from `app/` (pass, 108 tests).
- Final strict adversarial review retry (after cooldown) returned: `No actionable findings`.

### Completion Notes List

- Implemented and validated retention execution service with policy floor enforcement (minimum 183-day retention window) and deterministic run summaries.
- Added auditable run-history recording with structured metadata, request/correlation IDs, and replay lineage via `replay_of_run_id`.
- Integrated scheduled retention gating into sync loop at local policy schedule (01:30 Asia/Ho_Chi_Minh), with per-day idempotency and explicit skip/failure visibility.
- Exposed admin-only retention operations endpoints for run listing/filtering, manual execution, and failed-run replay.
- Added deterministic backend tests for retention success/failure, scheduler gating, replay linkage, and admin API behavior.
- Applied severity-ordered hardening from adversarial review passes (scheduler lock safety, strict retention config validation, async threadpool wrapping for blocking admin retention operations, safer correlation-id fallback behavior, and robust deleted-count fallback handling).
- Completed multi-pass adversarial review/fix/test loop to closure with final clean verdict and green regression.

### File List

- `app/src/config.py`
- `app/src/retention.py`
- `app/src/sync.py`
- `app/src/server.py`
- `app/.env.example`
- `app/tests/test_retention_operations.py`

## Change Log

- 2026-03-23: Story file created and set to `ready-for-dev`.
- 2026-03-23: Story moved to `in-progress` for implementation.
- 2026-03-23: Story completed and set to `done` after retention targeted + full backend regression pass.
- 2026-03-23: Multi-pass adversarial review loop completed with severity fixes applied and final verdict of no actionable findings.
