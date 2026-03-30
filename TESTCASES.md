# V-Ranger Mobile App -- Test Cases (P1 & P2)

> **Prerequisites for all tests:**
> - Backend server running (`python app/src/server.py`)
> - Flutter app running on device/emulator (`cd mobile && flutter run`)
> - Delete `data/users.json` before first run to seed fresh test accounts:
>   - `admin` / `admin123` (role: admin → maps to leader in mobile)
>   - `leader1` / `admin123` (role: leader)
>   - `ranger1` / `admin123` (role: ranger)

---

## 0. Developer Mode (Login Screen)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 0.1 | Activate dev mode | On login screen, tap the version text at the bottom 5 times rapidly (within 3 seconds) | Yellow "Developer Mode" panel appears with 3 test accounts; version text shows "· DEV" suffix; haptic feedback on activation |
| 0.2 | Quick login as Admin | Activate dev mode → tap "Admin / Leader" card | Username/password auto-filled → login succeeds → navigates to landing screen as leader role |
| 0.3 | Quick login as Leader | Activate dev mode → tap "Leader" card | Login succeeds → landing shows "Leader" role badge |
| 0.4 | Quick login as Ranger | Activate dev mode → tap "Ranger" card | Login succeeds → landing shows "Ranger" role badge; app-open check-in triggered |
| 0.5 | Close dev panel | Activate dev mode → tap X icon on the panel | Dev panel closes; version text returns to normal |
| 0.6 | Toggle dev mode off | With dev mode active, tap version text 5 times again | Dev panel closes; version text returns to normal |
| 0.7 | Tap count resets after timeout | Tap version text 3 times → wait 4 seconds → tap 2 more times | Dev mode does NOT activate (tap counter resets after 3s window) |

---

## 1. Login & Authentication (P1)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 1.1 | Successful login (leader) | Enter `admin` / `admin123` → tap Sign In | Navigates to landing screen; user info card shows "Administrator" and "Leader" role |
| 1.2 | Successful login (ranger) | Enter `ranger1` / `admin123` → tap Sign In | Navigates to landing screen; user info card shows "Test Ranger" and "Ranger" role |
| 1.3 | Invalid credentials | Enter `admin` / `wrongpass` → tap Sign In | Error snackbar "Invalid credentials" appears; stays on login screen |
| 1.4 | Empty username validation | Leave username empty → tap Sign In | Inline validation error under username field |
| 1.5 | Empty password validation | Enter username but leave password empty → tap Sign In | Inline validation error under password field |
| 1.6 | Password visibility toggle | Tap the eye icon next to password field | Password text toggles between hidden (dots) and visible |
| 1.7 | Remember me - persist | Check "Remember me" → login → force close app → reopen | App auto-restores session and navigates directly to landing (shows "Restoring session" spinner briefly) |
| 1.8 | Remember me - not checked | Uncheck "Remember me" → login → force close → reopen | App shows login screen (no session restored) |
| 1.9 | Logout flow | From landing → Account tab (bottom nav) → Logout button | Navigates back to login screen; session cleared |
| 1.10 | Pending account rejection | Register a new account → try to login before admin approval | 403 error with "Account pending approval" message |
| 1.11 | Network error | Disconnect network → try to login | Error snackbar with network error message |

---

## 2. Sign-up / Registration (P1.1)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 2.1 | Navigate to signup | On login screen → tap "Create account" link | Navigates to signup screen |
| 2.2 | Successful registration | Fill all fields (username, password, confirm password, display name, region, phone) → tap Register | Success message; navigates back to login screen |
| 2.3 | Password mismatch | Enter different passwords in password and confirm fields | Inline validation error "Passwords do not match" |
| 2.4 | Username already taken | Register with username "admin" (existing) | Error: "Username already taken" (409) |
| 2.5 | Empty required fields | Submit form with all fields empty | Inline validation errors on all required fields |
| 2.6 | New account is pending | Register successfully → immediately try to login | Login rejected with "Account pending approval" |
| 2.7 | Back navigation | Tap back button/arrow on signup screen | Returns to login screen |

---

## 3. Account Screen (P1.2)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 3.1 | View profile | Login → bottom nav → Account tab | Account screen shows avatar, display name, username, role badge, region, phone |
| 3.2 | Edit display name | Tap edit on display name → change text → save | Name updates; shows success feedback |
| 3.3 | Edit region | Tap edit on region → change → save | Region updates on profile |
| 3.4 | Edit phone | Tap edit on phone → change → save | Phone updates on profile |
| 3.5 | Upload avatar (camera) | Tap avatar → choose Camera | Camera opens; take photo → avatar updates |
| 3.6 | Upload avatar (gallery) | Tap avatar → choose Gallery | Gallery opens; select image → avatar updates |
| 3.7 | Role badge display (leader) | Login as leader → Account screen | Shows "Leader" role badge |
| 3.8 | Role badge display (ranger) | Login as ranger → Account screen | Shows "Ranger" role badge |
| 3.9 | Logout button | Tap Logout button | Confirmation → clears session → returns to login screen |

---

