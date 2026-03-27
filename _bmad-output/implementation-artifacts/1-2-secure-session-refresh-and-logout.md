# Story 1.2: Secure Session Refresh and Logout

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an authenticated mobile user,
I want secure session refresh and logout behavior,
so that I can continue safely without re-login churn and terminate sessions when needed.

## Acceptance Criteria

1. **Given** an expired access token and valid refresh/session token
   **When** the client calls `POST /api/mobile/auth/refresh`
   **Then** the backend issues a new access token
   **And** preserves role scope claims.

2. **Given** an authenticated session
   **When** the client calls `POST /api/mobile/auth/logout`
   **Then** the refresh/session token is invalidated
   **And** subsequent refresh attempts fail.

## Tasks / Subtasks

- [x] Task 1: Implement refresh endpoint for mobile session continuity (AC: 1)
  - [x] Add request model for `POST /api/mobile/auth/refresh`.
  - [x] Validate refresh/session token existence and expiry.
  - [x] Issue a new access token while preserving role claim from session context.
  - [x] Return token response without privileged backend credentials.

- [x] Task 2: Implement mobile logout and token invalidation (AC: 2)
  - [x] Add request model for `POST /api/mobile/auth/logout`.
  - [x] Invalidate refresh/session token and associated access tokens.
  - [x] Return explicit success response for valid logout.
  - [x] Reject refresh attempts after logout.

- [x] Task 3: Add automated regression tests (AC: 1, 2)
  - [x] Add test for refresh issuing a new access token and preserving role claims.
  - [x] Add test for refresh failure with invalid/expired refresh token.
  - [x] Add test for logout invalidation and subsequent refresh failure.
  - [x] Ensure no privileged backend credential fields are present in refresh responses.

- [x] Task 4: Validate implementation and document evidence (AC: 1, 2)
  - [x] Run full backend unit tests and confirm green.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-AUTH-002` and `FR-AUTH-003`.
- Refresh flow must preserve existing role scope claims (`leader` / `ranger`) established at login.
- Logout must invalidate refresh/session token and make future refresh calls fail.

### Architecture Compliance

- Preserve BFF boundary (`mobile -> FastAPI -> backend auth/session`).
- Reuse existing mobile auth token session stores in `app/src/server.py`.
- Keep existing dashboard login/session behavior intact.
- Continue using existing rate-limiting and logging conventions.

### Testing Requirements

- Tests must be deterministic and avoid external services.
- Reuse temporary `users.json` + patched startup background loop strategy from Story 1.1 tests.
- Validate both success and failure paths for refresh/logout behavior.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 1, Story 1.2)]
- Auth model baseline and contract: [Source: `_bmad-output/planning-artifacts/architecture.md` (Sections 3 AD-02, 6.1)]
- Project implementation rules: [Source: `_bmad-output/project-context.md` (Framework + Security + Testing rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests.test_mobile_auth -v` (14 tests passed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (81 tests passed)
- Adversarial code-review pass #2 on updated Story 1.2 scope: **No actionable findings**.

### Completion Notes List

- Added request models and handlers for `POST /api/mobile/auth/refresh` and `POST /api/mobile/auth/logout`.
- Implemented refresh logic that validates refresh token session state, renews access token, and preserves role scope claim.
- Implemented logout logic that invalidates refresh/session token and purges linked access tokens.
- Added deterministic regression coverage for refresh success, invalid/expired refresh failures, and post-logout refresh denial.
- Verified refresh response does not expose privileged backend credentials.
- Hardened token map mutation paths with defensive `.pop(..., None)` cleanup to avoid edge-case key deletion failures.
- Added malformed refresh-session guard to fail closed with `401 Invalid refresh token` instead of server error.
- Added regression tests for whitespace-only refresh/logout token rejection and malformed refresh-session payload handling.

### File List

- `_bmad-output/implementation-artifacts/1-2-secure-session-refresh-and-logout.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `app/src/server.py`
- `app/tests/test_mobile_auth.py`

## Change Log

- 2026-03-20: Story file created and moved to in-progress for implementation.
- 2026-03-20: Implemented refresh/logout mobile auth flows, added regression tests, and moved story to review.
- 2026-03-23: Resumed story in strict dev/review loop for adversarial hardening and full validation.
- 2026-03-23: Applied adversarial hardening fixes, re-ran targeted/full tests (green), final review clean, and closed story as done.
