# EarthRanger — App API Catalog (Master List)

**Date:** 2026-03-30  
**Prepared for:** Admin  
**Status:** Living API inventory (implemented + planned)

---

## Purpose

This document is the **single place to store all APIs needed for the app**:

- APIs already implemented in backend (`app/src/server.py`)
- APIs required to deliver additional approved functions (AF-01, AF-02, AF-03, AF-04, AF-05, AF-07, AF-08, AF-09, AF-10)

---

## Sources used

1. `app/src/server.py` (current implemented routes)
2. `_bmad-output/planning-artifacts/additional-functions-draft-2026-03-30.md` (new scope)
3. `_bmad-output/planning-artifacts/architecture.md`
4. `_bmad-output/planning-artifacts/epics.md`

---

## API contract conventions

- Base app API prefix: `/api/...`
- Mobile auth model: `Authorization: Bearer <access_token>`
- Dashboard auth model: cookie-based session (`session_token`)
- Role model in practice:
  - `admin` (system/operator controls)
  - `leader` (team/management controls)
  - `ranger` (field operations)
- Role model is mandatory for this project and limited to exactly these 3 roles.
- Scope policy: leader access applies only to rangers/resources where both `region` and `team` match the leader assignment.
- Scope policy: ranger access is self-only for non-schedule domains; for schedules, ranger access is same `region` + same `team` read-only.
- Scope policy: admin access is global across all `region`/`team` combinations for read/write operations.
- Database naming note: `team` replaces legacy `sub_region` for scope filtering.

---

## Screen-wise app API list (requested 2026-03-31)

### 1) `Quản lí công việc` (Work Management)

Required screen data:

- Leader ranger list/filter (same `region` + same `team` scope)
- Patrol count / scheduled work count and completion percentage
- Total patrol distance
- Events and event-status distribution created by ranger
- Time-range filter (`from` ... `to`)

| Method | Path                                                                                        | Role           | Status                                          | Purpose                                                                                                                                    |
| ------ | ------------------------------------------------------------------------------------------- | -------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| GET    | `/api/mobile/work-management?from=&to=&ranger_id=&page=&page_size=`                         | leader, ranger | Implemented + planned contract extension        | Calendar/day-level summary plus range-scoped metrics payload support                                                                       |
| GET    | `/api/mobile/work-management/rangers?active=&query=&page=&page_size=`                       | leader         | Planned (new)                                   | Ranger list for leader filter/dropdown                                                                                                     |
| GET    | `/api/mobile/work-management/summary?from=&to=&ranger_id=`                                  | leader, ranger | Planned (new)                                   | Aggregates: `patrol_count`, `scheduled_work_count`, `completion_percentage`, `total_distance_km`, `events_total`, `event_status_breakdown` |
| GET    | `/api/mobile/incidents?from=&to=&ranger_id=&event_type=&status=&priority=&page=&page_size=` | leader, ranger | Implemented baseline + planned filter extension | Reuse incident/event stream for ranger-created events on Work Management page                                                              |

### 2) `Quản lí lâm phần` (Incident Management)

Required screen data:

- Event list with event type, status, priority, note indicator
- Solved events / total events and solved percentage
- Attachment list per event (if present)
- Leader-only status update action
- Time-range filter (`from` ... `to`)

| Method | Path                                                                                                                         | Role           | Status                                            | Purpose                                                       |
| ------ | ---------------------------------------------------------------------------------------------------------------------------- | -------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| GET    | `/api/mobile/incidents?from=&to=&updated_since=&ranger_id=&event_type=&status=&priority=&has_note=&page=&page_size=&cursor=` | leader, ranger | Implemented baseline + planned contract extension | Incident/event list and filters for screen table/list         |
| GET    | `/api/mobile/incidents/summary?from=&to=&ranger_id=`                                                                         | leader         | Planned (new)                                     | Return `solved_count`, `total_count`, and `solved_percentage` |
| GET    | `/api/mobile/incidents/{incident_id}/attachments`                                                                            | leader         | Planned (new)                                     | List attachment metadata/files for each incident              |
| PATCH  | `/api/mobile/incidents/{incident_id}/status`                                                                                 | leader         | Planned (AF-02)                                   | Leader-controlled incident status transition                  |
| GET    | `/api/mobile/incidents/{incident_id}/status-history`                                                                         | leader         | Planned (new support API)                         | Incident status change audit timeline                         |

