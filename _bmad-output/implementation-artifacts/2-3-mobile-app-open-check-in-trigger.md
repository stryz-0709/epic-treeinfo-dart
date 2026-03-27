# Story 2.3: Mobile App-Open Check-In Trigger

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a ranger,
I want check-in to happen automatically on authenticated app open,
so that I do not need a separate manual attendance action.

## Acceptance Criteria

1. **Given** a ranger with valid session
   **When** the app enters foreground on a new day
   **Then** the client submits a check-in request automatically
   **And** updates the local day indicator from the server response.

2. **Given** the same day and repeated app opens
   **When** check-in is triggered again
   **Then** the UI remains stable
   **And** no duplicate daily check-in appears.

## Tasks / Subtasks

- [x] Task 1: Implement mobile app-open lifecycle trigger wiring (AC: 1)
  - [x] Add app lifecycle observer that listens for `resumed` app state.
  - [x] Trigger check-in sync automatically for authenticated ranger sessions.
  - [x] Keep behavior safe/no-op for unauthenticated or non-ranger sessions.

- [x] Task 2: Add mobile check-in service/provider state integration (AC: 1, 2)
  - [x] Add service call to backend `POST /api/mobile/checkins` with bearer token.
  - [x] Store check-in result state (`day_key`, `status`) for local indicator updates.
  - [x] Ensure repeated same-day app opens keep UI stable while backend idempotency prevents duplicates.

- [x] Task 3: Surface local day indicator updates in Work Management placeholder UI (AC: 1, 2)
  - [x] Display latest check-in day/status indicator on `/work-management` placeholder screen.
  - [x] Ensure indicator remains consistent on repeated same-day triggers.

- [x] Task 4: Add automated mobile regression tests (AC: 1, 2)
  - [x] Add provider-level tests for ranger session auto-checkin on app-open trigger.
  - [x] Add tests for repeated same-day trigger stability and idempotent status handling.
  - [x] Add tests for non-ranger/no-session no-op behavior.

- [x] Task 5: Validate implementation and document evidence (AC: 1, 2)
  - [x] Attempted Flutter test execution in workspace environment; blocked because Flutter CLI is not available (`flutter` not recognized).
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-WM-003` and `FR-WM-004` on mobile behavior.
- Trigger point: app foreground/resume should auto-submit check-in for ranger sessions.
- UI should reflect check-in response day indicator and remain stable on repeated same-day triggers.

### Architecture Compliance

- Keep app state in Provider-based boundaries.
- Reuse backend check-in endpoint (`POST /api/mobile/checkins`) introduced by Story 2.2.
- Avoid hardcoding privileged credentials in mobile code.

### Testing Requirements

- Prefer deterministic provider/unit-style tests for lifecycle-trigger logic.
- Validate no-op behavior for non-ranger and missing session.
- Validate repeated same-day behavior does not produce unstable UI state.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 2, Story 2.3)]
- Check-in ingest backend behavior: [Source: `app/src/server.py` (`POST /api/mobile/checkins`)]
- Project rules: [Source: `_bmad-output/project-context.md` (Phase 1 check-in idempotency and server-side enforcement)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `flutter test` from `mobile/epic-treeinfo-dart` (now available in environment; full suite passed: 30 tests)
- `flutter test test/work_management_provider_test.dart` from `mobile/epic-treeinfo-dart` (targeted Story 2.3 suite passed: 11 tests)
- `python -m unittest discover -s tests -v` from `app/` (full backend regression passed: 93 tests)

### Completion Notes List

- Added `MobileApiService` client integration for `POST /api/mobile/checkins` with bearer-token support and typed response/error handling.
- Added `WorkManagementProvider` app-open check-in state (`day_key`, `status`, `isSyncing`, `lastError`) and idempotent/stable UI update flow.
- Added `AppOpenCheckinLifecycle` observer to trigger sync on app start and foreground resume for authenticated ranger sessions only.
- Extended `AuthProvider` with mobile session metadata helpers to support ranger-session gating without leaking token internals to UI layers.
- Wired provider/service/lifecycle registration in `main.dart` and wrapped authenticated app routes so auto-check-in runs without manual action.
- Updated Work Management placeholder UI + localization strings to show current check-in day/status and error/loading hints.
- Added provider-level regression tests for success path, repeated same-day stability, backend `already_exists` handling, and non-ranger/no-session no-op behavior.
- Hardened token handling by trimming/capturing access tokens before mobile API calls to avoid whitespace-token edge cases.
- Extended regression coverage to assert whitespace-token ranger sessions remain explicit no-op for app-open check-in.
- Completed strict adversarial review loop with final verdict: no actionable findings.
- Full mobile + backend regression remained green after final patch (`flutter`: 30 passed, `python unittest`: 93 passed).

### File List

- `_bmad-output/implementation-artifacts/2-3-mobile-app-open-check-in-trigger.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `mobile/epic-treeinfo-dart/lib/main.dart`
- `mobile/epic-treeinfo-dart/lib/providers/auth_provider.dart`
- `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
- `mobile/epic-treeinfo-dart/lib/screens/feature_placeholder_screen.dart`
- `mobile/epic-treeinfo-dart/lib/services/app_localizations.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
- `mobile/epic-treeinfo-dart/lib/widgets/app_open_checkin_lifecycle.dart`
- `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented app-open auto check-in lifecycle/provider/service/UI wiring and provider regression tests; moved story to review with Flutter CLI validation limitation documented.
- 2026-03-23: Executed strict autonomous dev/review/test loop, applied token-handling robustness fix + test hardening, reran targeted and full regressions, and closed story to done after final adversarial review reported no actionable findings.
