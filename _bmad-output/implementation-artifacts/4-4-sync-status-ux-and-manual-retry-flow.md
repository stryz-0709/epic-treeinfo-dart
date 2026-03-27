# Story 4.4: Sync Status UX and Manual Retry Flow

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a mobile user,
I want visible sync status and retry controls,
so that I understand whether my offline actions are safely persisted.

## Acceptance Criteria

1. **Given** queued actions in mixed states
   **When** sync status UI renders
   **Then** each action is shown as `synced`, `pending`, or `failed`
   **And** status transitions are reflected in near real time.

2. **Given** failed queued actions
   **When** user selects retry
   **Then** replay is re-attempted with current connectivity context
   **And** UX behavior aligns with UX-DR-005.

## Tasks / Subtasks

- [x] Task 1: Expose queue status models for UI consumption in Work Management state layer (AC: 1)
  - [x] Extend `WorkManagementProvider` with read-only sync status view models derived from `MobileCheckinReplayQueue` records.
  - [x] Keep status mapping explicit (`pending`, `synced`, `failed`) and include retry metadata needed by UI (`attemptCount`, `nextRetryAt`, `lastError`, `updatedAt`).
  - [x] Ensure queue summaries and status list refresh after replay/check-in flows and notify listeners for near-real-time updates.

- [x] Task 2: Add Sync Status UX block to Work Management screen (AC: 1)
  - [x] Render a compact sync status panel in `work_management_screen.dart` with counts and per-item status rows/chips.
  - [x] Show clear visual state and text for `synced`, `pending`, and `failed` items.
  - [x] Preserve existing loading/empty/error behavior and avoid regressing role-based Work Management display.

- [x] Task 3: Implement manual retry interaction for failed queue items (AC: 2)
  - [x] Add provider APIs for retrying failed queued actions (single item and/or failed batch) using existing replay semantics.
  - [x] Wire retry controls in UI for failed items and disable controls while replay is in-flight.
  - [x] Surface deterministic user feedback for retry outcomes without exposing raw backend/internal errors.

- [x] Task 4: Keep replay behavior aligned with Phase 1 sync constraints (AC: 1, 2)
  - [x] Reuse existing backend endpoint contract `/api/mobile/checkins` and idempotent response handling (`created` / `already_exists`).
  - [x] Do not add direct EarthRanger polling or leader schedule offline write paths.
  - [x] Keep retry policy behavior consistent with queue baseline from Story 4.3 (initial 5s, max 15m, max 8 attempts).

- [x] Task 5: Add deterministic automated tests for sync status and manual retry flows (AC: 1, 2)
  - [x] Extend `work_management_provider_test.dart` for sync-status mapping, transitions, and failed->retry->synced paths.
  - [x] Add/extend widget tests for sync-status rendering and retry controls in Work Management UI.
  - [x] Re-run targeted mobile tests and full mobile regression suite.

## Dev Notes

### Technical Requirements

- Implements `FR-SYNC-006` and UX requirement `UX-DR-005`.
- Sync status UX must accurately reflect queue state from offline write queue (`pending`, `synced`, `failed`).
- Manual retry must trigger replay using current connectivity context and preserve idempotent safety.

### Architecture Compliance

- Preserve BFF boundary: replay and retry continue through backend `/api/mobile/checkins` only.
- Keep Provider/service split (`providers/*` orchestrates UI state, `services/*` encapsulates queue and network behavior).
- Keep existing queue/replay semantics from Story 4.3 as source of truth; Story 4.4 adds UX and operator controls, not a protocol redesign.

### Library and Framework Requirements

- Reuse existing Flutter dependencies and existing queue/provider abstractions.
- Avoid introducing new packages unless absolutely required by acceptance criteria.
- Continue existing state lifecycle patterns (`notifyListeners`, non-blocking UI updates, deterministic error messaging).

### File Structure Requirements

