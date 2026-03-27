# Supabase Login Setup (Admin Creates Leader/Ranger Accounts)

This project now supports backend-managed login using Supabase table `public.app_users`.

## What this enables

- Backend login uses **assigned passwords** (no password reset flow required).
- Admin users can create accounts and assign only:
  - `leader`
  - `ranger`
- Existing mobile login endpoints continue to work:
  - `POST /api/mobile/auth/login`
  - `POST /api/mobile/auth/refresh`
  - `POST /api/mobile/auth/logout`
  - `GET /api/mobile/me`

## 1) Prepare Supabase tables

Run:

- `app/deploy/supabase_auth_setup.sql`
- `app/deploy/supabase_schedule_setup.sql`

in Supabase SQL Editor for your project.

The schedule setup script adds:

- `public.schedules` — persistent workshift assignments with ranger/account snapshots
- `public.schedule_action_logs` — immutable create/update/delete history with actor identity and timestamps

It also links workshift assignees to `public.app_users` by `username`:

- `schedules.username` has a foreign key to `app_users.username`.
- A trigger auto-syncs `display_name`, `region`, and `role` from `app_users` whenever a schedule row is inserted (or assignee username changes).
- `public.schedules_with_user_profile` view exposes both snapshot fields and current values from `app_users` for monitoring.

### Schedule API source-of-truth behavior (important)

- `/api/mobile/schedules` GET/POST/PUT/DELETE now use **Supabase only** as schedule authority.
- In-memory process state is **not** trusted for schedule persistence.
- Multi-worker consistency and restart durability now depend on successful Supabase schedule schema setup.

### Schedule readiness mode

- Runtime flag: `SCHEDULE_READINESS_MODE`
  - `strict` (default)
  - `lazy` (local/dev fallback only)
- Unset mode defaults to `strict`.
- Unknown mode values fail closed at startup.
- Production must run strict mode (`lazy` is rejected in production).
- On readiness failures, client response is generic `503` with detail:
  - `Schedule service unavailable`
  - Internal missing-artifact details are logged server-side only.

## 2) Configure backend env

Set in backend runtime environment (or `app/.env`):

- `SUPABASE_URL`
- `SUPABASE_KEY` (service-role key)

## 3) Start backend

When Supabase is configured:

- Backend tries loading users from `public.app_users`.
- If table is empty, backend auto-seeds from local `app/users.json` once (bootstrap behavior).
- If Supabase user table is unavailable, backend safely falls back to file users.

## 4) Create accounts as admin

Use admin-authenticated endpoint:

- `POST /api/users`

Required payload:

- `username`
- `password` (assigned password)
- `role` (`leader` or `ranger`)

Optional payload:

- `display_name`
- `region`
- `position`
- `phone`

## 5) User login with assigned password

Users authenticate with the assigned password via:

- `POST /api/mobile/auth/login`

Response includes role claim (`leader` or `ranger`) and access/refresh tokens.

## Notes

- `admin` remains required for creating/deleting accounts.
- Legacy `viewer` role is normalized to `ranger` in API responses.
- Passwords are bcrypt-hashed server-side before persistence.

## 6) Manual Supabase setup beyond login table

Besides `app_users`, review these manual setup items:

1. **Project and environment separation**

- Use separate Supabase projects for `dev` and `prod`.
- Keep different keys/secrets per environment.

2. **Core backend secrets in runtime only**

- Set backend env vars:
  - `SUPABASE_URL`
  - `SUPABASE_KEY` (service-role key)
- Never place service-role keys in mobile assets.

3. **Production hardening in backend env**

- `ENVIRONMENT=production`
- non-default `SESSION_SECRET` (>= 32 chars)
- strict `CORS_ORIGINS` (no `*`)

4. **Retention configuration sanity**

- Confirm:
  - `RETENTION_SOURCE_TABLE` (default `daily_checkins`)
  - `RETENTION_AUDIT_TABLE` (default `retention_job_runs`)
- Create those tables (or change config to your chosen table names).

5. **Operational controls**

- Enable automated backups / PITR (plan-dependent in Supabase).
- Set up alerting for failed sync/retention jobs.
- Rotate service-role and EarthRanger tokens when leakage is suspected.

## 7) Extra security setups (recommended)

Yes — add these for stronger security:

- Keep all privileged credentials on backend only:
  - `SUPABASE_KEY` (service-role)
  - `EARTHRANGER_TOKEN`
  - session secrets
- For tables that should never be queried directly by mobile/web clients:
  - enable RLS
  - deny `anon` and `authenticated` unless explicitly needed
