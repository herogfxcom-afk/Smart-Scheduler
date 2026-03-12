# Smart Scheduler - AI Developer Guide

*Current version: v7.0.0-stable (Ground Truth Edition)*

## 🌟 Project Overview
Smart Scheduler is a group availability tracking application integrated deeply with Telegram Mini Apps and Google Calendar. It allows users to sync their personal calendars, share their working hours, and find common free slots among selected participants in a group chat to schedule meetings.

## 🏗️ Architecture & Tech Stack
**Frontend:**
- **Framework:** Flutter (Web).
- **Hosting:** Vercel.
- **Calendar:** Syncfusion `SfCalendar`.
- **Timezone Management:** Uses the `timezone` package and `flutter_timezone`. `SfCalendar` is configured with `timeZone: 'UTC'` to ensure alignment with manual local conversions.

**Backend:**
- **Framework:** Python / FastAPI.
- **Hosting:** Railway (cloud platform).
- **Database:** PostgreSQL (Neon) or SQLite (local development).
- **Timezone Management:** **`zoneinfo` (Python 3.9+)** for DST-aware calculations. NO longer uses `pytz` or naive datetimes for logic.

## 🚀 Key Architectural Truths (READ THIS)

### 1. The Timezone Manifesto
- **Storage:** All meetings and busy slots are stored in **UTC** without timezone offsets in the database.
- **Backend Logic:** `calendar_service.py` uses `ZoneInfo(user.timezone)` to convert UTC intervals into the user's local time ONLY for checking working hours. All intersections and group results are returned in **UTC**.
- **Frontend Logic:** The app receives UTC from the API. It converts it to the viewer's local time using `toUserLocal()` (which uses `tz.local`). 
- **SfCalendar Alignment:** `SfCalendar` MUST have `timeZone: 'UTC'` so that it doesn't apply internal shifts to the already-converted `toUserLocal` times.

### 2. Group Multi-TZ Intersection
- When calculating group availability (`snap_to_local=False`), the backend does not snap to any midnight. It calculates a continuous UTC timeline.
- A slot is a `match` only if **ALL** participants are free AND within their local working hours simultaneously.
- **Fractional Availability:** Slots where only some people are free are marked as `others_busy` with an `availability` percentage (e.g., "1/2 free").

### 3. Google OAuth & Production Proxies
- The `google_oauth.py` dynamically builds the `redirect_uri` by checking `X-Forwarded-Proto` and `X-Forwarded-Host` headers to handle Railway/Vercel proxies correctly.

## ⚠️ Critical Implementation Rules
1. **Never use naive `utcnow()`**: Use `datetime.now(timezone.utc)`.
2. **Never use `replace(tzinfo=None)`** for logic: Keep timezones attached until the final DB write.
3. **Flutter SfCalendar**: If the purple meeting bar is shifted by 2-3 hours, check if `timeZone: 'UTC'` is still set in `heatmap_grid.dart`.
4. **Idempotency**: Meetings use an `idempotency_key` (usually `group_CHATID_TIMESTAMP`) to prevent double-posts from Telegram.

## 🛠️ Commands
- **Backend Run:** `cmd /c uvicorn main:app --reload`
- **Frontend Build:** `cmd /c flutter build web --release --dart-define=API_URL=https://your-backend.url`
- **Git Release:** `git tag -a v7.0-stable -m "Stable multi-TZ version"; git push origin v7.0-stable`
