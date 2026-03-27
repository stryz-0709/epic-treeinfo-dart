---
project_name: "EarthRanger"
user_name: "Admin"
date: "2026-03-25"
sections_completed:
  [
    "technology_stack",
    "language_rules",
    "framework_rules",
    "phase1_mobile_scope_rules",
    "phase4_sync_reliability_rules",
    "performance_observability_rules",
    "testing_rules",
    "quality_rules",
    "workflow_rules",
    "context_maintenance_rules",
    "project_flow_snapshot",
    "anti_patterns",
  ]
status: "complete"
rule_count: 79
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **Backend API**: Python 3.12, FastAPI, Uvicorn, slowapi, pydantic-settings, python-dotenv, Jinja2
- **Data & integrations**: Supabase Python client, requests, gspread, google-auth, bcrypt
- **Mobile app**: Flutter SDK `^3.11.0`, Provider, http, flutter_dotenv, shared_preferences, flutter_map, cached_network_image
- **Secondary monitor service**: Python scripts in `zalo-monitor/` (EarthRanger polling + Zalo notification)
- **Deployment/runtime**: Docker + docker-compose (`app/docker-compose.yml`), nginx/systemd deployment scripts

## Current Project Flow Snapshot (2026-03-25)

- BMAD implementation flow has completed **Epic 1 → Epic 4** (`done` in `_bmad-output/implementation-artifacts/sprint-status.yaml`).
- Story set `4-1` through `4-6` is complete, including incremental ER sync, cache-first mobile reads, offline queue + replay, sync-status UX, retention operations, and performance/observability hardening.
- New infrastructure direction is currently being prepared in `_bmad-output/implementation-artifacts/tech-spec-wip.md` (status: in-progress).
- This context file is now treated as a **living guardrail artifact** and must be updated whenever newly implemented patterns become recurring conventions.

## Critical Implementation Rules

### Language-Specific Rules

- In Python backend code, use existing singleton getters (`get_settings()`, `get_supabase()`, `get_er_client()`) instead of re-instantiating clients per request.
- Keep timezone handling UTC-aware (`datetime.now(timezone.utc)`), and serialize timestamps with `.isoformat()`.
- Preserve existing type-hint style used in the codebase (PEP 604 unions like `dict | None`, built-in generics `list[dict]`).
- Keep module and function docstrings; this repository relies on descriptive docstrings for maintainability.
- For JSON containing Vietnamese text, preserve UTF-8 behavior (`ensure_ascii=False` where applicable).
- Do not hardcode credentials/tokens in source files; all secrets come from environment/config files.

### Framework-Specific Rules

- New FastAPI routes must follow current auth conventions: `Depends(require_auth)` for authenticated routes and explicit role checks for admin-only actions.
- Apply existing rate-limiting conventions (`@limiter.limit(...)`) for new API endpoints exposed to clients.
- Keep request correlation intact: do not bypass `RequestIDMiddleware`; retain `X-Request-ID` propagation.
- Keep logging structured and consistent with `src.logging_config`; use `log = logging.getLogger(__name__)` and structured `extra` fields when relevant.
- Use `get_settings()` as the single source of configuration for backend behavior.
- In Flutter, keep state management on Provider/ChangeNotifier (do not mix in another state framework unless deliberately migrating).
- In Flutter startup, continue loading env from `.env` via `flutter_dotenv` before service construction.
- Reuse existing service/provider boundaries (`services/*`, `providers/*`) instead of embedding API calls directly in widgets.

### Phase 1 Mobile Scope & Access Rules

- Phase 1 functional scope is limited to: **Work Management**, **Incident Management**, and **Schedule**.
- Work Management is a **calendar summary of ranger working days** with a visible indicator for days the ranger checked in.
- Phase 1 check-in semantic: app open counts as check-in; implement as **idempotent once per user per local day** (no duplicate check-ins).
- Incident Management in this app is **read-only consumption** of incidents/events created in EarthRanger mobile app.
- In Phase 1, this app should **pull and display** incidents; do **not** implement incident creation here unless PRD explicitly changes scope.
- Schedule in Phase 1 is display of day-to-ranger assignments (example: `19 March - Johnson`).
- Account model has two roles:
  - **leader**: overview of ranger work summaries, can create/edit schedules, can see all ranger incidents.
  - **ranger**: can only see own stats/work summary/schedule/incidents.
- Role enforcement must be implemented server-side/API-side; UI-only restrictions are insufficient.
- Any endpoint returning incident or attendance data must be scoped by role and user identity.
- Phase 1 delivery mode is **hybrid online + offline-capable**: local cache on phone + sync when internet returns.
- Offline sync queue is allowed in Phase 1 for ranger check-in/stat events; leader schedule writes remain online-only unless PRD explicitly expands this.
- Queue records must include an idempotency key (`user_id + action_type + day_key + client_uuid`) to prevent duplicate writes on retries.
- Daily check-in must be recorded by backend/server time and deduplicated server-side (`user_id + day_key` uniqueness).

