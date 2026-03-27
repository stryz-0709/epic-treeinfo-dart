# EarthRanger Full-Method Kickoff (Mobile-Next)

Date: 2026-03-19  
Scope: Establish BMAD full-method kickoff with explicit risk baseline before mobile function expansion.

---

## 1) Executive Summary

The project is ready to start a **full BMAD Method** kickoff, but there are several high-impact risks that should be handled early (or gated) to avoid costly rework during mobile feature implementation.

Top concerns:

1. **Security exposure risk in mobile data access**
2. **Weak/placeholder mobile authentication flow**
3. **Backend session/auth hardening gaps**
4. **Scalability bottleneck in tree list + analytics flow**

---

## 2) Risk Register (Current-State Findings)

## 2.1 Security Risks

### Critical — Mobile secret exposure path

- `mobile/epic-treeinfo-dart/lib/main.dart:35` loads `SUPABASE_KEY` into mobile runtime.
- `mobile/epic-treeinfo-dart/lib/services/supabase_service.dart:14` sends `Authorization: Bearer $apiKey` from client app.
- `mobile/epic-treeinfo-dart/pubspec.yaml:53` includes `.env` as app asset.

Why this matters:

- If this key is a privileged/service key, mobile distribution can expose DB-level permissions.

Recommended direction:

- Move mobile to backend-issued scoped tokens or restricted anon-key + strict Supabase RLS.
- Remove sensitive keys from mobile `.env` packaging.

### High — Hardcoded mobile admin credentials

- `mobile/epic-treeinfo-dart/lib/providers/auth_provider.dart:19` uses hardcoded `epic/password` check.

Why this matters:

- Any reverse-engineered app can bypass intended access model.

Recommended direction:

- Replace with real auth flow (backend session/JWT/OAuth) before adding security-sensitive mobile features.

### High — Backend session hardening gaps

- In-memory session store: `app/src/server.py:163` (`sessions: dict[...] = {}`)
- Cookie set without `secure=True`: `app/src/server.py:267`
- `session_secret` exists but is unused: `app/src/config.py:47`

Why this matters:

- Sessions are lost on restart/scale-out and are harder to harden/audit.

Recommended direction:

- Move sessions to Redis/DB store and enforce secure cookie flags in production.
- Either use signed tokens or explicitly integrate `session_secret` into session lifecycle.

### High — Broad CORS default

- Default wildcard origins: `app/src/config.py:83`
- Applied at startup: `app/src/server.py:139`

Why this matters:

- Overly broad CORS increases attack surface for browser-based clients.

Recommended direction:

- Restrict origins per environment and avoid wildcard in production.

### Medium — Webhook verification can be effectively disabled

- `webhook_secret` default empty: `app/src/config.py:51`
- Signature verification bypasses when secret empty: `app/src/server.py:363`

Why this matters:

- If not configured in production, webhook endpoints are easier to spoof.

Recommended direction:

- Enforce non-empty webhook secret in production boot checks.

## 2.2 Performance / Bottlenecks

### Medium — Unpaginated tree load + full analytics per request

- `app/src/server.py:301` fetches all trees.
- `app/src/server.py:311` computes analytics for all rows on each `/api/trees` request.
- `app/src/supabase_db.py:51` uses `select("*").execute()` with no pagination/filter.
- `app/src/models.py:169+` computes multiple full-list passes in `compute_analytics`.

Why this matters:

- As tree count grows, response time and memory usage can degrade significantly.

Recommended direction:

- Add pagination/filtering endpoints for mobile and dashboard.
- Pre-aggregate expensive analytics or cache by interval.

## 2.3 Flow / Architecture Risks

### Medium — Split integration logic between backend and monitor service

- Similar EarthRanger/Zalo concerns exist in `app/src/*` and `zalo-monitor/*`.

Why this matters:

- Drift risk, duplicated bug fixes, inconsistent behavior.

Recommended direction:

- Define single integration contract/shared utility layer or clear bounded ownership.

---

## 3) Full BMAD Method Kickoff Sequence (Recommended)

## Phase 1 — Analysis (focused)

1. `bmad-help` (confirm active path and required next step)
2. Optional but useful: `bmad-document-project` (baseline architecture + flows)

## Phase 2 — Planning (required)

3. `bmad-create-prd` (mobile function expansion + non-functional requirements)
4. Optional if UX-heavy screens are changing: `bmad-create-ux-design`

## Phase 3 — Solutioning (required)

5. `bmad-create-architecture` (security model, API contracts, caching strategy, data-access boundaries)
6. `bmad-create-epics-and-stories`
7. `bmad-check-implementation-readiness`

## Phase 4 — Implementation

8. `bmad-sprint-planning`
9. Story cycle: `bmad-create-story` → `bmad-dev-story` → `bmad-code-review`

---

## 4) Mobile-Next Candidate Epic Structure (Initial)

### Epic M1 — Security Foundation for Mobile

- Replace hardcoded auth with real backend/mobile auth.
- Remove privileged keys from mobile package.
- Establish token/session lifecycle and role enforcement.

### Epic M2 — Tree Operations Maturity

- Advanced search/filter/sort and pagination.
- Robust edit validations and conflict handling.
- Improve tree detail loading and image/token behavior.

### Epic M3 — Incident/Alert Workflow

- Implement incident list/detail/action flows.
- Push/notification alignment with backend alert rules.

### Epic M4 — Offline/Resilience

- Local cache + retry strategies.
- Clear sync status and conflict UX.

### Epic M5 — Observability & QA

- Mobile + backend telemetry consistency.
- Integration and E2E test coverage for critical flows.

---

## 5) Gate Criteria Before Broad Mobile Feature Expansion

1. No privileged DB keys in shipped mobile app.
2. Real authentication path replaces hardcoded credential checks.
3. `/api/trees` scaling approach decided (pagination/caching/aggregation).
4. Production CORS + webhook secret policies explicitly set.

---

## 6) Immediate Next Action

Start **Phase 2 Planning** now with `bmad-create-prd`, using this kickoff artifact as context and explicitly prioritizing the security and scalability gates above.

---

## 7) User-Confirmed Phase 1 Functional Scope (2026-03-19)

### In-Scope Features

1. **Work Management**
   - Calendar summary of ranger working days.
   - Show “online/check-in” icon on days ranger checked in.
   - Check-in trigger is app-open behavior (user opens app each day).

2. **Incident Management**
   - Show events created by ranger during working period.
   - Current assumption: incidents are created in EarthRanger mobile app and this app pulls/displays them.

3. **Schedule**
   - Display assigned working days (example: `19 March - Johnson`).

### Role Model

- **leader**
  - Team overview of ranger Work Management (filter/drop-list expected).
  - Can create schedule for rangers.
  - Can view all incidents created by rangers.

- **ranger**
  - Can view only own stats/data.

### Open Questions to Resolve in PRD

1. Work Management UI details are not finalized and need additional conversation.
2. Incident integration details need confirmation:
   - Exact ER event type(s),
   - Ranger identity mapping strategy,
   - Time-window and filtering rules.
3. Check-in semantics need firm policy:
   - Is check-in valid on app launch only when authenticated?
   - What timezone defines day boundaries?
   - How to prevent duplicate check-ins across devices/retries?

### Planning Impact

- Convert the above scope into formal FR/NFR items in PRD.
- Treat unresolved questions as explicit assumptions or pending decisions before implementation stories are approved.