### Scope + filter contract examples (`region` + `team`)

- Leader default scope request: `GET /api/mobile/work-management?from=2026-03-01&to=2026-03-31`.
  - Server applies leader identity scope (same `region` + same `team`) automatically.
- Leader ranger-filter request: `GET /api/mobile/work-management?from=2026-03-01&to=2026-03-31&ranger_id=ranger_a`.
  - Server validates the requested ranger is in the leader's same `region` + same `team`; otherwise returns scope denial.
- Ranger self request: `GET /api/mobile/incidents?from=2026-03-01&to=2026-03-31`.
  - Ranger sees self-only data regardless of optional filters.
- Contract rule: clients must **not** pass `region` or `team` as API filters; both are derived server-side from authenticated identity/profile.

---

## A) Implemented APIs (current backend)

### Mobile authentication and identity

| Method | Path                       | Auth                  | Role            | Status      | Purpose                     |
| ------ | -------------------------- | --------------------- | --------------- | ----------- | --------------------------- |
| POST   | `/api/mobile/auth/login`   | none                  | all valid users | Implemented | Issue access/refresh tokens |
| POST   | `/api/mobile/auth/refresh` | refresh token payload | all valid users | Implemented | Rotate access token         |
| POST   | `/api/mobile/auth/logout`  | refresh token payload | all valid users | Implemented | Invalidate session          |
| GET    | `/api/mobile/me`           | mobile bearer token   | leader, ranger  | Implemented | Return current user claims  |

### Mobile work operations

| Method | Path                                  | Auth                | Role           | Status      | Purpose                                      |
| ------ | ------------------------------------- | ------------------- | -------------- | ----------- | -------------------------------------------- |
| GET    | `/api/mobile/work-management`         | mobile bearer token | leader, ranger | Implemented | Calendar summary (role-scoped)               |
| GET    | `/api/mobile/incidents`               | mobile bearer token | leader, ranger | Implemented | Read-only incidents with filters/sync cursor |
| POST   | `/api/mobile/checkins`                | mobile bearer token | ranger         | Implemented | Idempotent daily check-in ingest             |
| GET    | `/api/mobile/schedules`               | mobile bearer token | leader, ranger | Implemented | Read schedules (role/account scoped)         |
| POST   | `/api/mobile/schedules`               | mobile bearer token | leader         | Implemented | Create schedule                              |
| PUT    | `/api/mobile/schedules/{schedule_id}` | mobile bearer token | leader         | Implemented | Update schedule                              |
| DELETE | `/api/mobile/schedules/{schedule_id}` | mobile bearer token | admin          | Implemented | Soft-delete schedule                         |

Schedule policy note:

- Ranger schedule reads are read-only and limited to same `region` + same `team`.
- Leader schedule writes are limited to same `region` + same `team` ranger targets.
- Admin schedule operations are global (cross-region/cross-team allowed).

### Tree and NFC operations

| Method | Path                   | Auth              | Role                                                                | Status      | Purpose                            |
| ------ | ---------------------- | ----------------- | ------------------------------------------------------------------- | ----------- | ---------------------------------- |
| GET    | `/api/trees`           | dashboard session | admin, leader, ranger (leader/ranger scope: same `region` + `team`) | Implemented | Tree list + stats/alerts/analytics |
| GET    | `/api/trees/{tree_id}` | dashboard session | authenticated                                                       | Implemented | Tree detail                        |
| GET    | `/api/nfc/{nfc_uid}`   | dashboard session | authenticated                                                       | Implemented | NFC to tree lookup                 |
| POST   | `/api/nfc/link`        | dashboard session | authenticated                                                       | Implemented | Link NFC UID to tree               |

### Admin, operations, and platform

| Method | Path                                        | Auth              | Role   | Status      | Purpose                     |
| ------ | ------------------------------------------- | ----------------- | ------ | ----------- | --------------------------- |
| POST   | `/api/sync`                                 | dashboard session | admin  | Implemented | Trigger manual sync         |
| GET    | `/api/admin/retention/runs`                 | dashboard session | admin  | Implemented | List retention run history  |
| POST   | `/api/admin/retention/run`                  | dashboard session | admin  | Implemented | Run retention job           |
| POST   | `/api/admin/retention/runs/{run_id}/replay` | dashboard session | admin  | Implemented | Replay failed retention run |
| GET    | `/api/users`                                | dashboard session | admin  | Implemented | List users                  |
| POST   | `/api/users`                                | dashboard session | admin  | Implemented | Create user (leader/ranger) |
| DELETE | `/api/users/{username}`                     | dashboard session | admin  | Implemented | Delete user                 |
| GET    | `/health`                                   | none              | public | Implemented | Health probe                |

