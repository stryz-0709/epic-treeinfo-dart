# Story 4.1: Server-Side Incremental EarthRanger Sync Worker

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an operations platform,
I want incidents synchronized from EarthRanger using incremental cursors,
so that incident visibility remains up to date without exceeding rate limits.

## Acceptance Criteria

1. **Given** configured ER integration credentials on backend
   **When** sync job runs
   **Then** it requests updates using `updated_since`/high-watermark cursor
   **And** stores cursor state for next run.

2. **Given** rate-limit or transient ER failures
   **When** sync retries are executed
   **Then** exponential backoff with jitter is applied
   **And** errors are logged with traceable context.

## Tasks / Subtasks

- [x] Task 1: Add incident mirror + cursor persistence primitives (AC: 1)
  - [x] Add Supabase data-access helpers for incident mirror upsert and sync cursor read/write.
  - [x] Ensure incident upsert is idempotent by stable ER event key (e.g., `er_event_id`).
  - [x] Store/retrieve stream cursor from `sync_cursors` for the incident stream.

- [x] Task 2: Implement incremental incident sync cycle in backend worker (AC: 1)
  - [x] Add a dedicated incident sync cycle in `app/src/sync.py` that loads previous cursor and passes `updated_since` to ER event fetch.
  - [x] Normalize ER payloads into incident mirror rows with defensive parsing for wrapper variations (`data/results` + optional fields).
  - [x] Reuse existing sync orchestration patterns (`run_sync_cycle`, logger conventions, settings-driven retries) instead of creating parallel ad-hoc worker flow.
  - [x] Persist new high-watermark cursor only after successful upsert.

- [x] Task 3: Add retry policy with exponential backoff + jitter for transient failures (AC: 2)
  - [x] Implement retry schedule using configured max attempts and bounded exponential delays.
  - [x] Include jitter in retry delay calculation to avoid synchronized retry spikes.
  - [x] Treat transient errors (including throttling/rate-limit responses) as retryable and preserve cursor safety.

- [x] Task 4: Improve observability and operational safety in sync worker (AC: 2)
  - [x] Emit structured logs with stream name, attempt number, cursor window, fetched count, upserted count, and error context.
  - [x] Keep existing sync loop behavior stable so one failed cycle does not crash the background worker thread.
  - [x] Keep all EarthRanger polling server-side only; no mobile/client ER polling paths.

- [x] Task 5: Add deterministic automated tests for incremental sync behavior (AC: 1, 2)
  - [x] Add backend tests (e.g., `app/tests/test_sync_incidents.py`) that mock ER + persistence to validate cursor bootstrap/update behavior.
  - [x] Add test coverage for retry/backoff+jitter behavior on transient failures.
  - [x] Add test coverage for no-op cycles (no new events) and malformed/partial event payload handling.

- [x] Review Follow-ups (AI)
  - [x] [AI-Review][High] Harden incident mapper against non-dict payload shapes to avoid crash-path sync failures.
  - [x] [AI-Review][High] Add cursor overlap + idempotent dedupe safeguards to reduce high-watermark boundary miss risk.
  - [x] [AI-Review][High] Deduplicate incident rows by `er_event_id` in-batch before persistence.
  - [x] [AI-Review][Medium] Advance cursor from source watermark even when rows are filtered malformed, preventing poison replay loops.
  - [x] [AI-Review][Medium] Preserve structured sync tracing fields in JSON logging output.
  - [x] [AI-Review][High] Guard top-level ER events payload shape and fail cycle for malformed wrappers instead of silent no-op success.
  - [x] [AI-Review][High] Strengthen monotonic cursor safety by re-checking latest stream cursor before write and preventing stale overwrite paths.
  - [x] [AI-Review][Medium] Honor upstream `Retry-After` guidance on rate-limit retries before fallback exponential backoff+jitter.
  - [x] [AI-Review][High] Make JSON formatter nested-extra serialization safe for non-primitive values.
  - [x] [AI-Review][Medium] Expand regression coverage for malformed payload failure paths, upsert-failure cursor safety, and sync-log trace context assertions.
  - [x] [AI-Review][High] Remove text-order cursor comparison dependency and enforce compare-and-swap style monotonic cursor updates.
  - [x] [AI-Review][High] Narrow insert exception handling in cursor persistence to race/unique conflicts only; re-raise non-conflict failures.
  - [x] [AI-Review][Medium] Use persisted `set_sync_cursor()` result as authoritative `cursor_after` in sync response/log context.
  - [x] [AI-Review][Medium] Treat invalid persisted cursor values as explicit sync failure instead of silent full-history fallback.
  - [x] [AI-Review][Medium] Add cycle detection to JSON formatter recursive `extra` sanitization.
  - [x] [AI-Review][Medium] Add direct cursor persistence unit tests (race + non-race + invalid stored cursor scenarios).
  - [x] [AI-Review][High] Reject explicit non-positive sync interval overrides and treat initial cursor read runtime failures as controlled failed-cycle results.
  - [x] [AI-Review][High] Handle NULL/empty-string cursor rows in CAS updates to prevent false contention loops.
  - [x] [AI-Review][High] Normalize/drop malformed nested tree payload shapes so single bad records cannot fail the tree cycle.
  - [x] [AI-Review][Medium] Expand regressions for interval override guards, runtime cursor read failures, empty-string cursor recovery, and tree nested-shape normalization branches.

