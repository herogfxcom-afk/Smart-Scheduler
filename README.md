# Smart Scheduler

A production-ready Telegram Mini App for group scheduling across multiple timezones.

## 🚀 Quick Start
- **Telegram Bot:** [Smart Scheduler Bot](https://t.me/your_bot_user)
- **Status:** Stable v8.1.0

## 📂 Project Structure
- `/` - FastAPI Backend (Railway)
  - `main.py` - API endpoints & Telegram Bot logic
  - `calendar_service.py` - Core scheduling algorithm (UTC intersection)
  - `models.py` - DB Schema (SQLAlchemy)
- `frontend/` - Flutter Web Frontend (Vercel)
  - `lib/screens/scheduler/` - Main scheduler logic & Heatmap
  - `lib/utils/timezone_utils.dart` - Local time conversion

## ⚙️ Core Features
- **DST-Aware Scheduling:** Uses `ZoneInfo` to handle global timezones correctly.
- **Group Availability:** Visualizes common free slots for teams in different regions.
- **Fractional "X/Y Free" Display:** Shows when some members are available even if it's not a full match.
- **Google Calendar Sync:** Full bi-directional sync with conflict protection.

## 🤖 AI & Developer Continuity
For developers and AI agents joining this project, please refer to the [AI_GUIDE.md](./AI_GUIDE.md) for the "Ground Truth" documentation on timezone handling and architecture.

---
*Created by Antigravity (Google DeepMind)*
