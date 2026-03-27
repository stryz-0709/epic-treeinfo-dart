---
title: "EarthRanger Production Backend Infrastructure Spec (HA)"
slug: "earthranger-production-backend-infrastructure-spec-ha"
created: "2026-03-25"
status: "ready-for-dev"
stepsCompleted: [1, 2, 3, 4]
tech_stack:
  - "Python 3.12"
  - "FastAPI"
  - "Uvicorn"
  - "slowapi"
  - "Supabase (Postgres)"
  - "Docker + docker-compose"
  - "nginx + systemd"
  - "EarthRanger API v1/v2"
  - "EarthRanger OAuth2 / Bearer token auth"
files_to_modify:
  - "app/src/config.py"
  - "app/src/server.py"
  - "app/src/sync.py"
  - "app/src/supabase_db.py"
  - "app/src/session_store.py"
  - "app/src/health_checks.py"
  - "app/.env.example"
  - "app/requirements.txt"
  - "app/docker-compose.yml"
  - "app/Dockerfile"
  - "app/deploy/setup.sh"
  - "app/deploy/earthranger-api.service"
  - "app/deploy/earthranger-worker.service"
  - "app/deploy/nginx.conf"
  - "app/deploy/supabase_auth_setup.sql"
  - "app/deploy/PRODUCTION_INFRA_RUNBOOK.md"
  - "docs/SUPABASE_LOGIN_SETUP.md"
  - ".github/workflows/deploy-backend.yml"
code_patterns:
  - "FastAPI BFF boundary (mobile -> backend -> Supabase/ER mirror)"
  - "Singleton config/client access via get_settings/get_supabase/get_er_client"
  - "Structured request logging with RequestID middleware"
  - "Production startup guardrails (CORS/webhook/session validation)"
  - "Incremental ER sync via updated_since + high-watermark cursor"
  - "Rate-limited API endpoints via slowapi decorators"
  - "UTC-aware datetime handling and ISO serialization"
test_patterns:
  - "Python unittest test modules under app/tests"
  - "Deterministic tests with mocked external integrations"
  - "Security regression tests for production guardrails"
  - "API behavior tests for auth, scope, pagination, and sync"
---

# Tech-Spec: EarthRanger Production Backend Infrastructure Spec (HA)

**Created:** 2026-03-25

## Overview

### Problem Statement

The project needs a complete production backend infrastructure specification that covers compute topology, networking, security controls, database architecture, operations, reliability, observability, and acceptance criteria. Existing project artifacts define application behavior and security baselines, but there is no single implementation-ready infrastructure spec that consolidates all production requirements for an HA deployment.

### Solution

Define an implementation-ready HA infrastructure blueprint for EarthRanger backend on VPS/VM-based hosting with managed data services. The specification will map current FastAPI + Supabase + EarthRanger integration behavior into production-grade infrastructure with explicit criteria for security, availability, scaling, operations, and validation.

### Scope

**In Scope:**

- Production environment topology (HA from day one)
- Compute/VPS sizing and node roles
- Network and ingress architecture (DNS, TLS, reverse proxy, firewalls)
- Database architecture and operational data boundaries (Supabase/Postgres)
- Secrets/configuration management and environment policy
- Reliability, backup, restore, DR, and failover criteria
- Monitoring, logging, alerting, and SLO-aligned operational criteria
- CI/CD and release controls for backend deployment
- Runbook-level acceptance criteria and verification checklist

**Out of Scope:**

- Mobile app UX feature redesign
- Rewriting domain logic for incident/work/schedule flows
- New product feature requirements outside infrastructure/operations
- Cloud-provider-specific procurement contracts and pricing negotiation

## Context for Development

### Codebase Patterns

- FastAPI Backend-for-Frontend boundary is the current baseline (mobile -> backend -> Supabase/ER mirror), and privileged credentials must remain backend-only.
- Runtime configuration and policy are centralized in `src/config.py`; production security is enforced at startup (`validate_security_baseline()`).
- Request handling follows structured observability patterns: `RequestIDMiddleware`, JSON logs, and slow-request warnings.
- API access control follows dependency-based enforcement (`Depends(require_auth)` / mobile role dependencies) and endpoint-level rate limits.
- Sync/retention orchestration currently runs as an in-process background loop (`run_loop`) started at app lifespan, which is a critical HA deployment constraint.
- Supabase access uses singleton helpers with dedicated table operations (`app_users`, `trees`, `incidents_mirror`, `sync_cursors`, `nfc_cards`).
- EarthRanger integration patterns emphasize incremental pull (`updated_since`, cursor watermark), defensive payload parsing, and idempotent replay-safe behavior.
- EarthRanger integration security guidance aligns with least-privilege service accounts, scoped permission sets, and secure token handling.

### Files to Reference