## Dev Notes

### Technical Requirements

- This story implements `FR-INT-001` and `FR-INT-002`.
- EarthRanger ingestion must remain backend-only and cursor-driven (`updated_since` / high-watermark).
- Incident mirror writes must be replay-safe and deterministic for downstream mobile read APIs.

### Architecture Compliance

- Preserve BFF boundary: mobile clients consume backend APIs, while backend workers own ER sync.
- Keep implementation aligned with existing singleton access patterns (`get_settings()`, `get_er_client()`, `get_supabase()`).
- Keep sync worker behavior compatible with current startup model (`server.py` lifespan launches background `run_loop`).

### Library and Framework Requirements

- Reuse existing `EarthRangerClient.get_events(..., updated_since=...)` in `app/src/earthranger.py`.
- Prefer Python stdlib (`datetime`, `time`, `random`) for retry/jitter; avoid introducing new dependencies unless strictly necessary.
- Keep UTC-aware timestamps (`datetime.now(timezone.utc)` / `.isoformat()`) and structured logging via module logger.

### File Structure Requirements

- Primary backend modules to extend:
  - `app/src/sync.py`
  - `app/src/supabase_db.py`
  - `app/src/models.py` (if event→incident row mapping helpers are introduced)
  - `app/src/config.py` (only if additional sync tuning settings are needed)
- Tests should be added under `app/tests/` and follow existing `unittest` + `fastapi.testclient` conventions.

### Project Structure Notes

- Keep implementation inside the established backend surface (`app/src/`) and avoid introducing duplicate sync entrypoints in scripts unless explicitly required.
- Preserve compatibility with current lifecycle startup path in `app/src/server.py` where background sync is spawned once.
- Prefer extending existing modules over creating competing abstractions for ER fetch, mapping, and persistence.

### Testing Requirements

- Tests must be deterministic and avoid live ER/Supabase calls.
- Use mocking for ER fetch responses, transient failures, and persistence outcomes.
- Validate both happy-path and failure-path behavior:
  - cursor loaded/applied on read,
  - cursor updated only on successful persistence,
  - retries/backoff+jitter applied on retryable failures,
  - logs include actionable correlation context.

### Implementation Guardrails

- Do **not** implement direct mobile polling to EarthRanger.
- Do **not** reset or advance cursor when upsert fails.
- Do **not** break existing `tree_rep` sync behavior while introducing incident sync capability.
- Do **not** replace singleton clients with per-request object construction.
- Do **not** add hardcoded secrets/tokens in code or test fixtures.

### References

- Story definition + ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 4, Story 4.1)]
- Integration/sync architecture: [Source: `_bmad-output/planning-artifacts/architecture.md` (Sections 3 AD-07, 4.2, 4.3, 8)]
- Product requirements: [Source: `_bmad-output/planning-artifacts/prd.md` (FR-INT-001, FR-INT-002; Section 6.6)]
- Project implementation rules: [Source: `_bmad-output/project-context.md` (Data Sync, Polling & Retention Rules; Framework-Specific Rules)]
- Existing backend sync code: [Source: `app/src/sync.py`]
- Existing ER client with `updated_since`: [Source: `app/src/earthranger.py`]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py -v` → pass (`Ran 4 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 47 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py tests/test_logging_config.py -v` → pass (`Ran 8 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 51 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py tests/test_logging_config.py -v` → pass (`Ran 15 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 58 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py tests/test_logging_config.py tests/test_supabase_sync_cursors.py -v` → pass (`OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 65 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py tests/test_logging_config.py tests/test_supabase_sync_cursors.py -v` → pass (`Ran 31 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 74 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py tests/test_logging_config.py tests/test_supabase_sync_cursors.py -v` → pass (`Ran 33 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 76 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_sync_incidents.py tests/test_logging_config.py tests/test_supabase_sync_cursors.py -v` → pass (`Ran 34 tests`, `OK`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` → pass (`Ran 77 tests`, `OK`)

### Completion Notes List

- Added incident mirror persistence helpers in `supabase_db.py`:
  - `upsert_incidents(rows)` with idempotent upsert on `er_event_id`
  - `get_sync_cursor(stream_name)` and `set_sync_cursor(stream_name, cursor_value)` for high-watermark state
- Added defensive ER incident mapping in `models.py`:
  - `event_to_incident_row(ev)` with robust ISO datetime normalization and ranger identity fallback extraction
- Extended `sync.py` with incremental incident pipeline:
  - `run_incident_sync_cycle()` uses persisted cursor and `updated_since` fetches
  - retry handling for transient/rate-limit failures with exponential backoff + jitter
  - structured logging for attempt, cursor window, fetched/upserted counts, and retry context
- Preserved existing tree sync behavior by keeping tree cycle logic and composing both tree + incident cycles in `run_sync_cycle()`.
- Added deterministic regression suite `test_sync_incidents.py` covering:
  - cursor bootstrap and high-watermark advancement
  - retry/backoff/jitter on transient failures
  - no-op cycles with no cursor movement
  - malformed event filtering before persistence
