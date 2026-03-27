# Story 4.3: Offline Queue and Idempotent Replay for Ranger Writes

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a ranger,
I want offline check-in/stat actions queued and replayed safely,
so that my attendance records remain correct after reconnect.

## Acceptance Criteria

1. **Given** offline state during check-in/stat action
   **When** action is captured
   **Then** queue item is saved with idempotency key format `user_id + action_type + day_key + client_uuid`
   **And** item is marked pending.

2. **Given** reconnect and replay cycle
   **When** queued items are submitted
   **Then** backend idempotency guarantees prevent duplicates
   **And** retries follow configured backoff policy (initial 5s, max 15m, max 8 attempts).

## Tasks / Subtasks

- [x] Task 1: Add durable offline write-queue primitives for ranger check-in actions (AC: 1)
  - [x] Introduce mobile write-queue service in `mobile/epic-treeinfo-dart/lib/services/` with SharedPreferences persistence and defensive parsing.
  - [x] Define queue record fields needed for replay safety: `user_id`, `action_type`, `day_key`, `client_uuid`, `idempotency_key`, `status`, `attempt_count`, `next_retry_at`, timestamps, and last error.
  - [x] Enforce idempotency key composition `user_id + action_type + day_key + client_uuid` when enqueueing offline writes.

- [x] Task 2: Integrate queue capture into app-open ranger check-in flow (AC: 1)
  - [x] Update check-in API payload builder in mobile service/provider to send idempotency metadata (`idempotency_key`, `client_time`, `timezone`, `app_version`) to backend.
  - [x] In `WorkManagementProvider.triggerAppOpenCheckin`, queue writes on offline/transient failure paths and mark queued record as `pending`.
  - [x] Keep auth-failure behavior safe (do not endlessly enqueue invalid-session failures).

- [x] Task 3: Implement replay orchestration with bounded retry policy (AC: 2)
  - [x] Add replay routine that submits ready pending items on reconnect/app resume.
  - [x] Apply exponential backoff with jitter using baseline policy: initial 5s, capped 15m, max 8 attempts then `failed` state.
  - [x] Mark successful replay items `synced` and preserve idempotent correctness when backend returns `already_exists`.

- [x] Task 4: Preserve compatibility with existing backend idempotent ingest contract (AC: 2)
  - [x] Keep `/api/mobile/checkins` replay-safe behavior (server dedupe by `user_id + day_key`) and pass client idempotency key unchanged.
  - [x] Keep project day boundary policy aligned with `Asia/Ho_Chi_Minh` when composing client day key.
  - [x] Ensure no direct EarthRanger polling is introduced in mobile write flow.

- [x] Task 5: Add deterministic automated tests for queue + replay behavior (AC: 1, 2)
  - [x] Add unit tests for queue persistence/state transitions/backoff timing in `mobile/epic-treeinfo-dart/test/`.
  - [x] Extend `work_management_provider_test.dart` to validate offline enqueue, pending state, replay success, duplicate-safe replay (`already_exists`), retry isolation, and integrity mismatch handling.
  - [x] Re-run targeted and full regression test suites for mobile + backend idempotent check-in coverage.

## Dev Notes

### Technical Requirements

- Implements `FR-SYNC-002`, `FR-SYNC-003`, `FR-SYNC-004`, `FR-SYNC-005`.
- Queue records must include idempotency key parts (`user_id`, `action_type`, `day_key`, `client_uuid`) and be replay-safe.
- Retry policy baseline is fixed for Phase 1: initial 5s, max 15m, maximum 8 attempts, then `failed` with manual retry path handled by later UX story.

### Architecture Compliance

- Keep BFF boundary intact: mobile writes only to backend `/api/mobile/checkins` (no direct ER/mobile polling).
- Preserve Provider/service split (`providers/*` orchestrates state, `services/*` encapsulates IO/persistence).
- Keep backend idempotency semantics authoritative (`created` / `already_exists`), with mobile replay treating both as successful persistence outcomes.

