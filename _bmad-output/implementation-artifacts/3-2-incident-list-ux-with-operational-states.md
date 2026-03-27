# Story 3.2: Incident List UX with Operational States

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a ranger or leader,
I want incident lists to show meaningful data and state feedback,
so that I can act on incident context even with stale or partial refreshes.

## Acceptance Criteria

1. **Given** incident data returned by API
   **When** the incident list screen renders
   **Then** records reflect role scope correctly
   **And** no cross-ranger leakage appears for ranger users.

2. **Given** empty, loading, stale, or refresh-error conditions
   **When** the screen updates
   **Then** clear UX state messaging is shown
   **And** behavior aligns with UX-DR-003.

## Tasks / Subtasks

- [x] Task 1: Implement mobile incident data integration layer (AC: 1)
  - [x] Extend mobile API service to fetch `GET /api/mobile/incidents` with filters and metadata.
  - [x] Add typed incident list response models aligned with backend contract.
  - [x] Keep API integration role-safe via bearer-token-authenticated requests.

- [x] Task 2: Add incident provider state management (AC: 1, 2)
  - [x] Add provider-level fetch state for loading, error, and last-sync metadata.
  - [x] Support role/scope-aware rendering inputs from backend (`scope`, `items`, `sync`).
  - [x] Track stale state from sync metadata for partial-refresh UX cues.

- [x] Task 3: Implement Incident Management list screen UX (AC: 1, 2)
  - [x] Replace placeholder route with dedicated incident list screen.
  - [x] Render incident records in role-safe list form (ranger/leader labels as applicable).
  - [x] Render loading, empty, stale, and refresh-error states with clear messaging.

- [x] Task 4: Add automated mobile regression tests (AC: 1, 2)
  - [x] Add provider tests for role scope and item mapping behavior.
  - [x] Add tests for loading, empty, stale, and refresh-error transitions.
  - [x] Keep tests deterministic without live backend dependencies.

- [x] Task 5: Validate implementation and document evidence (AC: 1, 2)
  - [x] Executed targeted and full Flutter regression in workspace environment (`flutter test test/incident_provider_test.dart`, `flutter test`).
  - [x] Executed full backend regression suite from `app/` (`python -m unittest discover -s tests -v`).
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-INC-001`, `FR-INC-002`, and `FR-INC-003`.
- Incident list UX consumes backend endpoint `GET /api/mobile/incidents` introduced by Story 3.1.
- UX must include clear operational states for loading, empty, stale, and refresh error flows.

### Architecture Compliance

- Keep state management in Provider boundaries and API transport logic in services.
- Preserve server-side role scope as source of truth; client renders scope-safe data only.
- Keep implementation aligned with existing mobile route/provider patterns.

### Testing Requirements

- Add deterministic provider-level tests for incident list state transitions.
- Validate no cross-ranger rendering in ranger-scoped payload handling.
- Cover stale and refresh-error UX states from API metadata/error paths.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 3, Story 3.2)]
- API baseline: [Source: `_bmad-output/planning-artifacts/architecture.md` (Section 6.3)]
- Project rules: [Source: `_bmad-output/project-context.md` (Phase 1 incidents read-only + role scope)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `flutter test test/incident_provider_test.dart` from `mobile/epic-treeinfo-dart/` (11 tests passed)
- `flutter test` from `mobile/epic-treeinfo-dart/` (42 tests passed)
- `python -m unittest discover -s tests -v` from `app/` (100 tests passed)
- Adversarial review loop executed after each fix cycle; final closure review verdict: PASS with no actionable findings.

### Completion Notes List

- Extended `mobile_api_service.dart` with typed incident models and `fetchIncidents` integration for `GET /api/mobile/incidents`.
- Added `IncidentProvider` for role-scoped incident state management, including loading/empty/error/stale handling and sync metadata tracking.
- Added defensive ranger-side visibility filtering (`visibleIncidents`) to prevent cross-ranger records from rendering in ranger view.
- Implemented dedicated `IncidentManagementScreen` replacing placeholder route, with list UI and explicit loading/empty/stale/refresh-error states.
- Wired `IncidentProvider` and `IncidentManagementScreen` in `main.dart` route/provider graph.
- Added localization keys in both Vietnamese and English for incident operational state messaging and labels.
- Added deterministic provider regression tests for role scope behavior, stale-state handling, and refresh-error flows.
- Hardened scope parsing by trimming `requested_ranger_id` and `effective_ranger_id` across incident/work/schedule models.
- Added incident pagination guardrails to clamp invalid API values (`page`, `page_size`, `total`, `total_pages`) safely.
- Added localized provider error tokens, cache/stale/leakage UX banners, and explicit refresh retry hint for clearer operational-state messaging.
- Added additional regression coverage for leader visibility, scope trimming behavior, and pagination guard behavior.

### File List

- `_bmad-output/implementation-artifacts/3-2-incident-list-ux-with-operational-states.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `mobile/epic-treeinfo-dart/lib/main.dart`
- `mobile/epic-treeinfo-dart/lib/providers/incident_provider.dart`
- `mobile/epic-treeinfo-dart/lib/screens/incident_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/services/app_localizations.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
- `mobile/epic-treeinfo-dart/lib/theme/app_theme.dart`
- `mobile/epic-treeinfo-dart/test/incident_provider_test.dart`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented incident list UX with operational states, provider/service integration, and regression tests; moved story to review with Flutter CLI limitation documented.
- 2026-03-23: Executed strict fix/test/review loop; addressed severity-ordered review findings (scope normalization, pagination hardening, localized UX messaging, leakage/cache/stale UX cues), re-ran targeted and full regressions, and closed story with final adversarial PASS.
