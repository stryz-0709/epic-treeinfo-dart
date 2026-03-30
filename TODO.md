# V-Ranger Mobile App -- Feature Progress Tracker

> Last updated: 2026-03-29

---

## Priority 1 -- Critical / Core Features ✅ ALL COMPLETE

### 1.1 Sign-up / Registration ✅ DONE
- **Backend**: `POST /api/mobile/auth/register` -- creates user with `status: 'pending'` (admin-approved flow)
- **Backend**: Login rejects `pending` / `rejected` accounts with 403
- **DB**: Added `status` column (`active|pending|rejected`) and `avatar_url` to `app_users`
- **Mobile**: `SignupScreen` with form validation (username, password, confirm, display name, region, phone)
- **Localization**: Full vi/en keys for signup flow
- **Could extend**: Admin panel to approve/reject pending users (currently manual DB update)

### 1.2 Account Screen ✅ DONE
- **Backend**: `GET /api/mobile/me` returns profile with region/phone/avatar_url
- **Backend**: `PUT /api/mobile/account/profile` updates display_name, region, phone
- **Backend**: `POST /api/mobile/account/avatar` uploads to Supabase Storage
- **Mobile**: `AccountScreen` replaces placeholder -- avatar (camera/gallery), editable fields, role badge, logout
- **Localization**: Full vi/en keys for account screen
- **Could extend**: Password change flow, admin user management screen

### 1.3 Work Management Enhancements ✅ DONE
- **Backend**: `GET /api/mobile/employees` -- role-scoped employee list
- **Backend**: `GET /api/mobile/work-management/stats` -- per-ranger checkin days, incidents found, date range
- **Mobile**: Leader stats panel (horizontal scroll cards) with check-in rate % and incident count per ranger
- **Skipped per user request**: Average comparison chart, weekly summary
- **Could extend**: Date range picker for stats, individual employee detail drill-down, export stats

### 1.4 Check-in GPS Enhancement ✅ DONE
- **Backend**: Check-in ingestion stores `latitude` and `longitude`
- **Mobile**: `geolocator` package captures GPS before check-in submission
- **Mobile**: Permission handling (denied gracefully, check-in still submits without coords)
- **Could extend**: Display check-in location on map, geofencing validation

---

## Priority 2 -- Major Feature Screens ✅ MOSTLY COMPLETE

### 2.1 Forest Compartment Management ✅ DONE
- **DB**: `forest_compartments` table schema + seed data in `app/deploy/supabase_forest_compartments.sql`
- **Backend**: `GET /api/mobile/forest-compartments` (list with incident counts), `GET /api/mobile/forest-compartments/{id}/incidents` (detail)
- **Backend**: In-memory seed with 5 sample compartments, incident matching by region
- **Mobile**: `ForestCompartmentScreen` with compartment cards, region chips, incident counts, resolution progress bar
- **Mobile**: Accessible from landing page "Forest Resource Management" card and `/forest-compartment` route
- **Localization**: Full vi/en keys
- **Could extend**: Compartment map view, document attachments, staff assignment display

### 2.2 Map Screen ✅ DONE
- **Mobile**: `MapScreen` with EarthRanger WebView (`webview_flutter`)
- **Mobile**: Loads `ER_WEB_URL` from `.env` (defaults to `https://epictech.pamdas.org`)
- **Mobile**: Loading indicator overlay, bottom navigation bar
- **Mobile**: Replaces `FeaturePlaceholderScreen` at `/maps` route
- **Could extend**: Native map layers, offline tile caching, marker overlays

### 2.3 Alerts Screen ✅ DONE
- **Backend**: `GET /api/mobile/alerts` -- recent 30-day incidents sorted by severity then recency, with alert_level classification (urgent/warning/info)
- **Mobile**: `AlertsScreen` with color-coded alert cards (red/orange/gray), pull-to-refresh
- **Mobile**: Replaces `FeaturePlaceholderScreen` at `/alerts` route
- **Localization**: Full vi/en keys
- **Could extend**: Alert sound/vibration, manager status change action, configurable event type filter

### 2.4 Notifications Screen + Push ⏭ SKIPPED
- Skipped per user preference (can be added later with Firebase setup)
- `/notifications` route still shows `FeaturePlaceholderScreen`

