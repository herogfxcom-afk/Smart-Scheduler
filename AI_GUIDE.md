# Smart Scheduler - AI Developer Guide

*Current version: v6.2.0-stable*

## 🌟 Project Overview
Smart Scheduler is a group availability tracking application integrated deeply with Telegram Mini Apps and Google Calendar. It allows users to sync their personal calendars, share their working hours, and find common free slots among selected participants in a group chat to schedule meetings.

## 🏗️ Architecture & Tech Stack
**Frontend:**
- **Framework:** Flutter (built for Web `flutter build web --release`).
- **Hosting:** Vercel.
- **Key packages:** `provider` (state management), `dio` (API calls), `go_router` (navigation), `intl` (date formatting).
- **Core Concept:** Must be run inside a Telegram WebApp (Mini App context). It uses `window.Telegram.WebApp` to fetch the initialization data and user ID.

**Backend:**
- **Framework:** Python / FastAPI.
- **Hosting:** Railway (cloud platform).
- **Database:** SQLite (`scheduler.db` stored in the root directory). Note: Railway ephemeral disks mean SQLite data can reset on redeploy unless a volume is attached.
- **Key packages:** `sqlalchemy`, `google-auth-oauthlib`, `google-api-python-client`, `pycryptodome` (for token encryption), `pytz`.

## 🚀 Deployment Instructions

### Backend (Railway)
1. Ensure you are in the root directory of the project.
2. The `Procfile` and `requirements.txt` are already configured.
3. Deploy command:
   ```bash
   cmd /c railway up -d
   ```
4. **Important Env Vars (already set on Railway):** `BOT_TOKEN`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `API_URL` (Frontend URL), `ENCRYPTION_KEY`.

### Frontend (Vercel)
1. Ensure the backend URL is correctly injected during the Flutter build.
2. Navigate to the `frontend/` directory.
3. Build the web app:
   ```bash
   cmd /c flutter build web --release --dart-define=API_URL=https://smart-scheduler-production-2006.up.railway.app
   ```
4. Deploy to Vercel using the user's specific token to bypass interactive prompts:
   ```bash
   cmd /c npx vercel deploy --prod --token=YOUR_VERCEL_TOKEN --yes
   ```
5. *Note:* If the Vercel URL changes, the user MUST update the URL in BotFather (`@BotFather -> /mybots -> Bot Settings -> Menu Button -> Configure menu button`) AND clear their Telegram cache.

## 🔑 Key Features Implemented (Up to v6.2.0)
1. **Google & Apple Calendar Sync:** Fetches busy slots securely.
2. **Online/Offline Meetings:** Users can choose meeting type. Online meetings generate Google Meet links; offline meetings include a location address.
3. **4-Color Heatmap Grid:**
   - **Green (`match`):** Everyone selected is free.
   - **Purple:** App-created meeting (creator can delete).
   - **Blue (`my_busy`):** The requesting user is busy (personal external event).
   - **Orange (`others_busy`):** The requesting user is free, but one or more other participants are busy.
4. **Double-Booking Protection:** Backend validation prevents booking meetings that overlap with existing app meetings OR external Google/Apple calendar events.
5. **Meeting Deletion:** Tapping a Purple slot opens details with a "Cancel Meeting" button. Deletes locally and from external calendars.
4. **Out-of-Hours rendering:** Working hours are enforced, but if a user has a meeting outside their working hours, the grid will force-render those slots as Blue (`my_busy`) so they are visible and editable.
5. **Telegram Invites:** Finalizing a meeting edits the existing bot message in the chat or sends a new one with a deep link back to the mini-app with cache-busting `v=` parameters.

## ⚠️ Important Pitfalls to Avoid
1. **Timezones:** The backend stores and expects all meeting times in **UTC** (`Z` suffix). The Flutter frontend parses this UTC string and converts it to `.toLocal()` for display. When modifying slots, always ensure you use `.toUtc().toIso8601String()`.
2. **Encryption:** OAuth refresh tokens are encrypted in the database. When debugging `calendar_service.py`, remember that tokens must be decrypted using `encryption.py` before being sent to the Google API.
3. **Telegram Caching:** Telegram UI caches Mini Apps aggressively. Whenever you change the frontend and deploy, you must add `?v=timestamp` to the URL or instruct the user to physically clear their Telegram Local Database Cache.....