### Data Sync, Polling & Retention Rules

- EarthRanger Web/API remains the source of truth for incident/event control; this app is a customization module.
- Do not poll EarthRanger API from mobile clients for business data; use server-side integration only.
- Server-side ER sync must be **incremental cursor-based** (`updated_since`/high-watermark), not repeated full scans where avoidable.
- ER polling cadence must be configurable and rate-limit-safe (centralized scheduler, retry with exponential backoff + jitter).
- Mobile-to-backend freshness strategy should be adaptive (foreground faster polling, background slower polling, immediate refresh on app open/foreground resume).
- Prefer conditional fetch patterns (`updated_since`, etag/version fields) for mobile sync endpoints to reduce bandwidth and battery usage.
- Device cache for incidents/schedules/stats should use structured local storage (SQLite/Hive/Isar class of store) rather than key-value blobs for relational data.
- Ranger stats retention policy: keep operational stats in Supabase for at least **6 months** with explicit retention job.
- For retention, keep raw records for audit window and maintain pre-aggregated daily/monthly summaries for leader dashboards.
- For patrol/event analytics evolution, persist **full patrol and event datasets** (normalized facts + raw payload snapshots) so future requirements can be computed without historical source re-fetch.
- For time-range movement analytics, persist ranger relocation/track-point history (`ranger_id`, timestamp, location) as a first-class data domain; distance metrics must be computed from recorded movement history, not inferred from summary-only fields.

### Performance, Pagination & Observability Rules

- Mobile read APIs (`/api/mobile/work-management`, `/api/mobile/incidents`, `/api/mobile/schedules`) must keep bounded pagination defaults and max caps; do not add unbounded list reads.
- Keep incremental fetch/query-window guards (`updated_since`, bounded date windows, or equivalent constrained filters) to avoid broad scans.
- Keep role scoping (`leader`/`ranger`) as the first filter gate before expensive query paths.
- Preserve request correlation end-to-end: `X-Request-ID` must propagate through middleware, endpoint logs, and response headers.
- Keep structured request lifecycle logs with route/method/status/duration and safe role/user scope metadata where available.
- Keep slow-request warning behavior config-driven (`REQUEST_SLOW_THRESHOLD_MS`, with legacy alias fallback support when present).
- Keep sync-cycle telemetry structured and stable (cycle status, counters, durations, correlation fields).

### Retention & Compliance Operations Rules

- Retention window for ranger operational stats must never be configured below **183 days** (6-month floor guard).
- Scheduled retention execution should run once per local day at policy time (`01:30 Asia/Ho_Chi_Minh`) with per-day idempotency.
- Retention runs must emit auditable metadata (`run_id`, status, cutoff, trigger, correlation/request IDs, replay linkage).
- Failed retention runs must remain replayable through admin-only paths with explicit `replay_of_run_id` lineage.
- Retention success/failure/skip outcomes must be visible in structured logs for operations triage.

### Testing Rules

- Prefer deterministic tests that do not require live EarthRanger, Supabase, Zalo, or Google APIs.
- For Flutter, place tests under `mobile/epic-treeinfo-dart/test/` and keep them fast smoke/unit style unless explicitly adding integration tests.
- For Python, introduce tests in a dedicated test structure before broad refactors; avoid coupling tests to production secrets.
- When adding network logic, design for mockability (inject clients/config rather than hardcoding request calls in route handlers).

### Code Quality & Style Rules

- Preserve existing Python organization: `app/src/` modules in snake_case, cohesive single-responsibility helpers (`models.py`, `supabase_db.py`, etc.).
- Keep the visual section-divider style in `server.py` (`# ───────────────────`) for readability consistency.
- Keep API response shapes backward compatible for mobile/dashboard consumers (`{"tree": ...}`, `{"ok": True, ...}`, etc.).
- In Dart, keep file naming and class organization consistent with current `lib/{models,providers,services,screens}` layout.
- In async provider methods, continue current state lifecycle pattern: set loading/error state, `notifyListeners()`, `try/catch/finally`.

### Development Workflow Rules

