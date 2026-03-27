# Story 4.6: Performance and Observability Hardening

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform owner,
I want mobile-facing endpoints optimized and observable,
so that performance remains stable and production troubleshooting is fast.

## Acceptance Criteria

1. **Given** mobile list and summary endpoints
   **When** requests are processed under normal load
   **Then** pagination/filtering and incremental payload practices are applied
   **And** endpoints avoid unnecessary full-table scans.

2. **Given** API requests across auth, work-management, incidents, schedules, and sync flows
   **When** logs and traces are reviewed
   **Then** request IDs and structured log fields support end-to-end correlation
   **And** key error/performance events are visible for operations monitoring.

## Tasks / Subtasks

- [x] Task 1: Harden mobile read endpoint query controls for predictable performance (AC: 1)
  - [x] Add explicit, bounded pagination defaults and max limits for `GET /api/mobile/work-management`, `GET /api/mobile/incidents`, and `GET /api/mobile/schedules`.
  - [x] Enforce deterministic sort/filter behavior to keep requests index-friendly and avoid accidental broad scans.
  - [x] Preserve backward-compatible response shapes while adding metadata needed for safe client paging.

- [x] Task 2: Apply incremental payload and query-window safeguards (AC: 1)
  - [x] Ensure list/summary endpoints consistently support incremental fetch patterns (`updated_since`, cursor/date windows, or equivalent constrained filters).
  - [x] Add defensive validation for date-range/query-window bounds to prevent oversized scans.
  - [x] Keep role-scoped filtering (`leader`, `ranger`) as the first gate before expensive query paths.

- [x] Task 3: Add endpoint-level observability for mobile API surfaces (AC: 2)
  - [x] Emit structured request lifecycle logs with `request_id`, route, method, status, duration, and role/user scope where available.
  - [x] Emit explicit structured logs for key error branches on auth/work/incidents/schedules/sync paths with correlation-safe fields.
  - [x] Add slow-request warning events with configurable threshold to improve production triage.

- [x] Task 4: Preserve and verify correlation propagation end-to-end (AC: 2)
  - [x] Validate `X-Request-ID` propagation from middleware to endpoint logs and response headers.
  - [x] Ensure operation-level logs (including sync/retention-assisted paths used by mobile flows) include request/correlation IDs when present.
  - [x] Keep observability implementation dependency-free and aligned with existing `logging_config` conventions.

- [x] Task 5: Add deterministic automated coverage for performance guards and observability (AC: 1, 2)
  - [x] Add/update backend tests for pagination bounds, query-window validation, and incremental parameter behavior.
  - [x] Add/update backend tests asserting request-id propagation and structured log/correlation fields for representative mobile endpoints.
  - [x] Re-run targeted tests for changed areas, then full backend regression suite.

## Dev Notes

### Technical Requirements

- Implements `NFR-PERF-001`, `NFR-PERF-002`, `NFR-PERF-003`, and `NFR-MNT-001` from Epic 4 Story 4.6.
- Keep APIs backward compatible for existing mobile consumers while adding safe performance guardrails.
- Observability must rely on structured logging and request-id correlation already established in backend middleware.

### Architecture Compliance

- Preserve BFF boundary: mobile traffic remains `mobile -> FastAPI -> backend data/integration`.
- Keep role scoping and auth checks as first-line query constraints.
- Avoid introducing new dependencies; reuse current FastAPI/logging/request-id stack.

### Library and Framework Requirements

- Use existing Python/FastAPI modules and helpers (`Depends(require_auth)`, `get_settings()`, `logging_config` request-id utilities).
- Keep logging structured and compatible with `src.logging_config.JSONFormatter` extras.
- Keep timezone handling and timestamp serialization consistent with repository norms.

### File Structure Requirements

- Primary implementation targets:
  - `app/src/config.py`
  - `app/src/server.py`
  - `app/src/supabase_db.py` (if query shaping/pagination helpers require adjustment)
  - `app/src/sync.py` (only if correlation/perf events on sync-adjacent paths need alignment)
- Test targets:
  - `app/tests/test_mobile_work_management.py`
  - `app/tests/test_mobile_incidents.py`
  - `app/tests/test_mobile_schedules.py`
  - `app/tests/test_mobile_auth.py`
  - `app/tests/test_sync_incidents.py`
  - Add a focused new test file if needed for observability assertions.

### Previous Story Intelligence

- Story 4.5 established robust structured run metadata and correlation conventions for retention/scheduler flows; reuse this style for endpoint observability.
- Story 4.5 emphasized deterministic tests and no external dependency coupling; keep this approach for all new performance/observability tests.
- Existing backend patterns already include request-id middleware and structured logging; extend rather than replace these foundations.

### Testing Requirements

- Keep tests deterministic and local (no live Supabase/EarthRanger).
- Validate both success and error-path observability fields.
- Validate pagination/range guardrails and incremental query behavior with clear boundary cases.

### Implementation Guardrails

- Do **not** break existing mobile response payload contracts.
- Do **not** bypass server-side role enforcement to optimize queries.
- Do **not** add unbounded list queries in mobile-facing endpoints.
- Do **not** introduce ad-hoc print/debug logging; keep structured logger usage only.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 4, Story 4.6)]
- Performance NFRs: [Source: `_bmad-output/planning-artifacts/prd.md` (Section 7.3 NFR-PERF-001/002/003)]
- Observability and request-id baseline: [Source: `_bmad-output/planning-artifacts/architecture.md` (Sections 4.2, 9)]
- Project guardrails: [Source: `_bmad-output/project-context.md` (Framework Rules, Data Sync Rules, Critical Don’t-Miss Rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `python -m unittest tests.test_observability_request_id tests.test_mobile_schedules -v`
- `python -m unittest tests.test_observability_request_id tests.test_mobile_performance_observability -v`
- `python -m unittest discover -s tests -p "test_*observability*.py" -v` (10 tests, all passing)
- `python -m unittest discover -s tests -v` (120 tests, all passing)

### Completion Notes List

- Hardened request-id middleware correlation behavior and response header propagation.
- Added structured slow-request warning logs backed by configurable threshold handling.
- Extended mobile schedules read API with incremental `updated_since` filtering and deterministic pagination metadata.
- Added sync cycle telemetry with structured per-cycle counters, duration, and status fields.
- Added and updated deterministic regression tests for performance guards and observability behavior.
- Post-review hardening fix: removed duplicate `REQUEST_SLOW_THRESHOLD_MS` setting shadowing and restored intended legacy-alias fallback to `MOBILE_SLOW_REQUEST_WARN_MS`.

### File List

- `app/src/server.py`
- `app/src/config.py`
- `app/.env.example`
- `app/src/sync.py`
- `app/tests/test_mobile_schedules.py`
- `app/tests/test_observability_request_id.py`

## Change Log

- 2026-03-23: Story file created and set to `ready-for-dev`.
- 2026-03-23: Story moved to `in-progress` for implementation.
- 2026-03-23: Implemented performance and observability hardening changes and marked story `done` after full regression pass.
- 2026-03-23: Completed adversarial post-implementation review loop, fixed slow-threshold config alias regression, and revalidated targeted plus full backend regression suites.