- Addressed code-review follow-ups with additional robustness hardening:
  - defensive payload type guards in incident mapper paths
  - 1-second cursor overlap to reduce strict-boundary misses
  - in-batch `er_event_id` dedup with newest-update precedence
  - source-watermark cursor advancement when fetched payloads are malformed
  - JSON logging enhancement to include custom structured `extra` fields (sync tracing metadata)
- Expanded tests for follow-up fixes:
  - duplicate event ID dedupe behavior
  - non-dict event shape resilience
  - malformed-only batch cursor progression
  - logging formatter inclusion of sync trace metadata
- Applied second review-fix hardening pass:
  - normalized/validated ER payload envelope (`list`, `results`, `data`, `data.results`) with explicit failure for unsupported shapes
  - fail-fast protection for `fetched > 0` batches that produce no parseable watermark (prevents silent "green but stuck" cycles)
  - pre-write latest-cursor recheck in sync flow to avoid stale cursor overwrite when another worker already advanced stream state
  - `Retry-After` support for HTTP throttling responses, with bounded fallback to exponential backoff+jitter
  - monotonic cursor persistence logic in `set_sync_cursor()` with normalized UTC cursor values and stale-write rejection path
  - recursive JSON-safe serialization for nested `extra` structures in logging formatter
- Expanded tests for second pass:
  - malformed top-level payload wrapper failure behavior
  - unparseable-event batch failure behavior without watermark
  - cursor skip behavior when stream already advanced externally
  - cursor safety when upsert fails
  - sync-level retry log context assertions
  - `Retry-After` precedence over backoff+jitter
  - nested non-serializable logging extras serialization
- Applied third review-fix hardening pass:
  - replaced text-based cursor ordering in persistence flow with compare-and-swap style row updates keyed by prior stored cursor value
  - raised explicit validation failures for malformed stored cursor values (both read and write paths) instead of silently degrading cursor behavior
  - narrowed insert error handling to unique/race conflicts only; non-conflict storage errors now surface immediately
  - updated sync cycle to fail fast on invalid initial cursor and to use persisted cursor payload from `set_sync_cursor()` as authoritative `cursor_after`
  - added cycle-safe recursion handling (`<cycle>`, depth cap) for structured logging extras
- Expanded tests for third pass:
  - invalid stored cursor failure before fetch
  - authoritative `cursor_after` sourced from persisted cursor response
  - dedicated `supabase_db` cursor tests for invalid stored value, monotonic update, non-conflict insert failure, and insert-race reconciliation
  - logging formatter cycle-handling regression test
- Applied final review-fix hardening pass:
  - handled initial cursor read runtime exceptions as controlled failed-cycle responses
  - fixed explicit `run_loop(interval_min=0)` override path to enforce non-positive interval rejection
  - updated cursor CAS logic to recover when existing stored cursor is `NULL` or empty-string/whitespace sentinel values
  - normalized tree event payloads defensively to drop malformed nested `event_details` objects and sanitize malformed `location` / `updates` fields
- Expanded tests for final pass:
  - runtime cursor-read exception failure-path coverage
  - explicit zero-interval override guard coverage
  - `set_sync_cursor()` recovery from existing empty-string cursor rows
  - tree sync regression coverage for malformed nested payloads and malformed location/updates normalization branches
- Final adversarial release-gate review found no actionable findings and cleared Story 4.1 for forward movement.

### File List

- `_bmad-output/implementation-artifacts/4-1-server-side-incremental-earthranger-sync-worker.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `app/src/models.py`
- `app/src/logging_config.py`
- `app/src/supabase_db.py`
- `app/src/sync.py`
- `app/tests/test_logging_config.py`
- `app/tests/test_supabase_sync_cursors.py`
- `app/tests/test_sync_incidents.py`

## Change Log

- 2026-03-20: Story file created and set to `ready-for-dev`.
- 2026-03-20: Story execution started via `bmad-dev-story`; sprint status moved to `in-progress`.
- 2026-03-20: Implemented incremental server-side incident sync worker with cursor persistence, retry backoff+jitter, defensive mapping, and automated regression tests; story moved to `review`.
- 2026-03-20: Addressed code-review findings with sync robustness hardening (boundary overlap, malformed-shape guards, in-batch dedupe, logging metadata emission) and expanded regression coverage.
- 2026-03-20: Addressed second code-review pass findings with payload-envelope validation, `Retry-After` retry support, monotonic cursor hardening, nested logging serialization safety, and additional guardrail tests.
- 2026-03-20: Addressed third code-review pass findings with CAS-style cursor persistence semantics, explicit invalid-cursor failure handling, authoritative persisted cursor reporting, cycle-safe logging extras, and direct cursor persistence unit tests.
- 2026-03-20: Addressed final review-fix pass with explicit interval override guard, runtime cursor-read failure containment, empty-string cursor-row recovery, and tree nested payload normalization hardening with expanded regressions.
- 2026-03-20: Final adversarial review gate returned no actionable findings; story status moved to `done`.