- Keep passwords as bcrypt hashes only (already implemented in backend).
- Prefer short-lived access tokens + refresh token flow (already implemented).
- Log and monitor suspicious login attempts and token misuse.

## 8) Big picture: what Supabase stores for this app

EarthRanger (ER) remains your upstream operational system. Supabase is your app's **operational read-model + analytics store**.

### A) Tables currently referenced by backend code

1. `app_users` — backend-managed login accounts and roles (`admin`, `leader`, `ranger`)
2. `trees` — mirrored tree records for dashboard and APIs
3. `nfc_cards` — NFC UID to tree mapping
4. `incidents_mirror` — mirrored ER incidents for mobile read APIs
5. `sync_cursors` — high-watermark cursors for incremental sync
6. `daily_checkins` — retention source table (configurable)
7. `retention_job_runs` — retention audit trail (configurable)
8. `schedules` — DB-backed mobile schedule source of truth
9. `schedule_action_logs` — immutable schedule mutation audit history

So, for the current implemented backend + retention defaults, plan for **9 Supabase tables**.

### B) Tables planned by architecture (recommended next)

- `idempotency_log` — replay-safe write deduplication audit

If you add it, practical total becomes **~10 tables**.

## 9) What to store vs not store

### Store in Supabase

- App-specific auth/account data (hashed passwords, roles, profile metadata)
- ER mirrors/read models needed by your UI and APIs (`trees`, incidents, mappings)
- Sync/processing state (`sync_cursors`, idempotency metadata)
- Operational analytics records (check-ins, schedule assignments, retention audits)

### Do NOT store (or avoid storing long-term)

- Plain-text passwords
- Service keys/tokens/secrets in tables
- Full raw ER payload history forever (unless you have a compliance reason)
- Duplicate data that can be derived cheaply at query time

## 10) Answer to "ER already stores data — do we still need our own DB?"

**Yes.** Keep ER as source-of-truth for core operations, and keep Supabase for:

- fast app-specific queries and role-scoped APIs
- offline/cache-friendly mobile behavior
- custom analytics and reports
- integration state (sync cursor, idempotency, retention audit)

This separation is the standard pattern: **ER = system of record**, **Supabase = app read/analysis model**.

## 11) Schedule DB-only cutover checklist (release runbook)

Use this checklist when moving environments to DB-only schedule authority.

1. **Inventory and freeze**

- Inventory all running API instances and target version.
- Freeze deploy churn during schedule cutover window.

2. **Apply schema artifacts**

- Apply `app/deploy/supabase_auth_setup.sql`.
- Apply `app/deploy/supabase_schedule_setup.sql`.

3. **Run canonical identity audits (must be zero anomalies)**

- Non-canonical app users:
  - `select username from public.app_users where username <> lower(trim(username));`
- Non-canonical active schedules:
  - `select schedule_id, username from public.schedules where deleted_at is null and username <> lower(trim(username));`
- Duplicate-active normalized collisions:
  - `select work_date, lower(trim(username)) as canonical_username, count(*) as active_rows from public.schedules where deleted_at is null group by work_date, lower(trim(username)) having count(*) > 1;`

4. **Readiness validation**

- Ensure runtime has `SCHEDULE_READINESS_MODE=strict` (or unset).
- Validate schedule preflight passes on all instances before opening traffic.

5. **Smoke matrix**

- Validate schedule endpoints:
  - `GET /api/mobile/schedules`
  - `POST /api/mobile/schedules`
  - `PUT /api/mobile/schedules/{schedule_id}`
  - `DELETE /api/mobile/schedules/{schedule_id}`
- Validate role matrix:
  - ranger write denied
  - leader create/update allowed
  - admin-account leader delete allowed

6. **Go/No-Go thresholds**

- 100% instance version parity (no mixed old writer versions).
- Canonical identity anomaly count = 0.
- Duplicate-active anomaly count = 0.
- Schedule smoke pass = 100%.
- 15-minute observation window guardrails:
  - schedule `5xx/503 < 1%`
  - no auth/scope regressions.

## 12) Rollback / contingency policy

- **Do not** re-enable in-memory schedule write authority.
- If schedule DB operations fail:
  - Keep schedule endpoints in maintenance/readiness-failed mode (`503`) temporarily.
  - Remediate schema/data issue.
  - Redeploy last known good **DB-backed** release.
- Trigger rollback when any of these occurs:
  - instance parity failure
  - smoke matrix failure
  - readiness/preflight failure on active instances
  - sustained breach of schedule error/conflict guardrails.