### Web app (non-`/api`) endpoints used by the app shell

| Method | Path      | Auth              | Status      | Purpose                |
| ------ | --------- | ----------------- | ----------- | ---------------------- |
| GET    | `/login`  | none              | Implemented | Login page             |
| POST   | `/login`  | form post         | Implemented | Dashboard login submit |
| GET    | `/logout` | dashboard session | Implemented | End dashboard session  |
| GET    | `/`       | dashboard session | Implemented | Dashboard app shell    |

---

## B) Required APIs for additional functions (target scope)

> These are the APIs required to complete additional approved functions.  
> Status values below indicate planning state, not implementation state.

### AF-01 — Weekly productivity insights

| Method | Path                                                                      | Role           | Status          | Purpose                                   |
| ------ | ------------------------------------------------------------------------- | -------------- | --------------- | ----------------------------------------- |
| GET    | `/api/mobile/insights/weekly?from=&to=&ranger_id=&include_variance=`      | leader, ranger | Planned (AF-01) | Weekly productivity snapshot + highlights |
| GET    | `/api/mobile/insights/weekly/top-activities?from=&to=&scope=team_or_self` | leader, ranger | Planned (AF-01) | Top activities summary                    |

### AF-02 — Forest compartment management (Quản lý lâm phần)

| Method | Path                                                                    | Role   | Status                          | Purpose                                      |
| ------ | ----------------------------------------------------------------------- | ------ | ------------------------------- | -------------------------------------------- |
| GET    | `/api/mobile/compartments/summary?from=&to=`                            | leader | Planned (AF-02)                 | Incident resolved/total ratio by compartment |
| GET    | `/api/mobile/compartments/hotspots?from=&to=&severity=`                 | leader | Planned (AF-02)                 | Unresolved incident hotspot list             |
| GET    | `/api/mobile/compartments/{compartment_id}/incidents?from=&to=&status=` | leader | Planned (AF-02)                 | Compartment incident drill-down              |
| POST   | `/api/mobile/incidents/{incident_id}/attachments`                       | leader | Planned (AF-02)                 | Attach operational documents/files           |
| PATCH  | `/api/mobile/incidents/{incident_id}/status`                            | leader | Planned (AF-02/AF-08 alignment) | Leader-only incident status transition       |

### AF-03 — Expanded schedule model (monthly planning metadata)

| Method | Path                                  | Role           | Status                             | Purpose                                           |
| ------ | ------------------------------------- | -------------- | ---------------------------------- | ------------------------------------------------- |
| GET    | `/api/mobile/schedules`               | leader, ranger | Planned contract extension (AF-03) | Add fields `schedule_name`, `sub_area`, `purpose` |
| POST   | `/api/mobile/schedules`               | leader         | Planned contract extension (AF-03) | Accept and validate monthly planning metadata     |
| PUT    | `/api/mobile/schedules/{schedule_id}` | leader         | Planned contract extension (AF-03) | Update extended schedule metadata                 |

### AF-04 — Forest resource management with RFID (valuable tree registry)

| Method | Path                                                                     | Role                        | Status          | Purpose                      |
| ------ | ------------------------------------------------------------------------ | --------------------------- | --------------- | ---------------------------- |
| GET    | `/api/mobile/forest-assets/trees?sub_area=&species=&health=&needs_care=` | leader, ranger              | Planned (AF-04) | Query valuable tree registry |
| POST   | `/api/mobile/forest-assets/trees`                                        | leader                      | Planned (AF-04) | Create RFID tree record      |
| GET    | `/api/mobile/forest-assets/trees/{asset_id}`                             | leader, ranger              | Planned (AF-04) | Tree asset detail            |
| PUT    | `/api/mobile/forest-assets/trees/{asset_id}`                             | leader                      | Planned (AF-04) | Update valuable tree record  |
| POST   | `/api/mobile/forest-assets/trees/{asset_id}/photos`                      | leader (+ranger if allowed) | Planned (AF-04) | Upload tree evidence photos  |
| POST   | `/api/mobile/forest-assets/rfid/link`                                    | leader                      | Planned (AF-04) | Link RFID tag to tree asset  |
| GET    | `/api/mobile/forest-assets/stats?group_by=species,health,sub_area`       | leader                      | Planned (AF-04) | Registry analytics           |
| GET    | `/api/mobile/forest-assets/alerts?class=needs-care`                      | leader, ranger              | Planned (AF-04) | Needs-care alert feed        |