- Primary implementation targets:
  - `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
  - `mobile/epic-treeinfo-dart/lib/widgets/` (if extracting sync-status components)
  - `mobile/epic-treeinfo-dart/lib/services/mobile_checkin_queue.dart` (only if minimal API exposure updates are required)
- Test targets:
  - `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`
  - `mobile/epic-treeinfo-dart/test/work_management_screen_test.dart` (or equivalent widget test file)

### Previous Story Intelligence

- Story 4.3 already established durable queue + replay + bounded retry semantics; this story should consume that state and expose UX controls, not duplicate queue logic.
- Story 4.2 already implemented stale/offline state patterns in Work Management UI; reuse existing banner/state patterns for consistency.
- Existing provider tests already cover queue transitions and replay behavior; extend these tests to validate user-facing sync status and manual retry outcomes.

### Testing Requirements

- Tests must be deterministic and mock-only (no live backend/ER/Supabase dependencies).
- Validate status transitions visible to UI (`pending -> synced`, `failed -> pending/synced`, and retry-disabled while replaying).
- Validate failed-item retry uses current session/access token handling and avoids enqueueing auth-invalid cases.

### Implementation Guardrails

- Do **not** alter Phase 1 scope by adding offline support for leader schedule writes.
- Do **not** regress existing role-scoped Work Management behavior or cache-first read flows.
- Do **not** bypass queue service invariants for status transitions or retry policy.
- Do **not** expose privileged/internal details in user-facing error text.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 4, Story 4.4)]
- PRD sync requirement: [Source: `_bmad-output/planning-artifacts/prd.md` (Section 6.5 FR-SYNC-006)]
- Architecture sync constraints: [Source: `_bmad-output/planning-artifacts/architecture.md` (AD-06, AD-10, Section 8)]
- Project rules: [Source: `_bmad-output/project-context.md` (Phase 1 Mobile Scope, Data Sync rules)]
- Prior implementation learnings: [Source: `_bmad-output/implementation-artifacts/4-3-offline-queue-and-idempotent-replay-for-ranger-writes.md`, `_bmad-output/implementation-artifacts/4-2-mobile-cache-first-read-models.md`]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- Targeted regression: `flutter test test/mobile_checkin_queue_test.dart test/work_management_provider_test.dart test/work_management_screen_test.dart` (pass).
- Full mobile regression: `flutter test` (pass).
- Adversarial review static pass: `flutter analyze` (initially flagged syntax error in `incident_management_screen.dart`; fixed and re-ran; no blocking errors).

### Completion Notes List

- Reconstructed and stabilized `work_management_screen.dart` to restore clean compilation and preserve existing Work Management behavior.
- Implemented sync status panel and manual retry controls for failed check-in queue items.
- Exposed queue-derived sync items and retry actions in `WorkManagementProvider`, including refresh APIs for near-real-time UI status updates.
- Added deterministic provider/widget/unit tests for status mapping and manual retry flow.
- Fixed analyzer-blocking syntax issue in `incident_management_screen.dart` during adversarial pass.
- Adjusted replay identity/day-key validation precedence to preserve expected retry behavior while keeping mismatch protection.
- Removed non-blocking analyzer warnings in incident/schedule providers and queue tests (remaining analyzer output is informational style guidance only).
- Full regression suite passes.

### File List

- `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
- `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_checkin_queue.dart`
- `mobile/epic-treeinfo-dart/lib/services/app_localizations.dart`
- `mobile/epic-treeinfo-dart/test/mobile_checkin_queue_test.dart`
- `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`
- `mobile/epic-treeinfo-dart/test/work_management_screen_test.dart`
- `mobile/epic-treeinfo-dart/lib/screens/incident_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/providers/incident_provider.dart`
- `mobile/epic-treeinfo-dart/lib/providers/schedule_provider.dart`

## Change Log

- 2026-03-23: Story file created and set to `ready-for-dev`.
- 2026-03-23: Story moved to `in-progress` for implementation.
- 2026-03-23: Story completed and set to `done` after passing targeted + full regression and adversarial review fixes.