| File                                                                               | Purpose                                                                                   |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `_bmad-output/planning-artifacts/architecture.md`                                  | Authoritative architecture decisions (BFF boundary, security, sync, data model baseline). |
| `_bmad-output/project-context.md`                                                  | Repository-specific implementation and security rules for agents/developers.              |
| `app/src/server.py`                                                                | Runtime behavior, auth/session endpoints, middleware, and startup lifecycle.              |
| `app/src/config.py`                                                                | Production configuration schema and security baseline validation logic.                   |
| `app/src/sync.py`                                                                  | Sync/retention scheduler behavior relevant to HA worker decomposition.                    |
| `app/src/supabase_db.py`                                                           | Supabase auth/tables access, incident mirror upserts, and sync cursor persistence.        |
| `app/deploy/earthranger.service`                                                   | Systemd service baseline and runtime assumptions.                                         |
| `app/deploy/nginx.conf`                                                            | Reverse proxy and health endpoint routing baseline.                                       |
| `app/deploy/setup.sh`                                                              | Ubuntu host bootstrap assumptions (nginx/certbot/ufw/python).                             |
| `app/docker-compose.yml`                                                           | Containerized deployment baseline and healthcheck conventions.                            |
| `app/.env.example`                                                                 | Canonical runtime environment variables and production-hardening controls.                |
| `app/deploy/supabase_auth_setup.sql`                                               | Supabase `app_users` schema, update trigger, and RLS baseline.                            |
| `docs/SUPABASE_LOGIN_SETUP.md`                                                     | Supabase environment, table, and security operational guidance.                           |
| `docs/BANG_BAO_GIA_EARTHRANGER_VTSG.md`                                            | Existing production server sizing baseline (4 vCPU, 16 GB RAM, 500 GB).                   |
| `https://support.earthranger.com/.../creating-and-managing-service-accounts`       | Official least-privilege service-account integration guidance.                            |
| `https://support.earthranger.com/.../creating-an-authentication-token`             | Official token creation, scope, expiry, and secure handling guidance.                     |
| `https://support.earthranger.com/.../earthranger-api`                              | Official API authentication/pagination/filtering integration patterns.                    |
| `https://sandbox.pamdas.org/api/v1.0/docs/topics/eventtype-sync.html`              | ETag + updated_since caveats for event-type/offline sync.                                 |
| `https://sandbox.pamdas.org/api/v1.0/docs/topics/patrol-sync.html`                 | Conditional-GET boundaries and patrol sync behavior for clients.                          |
| `https://sandbox.pamdas.org/api/v1.0/docs/architecture/architecture-overview.html` | EarthRanger architecture and scale characteristics (Postgres/Redis/Celery context).       |

### Technical Decisions

- Target topology: **Full HA from day one**.
- Preserve BFF security boundary: privileged credentials remain backend-only.
- Keep Supabase/Postgres as operational store boundary, with explicit table roles and retention controls.
- Enforce production startup guardrails from existing codebase in all deployment stages.
- Design infrastructure to separate API-serving and background sync/retention execution responsibilities.
- Follow least-privilege EarthRanger integration model: dedicated service account + scoped permission sets + managed token lifecycle.
- Incorporate official ER sync semantics into backend design: `updated_since` incremental pulls, pagination, and conditional GET where supported.
- Treat webhook and auth token handling as production-critical controls: secret rotation, revocation, auditability, and no client-side secret exposure.
- Keep deployment compatible with existing Ubuntu/nginx/systemd and Docker paths while defining HA controls (multi-node app tier, state externalization, managed failover).

## Implementation Plan

### Tasks

- [ ] Task 1: Introduce runtime role split for HA-safe process behavior
  - File: `app/src/config.py`
  - Action: Add explicit runtime role config (e.g., `APP_RUNTIME_ROLE=api|worker`) and validation rules for role-specific startup behavior.
  - Notes: Keep existing production guardrails; do not weaken `validate_security_baseline()` checks.

- [ ] Task 2: Prevent duplicate sync/retention loops on multi-node API tier
  - File: `app/src/server.py`
  - Action: Update lifespan startup to run background loop only for worker role; API role must not start sync loop thread.
  - Notes: Preserve existing request middleware, auth flows, and route behavior.

- [ ] Task 3: Prepare standalone worker execution path
  - File: `app/src/sync.py`
  - Action: Ensure sync/retention loop can run as a dedicated long-running worker process with clean shutdown and telemetry.
  - Notes: Keep incremental cursor behavior (`updated_since`, overlap window, monotonic cursor updates).

- [ ] Task 4: Externalize in-memory session/check-in/schedule state for HA consistency
  - File: `app/src/session_store.py` (new)
  - Action: Implement shared store abstraction (Redis-backed) for access/refresh sessions, check-in idempotency records, and schedule cache pointers.
  - Notes: Include TTLs aligned with token lifetimes; support graceful fallback for local test mode.