### AF-05 — Vegetation identification integration (FORESTRY 4.0)

| Method | Path                                                      | Role           | Status          | Purpose                                |
| ------ | --------------------------------------------------------- | -------------- | --------------- | -------------------------------------- |
| POST   | `/api/mobile/integrations/forestry4/sessions`             | leader, ranger | Planned (AF-05) | Start external identify flow           |
| POST   | `/api/mobile/integrations/forestry4/callback`             | system         | Planned (AF-05) | Secure callback result ingestion       |
| GET    | `/api/mobile/integrations/forestry4/results/{session_id}` | leader, ranger | Planned (AF-05) | Fetch summarized identification result |

### AF-07 — Reporting center

| Method | Path                                                                          | Role           | Status          | Purpose                          |
| ------ | ----------------------------------------------------------------------------- | -------------- | --------------- | -------------------------------- |
| GET    | `/api/mobile/reports/catalog`                                                 | leader, ranger | Planned (AF-07) | Enumerate report types/windows   |
| GET    | `/api/mobile/reports/{report_type}?period=month_or_quarter_or_year&from=&to=` | leader, ranger | Planned (AF-07) | Render report data               |
| POST   | `/api/mobile/reports/exports`                                                 | leader         | Planned (AF-07) | Create export job (PDF/CSV/XLSX) |
| GET    | `/api/mobile/reports/exports/{job_id}`                                        | leader         | Planned (AF-07) | Poll export status/download URL  |

### AF-08 — Alerts center with event-type rules

| Method | Path                                                         | Role           | Status          | Purpose                       |
| ------ | ------------------------------------------------------------ | -------------- | --------------- | ----------------------------- |
| GET    | `/api/mobile/alerts?event_type=&severity=&status=&from=&to=` | leader, ranger | Planned (AF-08) | Alerts feed                   |
| GET    | `/api/mobile/alerts/live`                                    | leader, ranger | Planned (AF-08) | Near-real-time ephemeral feed |
| GET    | `/api/admin/alerts/rules`                                    | admin, leader  | Planned (AF-08) | Read rule configuration       |
| PUT    | `/api/admin/alerts/rules`                                    | admin, leader  | Planned (AF-08) | Update alert rules            |

### AF-09 — Company notifications (admin-authored push)

| Method | Path                                                 | Role                  | Status          | Purpose                           |
| ------ | ---------------------------------------------------- | --------------------- | --------------- | --------------------------------- |
| GET    | `/api/mobile/notifications?limit=5&cursor=`          | admin, leader, ranger | Planned (AF-09) | Read latest company notifications |
| POST   | `/api/admin/notifications`                           | admin                 | Planned (AF-09) | Create notification               |
| PUT    | `/api/admin/notifications/{notification_id}`         | admin                 | Planned (AF-09) | Edit notification                 |
| DELETE | `/api/admin/notifications/{notification_id}`         | admin                 | Planned (AF-09) | Delete notification               |
| POST   | `/api/admin/notifications/{notification_id}/publish` | admin                 | Planned (AF-09) | Publish/push dispatch             |

### AF-10 — Account policy enhancements + media banner

| Method | Path                                         | Role                  | Status          | Purpose                        |
| ------ | -------------------------------------------- | --------------------- | --------------- | ------------------------------ |
| GET    | `/api/mobile/profile`                        | admin, leader, ranger | Planned (AF-10) | Profile read endpoint          |
| PATCH  | `/api/mobile/profile/avatar`                 | admin, leader, ranger | Planned (AF-10) | Avatar update only             |
| POST   | `/api/admin/users/{username}/password-reset` | admin                 | Planned (AF-10) | Policy-driven password control |
| GET    | `/api/mobile/home/banners`                   | admin, leader, ranger | Planned (AF-10) | Home carousel read             |
| POST   | `/api/admin/home/banners`                    | admin                 | Planned (AF-10) | Create campaign banner         |
| PUT    | `/api/admin/home/banners/{banner_id}`        | admin                 | Planned (AF-10) | Update banner                  |
| DELETE | `/api/admin/home/banners/{banner_id}`        | admin                 | Planned (AF-10) | Delete banner                  |

