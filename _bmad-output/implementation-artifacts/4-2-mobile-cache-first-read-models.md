# Story 4.2: Mobile Cache-First Read Models

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a mobile user,
I want cached Work Management, Incident, and Schedule data available offline,
so that I can continue reading operational context during connectivity loss.

## Acceptance Criteria

1. **Given** previously synced data
   **When** device is offline
   **Then** calendar, incident, and schedule screens render cached records
   **And** show stale/offline indicators where applicable.

2. **Given** network reconnect
   **When** refresh is triggered
   **Then** incremental updates are fetched and merged
   **And** cache is updated without duplicating records.

## Tasks / Subtasks

- [x] Task 1: Add shared cache read-model primitives for mobile feature data (AC: 1, 2)
  - [x] Introduce a cache service in `mobile/epic-treeinfo-dart/lib/services/` for Work Management, Incident, and Schedule read models using existing project dependencies.
  - [x] Persist cache payload + sync metadata (`last_synced_at`, source marker) and provide deterministic load/save APIs for providers.
  - [x] Keep serialization defensive for malformed/partial cache payloads and fall back safely to empty state.

- [x] Task 2: Implement cache-first loading in Work Management provider (AC: 1)
  - [x] On load, hydrate calendar state from cache before network refresh attempt.
  - [x] If online refresh fails but cached data exists, keep cached data visible and mark stale/offline state instead of hard error-only UX.
  - [x] Persist successful network fetches back into cache with normalized keys.

- [x] Task 3: Implement cache-first loading + incremental merge in Incident provider (AC: 1, 2)
  - [x] Hydrate incidents from cache for initial/refresh paths when network is unavailable.
  - [x] Merge online fetch results into current/cached incidents by stable incident identity without duplicates.
  - [x] Maintain stale/offline flags from sync metadata and refresh outcomes.

- [x] Task 4: Implement cache-first loading + incremental merge in Schedule provider (AC: 1, 2)
  - [x] Hydrate schedule list from cache before network call and preserve visibility when offline.
  - [x] Merge online results by `schedule_id` without duplicate rows and keep deterministic sorting.
  - [x] Persist merged schedule state and sync metadata after successful refresh.

- [x] Task 5: Expose stale/offline indicators in mobile screens for all three read models (AC: 1)
  - [x] Add clear stale/offline banner treatment for Work Management and Schedule screens, consistent with existing Incident stale messaging patterns.
  - [x] Preserve current loading/empty/error flows while prioritizing cached visibility when possible.

- [x] Task 6: Add deterministic automated tests for cache-first and merge behavior (AC: 1, 2)
  - [x] Extend provider unit tests (`work_management_provider_test.dart`, `incident_provider_test.dart`, `schedule_provider_test.dart`) with cache-hit/offline-fallback scenarios.
  - [x] Add tests for reconnect incremental merge and duplicate prevention for incidents/schedules/work-summary keys.
  - [x] Verify stale/offline state transitions are correct across: cache-only, refresh-success, and refresh-failure paths.

## Dev Notes

### Technical Requirements

- This story implements `FR-SYNC-001` and `FR-INT-003`.
- Mobile must render cached Work Management, Incident, and Schedule data in offline/failure conditions.
- Refresh behavior must support incremental merge semantics and prevent duplicate records.

### Architecture Compliance

- Preserve BFF boundary: mobile reads from backend APIs (`/api/mobile/work-management`, `/api/mobile/incidents`, `/api/mobile/schedules`) and never directly from EarthRanger.
- Keep provider/service layering consistent with existing structure (`lib/providers/*`, `lib/services/*`) and avoid embedding networking in widgets.
- Keep implementation aligned with Provider state lifecycle (`loading/error/ready` + `notifyListeners()`).

### Library and Framework Requirements

- Prefer existing dependencies from `pubspec.yaml` (notably `shared_preferences`) for cache persistence.
- Avoid introducing new package dependencies unless absolutely required by acceptance criteria.
- Continue using existing `MobileApiService` contracts and models for server payload parsing.

### File Structure Requirements

- Primary implementation files expected:
  - `mobile/epic-treeinfo-dart/lib/services/*cache*`
  - `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/providers/incident_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/providers/schedule_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/incident_management_screen.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/schedule_management_screen.dart`
- Tests expected under:
  - `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`
  - `mobile/epic-treeinfo-dart/test/incident_provider_test.dart`
  - `mobile/epic-treeinfo-dart/test/schedule_provider_test.dart`

### Testing Requirements

- Tests must be deterministic and not depend on live backend connectivity.
- Validate cache-first behavior for each provider when token exists but API fails.
- Validate reconnect merge behavior prevents duplicates and preserves deterministic ordering.
- Validate stale/offline flags and user-visible state contracts in provider layer.

### Implementation Guardrails

- Do **not** regress role-scoped filtering semantics for leader/ranger views.
- Do **not** hide hard errors when no cache exists; cached fallback should activate only when data is present.
- Do **not** duplicate records during merge; identity keys must be stable per model.
- Do **not** add direct EarthRanger/mobile polling behavior.

### References