- [ ] Task 5: Wire shared state store into API authentication and mobile flows
  - File: `app/src/server.py`
  - Action: Replace process-local dictionaries used by auth/session/check-in/schedule paths with shared store calls.
  - Notes: Preserve role/scope enforcement and response contracts; avoid breaking existing mobile clients.

- [ ] Task 6: Persist operational entities for durability and replay safety
  - File: `app/src/supabase_db.py`
  - Action: Add DB helpers for `schedules`, `daily_checkins`, and `idempotency_log` with deterministic upsert/read semantics.
  - Notes: Keep timezone-aware date keys and idempotent once-per-user-per-day constraints.

- [ ] Task 7: Extend Supabase SQL bootstrap for production data model hardening
  - File: `app/deploy/supabase_auth_setup.sql`
  - Action: Add/adjust DDL for schedule/check-in/idempotency/audit tables, indexes, and RLS policy stubs per backend-only access model.
  - Notes: Include unique constraints and audit timestamps; avoid exposing privileged table access to `anon/authenticated` clients.

- [ ] Task 8: Add readiness/dependency health checks for production orchestration
  - File: `app/src/health_checks.py` (new)
  - Action: Implement dependency checks (Supabase reachability, optional Redis reachability, config sanity) and expose liveness/readiness semantics.
  - Notes: Keep `/health` backward compatible; add additional readiness endpoint if needed.

- [ ] Task 9: Productionize service unit split for API and worker roles
  - File: `app/deploy/earthranger-api.service` (new)
  - Action: Define API service unit with hardened security options, restart policy, and environment file usage.
  - Notes: Bind app on localhost for reverse proxy routing.

- [ ] Task 10: Add worker service unit for sync/retention orchestration
  - File: `app/deploy/earthranger-worker.service` (new)
  - Action: Define dedicated worker unit running sync loop with runtime role `worker`.
  - Notes: Ensure only one worker active per environment (or include explicit leader election strategy).

- [ ] Task 11: Update ingress for HA backend node pool
  - File: `app/deploy/nginx.conf`
  - Action: Add upstream/load-balancing configuration for 2+ API nodes, timeouts, proxy headers, and health/rate-limit-safe routing.
  - Notes: Keep webhook path handling explicit and low-latency; preserve TLS-ready layout.

- [ ] Task 12: Align container topology with API + worker + shared state services
  - File: `app/docker-compose.yml`
  - Action: Define separate services for API and worker roles; add optional Redis service and health dependencies.
  - Notes: Keep current local developer workflow intact via profiles/overrides where needed.

- [ ] Task 13: Update runtime variable catalog for production operations
  - File: `app/.env.example`
  - Action: Document new HA/runtime-role/Redis settings, secret handling expectations, and secure defaults.
  - Notes: Include clear production-only requirements and forbidden configurations.

- [ ] Task 14: Ensure dependency and image/runtime compatibility
  - File: `app/requirements.txt`
  - Action: Add required shared-state/health/observability dependencies.
  - Notes: Pin versions conservatively to preserve compatibility with Python 3.12 base image.

- [ ] Task 15: Refresh host bootstrap script for HA baseline
  - File: `app/deploy/setup.sh`
  - Action: Add setup steps for dual-service deployment, systemd enablement, firewall ports, and post-deploy verification commands.
  - Notes: Keep script idempotent for reruns on existing hosts.

- [ ] Task 16: Publish production runbook and operational criteria
  - File: `app/deploy/PRODUCTION_INFRA_RUNBOOK.md` (new)
  - Action: Document topology, deployment sequence, rollback, backup/restore drills, incident response, and secret rotation procedures.
  - Notes: Include RTO/RPO targets, owner responsibilities, and verification gates.

- [ ] Task 17: Update Supabase operations documentation for backend production
  - File: `docs/SUPABASE_LOGIN_SETUP.md`
  - Action: Expand with full table inventory, retention jobs, RLS posture, backups/PITR expectations, and failure playbooks.
  - Notes: Keep explicit distinction between ER as source-of-truth and Supabase as app operational/read model.

- [ ] Task 18: Add CI/CD deployment and verification pipeline
  - File: `.github/workflows/deploy-backend.yml` (new)
  - Action: Define staged checks (lint/tests/security), deployment gates, smoke checks, and rollback trigger conditions.
  - Notes: Pipeline must fail closed on missing production security env requirements.

### Acceptance Criteria

