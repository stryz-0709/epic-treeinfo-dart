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

---

## A) Implemented APIs (current backend)

### Mobile authentication and identity

| Method | Path | Auth | Role | Status | Purpose |
|---|---|---|---|---|---|
| POST | `/api/mobile/auth/login` | none | all valid users | Implemented | Issue access/refresh tokens |
| POST | `/api/mobile/auth/refresh` | refresh token payload | all valid users | Implemented | Rotate access token |
| POST | `/api/mobile/auth/logout` | refresh token payload | all valid users | Implemented | Invalidate session |
| GET | `/api/mobile/me` | mobile bearer token | leader, ranger | Implemented | Return current user claims |

### Mobile work operations

| Method | Path | Auth | Role | Status | Purpose |
|---|---|---|---|---|---|
| GET | `/api/mobile/work-management` | mobile bearer token | leader, ranger | Implemented | Calendar summary (role-scoped) |
| GET | `/api/mobile/incidents` | mobile bearer token | leader, ranger | Implemented | Read-only incidents with filters/sync cursor |
| POST | `/api/mobile/checkins` | mobile bearer token | ranger | Implemented | Idempotent daily check-in ingest |
| GET | `/api/mobile/schedules` | mobile bearer token | leader, ranger | Implemented | Read schedules (role/account scoped) |
| POST | `/api/mobile/schedules` | mobile bearer token | leader | Implemented | Create schedule |
| PUT | `/api/mobile/schedules/{schedule_id}` | mobile bearer token | leader | Implemented | Update schedule |
| DELETE | `/api/mobile/schedules/{schedule_id}` | mobile bearer token | admin | Implemented | Soft-delete schedule |

### Tree and NFC operations

| Method | Path | Auth | Role | Status | Purpose |
|---|---|---|---|---|---|
| GET | `/api/trees` | dashboard session | admin, leader, ranger (region-scoped) | Implemented | Tree list + stats/alerts/analytics |
| GET | `/api/trees/{tree_id}` | dashboard session | authenticated | Implemented | Tree detail |
| GET | `/api/nfc/{nfc_uid}` | dashboard session | authenticated | Implemented | NFC to tree lookup |
| POST | `/api/nfc/link` | dashboard session | authenticated | Implemented | Link NFC UID to tree |

### Admin, operations, and platform

| Method | Path | Auth | Role | Status | Purpose |
|---|---|---|---|---|---|
| POST | `/api/sync` | dashboard session | admin | Implemented | Trigger manual sync |
| GET | `/api/admin/retention/runs` | dashboard session | admin | Implemented | List retention run history |
| POST | `/api/admin/retention/run` | dashboard session | admin | Implemented | Run retention job |
| POST | `/api/admin/retention/runs/{run_id}/replay` | dashboard session | admin | Implemented | Replay failed retention run |
| GET | `/api/users` | dashboard session | admin | Implemented | List users |
| POST | `/api/users` | dashboard session | admin | Implemented | Create user (leader/ranger) |
| DELETE | `/api/users/{username}` | dashboard session | admin | Implemented | Delete user |
| GET | `/health` | none | public | Implemented | Health probe |

### Web app (non-`/api`) endpoints used by the app shell

| Method | Path | Auth | Status | Purpose |
|---|---|---|---|---|
| GET | `/login` | none | Implemented | Login page |
| POST | `/login` | form post | Implemented | Dashboard login submit |
| GET | `/logout` | dashboard session | Implemented | End dashboard session |
| GET | `/` | dashboard session | Implemented | Dashboard app shell |

---

## B) Required APIs for additional functions (target scope)

> These are the APIs required to complete additional approved functions.  
> Status values below indicate planning state, not implementation state.

### AF-01 — Weekly productivity insights

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/insights/weekly?from=&to=&ranger_id=&include_variance=` | leader, ranger | Planned (AF-01) | Weekly productivity snapshot + highlights |
| GET | `/api/mobile/insights/weekly/top-activities?from=&to=&scope=team|self` | leader, ranger | Planned (AF-01) | Top activities summary |

### AF-02 — Forest compartment management (Quản lý lâm phần)

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/compartments/summary?from=&to=` | leader | Planned (AF-02) | Incident resolved/total ratio by compartment |
| GET | `/api/mobile/compartments/hotspots?from=&to=&severity=` | leader | Planned (AF-02) | Unresolved incident hotspot list |
| GET | `/api/mobile/compartments/{compartment_id}/incidents?from=&to=&status=` | leader | Planned (AF-02) | Compartment incident drill-down |
| POST | `/api/mobile/incidents/{incident_id}/attachments` | leader | Planned (AF-02) | Attach operational documents/files |
| PATCH | `/api/mobile/incidents/{incident_id}/status` | leader | Planned (AF-02/AF-08 alignment) | Leader-only incident status transition |

### AF-03 — Expanded schedule model (monthly planning metadata)

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/schedules` | leader, ranger | Planned contract extension (AF-03) | Add fields `schedule_name`, `sub_area`, `purpose` |
| POST | `/api/mobile/schedules` | leader | Planned contract extension (AF-03) | Accept and validate monthly planning metadata |
| PUT | `/api/mobile/schedules/{schedule_id}` | leader | Planned contract extension (AF-03) | Update extended schedule metadata |

### AF-04 — Forest resource management with RFID (valuable tree registry)

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/forest-assets/trees?sub_area=&species=&health=&needs_care=` | leader, ranger | Planned (AF-04) | Query valuable tree registry |
| POST | `/api/mobile/forest-assets/trees` | leader | Planned (AF-04) | Create RFID tree record |
| GET | `/api/mobile/forest-assets/trees/{asset_id}` | leader, ranger | Planned (AF-04) | Tree asset detail |
| PUT | `/api/mobile/forest-assets/trees/{asset_id}` | leader | Planned (AF-04) | Update valuable tree record |
| POST | `/api/mobile/forest-assets/trees/{asset_id}/photos` | leader (+ranger if allowed) | Planned (AF-04) | Upload tree evidence photos |
| POST | `/api/mobile/forest-assets/rfid/link` | leader | Planned (AF-04) | Link RFID tag to tree asset |
| GET | `/api/mobile/forest-assets/stats?group_by=species|health|sub_area` | leader | Planned (AF-04) | Registry analytics |
| GET | `/api/mobile/forest-assets/alerts?class=needs-care` | leader, ranger | Planned (AF-04) | Needs-care alert feed |

