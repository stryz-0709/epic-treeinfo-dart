# Story 3.4: Schedule UX for Ranger View and Leader Operations

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a ranger or leader,
I want schedule screens tailored to my role,
so that I can view or manage assignments with minimal confusion.

## Acceptance Criteria

1. **Given** a ranger user
   **When** opening schedule screen
   **Then** schedule entries are visible in read-only mode
   **And** edit controls are hidden.

2. **Given** a leader user
   **When** creating or editing schedule entries online
   **Then** the UI validates required fields and server errors
   **And** successful changes refresh visible schedule data.

3. **Given** UX design requirements for schedule states
   **When** schedule UI is implemented
   **Then** role actions, empty states, and error messages align with UX-DR-004.

## Tasks / Subtasks

- [x] Task 1: Implement schedule data integration layer in mobile service (AC: 1, 2)
  - [x] Add typed schedule models aligned with `GET /api/mobile/schedules` and leader write responses.
  - [x] Add authenticated fetch/create/update methods for schedule APIs.
  - [x] Keep API integration role-safe with backend bearer token contracts.

- [x] Task 2: Add role-aware schedule provider state management (AC: 1, 2, 3)
  - [x] Add provider state for loading, empty, error, and refresh transitions.
  - [x] Support ranger read-only scope and leader editing operations.
  - [x] Validate leader write input fields before API submission and track submit errors.

- [x] Task 3: Implement Schedule Management screen UX by role (AC: 1, 2, 3)
  - [x] Replace placeholder schedule route with a dedicated schedule screen.
  - [x] Render read-only schedule list for ranger sessions with edit/create controls hidden.
  - [x] Render leader create/edit controls with validation feedback and post-save refresh.
  - [x] Render loading, empty, and error states with localized messages.

- [x] Task 4: Add deterministic mobile regression tests (AC: 1, 2, 3)
  - [x] Add provider tests for ranger read-only behavior and hidden edit actions.
  - [x] Add tests for leader create/update validation and successful refresh behavior.
  - [x] Add tests for loading/empty/error state transitions.

- [x] Task 5: Validate implementation and document evidence (AC: 1, 2, 3)
  - [x] Run available automated tests and capture results.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-SCH-001`, `FR-SCH-002`, and `FR-SCH-003`.
- UX must consume schedule APIs from Story 3.3 (`GET`, `POST`, `PUT /api/mobile/schedules...`).
- Ranger mode must remain read-only in UI and must not expose create/edit affordances.

### Architecture Compliance

- Keep network contract handling in `services/` and state orchestration in Provider classes.
- Keep server-side role scope as source of truth, with UI role rendering derived from authenticated session + API scope payload.
- Keep route wiring and screen design consistent with existing Work/Incident management patterns.

### Testing Requirements

- Add deterministic provider-level tests with fake API adapters (no live backend dependency).
- Cover role-aware UX logic paths (ranger read-only, leader edit flows).
- Cover validation and failure paths for leader schedule writes.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 3, Story 3.4)]
- API baseline: [Source: `_bmad-output/planning-artifacts/architecture.md` (Section 6.4)]
- Project rules: [Source: `_bmad-output/project-context.md` (Provider/service boundaries + role-safe rendering)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `flutter --version` attempted in `mobile/epic-treeinfo-dart` (blocked: `flutter` command not recognized in environment)
- `python -m unittest discover -s tests` from `app/` → pass (`Ran 42 tests`, `OK`)
- `flutter test test/schedule_provider_test.dart` from `mobile/epic-treeinfo-dart` → pass (`All tests passed`, latest run `+12`)
- `flutter test` from `mobile/epic-treeinfo-dart` → pass (`All tests passed`, latest run `+52`)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` from `app/` → pass (`Ran 102 tests`, `OK`)

### Completion Notes List

- Extended mobile API contracts with typed schedule models and endpoints for read/create/update (`GET/POST/PUT /api/mobile/schedules...`).
- Added `ScheduleProvider` with role-aware scope handling, month/filter controls, loading/empty/error states, and leader-only write validation paths.
- Implemented `ScheduleManagementScreen` to replace placeholder route with ranger read-only list and leader create/edit UX using validated form input.
- Added schedule localization keys for both Vietnamese and English to cover role labels, action buttons, validation, and state messaging.
- Wired new schedule provider and screen through `main.dart` route/provider graph.
- Added deterministic provider regression tests for ranger read-only behavior, leader filter behavior, leader create/update flows, and error handling.
- Applied adversarial review remediation cycle: sanitized API-facing schedule errors, enforced in-flight submit guard, hardened month-navigation/load race handling, trimmed editor ranger input, stabilized leader dropdown selected value, and added deterministic regression coverage for concurrent operations.
- Re-ran targeted + full mobile regressions and full backend regressions after remediation; all suites remain green.
- Final review adjudication: no actionable findings remain for Story 3.4 scope.

### File List

- `_bmad-output/implementation-artifacts/3-4-schedule-ux-for-ranger-view-and-leader-operations.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `mobile/epic-treeinfo-dart/lib/main.dart`
- `mobile/epic-treeinfo-dart/lib/providers/schedule_provider.dart`
- `mobile/epic-treeinfo-dart/lib/screens/schedule_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/services/app_localizations.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
- `mobile/epic-treeinfo-dart/test/schedule_provider_test.dart`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented schedule UX by role (ranger read-only + leader create/edit), added provider/service/test coverage, and moved story to review with Flutter CLI limitation documented.
- 2026-03-23: Completed strict adversarial fix/test loops (High→Medium→Low), revalidated targeted + full regressions, and closed story as done.
