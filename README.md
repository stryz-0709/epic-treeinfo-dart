# EarthRanger Integration Platform

Hệ thống tích hợp EarthRanger cho quản lý tuần tra rừng, giám sát cây và cảnh báo thời gian thực.

## Project Structure

```
EarthRanger/
├── app/              # Main FastAPI application (dashboard + API)
├── mobile/           # Mobile apps workspace
│   └── epic-treeinfo-dart/  # Imported V-Ranger Flutter mobile app
├── zalo-monitor/     # Standalone Zalo alert monitor (polls ER → sends to Zalo)
├── scripts/          # Utility scripts (create events, patrol reports, analysis)
├── reports/          # Lighthouse audits & generated reports
├── data/             # CSV data exports (patrols, tracking, accounts)
├── docs/             # Documentation (setup, pricing, guides)
└── tools/            # Account generation & one-off utilities
```

## Quick Start

### 1. Run the Dashboard (app)

```bash
cd app
cp .env.example .env   # Fill in your credentials
pip install -r requirements.txt
uvicorn src.server:app --host 0.0.0.0 --port 8000
```

### 2. Run with Docker

```bash
cd app
docker-compose up -d
```

### 3. Deploy to Production

```bash
cd app/deploy
deploy.bat
```

### 4. Run the Zalo Monitor

```bash
cd zalo-monitor
python earthranger_monitor.py
```

## Tech Stack

- **Backend:** Python 3.12, FastAPI, Uvicorn
- **Database:** Supabase (PostgreSQL)
- **Integrations:** EarthRanger API, Zalo OA, Google Sheets
- **Deployment:** Docker, systemd, nginx on DigitalOcean

## Security Baseline (Phase 1 Story 1.4)

- Mobile artifacts must not include privileged credentials (EarthRanger username/password, service-role keys, long-lived tokens).
- Backend production mode enforces:
  - no wildcard CORS origins,
  - non-default session secret.
- Mobile configuration uses `.env.example` as template; keep real `.env` local-only and uncommitted.
- If password grant is explicitly enabled for controlled scenarios, OAuth token endpoint must be HTTPS and host-allowlisted.

### Key Rotation Playbook (when leakage is suspected)

1. Rotate `SUPABASE_KEY` (service-role) in Supabase project settings.
2. Rotate `EARTHRANGER_TOKEN` and revoke old token.
3. Generate a new `SESSION_SECRET`.
4. Redeploy backend with updated runtime `.env` values.

### Security Validation Commands

From `app/`:

- `python -m src.security_checks`
- `python -m unittest discover -s tests -v`

## Workspace Notes (2026-03-18)

- Imported mobile repository: `mobile/epic-treeinfo-dart`
- Existing web dashboard and current project files were kept intact (no deletions).
- Reorganization is non-destructive: web stack remains in its current folders, mobile app is now grouped under `mobile/`.
