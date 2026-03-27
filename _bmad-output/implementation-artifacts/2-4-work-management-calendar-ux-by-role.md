# Story 2.4: Work Management Calendar UX by Role

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a leader or ranger,
I want a clear Work Management calendar UI with role-appropriate controls,
so that I can quickly understand check-in coverage.

## Acceptance Criteria

1. **Given** a leader user
   **When** opening Work Management
   **Then** a ranger filter/drop-list is available
   **And** the selected ranger/team scope is reflected in calendar data.

2. **Given** a ranger user
   **When** opening Work Management
   **Then** only self calendar data is shown
   **And** no controls for viewing other rangers are displayed.

3. **Given** loading, empty, or error states
   **When** the calendar screen renders
   **Then** clear UX states are shown
   **And** they align with UX-DR-001 and UX-DR-002.

## Tasks / Subtasks

- [x] Task 1: Add role-aware Work Management calendar screen (AC: 1, 2)
  - [x] Replace current Work Management placeholder route with dedicated calendar screen.
  - [x] Render month grid with per-day check-in coverage indicators.
  - [x] Keep ranger view self-scoped and hide leader-only controls.

- [x] Task 2: Add leader ranger-filter/drop-list interaction (AC: 1)
  - [x] Show ranger filter control only for leader scope.
  - [x] Wire filter changes to summary API query (`ranger_id`) and refresh calendar data.
  - [x] Preserve team-scope view when no ranger is selected.

- [x] Task 3: Add UX state handling for loading/empty/error (AC: 3)
  - [x] Show loading state while summary data is in flight.
  - [x] Show explicit empty state when no summary rows exist for the selected scope/month.
  - [x] Show recoverable error state with retry action when fetch fails.

- [x] Task 4: Add provider/service support and tests (AC: 1, 2, 3)
  - [x] Extend mobile API service for `GET /api/mobile/work-management` query/response parsing.
  - [x] Extend `WorkManagementProvider` with calendar summary role/filter state.
  - [x] Add provider tests for leader filter behavior, ranger self scope, and UX state transitions.

- [x] Task 5: Validate implementation and document evidence (AC: 1, 2, 3)
  - [x] Run targeted and full Flutter tests successfully in workspace (`work_management_provider_test.dart` and full `flutter test`).
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-WM-001`, `FR-WM-002`, `FR-WM-005`, and `FR-WM-006`.
- Calendar UX consumes backend summary endpoint `GET /api/mobile/work-management` introduced in Story 2.1.
- Leader filter behavior should map to backend ranger scope semantics (`ranger_id` optional for team scope).

### Architecture Compliance

- Keep state management within existing Provider boundaries (`WorkManagementProvider`).
- Keep API calls in services layer (`mobile_api_service.dart`) and avoid embedding HTTP logic in widgets.
- Preserve role enforcement as server-side source of truth; UI controls mirror but do not replace backend checks.

### Testing Requirements

- Add deterministic provider-level tests for role/filter and state transitions.
- Cover loading, empty, and error flows.
- Keep tests independent from live backend dependencies.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 2, Story 2.4)]
- Architecture decision references: [Source: `_bmad-output/planning-artifacts/architecture.md` (AD-03, Section 6.2)]
- Project rules: [Source: `_bmad-output/project-context.md` (Provider/service boundaries + role-scope rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `flutter test test/work_management_provider_test.dart` from `mobile/epic-treeinfo-dart` (20 tests passed)
- `flutter test` from `mobile/epic-treeinfo-dart` (39 tests passed)
- `python -m unittest discover -s tests` from `app/` (97 tests passed)
- Final defect-only adversarial review pass (no actionable findings)

### Completion Notes List

- Added dedicated `WorkManagementScreen` and routed `/work-management` to a role-aware calendar UX instead of generic placeholder content.
- Added month grid rendering with per-day indicator logic derived from summary coverage (`checked` vs `total`) and selected-day detail text.
- Added leader-only ranger filter/drop-list and wired filter changes to scoped summary reloads.
- Added explicit loading, empty, and recoverable error states (with retry) for summary fetch UX.
- Extended `MobileApiService` with typed work-summary models and `GET /api/mobile/work-management` query/response parsing.
- Extended `WorkManagementProvider` with month navigation, role/scope/filter state, and day-level aggregation helpers while preserving existing app-open check-in logic.
- Added and expanded provider tests for leader team/filter behavior, ranger self scope, missing-token state, and API-failure state.
- Added localization keys for new calendar role/filter/state strings in both Vietnamese and English.
- Resolved adversarial review findings with production-safe fixes: stale async request guard, role clamping to mobile claims, paginated summary fetch, session-scoped filter reset, non-fatal cache failure handling, and sanitized error messaging.
- Added retry action for refresh-error banner and hardened leader filter dropdown binding/value handling.
- Added/updated provider tests for race conditions, pagination overflow, session rollover isolation, cache read/save failure resilience, and check-in failure state reset.
- Final closure verification completed: targeted tests green, full mobile regression green, full backend regression green, and final adversarial review returned zero actionable defects.

### File List

- `_bmad-output/implementation-artifacts/2-4-work-management-calendar-ux-by-role.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `mobile/epic-treeinfo-dart/lib/main.dart`
- `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
- `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/services/app_localizations.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
- `mobile/epic-treeinfo-dart/pubspec.yaml`
- `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented role-aware Work Management calendar UX, leader filter interactions, provider/service integrations, and provider regression tests; moved story to review with Flutter CLI limitation documented.
- 2026-03-23: Executed strict autonomous dev→adversarial-review loop; applied High→Medium→Low findings until no actionable defects remained and all targeted/full regressions passed; story moved to done.
- 2026-03-23: Finalized closure evidence with updated regression totals and zero-actionable final review confirmation.
