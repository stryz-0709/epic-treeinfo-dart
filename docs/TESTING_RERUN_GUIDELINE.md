# EarthRanger Rerun Testing Guideline (Backend + Mobile)

Use this playbook every time you want to rerun mobile testing quickly and consistently.

---

## 1) Pre-check (once per session)

### Required tools
- Python virtual environment exists at: `C:\Users\Admin\Desktop\EarthRanger\.venv`
- Flutter + Android SDK installed
- USB debugging enabled on phone

### Recommended project state
- Backend config file exists: `app/.env`
- Mobile config file exists: `mobile/epic-treeinfo-dart/.env`

---

## 2) Hard reset before rerun

Run these from PowerShell.

### Stop old backend on port 8000
`Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force }`

### (Optional) Clear old mobile app data when login/session is weird
`adb shell pm clear com.epictech.vranger`

---

## 3) Start backend correctly (important)

> Always start from the `app/` folder.  
> If started from workspace root, `.env` may not load correctly.

`Set-Location "C:\Users\Admin\Desktop\EarthRanger\app"`

`c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m uvicorn src.server:app --host 0.0.0.0 --port 8000 --log-level info`

### Health check
`Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:8000/health"`

Expected: HTTP 200 and JSON status response.

---

## 4) Update app to phone (fast path)

Use the helper script from mobile folder:

`Set-Location "C:\Users\Admin\Desktop\EarthRanger\mobile\epic-treeinfo-dart"`

### Fast install only
`./fast-deploy-phone.ps1 -InstallOnly`

### Run with live debug session (for active coding)
`./fast-deploy-phone.ps1`

What this script already handles:
- auto-detect Android device
- ensure `adb` is available (from local Android SDK path)
- run `adb reverse tcp:8000 tcp:8000`
- deploy app quickly

---

## 5) Login checklist

### Known working default admin (local)
- Username: `admin`
- Password: `admin123`

### If login fails
1. Confirm backend log shows which username is being submitted.
2. Ensure you are using `admin` (not an old remembered account).
3. Clear app data and reinstall:
   - `adb shell pm clear com.epictech.vranger`
   - `./fast-deploy-phone.ps1 -InstallOnly`
4. Retry login.

---

## 6) Work Schedule test flow

1. Login as leader/admin.
2. Open `Schedule Management`.
3. Verify schedule list loads.
4. Create a schedule item.
5. Edit the same schedule item.
6. Pull-to-refresh and verify data persists.
7. Optional: switch month/filter and verify list integrity.

---

## 7) Live monitoring during test

Keep backend terminal visible and watch for these endpoints:
- `POST /api/mobile/auth/login`
- `GET /api/mobile/schedules`
- `POST /api/mobile/schedules`
- `PUT /api/mobile/schedules/{schedule_id}`

Interpretation tips:
- `401` on login: wrong username/password or stale app state
- `403` on schedule write: role/scope restriction
- `404` on update: schedule ID not found (stale item)
- `200`/`201`: normal success

---

## 8) Known noisy logs (usually not blocker for mobile login)

You may still see background sync warnings/errors related to EarthRanger or retention tables, for example:
- EarthRanger `401` / event type fetch warnings
- retention table missing warnings

These can be investigated separately if mobile auth/schedule endpoints still pass.

---

## 9) Quick rerun command sequence (copy-paste order)

`Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force }`

`Set-Location "C:\Users\Admin\Desktop\EarthRanger\app"`

`c:/Users/Admin/Desktop/EarthRanger/.venv/Scripts/python.exe -m uvicorn src.server:app --host 0.0.0.0 --port 8000 --log-level info`

`Set-Location "C:\Users\Admin\Desktop\EarthRanger\mobile\epic-treeinfo-dart"`

`./fast-deploy-phone.ps1 -InstallOnly`

---

## 10) Optional: when to restart everything again

Do a full rerun cycle if any of these occur:
- phone shows network/auth errors after backend restart
- backend logs show different username than expected
- app appears to keep old session unexpectedly
- `adb`/device connection changed (USB reconnect)