- Treat this repository as a multi-surface workspace: backend (`app/`), mobile (`mobile/epic-treeinfo-dart/`), and monitor (`zalo-monitor/`) can evolve independently.
- For backend config changes, update both `src/config.py` defaults and `app/.env.example` placeholders together.
- Keep deployment assumptions compatible with existing compose and deployment scripts (volume mounts for `users.json` and `static/`).
- Do not break preserved workspace structure decisions documented in `WORKSPACE_ORGANIZATION.md`.
- For BMAD artifacts, use `_bmad-output/` as canonical location for planning and implementation files.
- If implementation requires a decision that is not yet settled (event ownership mapping, timezone policy, schedule source), treat it as an explicit PRD open question before coding.
- Recommended security baseline for mobile features: **Backend-for-Frontend API pattern** (mobile -> FastAPI -> Supabase/ER), rather than direct privileged Supabase access from mobile.
- Auth/session architecture should be production-grade (short-lived access token + refresh/session strategy, server-side role enforcement, revocation path).
- After any story/quick-dev implementation that introduces a recurring pattern or guardrail, update `_bmad-output/project-context.md` in the same delivery pass before final closure.
- When moving a story to `done` in sprint tracking, verify this file for required rule deltas and bump `Last Updated` if any durable rule changed.
- Implementation artifacts should explicitly state whether a **Project Context Delta** exists (`none` or concrete rule updates) to avoid drift.
- Do not defer context maintenance to a future sprint when the new behavior is already shipped.

### Critical Don't-Miss Rules

- Never commit or expose live secrets from `.env`, service account files, `zalo-monitor/*.json`, or token-bearing configs.
- Preserve login compatibility behavior in backend auth: legacy SHA-256 hashes are auto-migrated to bcrypt on successful login.
- Keep region-based data visibility behavior in `/api/trees` for non-admin users.
- EarthRanger API payload shapes can vary (`data/results` wrappers and optional fields); maintain defensive parsing patterns.
- Zalo token lifecycle depends on Google Sheet-backed refresh flow; do not replace with static token assumptions.
- In Flutter auth/provider code, treat hardcoded admin credentials as temporary legacy behavior; do not extend this pattern to new security-sensitive features.
- Avoid introducing breaking changes to webhook signature verification and alert filtering logic without coordinated backend/mobile updates.
- Do not use privileged Supabase/service keys in distributed mobile apps; use backend-mediated access or strict least-privilege/RLS model.
- Do not model check-in as a purely local flag; persist and deduplicate at backend data layer so leader/ranger views stay consistent.
- Service-role keys must exist only in backend/server runtime secrets and never in app assets, git, or client binaries.
- If direct mobile-to-Supabase access is used for any endpoint, only `anon` key + strict Row Level Security (RLS) policies are allowed.
- EarthRanger username/password and long-lived API tokens must never be embedded in mobile code or mobile `.env` assets.
- If key leakage is suspected, rotate Supabase keys and revoke/reissue dependent secrets immediately before release.
- Do not expose ER API credentials or ER OAuth password-grant flows directly to mobile clients for data sync.
- Respect ER API rate limits by centralizing polling in backend services and preventing fan-out polling from user devices.
- Offline sync replay must be safe to run multiple times; backend endpoints handling queued writes must be idempotent.

### Recently Stabilized in Epic 4 (Do Not Regress)

- Offline ranger write queue semantics are now stabilized: statuses `pending/synced/failed`, bounded retries (initial `5s`, max `15m`, max `8 attempts`), and deterministic manual retry behavior.
- Mobile cache-first read models for Work Management, Incidents, and Schedules are baseline behavior and should keep stale/offline indicators.
- Incremental EarthRanger sync is cursor-driven with defensive payload parsing and retry/backoff+jitter safeguards.
- Observability and performance guardrails (request-id correlation, structured lifecycle logs, bounded query patterns) are now baseline operational requirements.
- Retention operations are auditable and replay-aware; do not replace with opaque cleanup jobs.

### Phase 1 Open Questions (Resolve in PRD)

- Incident ownership mapping: which ER fields define “created by this ranger” in a reliable way?
- Future timezone strategy: Phase 1 currently uses `Asia/Ho_Chi_Minh` day boundaries; define policy for multi-timezone rollout if scope expands.
- Schedule source-of-truth evolution: keep current backend API model or move to a dedicated scheduling ownership model in later phases.
- Leader UX detail: exact team/ranger filter interactions (drop-list behavior and scope defaults).
- Phase 2 auth evolution path: continue backend JWT/session baseline or migrate toward Supabase Auth + RLS integration.
- ER sync SLA targets: acceptable delay for incident visibility between ER center control and this module.

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code.
- Follow all rules unless explicitly overridden by user instruction.
- Prefer the existing repository pattern over generic best-practice templates.
- If a change introduces a new recurring pattern, update this file in the same task.
- Before marking implementation work complete, verify whether project-context rules changed; if yes, update this file and include the delta in the implementation artifact.
- Treat project-context maintenance as part of Definition of Done for BMAD implementation flows.

**For Humans:**

- Keep this file lean; remove rules that become obvious or obsolete.
- Update when stack versions, auth model, or deployment patterns change.
- Re-run BMAD project-context generation after major architecture shifts.
- Keep Phase 1 scope decisions synchronized with PRD/architecture artifacts to avoid implementation drift.
- During story closure, ensure sprint status + implementation artifact + this file stay synchronized.

Last Updated: 2026-03-27