### AF-05 — Vegetation identification integration (FORESTRY 4.0)

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| POST | `/api/mobile/integrations/forestry4/sessions` | leader, ranger | Planned (AF-05) | Start external identify flow |
| POST | `/api/mobile/integrations/forestry4/callback` | system | Planned (AF-05) | Secure callback result ingestion |
| GET | `/api/mobile/integrations/forestry4/results/{session_id}` | leader, ranger | Planned (AF-05) | Fetch summarized identification result |

### AF-07 — Reporting center

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/reports/catalog` | leader, ranger | Planned (AF-07) | Enumerate report types/windows |
| GET | `/api/mobile/reports/{report_type}?period=month|quarter|year&from=&to=` | leader, ranger | Planned (AF-07) | Render report data |
| POST | `/api/mobile/reports/exports` | leader | Planned (AF-07) | Create export job (PDF/CSV/XLSX) |
| GET | `/api/mobile/reports/exports/{job_id}` | leader | Planned (AF-07) | Poll export status/download URL |

### AF-08 — Alerts center with event-type rules

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/alerts?event_type=&severity=&status=&from=&to=` | leader, ranger | Planned (AF-08) | Alerts feed |
| GET | `/api/mobile/alerts/live` | leader, ranger | Planned (AF-08) | Near-real-time ephemeral feed |
| GET | `/api/admin/alerts/rules` | admin, leader | Planned (AF-08) | Read rule configuration |
| PUT | `/api/admin/alerts/rules` | admin, leader | Planned (AF-08) | Update alert rules |

### AF-09 — Company notifications (admin-authored push)

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/notifications?limit=5&cursor=` | admin, leader, ranger | Planned (AF-09) | Read latest company notifications |
| POST | `/api/admin/notifications` | admin | Planned (AF-09) | Create notification |
| PUT | `/api/admin/notifications/{notification_id}` | admin | Planned (AF-09) | Edit notification |
| DELETE | `/api/admin/notifications/{notification_id}` | admin | Planned (AF-09) | Delete notification |
| POST | `/api/admin/notifications/{notification_id}/publish` | admin | Planned (AF-09) | Publish/push dispatch |

### AF-10 — Account policy enhancements + media banner

| Method | Path | Role | Status | Purpose |
|---|---|---|---|---|
| GET | `/api/mobile/profile` | admin, leader, ranger | Planned (AF-10) | Profile read endpoint |
| PATCH | `/api/mobile/profile/avatar` | admin, leader, ranger | Planned (AF-10) | Avatar update only |
| POST | `/api/admin/users/{username}/password-reset` | admin | Planned (AF-10) | Policy-driven password control |
| GET | `/api/mobile/home/banners` | admin, leader, ranger | Planned (AF-10) | Home carousel read |
| POST | `/api/admin/home/banners` | admin | Planned (AF-10) | Create campaign banner |
| PUT | `/api/admin/home/banners/{banner_id}` | admin | Planned (AF-10) | Update banner |
| DELETE | `/api/admin/home/banners/{banner_id}` | admin | Planned (AF-10) | Delete banner |

---

## C) External integration APIs required by backend

### EarthRanger endpoints currently used by sync flows

| Method | Upstream path | Used by | Purpose |
|---|---|---|---|
| GET | `/api/v2.0/activity/eventtypes/` (fallback `/api/v1.0/activity/eventtypes/`) | `EarthRangerClient.resolve_event_type_uuid` | Resolve event type UUID |
| GET | `/api/v1.0/activity/events/` | `run_sync_cycle` | Fetch tree and incident events |

### EarthRanger endpoints available in integration client for future scope

| Method | Upstream path | Purpose |
|---|---|---|
| GET | `/api/v1.0/activity/event/{event_id}/` | Read event detail |
| POST | `/api/v1.0/activity/events/` | Create event |
| PATCH | `/api/v1.0/activity/event/{event_id}/` | Update event |
| GET | `/api/v1.0/activity/event/{event_id}/files/` | List files |
| POST | `/api/v1.0/activity/event/{event_id}/files/` | Upload files |
| GET | `/api/v1.0/activity/event/{event_id}/notes/` | List notes |
| POST | `/api/v1.0/activity/event/{event_id}/notes/` | Create note |
| PATCH | `/api/v1.0/activity/event/{event_id}/note/{note_id}/` | Update note |
| DELETE | `/api/v1.0/activity/event/{event_id}/note/{note_id}/` | Delete note |
| GET | `/api/v1.0/activity/event/{event_id}/relationships/` | Relationship lookup |
| POST | `/api/v1.0/activity/event/{event_id}/relationships/{rel_type}/` | Relationship create |
| GET | `/api/v1.0/activity/patrols/` | Patrol data |
| GET | `/api/v1.0/user/me/` | User identity check |
| GET | `/api/v1.0/sources/` | Source listing |
| GET | `/api/v1.0/subjects/` | Subject listing |

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

This catalog intentionally includes both current production surface and required target surface so the app can track all needed APIs in one place.