- Story definition + ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 4, Story 4.2)]
- Sync/caching architecture baseline: [Source: `_bmad-output/planning-artifacts/architecture.md` (Sections 8, 9; AD-07)]
- Project rules: [Source: `_bmad-output/project-context.md` (Phase 1 Mobile Scope Rules, Data Sync Rules, Framework Rules)]
- Current mobile providers/screens:
  - `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/providers/incident_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/providers/schedule_provider.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/incident_management_screen.dart`
  - `mobile/epic-treeinfo-dart/lib/screens/schedule_management_screen.dart`

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- Flutter SDK verification: `Flutter 3.41.5` / `Dart 3.11.3`.
- Targeted provider regression: `flutter test test/incident_provider_test.dart test/schedule_provider_test.dart test/work_management_provider_test.dart` (`+27`, all passed).
- Full mobile regression: `flutter test` (`+28`, all passed).
- Post-hardening re-run: targeted provider regression (`+27`) and full mobile regression (`+28`) both passed.
- Post-fix adversarial verification: no actionable Critical/High findings remaining.
- Autonomous BMAD targeted regression: `C:\Users\Admin\tools\flutter\bin\flutter.bat test test/incident_provider_test.dart test/schedule_provider_test.dart test/work_management_provider_test.dart` (`+29`, all passed).
- Autonomous BMAD full regression: `C:\Users\Admin\tools\flutter\bin\flutter.bat test` (`+30`, all passed).
- Second adversarial review pass: no actionable High/Medium findings; closure approved.

### Completion Notes List

- Added shared cache primitives via `SharedPreferencesMobileReadModelCache` with defensive parsing and bounded cache-bucket pruning.
- Implemented cache-first hydration + refresh-failure fallback semantics for Work, Incident, and Schedule providers.
- Implemented deterministic incremental merge semantics for reconnect refreshes without duplicate rows.
- Added stale/offline provider state propagation and mobile-screen banners for Work/Incident/Schedule read models.
- Hardened ranger-scope behavior to fail closed when effective ranger scope metadata is missing.
- Added active cache-key guards to prevent cross-query in-memory merge contamination.
- Strengthened incident fallback identity generation and leader filter validation for schedule scope changes.
- Partitioned read-model cache keys by authenticated session to prevent cross-account cache reuse on shared devices.
- Hardened no-fallback error paths to clear in-memory incident/schedule state and avoid stale unauthorized visibility.
- Normalized incident fallback identity tokens (whitespace/case) so cosmetic payload changes do not create duplicate fallback merges.
- Strengthened schedule fallback identity to use timestamp-aware keys when `schedule_id` is absent and added deterministic identity tie-break sorting.
- Added regression coverage for normalized incident fallback identity and timestamp-aware schedule fallback merge behavior.

### File List

- `mobile/epic-treeinfo-dart/.env.example`
- `mobile/epic-treeinfo-dart/lib/main.dart`
- `mobile/epic-treeinfo-dart/lib/providers/auth_provider.dart`
- `mobile/epic-treeinfo-dart/lib/providers/work_management_provider.dart`
- `mobile/epic-treeinfo-dart/lib/providers/incident_provider.dart`
- `mobile/epic-treeinfo-dart/lib/providers/schedule_provider.dart`
- `mobile/epic-treeinfo-dart/lib/screens/work_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/screens/incident_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/screens/schedule_management_screen.dart`
- `mobile/epic-treeinfo-dart/lib/services/app_localizations.dart`
- `mobile/epic-treeinfo-dart/lib/services/earthranger_auth.dart`
- `mobile/epic-treeinfo-dart/lib/services/supabase_service.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_api_service.dart`
- `mobile/epic-treeinfo-dart/lib/services/mobile_read_model_cache.dart`
- `mobile/epic-treeinfo-dart/lib/widgets/app_open_checkin_lifecycle.dart`
- `mobile/epic-treeinfo-dart/test/work_management_provider_test.dart`
- `mobile/epic-treeinfo-dart/test/incident_provider_test.dart`
- `mobile/epic-treeinfo-dart/test/schedule_provider_test.dart`
- `mobile/epic-treeinfo-dart/pubspec.lock`
- `_bmad-output/implementation-artifacts/4-2-mobile-cache-first-read-models.md`

## Change Log

- 2026-03-23: Story file created and set to `ready-for-dev`.
- 2026-03-23: Story execution started via `bmad-dev-story`; sprint status moved to `in-progress`.
- 2026-03-23: Implemented cache-first read models and stale/offline UX for Work/Incident/Schedule flows.
- 2026-03-23: Added deterministic provider regression coverage for cache-first fallback and merge de-duplication semantics.
- 2026-03-23: Applied adversarial hardening for ranger-scope filtering, incident identity fallback, and cache growth controls; all tests passing.
- 2026-03-23: Added session-partition cache keys and key-aware fallback hardening; post-fix adversarial verification reported no actionable Critical/High findings.
- 2026-03-23: Autonomous BMAD loop pass: applied additional incident/schedule fallback-identity hardening, added two regression tests, re-ran targeted (`+29`) and full (`+30`) test suites, re-ran adversarial review with no actionable High/Medium findings, and closed story as `done`.