## 4. Landing Screen & Navigation

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 4.1 | Landing page loads | Login successfully | Landing page shows: user info card (name, role, duty status, date), 6 feature cards, bottom nav bar |
| 4.2 | User info card | Check the green card at top | Shows correct display name, role (Leader/Ranger), "On Duty" status, current date in correct locale |
| 4.3 | Feature cards present | Verify all 6 cards visible | Work Management, Incident Management, Forest Resources, Schedule Management, Reports, Patrol Management |
| 4.4 | Bottom nav - Home | Tap Home in bottom nav | Stays on landing (already on home) |
| 4.5 | Bottom nav - Maps | Tap Maps in bottom nav | Navigates to Map screen (WebView) |
| 4.6 | Bottom nav - Alerts | Tap Alerts in bottom nav | Navigates to Alerts screen |
| 4.7 | Bottom nav - Notifications | Tap Notifications in bottom nav | Navigates to Notifications placeholder screen |
| 4.8 | Bottom nav - Account | Tap Account in bottom nav | Navigates to Account screen |
| 4.9 | Localization (Vietnamese) | Switch to Vietnamese in settings | All landing page text shows in Vietnamese |
| 4.10 | Localization (English) | Switch to English in settings | All landing page text shows in English |

---

## 5. Work Management (P1.3)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 5.1 | View as ranger | Login as ranger → tap "Work Management" card | Shows ranger's own work calendar with check-in history |
| 5.2 | Check-in action (ranger) | On work management → tap Check-in button | Check-in recorded; calendar updates with today's entry; GPS coordinates captured if permission granted |
| 5.3 | View as leader | Login as leader → tap "Work Management" card | Shows leader stats panel with horizontal scroll cards for each ranger |
| 5.4 | Leader stats cards | As leader, view stats panel | Each ranger card shows: name, check-in days count, incidents found, check-in rate % |
| 5.5 | Empty state | Login as leader with no ranger data | Shows appropriate empty/no-data message |

---

## 6. Check-in GPS Enhancement (P1.4)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 6.1 | GPS permission granted | Login as ranger → check-in with GPS permission enabled | Check-in succeeds with latitude/longitude attached |
| 6.2 | GPS permission denied | Deny GPS permission → attempt check-in | Check-in still succeeds (without GPS coords); no crash |
| 6.3 | GPS coordinates stored | Check-in with GPS → verify backend data | Backend stores latitude and longitude with the check-in record |
| 6.4 | Location accuracy | Check-in with GPS in known location | Recorded coordinates are reasonably accurate (within ~100m of actual position) |

---

## 7. Forest Compartment Management (P2.1)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 7.1 | Navigate to screen | Landing → tap "Forest Resources" card | Opens Forest Compartment screen |
| 7.2 | Load compartments | Screen loads | Shows 5 sample compartment cards with name, region chip, area (ha) |
| 7.3 | Region chips color-coded | Check region chips on cards | Different regions show different colored chips (Bắc, Nam, Tây, Đông) |
| 7.4 | Incident counts | Check incident data on cards | Each card shows total, resolved, unresolved incident counts |
| 7.5 | Resolution progress bar | Check progress bars | Progress bar shows % of resolved incidents; 0% if no incidents |
| 7.6 | Pull to refresh | Pull down on the list | Loading indicator appears → data refreshes |
| 7.7 | Empty state | (If backend returns no compartments) | Shows appropriate empty message |
| 7.8 | Error state | Stop backend → pull to refresh | Shows error message |
| 7.9 | Localization | Switch language → reopen screen | All labels/titles show in correct language |

---

## 8. Map Screen (P2.2)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 8.1 | Navigate to map | Bottom nav → Maps | Map screen opens with WebView loading |
| 8.2 | Loading indicator | While WebView loads | Loading overlay with spinner shown until page finishes loading |
| 8.3 | EarthRanger map loads | Wait for page to finish loading | EarthRanger web map displays correctly in the WebView |
| 8.4 | Map interaction | Pinch to zoom, drag to pan | WebView map responds to touch gestures |
| 8.5 | Bottom navigation bar | Check bottom of map screen | Bottom nav bar present with correct items |
| 8.6 | ER_WEB_URL from .env | Set custom `ER_WEB_URL` in `.env` → restart | WebView loads the custom URL |
| 8.7 | Default URL | Remove `ER_WEB_URL` from `.env` | Defaults to `https://epictech.pamdas.org` |
| 8.8 | Back navigation | Tap back button | Returns to previous screen |

---

## 9. Alerts Screen (P2.3)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 9.1 | Navigate to alerts | Bottom nav → Alerts | Alerts screen opens |
| 9.2 | Load alerts | Screen loads with incident data | Shows alert cards for incidents from the last 30 days |
| 9.3 | Urgent alerts (red) | Check high-severity alerts | Cards with `alert_level: urgent` show red color scheme |
| 9.4 | Warning alerts (orange) | Check medium-severity alerts | Cards with `alert_level: warning` show orange color scheme |
| 9.5 | Info alerts (gray) | Check low-severity alerts | Cards with `alert_level: info` show gray color scheme |
| 9.6 | Alert card content | Check a single alert card | Shows: title, status, severity, occurrence time |
| 9.7 | Sorting order | Check card ordering | Sorted by severity (urgent first) then by recency (newest first) |
| 9.8 | Pull to refresh | Pull down on alert list | Data refreshes from backend |
| 9.9 | Empty state | (With no recent incidents) | Shows "No alerts" message |
| 9.10 | Error state | Stop backend → pull to refresh | Shows error message |
| 9.11 | Bottom navigation bar | Check bottom nav | Present with Alerts tab highlighted |
| 9.12 | Localization | Switch language | All alert labels in correct language |

