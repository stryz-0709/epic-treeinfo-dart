# Phase 1 Mobile PRD Input (User-Confirmed)

Date: 2026-03-19

## Product Goal

Deliver Phase 1 mobile capabilities for ranger operations visibility:

- Work Management
- Incident Management
- Schedule

## User Roles

## leader

- Can view overview of ranger work/check-in status for authorized rangers in the same `region` and `team`.
- Can filter/select rangers (drop-list expected) within same `region` + `team` scope.
- Can create and manage ranger schedules only for authorized rangers in the same `region` and `team`.
- Can view incidents created by authorized rangers in the same `region` and `team`.

## ranger

- Can view only own stats/work/check-ins/schedule/incidents.

## Phase 1 Functional Scope

### F1 — Work Management Calendar

- Show ranger working-day summary in calendar form.
- Display online/check-in indicator on days ranger checked in.
- Check-in trigger: app open counts as check-in for the day.

### F2 — Incident Management (Read-Only)

- Show incidents/events created by ranger over working period.
- Assumption: events are created in EarthRanger mobile app; this app only pulls/displays from ER.

### F3 — Schedule Display

- Display working-day assignments (example: `19 March - Johnson`).

## Business Rules (Current)

- Check-in should be idempotent per user/day (avoid duplicate records for same day).
- Access control must be enforced server-side by role and user identity.
- Ranger cannot view other ranger data.
- Leader permissions apply only to rangers with the same `region` and `team`.

## Non-Functional Priorities

1. Security hardening for mobile access model.
2. Data correctness for check-ins and role-scoped views.
3. Scalable list/query flow for incidents and calendar data.
4. Offline-capable UX with safe sync behavior.

## Open Questions (Must Resolve in PRD)

1. Work Management UX details (calendar interactions, icons, filters).
2. Incident mapping to ranger identity in ER (which fields are source of truth).
3. Check-in validation semantics:
   - app-open only vs authenticated app-open,
   - timezone policy for day boundaries,
   - duplicate prevention across retries/devices.
4. Schedule source-of-truth model and API ownership.

## Security Constraints for Phase 1

- Do not ship privileged/service data keys in mobile app package.
- Use least-privilege data access model for mobile reads/writes.
- Keep role-based access control at backend/API layer, not UI-only.

## Recommended Professional Security Setup (Proposed)

### Recommended architecture for Phase 1

- Use **Backend-for-Frontend (BFF)** for mobile:
  - Mobile app calls FastAPI endpoints.
  - FastAPI owns service-role access and ER credentials in server env only.
  - Mobile never receives service-role key.

### Supabase recommendation

- Keep `service-role` key only on backend server.
- For any direct mobile Supabase call, use `anon` key only + strict RLS policies.
- Define explicit RLS by role/user scope (leader same-region+same-team scope vs ranger self scope).

### Authentication recommendation

- Replace hardcoded mobile login with production auth flow.
- Phase 1 practical path:
  1.  Backend auth endpoint issues short-lived token/session.
  2.  Role claims (`leader`, `ranger`) enforced server-side on every data endpoint.
  3.  Check-in endpoint requires authenticated user and server-side dedup logic.

### Secret management baseline

- Remove privileged secrets from mobile `.env` assets.
- Store backend secrets in deployment env/secret manager only.
- Rotate Supabase keys if service-role was ever packaged in mobile builds.

## Phase 1 Sync Mode (Updated)

### Decision

- **Phase 1 is hybrid offline-capable**:
  - Keep local cache on user phone for Work Management / Incident / Schedule views.
  - Sync cached data and queued actions when internet is available.

### Write policy in Phase 1

- Ranger check-in/stat updates can be queued offline and replayed later.
- Leader schedule create/update actions are online-only in Phase 1 unless explicitly expanded in PRD.

### Reliability requirements

- Offline replay must be idempotent with a client-generated idempotency key.
- Backend must deduplicate check-ins by user/day and tolerate repeated retries.
- Queue needs retry/backoff policy and a visible sync status for users.

## Where We Start (Execution Order)

1. **Finalize PRD** (`bmad-create-prd`) using this file as input.
2. **Security first (mandatory gate before broad feature work):**

- Rotate Supabase service-role key.
- Remove privileged secrets from mobile package/assets.
- Move mobile data access to backend BFF endpoints.

3. **Define Phase 1 API contracts (architecture step):**

- Auth/session endpoints and role claims.
- Check-in ingest endpoint with idempotency.
- Work management, schedule, and incident read endpoints with role-scoped filters.

4. **Implement local cache + sync queue skeleton in mobile:**

- Read cache first, network refresh next.
- Queue offline check-ins and replay on reconnect.

5. **Then start story implementation cycle** (`bmad-sprint-planning` -> `bmad-create-story` -> `bmad-dev-story` -> `bmad-code-review`).