### 2.5 Reports (In-App View) ✅ DONE
- **Backend**: `GET /api/mobile/reports/{type}` with types: `forest-protection`, `incidents`, `work-performance`
- **Backend**: Date range filtering, aggregated stats per ranger
- **Mobile**: `ReportsScreen` with 3 tabs, date range quick buttons (this month/quarter/year/custom)
- **Mobile**: Forest protection tab: total/resolved/unresolved, severity/status breakdowns
- **Mobile**: Incidents tab: total, per-ranger breakdown
- **Mobile**: Work performance tab: checkin rates, per-ranger table
- **Mobile**: Replaces `WorkManagementScreen` at `/reports-management` route
- **Localization**: Full vi/en keys
- **Could extend**: PDF/Excel export, chart visualizations

---

## Priority 3 -- Feature Enhancements 🔲 NOT STARTED

### 3.1 Forest Resource Enhancements
- Species/status statistics, care alerts, sub-compartment field, FORESTRY 4.0 web link
- Current: Tree NFC scan + detail screen exists, no statistics dashboard

### 3.2 Patrol Management Screen
- Land patrol + drone patrol, EarthRanger integration, banner images
- Current: `/patrol-management` reuses `IncidentManagementScreen`

### 3.3 Incident Detail + Status Update
- Drill-down detail screen, manager status change, attachments
- Current: Read-only incident list with severity/status display

### 3.4 Background GPS / Patrol Tracking
- Route tracking during patrols, distance/hours calculation
- Current: GPS captured at check-in only (1.4)

---

## Priority 4 -- Polish & Infrastructure 🔲 NOT STARTED

### 4.1 Supabase Schema Migrations
- Formalize all tables as versioned migrations

### 4.2 Persistent Mobile Token Store
- Move in-memory sessions to DB (currently lost on server restart)

### 4.3 Persistent Work/Incident Data
- Move in-memory work summary and incident records to Supabase tables

### 4.4 iOS NFC Support
- Enable CoreNFC entitlements for iOS NFC reading

### 4.5 Localization (Ongoing)
- Add vi/en keys for all new screens as they are built
- Current: Keys exist for login, signup, account, work management, incidents, schedules

### 4.6 Developer Mode ✅ DONE
- **Mobile**: Login screen dev mode (tap version text 5x to activate)
- **Mobile**: Quick-login panel with 3 test accounts (Admin/Leader, Leader, Ranger)
- **Mobile**: Configurable via `.env` keys (`DEV_ADMIN_USERNAME`, `DEV_DEFAULT_PASSWORD`, etc.)
- **Backend**: Seeded `leader1` and `ranger1` test accounts alongside `admin` on first boot
- **Could extend**: Add more test accounts, show current backend URL in dev panel

### 4.7 Testing (Ongoing)
- `TESTCASES.md` created with 80+ test cases covering all P1 and P2 features
- Organized by feature area: Dev Mode, Auth, Signup, Account, Navigation, Work Management, GPS, Forest Compartments, Map, Alerts, Reports, Incidents, Schedules, NFC/Tree, Cross-cutting
- Widget + integration tests for new screens and providers

---

## Architecture Overview

```
Flutter App (mobile/)
  ├── Screens: login, signup, landing, home, account, work-mgmt, incident-mgmt,
  │            schedule-mgmt, tree-detail, link-tree, map, alerts,
  │            forest-compartment, reports, feature-placeholder
  ├── Providers: auth, settings, tree, work-mgmt, incident, schedule
  ├── Services: mobile_api, supabase, earthranger_auth, checkin_queue, cache, localizations
  └── Routes: /login, /signup, /landing, /home, /detail, /link, /account,
              /work-management, /incident-management, /schedule-management,
              /resource-management, /reports-management, /patrol-management,
              /forest-compartment, /maps, /alerts, /notifications

Backend API (app/src/server.py)
  ├── Mobile Auth: login, refresh, logout, register
  ├── Mobile Profile: me, profile update, avatar upload
  ├── Mobile Data: work-management, stats, employees, incidents, checkins, schedules
  ├── Mobile Features: forest-compartments, alerts, reports (3 types)
  └── Admin/Dashboard: trees, nfc, sync, users, retention

Database (Supabase)
  ├── app_users (with status, avatar_url)
  ├── trees, nfc_cards
  ├── schedules, schedule_action_logs
  ├── incidents_mirror, sync_cursors
  ├── forest_compartments (schema + seed data available)
  └── [pending] notifications
```
