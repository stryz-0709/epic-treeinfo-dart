---
title: "Sprint Plan - Database-Only Work Schedule Source of Truth"
created: "2026-03-25"
status: "ready"
source_spec: "_bmad-output/implementation-artifacts/tech-spec-database-only-work-schedule-source-of-truth.md"
owner: "quick-flow-solo-dev"
---

# Sprint Plan: Database-Only Work Schedule Source of Truth

## Sprint Goal

Move mobile schedule APIs from in-memory authority to Supabase-only persistence while preserving API contract, role behavior, and deterministic client sync behavior.

## Scope

In scope for this sprint plan:

- `app/src/supabase_db.py`
- `app/src/server.py`
- `app/deploy/supabase_schedule_setup.sql`
- `app/tests/test_mobile_schedules.py`
- `docs/SUPABASE_LOGIN_SETUP.md`

Out of scope:

- Mobile UI redesign
- New cache layer
- Cross-domain data-model refactors

## Execution Strategy

Implement in five controlled waves:

1. **Storage foundation** (DB helpers + readiness gate)
2. **Read path migration** (GET schedules + sync tombstones + pagination consistency)
3. **Write path migration** (POST/PUT/DELETE, conflict and actor/audit parity)
4. **Hardening and invariants** (claim precedence, SQL canonical identity checks)
5. **Verification and rollout docs** (tests + cutover/rollback runbook)

## Work Breakdown (Mapped to Tech-Spec Tasks)

### Wave 1 — Storage Foundation

- Task 1: Add schedule repository helpers in `supabase_db.py`
- Task 2: Add schedule schema preflight and readiness mode handling (`strict`/`lazy`)

**Exit criteria:**

- Repository exposes list/create/update/soft-delete primitives
- Readiness gate can fail closed with generic `503` behavior contract

### Wave 2 — Read Path Migration

- Task 3: Replace `GET /api/mobile/schedules` in-memory source with Supabase-backed query
- Task 5 (partial): Preserve response envelope and field compatibility (`items/scope/filters/pagination/directory`)

**Exit criteria:**

- Deterministic ordering: `(work_date, username, schedule_id)`
- `updated_since` + `snapshot_at` semantics preserved
- `sync.deleted_schedule_ids` present and deterministic when cursor is provided

### Wave 3 — Write/Delete Path Migration

- Task 4: Replace POST/PUT/DELETE write authority with DB mutations
- Task 5 (remaining): Preserve field and error compatibility for Flutter parser

**Exit criteria:**

- Leader/admin permissions unchanged
- Conflict maps to `409` without SQL leakage
- Delete response uses authenticated actor (`deleted_by`) and persists same actor in mutation fields

### Wave 4 — Invariants and Security Hardening

- Task 10: SQL safety checks and canonical username invariant validation
- Task 11: Claim precedence validation (`role`, `account_role`) in auth dependency

**Exit criteria:**

- Allowed claim combinations enforced (`leader/admin`, `leader/leader`, `ranger/ranger`)
- Invalid combinations rejected with `401`
- Pre-cutover anomaly checks documented and executable

### Wave 5 — Tests and Operations

- Task 6: Migrate schedule tests to repository-backed behavior
- Task 7: Add DB edge-case tests (409/404/503 mapping, tombstones, normalization collisions)
- Task 8 + 9: Add cutover, rollback, and operations runbook updates

**Exit criteria:**

- Targeted schedule tests pass
- Full backend regression pass for adjacent API families
- Docs contain objective go/no-go + rollback guardrails

## Suggested Execution Order (Daily Cadence)

### Day 1

- Implement Wave 1
- Add readiness gate tests (minimum path coverage)

### Day 2

- Implement Wave 2 (GET)
- Add read-path and pagination/snapshot tests

### Day 3

- Implement Wave 3 (POST/PUT/DELETE)
- Add conflict/not-found/actor-parity tests

### Day 4

- Implement Wave 4 (SQL + auth claim precedence)
- Add normalization and claim-combo tests

### Day 5

- Complete Wave 5 (docs + full validation)
- Run smoke/regression matrix and finalize release checklist

## Quality Gates

## Must-pass functional gates

- AC 1–10, 12–13, 16–17, 20–23, 25–30 from source tech spec

## Must-pass reliability and rollout gates

- AC 11, 14–15, 18–19, 24, 27–29

## Regression matrix

- `/api/mobile/auth/*`
- `/api/mobile/me`
- `/api/mobile/work-management`
- `/api/mobile/incidents`

## Risk Register (Condensed)

1. **Contract drift risk** (Flutter parser breakage)
   - Mitigation: keep response keys stable and add contract tests first

2. **Readiness-gate false positives/negatives**
   - Mitigation: strict default + clear local lazy behavior + synchronized preflight checks

3. **Identity collision during cutover**
   - Mitigation: pre-cutover normalization audits must be zero before go-live

4. **Delete actor inconsistency**
   - Mitigation: enforce actor from auth claims for response and persisted mutation fields in same transaction path

## Delivery Output Checklist

- [ ] DB helper layer complete and covered by tests
- [ ] API read/write endpoints fully DB-backed
- [ ] In-memory schedule write authority removed
- [ ] SQL invariants and migration checks complete
- [ ] Auth claim precedence enforcement shipped
- [ ] Tests updated and passing
- [ ] Ops docs updated with cutover + rollback runbook
- [ ] Final smoke/regression evidence attached

## Definition of Done

This sprint plan is done when all scoped files are updated, quality gates are green, and rollout can proceed with objective go/no-go criteria and no reintroduction of in-memory schedule authority.