- [ ] AC 1: Given `ENVIRONMENT=production`, when backend starts, then startup must fail if CORS origins include `*`, `WEBHOOK_SECRET` is empty, or `SESSION_SECRET` is weak/default.
- [ ] AC 2: Given HA API deployment with multiple API nodes, when services start, then sync/retention background loop runs only in worker role and never in API role.
- [ ] AC 3: Given a valid mobile access/refresh session, when requests are load-balanced across API nodes, then authentication remains consistent and token refresh/logout behavior is correct on every node.
- [ ] AC 4: Given duplicate check-in submissions (same user/day/idempotency key), when processed through different API nodes, then only one durable check-in record exists and response indicates created vs already_exists correctly.
- [ ] AC 5: Given schedule create/update operations by leaders, when API instances restart or fail over, then schedule data remains durable and consistent (no in-memory loss).
- [ ] AC 6: Given EarthRanger event sync with `updated_since`, when worker restarts mid-cycle, then cursor handling remains monotonic and no backward regression occurs.
- [ ] AC 7: Given EarthRanger API transient failures (429/5xx), when sync retries execute, then bounded exponential backoff with jitter is applied and final failure is logged with actionable context.
- [ ] AC 8: Given EarthRanger token compromise handling, when token rotation is performed, then old token is revoked and backend resumes sync/API access with replacement token without client-side secret leakage.
- [ ] AC 9: Given a request to readiness endpoint, when any critical dependency is unavailable (Supabase and configured shared state), then readiness returns unhealthy while liveness remains available.
- [ ] AC 10: Given nginx upstream with multiple API backends, when one backend is unavailable, then requests continue through healthy backend(s) without exposing internal host details.
- [ ] AC 11: Given backup/restore procedures, when restoring to a staging target, then operational tables (auth users, check-ins, schedules, incident mirror cursors, retention audit) recover to a verifiable consistent state.
- [ ] AC 12: Given CI/CD pipeline execution for production branch, when tests/security checks fail, then deployment is blocked and no runtime changes are applied.
- [ ] AC 13: Given webhook calls in production, when signature is missing/invalid, then request is rejected with unauthorized status and logged for audit.
- [ ] AC 14: Given EarthRanger permission model setup, when service account permissions are scoped minimally, then backend integration succeeds without granting unnecessary create/update/delete rights.
- [ ] AC 15: Given target baseline sizing (4 vCPU, 16 GB RAM, 500 GB) and HA topology, when expected load tests are executed, then API p95 latency and sync completion SLA meet documented SLO thresholds in runbook.

## Additional Context

### Dependencies

- EarthRanger backend integration credentials: dedicated service account + scoped permissions + managed auth token lifecycle.
- Supabase/Postgres project with required tables and indexes: `app_users`, `trees`, `incidents_mirror`, `sync_cursors`, `daily_checkins`, `schedules`, `idempotency_log`, `retention_job_runs`.
- Shared state backend for HA session and idempotency consistency (Redis recommended).
- Reverse proxy and TLS tooling: nginx + certbot.
- Process supervision: systemd service units for API and worker.
- Container/runtime dependencies aligned to Python 3.12 and required libraries from `requirements.txt`.
- CI/CD execution environment with secure secret injection and deployment credentials.

### Testing Strategy

- **Unit tests**
  - Add tests for runtime role gating (API role must not start sync loop; worker role must).
  - Add tests for shared-state session/check-in behavior across simulated multi-node access.
  - Extend security baseline tests for new production env validations and readiness checks.

- **Integration tests**
  - Validate API + worker + shared-state composition using docker-compose profile.
  - Validate sync cursor monotonic behavior under restart/retry scenarios.
  - Validate schedule/check-in durability through process restarts.

- **Operational verification**
  - Health/liveness/readiness checks through nginx.
  - Failover drill: remove one API node and confirm continued service.
  - Backup/restore rehearsal on staging clone with data integrity checklist.
  - Secret rotation drill (EarthRanger token, session secret, webhook secret).

- **Manual smoke tests**
  - Login/refresh/logout across load-balanced nodes.
  - Ranger check-in idempotency under retry and reconnect scenarios.
  - Leader schedule read/write under concurrent API traffic.
  - Webhook signature enforcement in production mode.

### Notes

- **High-risk items**
  - Current in-process sync/session state in `server.py` is incompatible with true HA unless externalized/split by runtime role.
  - EarthRanger token governance (scope/expiry/revocation) is operationally critical; weak handling can cause outage or compromise.
  - Event-type and patrol sync semantics differ in conditional GET support; misuse can cause stale caches or unnecessary load.

- **Known limitations (current baseline)**
  - Existing deployment is optimized for single-instance runtime and must be evolved for multi-node consistency.
  - `webhook/camera` path currently has weaker signature controls than `/webhook/earthranger` and should be aligned.

- **Future considerations (out of current scope)**
  - Managed load balancer + autoscaling migration path after first HA stabilization.
  - Full observability stack (metrics backend + dashboards + SLO alert rules) standardization.
  - Multi-region DR with asynchronous replication and tested failback.
