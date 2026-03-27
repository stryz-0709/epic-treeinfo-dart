# Code Review Report — Database-Only Schedule Source of Truth

Date: 2026-03-25  
Reviewer workflow: `bmad-code-review`  
Review mode: **full** (spec provided)  
Scope source: **file-scope snapshot review** (workspace has no git baseline in this environment)

## Checkpoint Summary

- Scope files reviewed: **5**
  - `app/src/server.py`
  - `app/src/supabase_db.py`
  - `app/deploy/supabase_schedule_setup.sql`
  - `app/tests/test_mobile_schedules.py`
  - `docs/SUPABASE_LOGIN_SETUP.md`
- Spec/context loaded:
  - `/_bmad-output/implementation-artifacts/tech-spec-database-only-work-schedule-source-of-truth.md`
  - `/_bmad-output/project-context.md`
- Parallel review layers executed:
  - Blind Hunter
  - Edge Case Hunter
  - Acceptance Auditor
- Failed layers: **none**

## Triage Output

Raw findings collected: **22**  
Rejected as noise/unsupported after evidence check: **17**  
Remaining findings: **5**

### Patch Findings

1. **`scope.requested_ranger_id` is not normalized in schedule response echo**
   - Source: `auditor`
   - Constraint: Spec envelope contract requires normalized echo of request filter.
   - Evidence:
     - `app/src/server.py:1876` uses trim-only (`requested_ranger_id = (ranger_id or "").strip() or None`).
     - `app/src/server.py:1946` returns that value directly in response scope.
     - Internal scope resolver normalizes to lowercase (`app/src/server.py` `_resolve_mobile_schedule_scope`).
   - Risk: mixed-case client filters can round-trip with inconsistent response identity key semantics.

2. **Update endpoint lacks object-level scope enforcement for existing schedule row**
   - Source: `blind` (validated in code)
   - Constraint: Non-admin leader scope/assignee policy should deny leader-targeted schedule operations.
   - Evidence:
     - `app/src/server.py:2008` validates only requested target assignee via `_validate_mobile_schedule_assignee_scope(...)`.
     - `app/src/supabase_db.py:710-765` updates by `schedule_id` after existence check; no policy check against current assignee role/scope.
   - Risk: if a non-admin leader obtains a leader-assigned `schedule_id`, they can retarget/update it to a ranger assignment.

3. **Strict readiness identity preflight can pass despite scan truncation**
   - Source: `edge`
   - Constraint: Strict readiness should fail closed when identity anomaly checks are incomplete.
   - Evidence:
     - `app/src/supabase_db.py:275` caps active-row preflight scan with `limit(SCHEDULE_MAX_QUERY_ROWS)`.
     - `app/src/supabase_db.py:308` only logs warning when cap is hit; readiness still may pass.
   - Risk: canonical-identity or duplicate-active anomalies beyond first batch may remain undetected.

4. **Schedule/tombstone reads are hard-capped without truncation handling**
   - Source: `edge`
   - Constraint: Pagination/delta semantics should remain complete and deterministic under load.
   - Evidence:
     - `app/src/supabase_db.py:569` list query uses `limit(SCHEDULE_MAX_QUERY_ROWS)`.
     - `app/src/supabase_db.py:629` tombstone query uses `limit(SCHEDULE_MAX_QUERY_ROWS)`.
     - No explicit truncation detection/error path before returning items/tombstones.
   - Risk: incomplete reads/tombstones for large result sets can break sync correctness and pagination totals.

5. **Ops doc contradicts DB-only rollout state for schedules**
   - Source: `auditor`
   - Constraint: Setup/runbook docs must reflect current DB-only schedule authority.
   - Evidence:
     - `docs/SUPABASE_LOGIN_SETUP.md:39` states schedule endpoints are already Supabase-only.
     - `docs/SUPABASE_LOGIN_SETUP.md:170-173` still lists `schedules` and `schedule_action_logs` as “planned next”.
   - Risk: operator confusion during environment setup, rollout, and support handoffs.

## Final Summary

**0** intent_gap, **0** bad_spec, **5** patch, **0** defer findings. **17** findings rejected as noise.

## Recommended Next Steps

- Address patch findings in a focused implementation pass.
- Add targeted tests for object-level update authorization and high-volume truncation behavior.
- Update setup docs to remove rollout contradictions.
