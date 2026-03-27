# Story 1.1: Backend Login with Role Claims

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a ranger or leader,
I want to sign in through backend authentication,
so that my session and role are trusted by server-side authorization.

## Acceptance Criteria

1. **Given** valid user credentials
   **When** the client calls `POST /api/mobile/auth/login`
   **Then** the backend returns a valid access token, refresh/session token, and role claim
   **And** no privileged service credentials are returned in the response.

2. **Given** invalid credentials
   **When** the client calls `POST /api/mobile/auth/login`
   **Then** the backend returns an authentication error
   **And** no session is created.

## Tasks / Subtasks

- [x] Task 1: Implement mobile login endpoint and token issue flow (AC: 1)
  - [x] Add request/response models for `POST /api/mobile/auth/login`.
  - [x] Validate credentials against backend user store and preserve legacy SHA-256 migration behavior.
  - [x] Return short-lived access token + refresh/session token + normalized role claim (`leader` or `ranger`).
  - [x] Ensure response does not include privileged backend credentials.

- [x] Task 2: Enforce failed-auth behavior (AC: 2)
  - [x] Return authentication error for invalid username/password.
  - [x] Ensure no mobile token session is created on failed authentication.
  - [x] Keep existing dashboard login/session behavior unchanged.

- [x] Task 3: Add automated regression tests (AC: 1, 2)
  - [x] Add tests for successful login token payload and role claim normalization.
  - [x] Add tests for invalid credential rejection and no token session creation.
  - [x] Add guard test asserting privileged service credentials are never exposed in login response.

- [x] Task 4: Validate implementation and document evidence (AC: 1, 2)
  - [x] Run full backend unit tests and confirm green.
  - [x] Update story record (Debug Log, Completion Notes, File List, Change Log).

## Dev Notes

### Technical Requirements

- This story implements `FR-SEC-002`, `FR-AUTH-001`, `FR-AUTH-002`, and `FR-AUTH-003` for backend login foundations.
- Access token and refresh/session token should be backend-issued and tied to role claims.
- Role claims must align with project roles:
  - `admin` → `leader`
  - `viewer` (and other non-admin roles) → `ranger`

### Architecture Compliance

- Preserve BFF boundary (`mobile -> FastAPI -> backend auth/session`).
- Reuse backend conventions:
  - `get_settings()` configuration singleton
  - route rate limiting with `@limiter.limit(...)`
  - request ID middleware/logging conventions
- Avoid introducing new auth frameworks; extend existing FastAPI server auth module incrementally.

### Testing Requirements

- Tests must be deterministic and avoid live integrations.
- Startup sync loop must be neutralized in tests where app startup is exercised.
- Validate both positive and negative login paths.

### References

- Story definition and ACs: [Source: `_bmad-output/planning-artifacts/epics.md` (Epic 1, Story 1.1)]
- Auth model baseline and contract: [Source: `_bmad-output/planning-artifacts/architecture.md` (Sections 3 AD-02, 6.1)]
- Project implementation rules: [Source: `_bmad-output/project-context.md` (Framework + Security + Testing rules)]

## Dev Agent Record

### Agent Model Used

GPT-5.3-Codex

### Debug Log References

- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (19 tests passed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest tests/test_mobile_auth.py -v` (11 tests passed)
- `c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m unittest discover -s tests -v` (78 tests passed)

### Completion Notes List

- Added mobile auth session stores and token issuance helpers for backend-issued access/refresh session model.
- Implemented `POST /api/mobile/auth/login` with rate limiting, role claim normalization (`leader`/`ranger`), and legacy SHA-256 to bcrypt migration compatibility.
- Ensured invalid mobile credentials return `401 Invalid credentials` and do not create mobile sessions.
- Added cleanup of mobile auth sessions when an admin deletes a user.
- Added configurable token TTL settings in backend config and documented env vars in `app/.env.example`.
- Added deterministic backend regression tests for success, invalid credentials, role mapping, and legacy hash migration.
- Applied adversarial code-review hardening for Story 1.1: bounded mobile login credential sizes (`username` max 128, `password` max 256).
- Replaced legacy SHA-256 equality check with timing-safe `hmac.compare_digest` in `_verify_pw`.
- Added deterministic regression test asserting overlong credential payloads are rejected and create no sessions.
- Re-ran targeted and full backend test suites; second adversarial review pass returned no actionable findings.

### File List

- `_bmad-output/implementation-artifacts/1-1-backend-login-with-role-claims.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `app/src/config.py`
- `app/src/server.py`
- `app/.env.example`
- `app/tests/test_mobile_auth.py`

## Change Log

- 2026-03-19: Story file created and moved to in-progress for implementation.
- 2026-03-19: Implemented backend mobile login endpoint with role claims, access/refresh token issuance, regression tests, and moved story to review.
- 2026-03-23: Completed autonomous adversarial review loop; applied medium/low auth hardening, passed targeted/full regressions, and moved story to done.

## Senior Developer Review (AI)

- **Date:** 2026-03-23
- **Outcome:** Approve
- **Status impact:** Story moved from `review` to `done`

### Review Summary

- Pass 1 identified one Medium and two Low auth hardening findings (credential bound checks and timing-safe legacy hash compare), all resolved.
- Targeted regression (`test_mobile_auth.py`) and full backend regression (`unittest discover`) passed after fixes.
- Pass 2 adversarial review returned no actionable findings; acceptance criteria remain satisfied.
