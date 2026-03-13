# Smart Scheduler - AI Developer Guide

*Current version: v10.0.0-stable (Final Ground Truth)*

## 🌟 Project Overview
Smart Scheduler is a group availability tracking application integrated deeply with Telegram Mini Apps and Google Calendar. It allows users to sync their personal calendars, share their working hours, and find common free slots among selected participants in a group chat to schedule meetings.

## 🏗️ Architecture & Tech Stack
**Frontend:**
- **Framework:** Flutter (Web).
- **Hosting:** Vercel.
- **Calendar:** Syncfusion `SfCalendar`.
- **Timezone Management:** Sources truth from `window.userTimezone` and `window.userTzOffset` injected via `index.html`. 
- **SfCalendar Sync:** `SfCalendar.timeZone` MUST be set to `getUserTimezone()` (IANA). Appointments MUST be passed as UTC. This prevents double-shifting.
- **WASM/CanvasKit:** Build uses `--no-tree-shake-icons --verbose` to ensure compatibility.

**Backend:**
- **Framework:** Python / FastAPI.
- **Hosting:** Railway.
- **Timezone Management:** **`zoneinfo` (Python 3.9+)** for all logic. Uses `ZoneInfo(iana_str)` from the frontend `timezone` query param.
- **Data Consistency:** Immediate `BusySlot` purge during `delete_meeting` to eliminate "black gaps" on the heatmap instantly.

## 🚀 Key Architectural Truths (READ THIS)

### 1. The Timezone Manifesto (v10.0)
- **Detection (Web):** `index.html` captures IANA TZ. Dart accesses this via `getUserTimezone()` in `timezone_utils.dart`.
- **SfCalendar Rule:** NEVER set `SfCalendar.timeZone` to 'UTC' if providing local times. The golden pattern is: `SfCalendar.timeZone = getUserTimezone()` + `Appointment(startTime: utcTime, ...)`. 
- **Backend Rule:** Always use `ZoneInfo(user_tz_name)` for free slot calculations. Fallback to `"UTC"`.
- **Working Hours:** Stored as "HH:mm" strings. Backend parses to fractional hours. Frontend uses `toUserLocal()` for boundary checks.

### 2. Meeting Lifecycle
- **Creation:** `SchedulerScreen` collects participant IDs (`invited_telegram_ids`) and sends a `POST` to `/meeting/create`.
- **Deletion:** In addition to deleting from Google/Outlook, the backend MUST manually delete `BusySlot` records matching the meeting window for all participants. This avoids waiting for a slow re-sync.

### 3. UI Stability (Golden Tests)
- **Command:** `flutter test test/golden/heatmap_test.dart --update-goldens`.
- **Baseline:** Moscow (+3), NY (DST aware), and Tokyo (+9) shifts are verified.

## ⚠️ Critical Implementation Rules
1. **Timezone Utility**: Always use `toUserLocal(dateTime)` for display check.
2. **Scheduling**: Ensure `invited_telegram_ids` is populated in the frontend `POST`.
3. **Data Integrity**: If deleting a meeting, purge matching `BusySlot` entries in the same transaction.
4. **Imports**: `find_common_free_slots` in Python must be a global import in `main.py` to avoid `NameError` in `get_solo_scheduler`.

## 🛠️ Commands
- **Git Freeze (Current Stable):** `git tag -a v10.0-stable -m "Timezone fixed, invitations fixed, deletion purge implemented"; git push origin v10.0-stable`