### Library and Framework Requirements

- Reuse existing Flutter dependencies only; prefer `shared_preferences` for queue persistence.
- Avoid adding new packages for UUID/timezone unless strictly necessary; keep implementation lightweight and deterministic for unit tests.
- Continue existing provider lifecycle patterns (`notifyListeners`, loading/error/offline state separation).

### File Structure Requirements

- Primary implementation targets:
  - `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
  - `mobile/epic-treeinfo-dart/lib/services/` (new offline queue service)
  - `mobile/epic-treeinfo-dart/lib/providers/auth_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/main.dart`
- Test targets:
  - `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`
  - `mobile/epic-treeinfo-dart/test/` (new queue service tests)

### Previous Story Intelligence

- Story 4.2 already introduced cache-first read models and stale/offline state handling in mobile providers; avoid duplicating caching logic and instead extend provider behavior for write queue lifecycle.
- Story 4.1 hardened backend retry/backoff semantics and structured logging; reuse those guardrail ideas for mobile replay behavior (bounded retries, deterministic tests, defensive parsing).
- Existing check-in flow is already app-open-triggered and idempotent server-side; this story should wrap that flow with durable offline capture + replay, not redesign backend contract.

### Testing Requirements

- Tests must be deterministic and mock-only (no live backend/ER/Supabase dependencies).
- Validate all queue state transitions: `pending -> synced`, `pending -> failed` after max attempts, and `pending` retention with scheduled `next_retry_at`.
- Validate replay behavior when backend responds `already_exists` to guarantee duplicate-safe completion.

### Implementation Guardrails

- Do **not** queue leader schedule writes in this story (Phase 1 scope excludes this).
- Do **not** regress existing role-scoped read models from Story 4.2.
- Do **not** enqueue on invalid-session auth failures (401/403); surface re-auth path instead.
- Do **not** create alternate check-in endpoints; replay must reuse existing `/api/mobile/checkins`.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 4, Story 4.3)]
- PRD sync requirements: [Source: `_bmad-output/planning-artifacts/prd.md` (Section 6.5 FR-SYNC-002..005)]
- Architecture offline write policy: [Source: `_bmad-output/planning-artifacts/architecture.md` (AD-04, AD-06, AD-10, Section 8)]
- Project rules: [Source: `_bmad-output/project-context.md` (Phase 1 Mobile Scope, Data Sync rules)]
- Prior implementation learnings: [Source: `_bmad-output/implementation-artifacts/4-2-mobile-cache-first-read-models.md`, `_bmad-output/implementation-artifacts/4-1-server-side-incremental-earthranger-sync-worker.md`]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `flutter test test/work_management_provider_test.dart test/mobile_checkin_queue_test.dart test/work_management_screen_test.dart` (pass)
- `flutter test` (pass)
- `python -m unittest discover -s tests -v` from `app/` (pass, 108 tests)

### Completion Notes List

- Added durable offline queue behavior and replay hardening for ranger check-ins with bounded retry/backoff and SharedPreferences persistence.
- Added user-scoped queue summaries/replay reads and user-scoped mutation guards on sync/failure/manual-retry transitions.
- Enforced strict direct/replay integrity checks for day-key and non-empty idempotency-key mismatches.
- Added check-in request timeout handling in mobile API service (`408` mapping for timeout).
- Added/updated deterministic mobile tests for replay mismatch handling, user scoping, single-item retry isolation, rearm dedupe behavior, and compaction behavior.
- Completed full regression verification across Flutter mobile and Python backend suites.

### File List

- `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_checkin_queue.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
- `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
- `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`
- `mobile/epic-treeinfo-dart/test/mobile_checkin_queue_test.dart`
- `mobile/epic-treeinfo-dart/test/work_management_screen_test.dart`

## Change Log

- 2026-03-23: Story file created and set to `ready-for-dev`.
- 2026-03-23: Completed offline queue/replay hardening, tests, and final verification; status set to `done`.