---

## 10. Reports Screen (P2.5)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 10.1 | Navigate to reports | Landing → tap "Reports" card | Reports screen opens with 3 tabs |
| 10.2 | Three tabs present | Check tab bar | Tabs: "Forest Protection", "Incidents", "Work Performance" |
| 10.3 | Date range - This Month | Tap "This Month" quick button | Data filtered to current month; date chips update |
| 10.4 | Date range - This Quarter | Tap "This Quarter" quick button | Data filtered to current quarter |
| 10.5 | Date range - This Year | Tap "This Year" quick button | Data filtered to current year |
| 10.6 | Date range - Custom | Tap "Custom" → select date range | Data filtered to custom range |
| 10.7 | Forest Protection tab | View Forest Protection tab | Shows: total/resolved/unresolved counts, severity breakdown, status breakdown |
| 10.8 | Incidents tab | Switch to Incidents tab | Shows: total incidents, per-ranger breakdown |
| 10.9 | Work Performance tab | Switch to Work Performance tab | Shows: check-in rates, per-ranger table with days/incidents |
| 10.10 | Data updates on tab switch | Switch between tabs | Each tab loads its respective data type |
| 10.11 | Empty data | Set date range with no data | Shows "No data" or zeros |
| 10.12 | Localization | Switch language | Tab labels and all metrics in correct language |

---

## 11. Incident Management

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 11.1 | Navigate to incidents | Landing → tap "Incident Management" card | Incident management screen opens |
| 11.2 | Incident list loads | Screen loads | Shows list of incidents with title, severity, status |
| 11.3 | Severity display | Check incident severity labels | Severity levels displayed correctly (color-coded) |
| 11.4 | Status display | Check incident status | Status shown for each incident |
| 11.5 | Empty state | (No incidents synced) | Shows appropriate empty message |

---

## 12. Schedule Management

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 12.1 | Navigate to schedules | Landing → tap "Schedule Management" card | Schedule management screen opens |
| 12.2 | Schedule list loads | Screen loads | Shows list of schedules |
| 12.3 | Schedule details | Tap on a schedule item | Shows schedule detail information |

---

## 13. NFC / Tree Search (Home Screen)

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 13.1 | Navigate to tree search | Landing → bottom nav → navigate to home/NFC screen | Home screen with NFC search card shown |
| 13.2 | Manual NFC ID entry | Type NFC ID in text field → tap Search | Searches for tree; shows tree detail if found, "Not Found" if not |
| 13.3 | NFC scan (Android) | Tap NFC icon → scan NFC tag | Tag UID auto-fills → search triggers → shows result |
| 13.4 | NFC unavailable | On device without NFC → tap scan | Shows "NFC not available" error message |
| 13.5 | Tree not found | Search for non-existent NFC ID | "Not Found" card appears with admin link-tree option (if admin) |
| 13.6 | Tree detail display | Search and find a tree | Navigates to tree detail screen with tree data |
| 13.7 | Link tree (admin) | As admin, search non-existent → tap "Link Tree" | Navigates to link tree screen |

---

## 14. Cross-cutting Concerns

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| 14.1 | Language switch (vi → en) | Settings → switch to English | All screens update to English text |
| 14.2 | Language switch (en → vi) | Settings → switch to Vietnamese | All screens update to Vietnamese text |
| 14.3 | Role-based UI (leader) | Login as leader → check all screens | Leader-specific features visible (stats panel, management tools) |
| 14.4 | Role-based UI (ranger) | Login as ranger → check all screens | Ranger-specific features visible (check-in, own calendar) |
| 14.5 | Network offline handling | Disconnect network → use various screens | Graceful error messages; no crashes |
| 14.6 | Back navigation | Navigate deep (3+ screens) → tap back repeatedly | Navigates back through stack correctly without errors |
| 14.7 | Keyboard dismiss | Tap outside text field on any form screen | Keyboard dismisses correctly |
| 14.8 | App orientation | Rotate device | App handles rotation gracefully (or locks to portrait) |
| 14.9 | Session expiry | Wait for token to expire → perform API action | App handles 401 gracefully (ideally refreshes or prompts re-login) |

---

## Test Account Quick Reference

| Account | Username | Password | Mobile Role | Notes |
|---------|----------|----------|-------------|-------|
| Admin | `admin` | `admin123` | leader | Has admin dashboard access + leader mobile features |
| Leader | `leader1` | `admin123` | leader | Standard leader features |
| Ranger | `ranger1` | `admin123` | ranger | Ranger features, check-in triggers on login |

> **Tip:** Use Developer Mode (tap version text 5 times on login screen) for quick account switching during testing.