---

## C) External integration APIs required by backend

### EarthRanger endpoints currently used by sync flows

| Method | Upstream path                                                                | Used by                                     | Purpose                        |
| ------ | ---------------------------------------------------------------------------- | ------------------------------------------- | ------------------------------ |
| GET    | `/api/v2.0/activity/eventtypes/` (fallback `/api/v1.0/activity/eventtypes/`) | `EarthRangerClient.resolve_event_type_uuid` | Resolve event type UUID        |
| GET    | `/api/v1.0/activity/events/`                                                 | `run_sync_cycle`                            | Fetch tree and incident events |

### EarthRanger endpoints available in integration client for future scope

| Method | Upstream path                                                   | Purpose             |
| ------ | --------------------------------------------------------------- | ------------------- |
| GET    | `/api/v1.0/activity/event/{event_id}/`                          | Read event detail   |
| POST   | `/api/v1.0/activity/events/`                                    | Create event        |
| PATCH  | `/api/v1.0/activity/event/{event_id}/`                          | Update event        |
| GET    | `/api/v1.0/activity/event/{event_id}/files/`                    | List files          |
| POST   | `/api/v1.0/activity/event/{event_id}/files/`                    | Upload files        |
| GET    | `/api/v1.0/activity/event/{event_id}/notes/`                    | List notes          |
| POST   | `/api/v1.0/activity/event/{event_id}/notes/`                    | Create note         |
| PATCH  | `/api/v1.0/activity/event/{event_id}/note/{note_id}/`           | Update note         |
| DELETE | `/api/v1.0/activity/event/{event_id}/note/{note_id}/`           | Delete note         |
| GET    | `/api/v1.0/activity/event/{event_id}/relationships/`            | Relationship lookup |
| POST   | `/api/v1.0/activity/event/{event_id}/relationships/{rel_type}/` | Relationship create |
| GET    | `/api/v1.0/activity/patrols/`                                   | Patrol data         |
| GET    | `/api/v1.0/user/me/`                                            | User identity check |
| GET    | `/api/v1.0/sources/`                                            | Source listing      |
| GET    | `/api/v1.0/subjects/`                                           | Subject listing     |

---

## D) Governance for this API catalog

1. Treat this file as the **API source-of-truth artifact** during planning and story creation.
2. Any API add/remove/change must update this file in the same change set.
3. When AF items are approved, move each endpoint status from `Planned` to `Approved` before development.
4. After implementation, update status to `Implemented` and attach test evidence references.

---

## E) Current summary counts

- Implemented app APIs: **22**
- Implemented web/system endpoints (non-`/api`): **5** (`/login` GET/POST, `/logout`, `/`, `/health`)
- Planned additional APIs/contracts for AF scope: **36** entries (including AF-03 contract extensions)
- Screen-driven contract additions requested on 2026-03-31: **9** entries (including 3 contract extensions and 5 net-new endpoints, plus 1 existing AF-02 endpoint reused in the screen map)

This catalog intentionally includes both current production surface and required target surface so the app can track all needed APIs in one place.

---

## F) Database recheck + API gap addendum (2026-03-30)

### F1. Database design recheck (based on current app requirements)

**Conclusion: Yes, database modifications are needed.**

#### Immediate baseline gaps (Phase 1 contract vs runtime reality)

1. **Check-ins are not durable yet**

- Current check-in storage is process memory (`mobile_daily_checkins`), so restart loses data.
- Required: persist to `daily_checkins` with unique constraint `(user_id, day_key)` and server-side dedup policy.

2. **Incident API read path is process memory-backed**

- Current incident API reads from `mobile_incident_records` in memory.
- Required: read from durable `incidents_mirror` (already used by sync upsert path) with role-scope filters.

3. **Core operational tables are referenced but not included in deploy SQL setup scripts**

- Add migration scripts for:
  - `daily_checkins`
  - `incidents_mirror`
  - `sync_cursors`
  - `retention_job_runs`
  - `idempotency_log`

