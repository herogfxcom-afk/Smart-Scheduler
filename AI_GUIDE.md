# Smart Scheduler - AI Developer Guide

*Current version: v8.1.5-stable (Final Ground Truth)*

## 🌟 Project Overview
Smart Scheduler is a group availability tracking application integrated deeply with Telegram Mini Apps and Google Calendar. It allows users to sync their personal calendars, share their working hours, and find common free slots among selected participants in a group chat to schedule meetings.

## 🏗️ Architecture & Tech Stack
**Frontend:**
- **Framework:** Flutter (Web).
- **Hosting:** Vercel.
- **Calendar:** Syncfusion `SfCalendar`.
- **Timezone Management:** Sources truth from `window.userTimezone` and `window.userTzOffset` injected via `index.html`. Uses `timezone` package for conversions.
- **WASM/CanvasKit:** Build uses `--no-tree-shake-icons --verbose` to ensure compatibility and debugging depth.

**Backend:**
- **Framework:** Python / FastAPI.
- **Hosting:** Railway.
- **Database:** PostgreSQL (Neon) or SQLite (dev).
- **Timezone Management:** **`zoneinfo` (Python 3.9+)** for all logic. Notifications are personalized—the bot sends messages formatted in the recipient's local TZ.

## 🚀 Key Architectural Truths (READ THIS)

### 1. The Timezone Manifesto (Updated)
- **Detection (Web):** `index.html` captures `Intl.DateTimeFormat().resolvedOptions().timeZone` at runtime. Dart accesses this via `JS Interop` in `timezone_utils.dart`.
- **Storage:** All meetings and busy slots are stored in **UTC**.
- **Backend Notifications:** When sending Telegram messages, `main.py` fetches the user's `timezone` from the DB and uses `ZoneInfo` to format the display time.
- **Frontend Display:** `toUserLocal()` in Dart uses the native browser environment to handle shifts. `SfCalendar` remains in `UTC` to avoid double-shaping issues.

### 2. UI Stability (Golden Tests)
- **Package:** `golden_toolkit`.
- **Location:** `test/golden/`.
- **Command:** `flutter test --update-goldens` to refresh snapshots.
- **Purpose:** Prevents layout shifts and timezone-related rendering bugs (e.g., blocks shifting by 2 hours).

### 3. Build & Deployment
- **Critical File:** `build.sh` handles Flutter SDK installation and build on Vercel.
- **Avoid:** Never commit the `frontend/build/` directory; it is ignored via `.gitignore` to keep the repo clean.
- **Compilation:** Always ensure `AvailabilityProvider` and `AuthProvider` are imported in screen widgets to prevent "Type not found" errors in release mode.

## ⚠️ Critical Implementation Rules
1. **Timezone Utility**: Always use `toUserLocal(dateTime)` for display and `userNow()` instead of `DateTime.now()`.
2. **Safe Imports**: When adding screens, check for `provider` and `auth_provider` imports. Vercel's build is stricter than local debug.
3. **Git Hygiene**: Keep large binary blobs (like builds) out of the repo.
4. **Golden Tests**: Run them before any major UI refactor.

## 🛠️ Commands
- **Backend Run:** `uvicorn main:app --reload`
- **Frontend Build:** `cd frontend && bash build.sh`
- **Update Vercel Environment:** Set `API_URL` to point to the Railway backend.
- **Git Freeze:** `git tag -a v8.1-stable -m "Final stable version with perfect TZ and build fixes"; git push origin v8.1-stable`
