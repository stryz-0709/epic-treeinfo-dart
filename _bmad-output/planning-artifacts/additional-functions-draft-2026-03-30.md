# EarthRanger — Draft Full Required Functions (Backend Only, Non-Technical)

**Date:** 2026-03-30  
**Prepared for:** Admin  
**Status:** Draft for review

---

## What this document is

This is a **plain-language list of all backend functions the app needs**.

- It focuses only on server-side capabilities (no mobile/web screen design).
- It includes both:
  - functions already delivered in current scope, and
  - additional functions requested for next scope.

---

## Scope boundary (backend only)

Included:

- account and permission control
- business rules and validations
- syncing and storage with external systems
- reporting, alerts, and notifications
- operations, security, and audit controls

Not included:

- mobile UI flows
- web layout/UX details
- hardware procurement/installation

---

## Roles used in this draft

- **Admin**: system-level control
- **Leader**: management and team planning
- **Ranger**: field operations user

---

## A. Core backend functions required for go-live baseline

### 1) Sign-in and safe session handling

The backend must:

- let users sign in with valid credentials
- keep sessions active safely (refresh when needed)
- let users sign out and immediately stop old sessions
- reject invalid sign-in attempts

Who uses it: **Admin, Leader, Ranger**

### 2) Role-based access control

The backend must:

- decide what each role can and cannot do
- prevent Rangers from viewing other Rangers’ private work data
- allow Leaders to view team data but not system-level admin controls
- enforce all permissions on the server side (not only in app screens)

Who uses it: **All roles**

### 3) User account administration

The backend must:

- let Admin list users
- let Admin create Leader/Ranger accounts
- let Admin remove accounts safely
- revoke active sessions when an account is removed

Who uses it: **Admin**

### 4) Daily work management summary

The backend must:

- provide day-by-day work status data for calendar views
- support filtering by date range
- support Leader team view and Ranger self-only view
- return clear totals so app can show quick summaries

Who uses it: **Leader, Ranger**

### 5) Daily check-in recording (no duplicates)

The backend must:

- record check-in when Ranger opens app
- guarantee only one valid check-in per person per day
- safely handle repeated submissions without creating duplicates
- mark check-in status for that day’s work summary

Who uses it: **Ranger (direct), Leader (view results)**

### 6) Incident visibility (read-focused baseline)

The backend must:

- provide incident list from synced EarthRanger data
- let Rangers see only their own mapped incidents
- let Leaders see authorized team incidents
- support date/status filtering and controlled pagination

Who uses it: **Leader, Ranger**

### 7) Schedule assignment management

The backend must:

- show schedule assignments by day
- allow Leader to create and update schedules
- allow Admin to remove schedule records when needed
- keep Ranger in read-only mode for schedule data
- enforce assignment rules and validation before saving

Who uses it: **Leader, Ranger, Admin**

### 8) Tree registry and NFC linkage

The backend must:

- provide tree list and tree detail
- support lookup by NFC tag
- allow linking NFC tags to tree records
- provide overall tree health summaries and alerts

Who uses it: **Authenticated users (with role filters where needed)**

### 9) EarthRanger data synchronization

The backend must:

- pull updates from EarthRanger on a recurring schedule
- sync only new/changed data (not full reload every time)
- retry safely when network/service issues happen
- support manual sync trigger for operations team

Who uses it: **Admin/Operations (control), all users (consume synced data)**

### 10) Data retention and replayable operations

The backend must:

- keep required operational data for minimum retention window (6 months baseline)
- run retention cleanup on schedule
- keep an audit trail of each retention run
- allow replay of failed retention runs

Who uses it: **Admin/Operations**

### 11) Operational health and observability

The backend must:

- expose health status for deployment monitoring
- keep structured logs for troubleshooting
- attach request IDs so incidents can be traced end-to-end
- warn on slow requests and failed operations

Who uses it: **Operations team**

### 12) Security guardrails

The backend must:

- run with secure production settings (no weak default secrets)
- restrict allowed origins in production
- keep privileged credentials out of mobile-distributed assets
- apply request limits to sensitive operations (login/sync/API)

Who uses it: **All roles benefit; operated by Admin/DevOps**

---

## B. Additional required backend functions (next approved scope)

### AF-01 — Weekly productivity insights

Backend must provide:

- weekly performance summary by ranger/team
- “top activities this week” highlights
- optional comparison with previous period

Primary roles: **Leader, Ranger**

### AF-02 — Forest compartment management (Quản lý lâm phần)

Backend must provide:

- incident progress by compartment (resolved vs total)
- unresolved hotspot list by compartment
- incident drill-down per compartment and period
- attachment handling for incident records
- leader-controlled incident status updates

Primary roles: **Leader**

### AF-03 — Expanded monthly schedule details

Backend must extend schedule records with:

- schedule name
- sub-area (`tiểu khu`)
- reason/purpose

Primary roles: **Leader write, Ranger read**

### AF-04 — Forest resource management with RFID (valuable trees)

Backend must provide:

- valuable tree registry with RFID linkage
- full tree profile (species, age, health, location, photos, value)
- statistics by species/health/sub-area
- “needs care” alert feed

Primary roles: **Leader (full), Ranger (view/report by policy)**

### AF-05 — FORESTRY 4.0 integration

Backend must provide:

- secure handoff to external vegetation identification flow
- secure callback/result intake
- result history retrieval for users

Primary roles: **Leader, Ranger**

### AF-07 — Reporting center

Backend must provide:

- report types:
  1. forest protection management
  2. incident report
  3. work efficiency report
- period filters (month/quarter/year)
- export job flow and downloadable result

Primary roles: **Leader (full), Ranger (limited by policy)**

### AF-08 — Alerts center with event-type rules

Backend must provide:

- alert feed by event type, severity, and status
- live alert stream for active operations
- configurable alert rules (managed by admin/leader)
- strict role control for who can update incident status

Primary roles: **Leader, Ranger, Admin (rules management)**

### AF-09 — Company notifications

Backend must provide:

- admin-created announcement management
- publish/send push notifications
- latest notification feed for users

Primary roles: **Admin authoring; all roles receive**

### AF-10 — Account policy controls + home banner management

Backend must provide:

- profile read and avatar update
- policy-based password control (admin-managed)
- banner content management for home communication carousel

Primary roles: **Admin, Leader, Ranger**

---

## C. Priority recommendation (backend view)

### Priority 1 (high value, faster rollout)

- AF-01 Weekly insights
- AF-07 Reporting center
- AF-08 Alerts center
- AF-09 Company notifications

### Priority 2 (medium

complexity)

- AF-02 Compartment management
- AF-03 Expanded schedule model
- AF-10 Account policy + banner management

### Priority 3 (strategic, higher complexity)

- AF-04 RFID valuable tree management
- AF-05 FORESTRY 4.0 integration

---

## D. Decisions needed before implementation

1. Should alerts be temporary-only, or stored for history?
2. For incident ownership, keep current mapping or refine mapping rules?
3. For RFID records, should backend trust EarthRanger first or local registry first?
4. Final export formats for reports (PDF/CSV/XLSX)?
5. Exact Ranger edit rights in AF-04 and AF-05?

---

## E. Approval checklist

Mark each as:

- `APPROVE`
- `PARK`
- `DROP`

Core baseline (A): [ ] APPROVE  
AF-01: [ ]  
AF-02: [ ]  
AF-03: [ ]  
AF-04: [ ]  
AF-05: [ ]  
AF-07: [ ]  
AF-08: [ ]  
AF-09: [ ]  
AF-10: [ ]