4. **Identity scope columns need explicit `team` migration support**

- Ensure `app_users` and schedule-related schema include `team` and support rename migration from legacy `sub_region` where present.
- Leader scope filters must use both `region` and `team` as server-side matching keys.

5. **Idempotency audit trail is planned but missing**

- Add `idempotency_log` for replay visibility and operational forensics (`idempotency_key`, `endpoint`, `status`, `first_seen_at`, `last_seen_at`, request correlation fields).

#### Strongly recommended security/durability upgrades

6. **Persist mobile auth session state**

- Current access/refresh token maps are in memory.
- Add durable session tables (or equivalent) to support restart safety, revocation lineage, and multi-worker consistency.

7. **Indexes for mobile query patterns**

- Ensure indexes for common filters/sorts:
  - `daily_checkins(user_id, day_key)` unique
  - `incidents_mirror(mapped_ranger_id, updated_at desc)`
  - `incidents_mirror(mapping_status, updated_at desc)`
  - `retention_job_runs(status, started_at desc)`

#### Additional-function (AF) schema deltas

8. **AF-03 schedule metadata extension**

- Extend `schedules` with `schedule_name`, `sub_area`, `purpose` (+ optional validation constraints).

9. **New entities required for AF scope**

- AF-02: `compartments`, `incident_compartment_links`, `incident_status_history`, `incident_attachments`
- AF-04: `forest_assets`, `forest_asset_photos`, `rfid_tags` (or evolve `nfc_cards`), `forest_asset_care_events`
- AF-05: `forestry4_sessions`, `forestry4_results`, `forestry4_callback_logs`
- AF-07: `report_export_jobs`, `report_export_artifacts`
- AF-08: `alert_rules`, `alerts`, `alert_deliveries`, `alert_ack_events`
- AF-09: `notifications`, `notification_publications`, `notification_receipts`, `device_push_tokens`
- AF-10: `home_banners`, plus `app_users.avatar_url` and password policy audit table (`user_password_events`)

### F2. API coverage recheck (do we need more APIs?)

**Conclusion: Yes, add a small set of supporting APIs to complete operational workflows.**

#### Recommended API additions to this catalog

1. **AF-02 attachments lifecycle completeness**

- `GET /api/mobile/incidents/{incident_id}/attachments`
- `DELETE /api/mobile/incidents/{incident_id}/attachments/{attachment_id}`

2. **AF-02/AF-08 incident state governance**

- `GET /api/mobile/incidents/{incident_id}/status-history`
- `GET /api/mobile/incidents/{incident_id}/allowed-transitions`

3. **AF-04 RFID/tree evidence management completeness**

- `GET /api/mobile/forest-assets/trees/{asset_id}/photos`
- `DELETE /api/mobile/forest-assets/trees/{asset_id}/photos/{photo_id}`
- `POST /api/mobile/forest-assets/rfid/unlink`

4. **AF-05 integration observability and retries**

- `GET /api/mobile/integrations/forestry4/sessions/{session_id}`
- `POST /api/mobile/integrations/forestry4/sessions/{session_id}/retry`

5. **AF-07 export retrieval clarity**

- `GET /api/mobile/reports/exports/{job_id}/download`

6. **AF-08 alert operator/user actions**

- `PATCH /api/mobile/alerts/{alert_id}/ack`
- `PATCH /api/mobile/alerts/{alert_id}/resolve` (leader/admin policy)

7. **AF-09 notification UX completeness**

- `POST /api/mobile/notifications/{notification_id}/read`
- `GET /api/mobile/notifications/unread-count`
- `POST /api/mobile/devices/push-token`

8. **AF-10 profile and banner publication controls**

- `PATCH /api/mobile/profile` (optional non-avatar fields)
- `POST /api/admin/home/banners/{banner_id}/publish`
- `POST /api/admin/home/banners/{banner_id}/unpublish`

### F3. Sequencing note

Implement in this order for risk control:

1. **Baseline durability first** (`daily_checkins`, `incidents_mirror` read path, `sync_cursors`, `retention_job_runs`, `idempotency_log`).
2. **AF-03 schedule extension** (lowest disruption, reuses existing APIs).
3. **AF-01/07/08/09** (faster value delivery).
4. **AF-02/04/05** (higher integration complexity).
