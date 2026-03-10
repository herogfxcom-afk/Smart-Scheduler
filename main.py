from fastapi import FastAPI, Depends, HTTPException, Header, Request as FastAPIRequest, Request, Query
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
from sqlalchemy import text
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
import pytz
from auth import get_current_user
from google_oauth import router as google_auth_router
from outlook_oauth import router as outlook_auth_router
from models import User, BusySlot, Meeting
from database import get_db
from encryption import decrypt_token, encrypt_token
from calendar_service import GoogleCalendarService
from caldav_service import AppleCalendarService
import json
import os
import requests
import asyncio

app = FastAPI(title="Smart Scheduler API")

# Create database tables
from database import engine
import models
models.Base.metadata.create_all(bind=engine)

# Production Migration: Ensure 'email' column exists
@app.on_event("startup")
def migrate_db():
    from sqlalchemy import text, inspect
    inspector = inspect(engine)
    
    # Check users table
    users_cols = [col['name'] for col in inspector.get_columns('users')]
    if 'email' not in users_cols:
        with engine.connect() as conn:
            try:
                conn.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR(255)"))
                conn.commit()
                print("Migration: Added email column to users table.")
            except Exception as e:
                print(f"Migration Error (email): {e}")

    # Check groups table for telegram_chat_id type change
    try:
        with engine.connect() as conn:
            # We use USING clause for PostgreSQL to handle BigInteger to VARCHAR conversion
            if engine.url.drivername == 'postgresql':
                conn.execute(text("ALTER TABLE groups ALTER COLUMN telegram_chat_id TYPE VARCHAR(255) USING telegram_chat_id::text"))
            else:
                # SQLite or others - note SQLite can't actually do this via ALTER, 
                # but we'll try standard SQL for MySQL/etc.
                conn.execute(text("ALTER TABLE groups ALTER COLUMN telegram_chat_id VARCHAR(255)"))
                
            conn.commit()
            print("Migration: Updated telegram_chat_id to VARCHAR for invite tokens.")
    except Exception as e:
        print(f"Migration Note (telegram_chat_id): {e}. This might be expected on SQLite or if already migrated.")

    # Check user_availability table
    if not inspector.has_table('user_availability'):
        try:
            models.Base.metadata.tables['user_availability'].create(engine)
            print("Migration: Created user_availability table.")
        except Exception as e:
            print(f"Migration Error (user_availability): {e}")

    # Check group_meetings table for user_id column
    meeting_cols = [col['name'] for col in inspector.get_columns('group_meetings')]
    if 'user_id' not in meeting_cols:
        try:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE group_meetings ADD COLUMN user_id INTEGER REFERENCES users(id)"))
                conn.commit()
                print("Migration: Added user_id column to group_meetings table.")
        except Exception as e:
            print(f"Migration Error (user_id): {e}")

    # --- PHASE 0: MULTI-CALENDAR MIGRATION ---
    
    # 1. Create calendar_connections table if it doesn't exist
    if not inspector.has_table('calendar_connections'):
        try:
            models.CalendarConnection.__table__.create(engine)
            print("Migration: Created calendar_connections table.")
        except Exception as e:
            print(f"Migration Error (calendar_connections): {e}")

    # 2. Add connection_id to busy_slots if it doesn't exist
    busy_cols = [col['name'] for col in inspector.get_columns('busy_slots')]
    if 'connection_id' not in busy_cols:
        try:
            with engine.connect() as conn:
                conn.execute(text("ALTER TABLE busy_slots ADD COLUMN connection_id INTEGER REFERENCES calendar_connections(id)"))
                conn.commit()
                print("Migration: Added connection_id to busy_slots table.")
        except Exception as e:
            print(f"Migration Error (connection_id): {e}")

    # 4. Check meeting_invites table
    if not inspector.has_table('meeting_invites'):
        try:
            models.MeetingInvite.__table__.create(engine)
            print("Migration: Created meeting_invites table.")
        except Exception as e:
            print(f"Migration Error (meeting_invites): {e}")

    # 3. Data Migration: Move tokens from User to CalendarConnection
    from sqlalchemy.orm import Session
    from database import SessionLocal
    db = SessionLocal()
    
    # Check if legacy columns exist before trying to query them
    user_cols = [col['name'] for col in inspector.get_columns('users')]
    if 'google_refresh_token' not in user_cols and 'apple_auth_data' not in user_cols:
        print("Migration: Legacy token columns already removed. Skipping data migration.")
        db.close()
        return

    try:
        # Use text() to safely query columns that might be deleted in the code but still exist in DB
        users_with_tokens = db.execute(text("SELECT id, email, google_refresh_token, apple_auth_data FROM users WHERE google_refresh_token IS NOT NULL OR apple_auth_data IS NOT NULL")).all()
        
        for u_id, u_email, g_token, a_token in users_with_tokens:
            # Migrate Google
            if g_token:
                # Check if already migrated
                exists = db.query(models.CalendarConnection).filter_by(user_id=u_id, provider='google').first()
                if not exists:
                    new_conn = models.CalendarConnection(
                        user_id=u_id,
                        provider='google',
                        email=u_email,
                        auth_data=g_token,
                        is_active=1
                    )
                    db.add(new_conn)
                    print(f"Migration: Moved Google token for user {u_id}")
            
            # Migrate Apple
            if a_token:
                exists = db.query(models.CalendarConnection).filter_by(user_id=u_id, provider='apple').first()
                if not exists:
                    new_conn = models.CalendarConnection(
                        user_id=u_id,
                        provider='apple',
                        auth_data=a_token,
                        is_active=1
                    )
                    db.add(new_conn)
                    print(f"Migration: Moved Apple token for user {u_id}")
        
        db.commit()
    except Exception as e:
        print(f"Migration Error (Data Migration): {e}")
        db.rollback()
    finally:
        db.close()

# CORS - raw middleware that always injects correct headers regardless of origin
class CORSEverywhere(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS":
            response = Response(status_code=200)
        else:
            try:
                response = await call_next(request)
            except Exception as e:
                # Ensure even error responses have CORS headers
                print(f"Middleware Error: {str(e)}")
                response = Response(content=json.dumps({"detail": str(e)}), status_code=500)
        
        origin = request.headers.get("origin", "*")
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS, PATCH"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Requested-With, init-data, accept, origin"
        response.headers["Access-Control-Max-Age"] = "600"
        return response

app.add_middleware(CORSEverywhere)

# ─────────────────── TELEGRAM HELPERS ───────────────────
from functools import lru_cache

@lru_cache(maxsize=128)
def is_user_in_chat(chat_id: str, user_telegram_id: int) -> bool:
    """Checks if a user is still a member of a Telegram chat."""
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return True # Fallback if bot not configured
    
    try:
        # Safe int conversion for numeric chat_ids
        try:
            target_chat = int(chat_id)
        except:
            target_chat = str(chat_id)

        resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getChatMember", params={
            "chat_id": target_chat,
            "user_id": int(user_telegram_id)
        }, timeout=5).json()
        
        if not resp.get("ok"):
            desc = resp.get('description', '')
            if 'chat not found' in desc.lower():
                return "bot_not_in_chat"
            print(f"DEBUG: is_user_in_chat API Error: {desc}")
            return "error"
            
        status = resp.get("result", {}).get("status")
        # Allowed statuses
        if status in ["member", "administrator", "creator", "restricted"]:
            return "ok"
        return "not_member"
    except Exception as e:
        print(f"TRACE: is_user_in_chat system error: {e}")
        return True # Soft fail on network error

# ─────────────────── ROUTERS ───────────────────
app.include_router(google_auth_router)
app.include_router(outlook_auth_router)

# ─────────────────── TELEGRAM BOT WEBHOOK ───────────────────
# Bot runs as a webhook inside FastAPI - no separate process needed!

async def _setup_bot_ui():
    """Registers the webhook and sets up the bot menu button."""
    bot_token = os.getenv("BOT_TOKEN")
    api_url = os.getenv("API_URL", "")
    if not bot_token or not api_url:
        print("BOT UI SETUP: Skipping - BOT_TOKEN or API_URL not set")
        return
        
    # 1. Webhook
    webhook_url = f"{api_url.rstrip('/')}/webhook/bot"
    resp = requests.post(f"https://api.telegram.org/bot{bot_token}/setWebhook", json={"url": webhook_url, "drop_pending_updates": True}).json()
    print(f"BOT WEBHOOK: setWebhook → {resp}")
    
    # 2. Menu Button (Global)
    # This button appears next to the bot's input field in all chats.
    # Note: In groups, it might just open the command list, but in private it opens the app.
    menu_resp = requests.post(f"https://api.telegram.org/bot{bot_token}/setChatMenuButton", json={
        "menu_button": {
            "type": "web_app",
            "text": "📊 Magic Sync",
            "web_app": {"url": api_url}
        }
    }).json()
    print(f"BOT MENU: setChatMenuButton → {menu_resp}")

@app.on_event("startup")
async def on_startup_webhook():
    asyncio.create_task(_setup_bot_ui())

@app.post("/webhook/bot")
async def telegram_webhook(req: FastAPIRequest, db: Session = Depends(get_db)):
    """Receives Telegram updates and handles /sync command."""
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return {"ok": False}
    
    try:
        update = await req.json()
    except Exception:
        return {"ok": False}
    
    # 1. Handle regular messages (/sync, /start etc)
    message = update.get("message") or update.get("edited_message")
    
    # 2. Handle bot added to group (my_chat_member)
    my_chat_member = update.get("my_chat_member")
    if my_chat_member and my_chat_member.get("new_chat_member", {}).get("status") == "member":
        # Bot just added to group! Send invitation automatically.
        chat = my_chat_member.get("chat", {})
        chat_id = chat.get("id")
        chat_title = chat.get("title", "Группа")
        await _send_sync_invite(bot_token, chat_id, chat_title, db)
        return {"ok": True}

    # 3. Handle Inline Query (@botname)
    inline_query = update.get("inline_query")
    if inline_query:
        query_id = inline_query.get("id")
        # Get bot's username  
        bot_info_resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getMe").json()
        bot_username = bot_info_resp.get("result", {}).get("username", "smartschedulertime_bot")
        
        # We offer a button to launch the app (generic since we don't know the chat_id here)
        # But we can say "Share Magic Sync in this chat"
        results = [{
            "type": "article",
            "id": "magic_sync",
            "title": "📊 Поделиться Magic Sync",
            "description": "Позволяет всем участникам синхронизировать календари.",
            "input_message_content": {
                "message_text": "📊 *Magic Sync: Синхронизация календарей*\n\nНажмите кнопку ниже, чтобы начать!",
                "parse_mode": "Markdown"
            },
            "reply_markup": {
                "inline_keyboard": [[{
                    "text": "📊 Magic Sync",
                    "url": f"https://t.me/{bot_username}/app" # Generic launch
                }]]
            }
        }]
        requests.post(f"https://api.telegram.org/bot{bot_token}/answerInlineQuery", json={
            "inline_query_id": query_id,
            "results": results,
            "cache_time": 300
        })
        return {"ok": True}

    if not message:
        return {"ok": True}
    
    text = message.get("text", "")
    chat = message.get("chat", {})
    chat_id = chat.get("id")
    chat_type = chat.get("type", "")
    chat_title = chat.get("title", "Группа")
    
    # Only respond to /sync or /start in groups
    if (text.startswith("/sync") or text.startswith("/start")) and chat_type in ["group", "supergroup"]:
        await _send_sync_invite(bot_token, chat_id, chat_title, db)
    
    return {"ok": True}

async def _send_sync_invite(bot_token: str, chat_id: int, chat_title: str, db: Session):
    """Internal helper to send the Magic Sync button to a chat."""
    bot_info_resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getMe").json()
    bot_username = bot_info_resp.get("result", {}).get("username", "smartschedulertime_bot")
    
    # IMPORTANT: StartApp parameter CANNOT contain the minus (-) sign.
    # Replace negative ID prefix with 'n'
    clean_chat_id = str(chat_id).replace("-", "n")
    deep_link = f"https://t.me/{bot_username}/app?startapp=group_{clean_chat_id}"
    
    # Build the web_app URL — pass group chat_id as query param
    # The frontend reads window.location.search or Telegram's startParam for group context
    frontend_url = os.getenv("API_URL", "https://smart-scheduler-production-2006.up.railway.app")
    # Use the Vercel frontend URL (separate from Railway backend)
    web_app_url = f"https://frontend-five-gules-5u3aqd6fzp.vercel.app/?startapp=group_{clean_chat_id}"

    payload = {
        "chat_id": chat_id,
        "text": f"📊 *Синхронизация календарей для: {chat_title}*\n\n"
                "Нажмите кнопку ниже, чтобы синхронизировать свой календарь и найти общее время!",
        "parse_mode": "Markdown",
        "reply_markup": json.dumps({
            "inline_keyboard": [[{
                "text": "📊 Magic Sync",
                "web_app": {"url": web_app_url}
            }]]
        })
    }
    
    result = requests.post(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        json=payload
    ).json()
    
    # Save group to DB
    import models as _models
    group = db.query(_models.Group).filter(_models.Group.telegram_chat_id == str(chat_id)).first()
    if not group:
        group = _models.Group(telegram_chat_id=str(chat_id), title=chat_title)
        db.add(group)
    if result.get("ok"):
        group.last_invite_message_id = result["result"]["message_id"]
    db.commit()
    print(f"BOT: Sent Magic Sync to {chat_title} (chat_id={chat_id}), link={deep_link}")
    
    return {"ok": True}
# ─────────────────────────────────────────────────────────────

@app.get("/api/status")
async def api_status():
    return {
        "status": "online",
        "version": "5.0-dev",
        "database": "connected",
        "message": "Dashboard, Meeting Management, and Custom Availability ready.",
        "bot_webhook": bool(os.getenv("BOT_TOKEN") and os.getenv("API_URL"))
    }

@app.get("/cors-debug")
async def cors_debug():
    return {"cors": "enabled", "middleware": "CORSEverywhere"}

@app.get("/auth/me")
async def get_me(current_user: User = Depends(get_current_user)):
    """Returns the current user profile including all connected calendars."""
    return {
        "id": current_user.id,
        "telegram_id": current_user.telegram_id,
        "username": current_user.username,
        "first_name": current_user.firstName if hasattr(current_user, 'firstName') else current_user.first_name,
        "email": current_user.email,
        "is_connected": any(c.provider == 'google' and c.is_active for c in current_user.connections),
        "is_apple_connected": any(c.provider == 'apple' and c.is_active for c in current_user.connections),
        "connections": [
            {
                "id": c.id,
                "provider": c.provider,
                "email": c.email,
                "status": c.status,
                "is_active": bool(c.is_active),
                "last_sync": c.last_sync.isoformat() + "Z" if c.last_sync else None
            } for c in current_user.connections
        ]
    }

@app.post("/groups/sync")
async def sync_group(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Links user to a group via telegram_chat_id."""
    raw_chat_id = data.get("chat_id")
    if not raw_chat_id:
        raise HTTPException(status_code=400, detail="chat_id is required")
    
    # Use the ID as-is (string) for database consistency with invite tokens
    chat_id = str(raw_chat_id)
    
    # Check if group exists
    print(f"DEBUG: sync_group called for chat_id={chat_id} by user={current_user.id}")
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == chat_id).first()
    if not group:
        print(f"DEBUG: Creating new group for chat_id={chat_id}")
        group = models.Group(telegram_chat_id=chat_id, title=data.get("title"))
        db.add(group)
        db.commit()
        db.refresh(group)
    else:
        print(f"DEBUG: Found existing group_id={group.id} for chat_id={chat_id}")
    
    # 2. Link user to group if not already linked
    participant = db.query(models.GroupParticipant).filter(
        models.GroupParticipant.group_id == group.id,
        models.GroupParticipant.user_id == current_user.id
    ).first()

    # 1.5 Verify Telegram Membership (Security Fix)
    membership_status = is_user_in_chat(chat_id, current_user.telegram_id)
    if membership_status == "bot_not_in_chat":
        raise HTTPException(status_code=400, detail="Bot is not a member of this group. Please add @smartschedulertime_bot to the chat.")
    elif membership_status != "ok":
        print(f"DEBUG: Denying group sync - user {current_user.telegram_id} status {membership_status} in chat {chat_id}")
        # If user was a participant, remove them
        if participant:
            db.delete(participant)
            db.commit()
        raise HTTPException(status_code=403, detail="You are not a member of this Telegram group")

    if not participant:
        participant = models.GroupParticipant(
            group_id=group.id, 
            user_id=current_user.id,
            is_synced=1 if any(c.is_active for c in current_user.connections) else 0
        )
        db.add(participant)
    else:
        # Update sync status
        participant.is_synced = 1 if any(c.is_active for c in current_user.connections) else 0
        
    db.commit()
    
    # 3. Update Telegram Message (Dynamic Update)
    if group.last_invite_message_id:
        try:
            print(f"DEBUG: Attempting to update TG message for chat {chat_id}, msg {group.last_invite_message_id}")
            participants_count = db.query(models.GroupParticipant).filter(
                models.GroupParticipant.group_id == group.id,
                models.GroupParticipant.is_synced == 1
            ).count()
            
            # Safe int for TG API
            try:
                target_chat = int(chat_id)
            except:
                target_chat = chat_id

            bot_token = os.getenv("BOT_TOKEN")
            # Fetch bot username for deep linking
            bot_resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getMe").json()
            bot_username = bot_resp.get("result", {}).get("username", "smartschedulertime_bot")

            new_text = (
                f"📊 **Ищу общее время для встречи: {group.title or 'Group'}**\n\n"
                f"✅ Присоединилось: {participants_count} чел.\n\n"
                f"Нажмите кнопку ниже, чтобы синхронизировать календари."
            )
            
            # Build inline keyboard manually for reliability across different bot versions
            # Ensure startapp parameter uses 'n' prefix for negative IDs
            clean_param = chat_id.replace("-", "n")
            reply_markup = {
                "inline_keyboard": [[{
                    "text": "📊 Magic Sync",
                    "url": f"https://t.me/{bot_username}/app?startapp=group_{clean_param}"
                }]]
            }
            
            resp = requests.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
                "chat_id": target_chat,
                "message_id": int(group.last_invite_message_id),
                "text": new_text,
                "parse_mode": "Markdown",
                "reply_markup": json.dumps(reply_markup)
            }, timeout=3).json()
            print(f"DEBUG: Message update result: {resp}")
        except Exception as e:
            print(f"TRACE: Failed to update TG message for chat {chat_id}: {e}")

    return {"status": "success", "group_id": group.id}

@app.get("/groups/{chat_id}/participants")
async def get_group_participants(chat_id: str, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns all participants in a group."""
    print(f"DEBUG: Fetching participants for chat_id: {chat_id}")
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == str(chat_id)).first()
    if not group:
        print(f"DEBUG: Group not found in DB for chat_id: {chat_id}")
        return []
    
    # Security Check: Verify requesting user is in the group
    membership_status = is_user_in_chat(chat_id, current_user.telegram_id)
    if membership_status == "bot_not_in_chat":
        print(f"DEBUG: Bot missing from chat {chat_id}")
        return [] # Return empty for now, but frontend can infer from sync_group failures
    elif membership_status != "ok":
        print(f"DEBUG: Denying /participants fetch - user {current_user.telegram_id} NOT in chat {chat_id}")
        return []

    participants = db.query(models.GroupParticipant).filter(models.GroupParticipant.group_id == group.id).all()
    print(f"DEBUG: Found {len(participants)} potential participants in DB")
    
    bot_token = os.getenv("BOT_TOKEN")
    active_participants = []
    
    for p in participants:
        u = p.user
        print(f"DEBUG: Checking membership for user {u.telegram_id} ({u.username}) in chat {chat_id}")
        try:
            # Safe int conversion for numeric chat_ids
            try:
                target_chat = int(chat_id)
            except:
                target_chat = str(chat_id)

            # Check if user is still in chat
            status = is_user_in_chat(chat_id, u.telegram_id)
            
            if status == "ok":
                active_participants.append({
                    "id": u.id,
                    "telegram_id": u.telegram_id,
                    "username": u.username,
                    "first_name": u.first_name,
                    "photo_url": u.photo_url,
                    "email": u.email,
                    "is_synced": bool(p.is_synced)
                })
            elif status in ["not_member", "left", "kicked"]:
                print(f"DEBUG: HARD DELETE ghost participant {u.telegram_id} (status: {status})")
                db.delete(p)
                db.commit()
            else:
                print(f"DEBUG: Status {status} for {u.telegram_id}, excluding but NOT deleting yet.")
        except Exception as e:
            print(f"TRACE: Error checking member {u.telegram_id}: {e}")
            active_participants.append({
                "id": u.id,
                "telegram_id": u.telegram_id,
                "username": u.username,
                "first_name": u.first_name,
                "photo_url": u.photo_url,
                "email": u.email,
                "is_synced": bool(p.is_synced)
            })
            
    # Final Deduplication check (server-side) based on telegram_id
    seen_ids = set()
    final_output = []
    for ap in active_participants:
        if ap["telegram_id"] not in seen_ids:
            final_output.append(ap)
            seen_ids.add(ap["telegram_id"])
        else:
            print(f"DEBUG: Filtering duplicate local participant {ap['telegram_id']}")

    print(f"DEBUG: Returning {len(final_output)} active participants")
    return final_output

@app.post("/auth/apple/connect")
async def connect_apple(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Saves encrypted iCloud credentials (email + app-specific password)."""
    apple_email = data.get("email")
    app_password = data.get("password")
    
    if not apple_email or not app_password:
        raise HTTPException(status_code=400, detail="Email and App-Specific Password required")
        
    auth_payload = json.dumps({"email": apple_email, "password": app_password})
    current_user.apple_auth_data = encrypt_token(auth_payload)
    db.commit()
    
    return {"status": "success"}

@app.post("/calendar/sync")
async def sync_calendar(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Syncs busy slots from all connected calendars to the database."""
    try:
        total_slots = 0
        active_connections = [c for c in current_user.connections if c.is_active]
        
        if not active_connections:
             print(f"DEBUG: No calendars connected for user {current_user.id}")
             raise HTTPException(status_code=400, detail="No calendars connected")

        # Clear old slots for this user before re-syncing everything
        db.query(BusySlot).filter(BusySlot.user_id == current_user.id).delete()
        
        start = datetime.utcnow()
        end = start + timedelta(days=21) # Sync 3 weeks ahead

        for conn in active_connections:
            all_busy_slots = []
            try:
                # 1. Sync Google
                if conn.provider == 'google':
                    refresh_token = decrypt_token(conn.auth_data)
                    g_service = GoogleCalendarService(refresh_token)
                    google_busy = await g_service.get_busy_slots(start, end)
                    all_busy_slots.extend(google_busy)
                    
                # 2. Sync Apple
                elif conn.provider == 'apple':
                    apple_data = json.loads(decrypt_token(conn.auth_data))
                    a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                    apple_busy = a_service.get_busy_slots(start, end)
                    all_busy_slots.extend(apple_busy)

                # 3. Sync Outlook (Microsoft Graph)
                elif conn.provider == 'outlook':
                    from outlook_service import OutlookCalendarService
                    refresh_token = decrypt_token(conn.auth_data)
                    o_service = OutlookCalendarService(refresh_token)
                    outlook_busy = await o_service.get_busy_slots(start, end)
                    all_busy_slots.extend(outlook_busy)
                
                # Update last sync time
                conn.last_sync = datetime.utcnow()
                conn.status = "active"
                conn.last_error = None
                
                # 3. Save slots with connection_id
                for slot in all_busy_slots:
                    try:
                        s_out = slot['start'].replace('Z', '+00:00')
                        e_out = slot['end'].replace('Z', '+00:00')
                        new_slot = BusySlot(
                            user_id=current_user.id,
                            connection_id=conn.id,
                            start_time=datetime.fromisoformat(s_out).astimezone(pytz.utc).replace(tzinfo=None),
                            end_time=datetime.fromisoformat(e_out).astimezone(pytz.utc).replace(tzinfo=None)
                        )
                        db.add(new_slot)
                        total_slots += 1
                    except Exception as parse_e:
                        print(f"DEBUG: Error parsing slot {slot}: {parse_e}")

            except Exception as conn_e:
                print(f"DEBUG: Connection {conn.id} ({conn.provider}) sync failed: {conn_e}")
                conn.status = "error"
                conn.last_error = str(conn_e)
        
        db.commit()
        print(f"DEBUG: Successfully synced {total_slots} slots from {len(active_connections)} calendars for user {current_user.id}")
        return {"status": "success", "synced_count": total_slots, "connections_synced": len(active_connections)}
        
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Sync failed: {str(e)}")

# Removed duplicate finalize_meeting to prevent conflicts

@app.get("/calendar/busy-slots")
async def get_busy_slots(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns cached busy slots for the user with explicit Z suffix."""
    slots = db.query(BusySlot).filter(BusySlot.user_id == current_user.id).all()
    return [
        {"start": s.start_time.isoformat() + "Z", "end": s.end_time.isoformat() + "Z"} 
        for s in slots
    ]

# ─────────────────── AVAILABILITY ENDPOINTS ───────────────────
@app.get("/api/availability")
async def get_availability(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns the user's working hours for each day of the week."""
    avail = db.query(models.UserAvailability).filter(models.UserAvailability.user_id == current_user.id).all()
    
    # If not set, return defaults
    if not avail:
        return [
            {"day_of_week": i, "start_time": "09:00", "end_time": "18:00", "is_enabled": 1}
            for i in range(7)
        ]
        
    return [
        {
            "day_of_week": a.day_of_week,
            "start_time": a.start_time,
            "end_time": a.end_time,
            "is_enabled": a.is_enabled
        } for a in avail
    ]

@app.post("/api/availability")
async def update_availability(data: list[dict], current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Updates user's working hours."""
    # Clear existing
    db.query(models.UserAvailability).filter(models.UserAvailability.user_id == current_user.id).delete()
    
    for item in data:
        new_avail = models.UserAvailability(
            user_id=current_user.id,
            day_of_week=item["day_of_week"],
            start_time=item["start_time"],
            end_time=item["end_time"],
            is_enabled=item.get("is_enabled", 1)
        )
        db.add(new_avail)
    
    db.commit()
    return {"status": "success"}

# ─────────────────── MEETING MANAGEMENT ───────────────────
@app.get("/api/meetings/my")
async def get_my_meetings(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns meetings created by the user or where they are invited."""
    # 1. Meetings where user has an invite
    invites = db.query(models.MeetingInvite).filter(models.MeetingInvite.user_id == current_user.id).all()
    meeting_ids = [i.meeting_id for i in invites]
    
    # 2. Fetch those meetings
    meetings = db.query(models.GroupMeeting).filter(models.GroupMeeting.id.in_(meeting_ids)).all()
    
    # Map invites for quick status lookup
    invite_map = {i.meeting_id: i for i in invites}
    
    result = []
    for m in sorted(meetings, key=lambda x: x.start_time):
        invite = invite_map.get(m.id)
        result.append({
            "id": m.id,
            "title": m.title,
            "start": m.start_time.isoformat() + "Z",
            "end": m.end_time.isoformat() + "Z",
            "location": m.location,
            "group_id": m.group_id,
            "group_title": m.group.title if m.group else None,
            "is_creator": m.user_id == current_user.id,
            "status": invite.status if invite else "unknown",
            "invite_id": invite.id if invite else None,
            "google_event_id": invite.google_event_id if invite else None
        })
    return result

@app.post("/api/invites/{invite_id}/respond")
async def respond_to_invite(invite_id: int, data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Accepts or declines a meeting invitation."""
    status = data.get("status")
    if status not in ["accepted", "declined"]:
        raise HTTPException(status_code=400, detail="Invalid status")
        
    invite = db.query(models.MeetingInvite).filter(models.MeetingInvite.id == invite_id, models.MeetingInvite.user_id == current_user.id).first()
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")
        
    invite.status = status
    
    # If accepted, try to add to Google/Apple Calendar
    if status == "accepted":
        meeting = invite.meeting
        for conn in current_user.connections:
            if not conn.is_active: continue
            if conn.provider == 'google':
                try:
                    from calendar_service import GoogleCalendarService
                    from encryption import decrypt_token
                    refresh_token = decrypt_token(conn.auth_data)
                    g_service = GoogleCalendarService(refresh_token)
                    # Use existing creator's event details
                    g_event = await g_service.create_event(
                        meeting.title, 
                        meeting.start_time, 
                        meeting.end_time,
                        location=meeting.location
                    )
                    invite.google_event_id = g_event.get('id')
                except Exception as e:
                    print(f"DEBUG: Failed to sync accepted meeting to Google: {e}")
            
            # Apple logic could be added here too
            
    db.commit()
    return {"status": "success"}

@app.delete("/api/meetings/{meeting_id}")
async def delete_meeting(meeting_id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Deletes a meeting from DB and Google Calendar if applicable."""
    meeting = db.query(models.GroupMeeting).filter(models.GroupMeeting.id == meeting_id).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
        
    # Delete from Google Calendar if event exists and user is connected
    if meeting.google_event_id and current_user.google_refresh_token:
        try:
            from calendar_service import GoogleCalendarService
            from encryption import decrypt_token
            refresh_token = decrypt_token(current_user.google_refresh_token)
            g_service = GoogleCalendarService(refresh_token)
            await g_service.delete_event(meeting.google_event_id)
        except Exception as e:
            print(f"DEBUG: Failed to delete Google Event {meeting.google_event_id}: {e}")
            
    db.delete(meeting)
    db.commit()
    return {"status": "success"}

@app.patch("/api/meetings/{meeting_id}")
async def update_meeting(meeting_id: int, data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Updates meeting details."""
    meeting = db.query(models.GroupMeeting).filter(models.GroupMeeting.id == meeting_id).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
        
    if "title" in data: meeting.title = data["title"]
    if "location" in data: meeting.location = data["location"]
    if "start" in data: 
        s_raw = data["start"].replace('Z', '+00:00')
        meeting.start_time = datetime.fromisoformat(s_raw).astimezone(pytz.utc).replace(tzinfo=None)
    if "end" in data: 
        e_raw = data["end"].replace('Z', '+00:00')
        meeting.end_time = datetime.fromisoformat(e_raw).astimezone(pytz.utc).replace(tzinfo=None)
    
    db.commit()
    return {"status": "success"}

@app.post("/calendar/free-slots")
async def get_free_slots(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Finds common free slots for a list of telegram user IDs.
    """
    try:
        # 1. Parse IDs
        tg_ids = data.get("telegram_ids", [])
        if not tg_ids:
            return {"free_slots": [], "debug": "no_tg_ids_provided"}
            
        # Ensure the requesting user's telegram_id is always included (if they are syncing themselves)
        if current_user.telegram_id not in tg_ids:
            tg_ids.append(current_user.telegram_id)
            
        # 2. Find internal user IDs
        users = db.query(User).filter(User.telegram_id.in_(tg_ids)).all()
        
        # 2.5 Security Verification for Groups (If chat_id provided)
        chat_id = data.get("chat_id")
        if chat_id:
            # 1. Check if requesting user is in chat
            if not is_user_in_chat(chat_id, current_user.telegram_id):
                 return {"free_slots": [], "debug": "forbidden_not_in_chat"}
            
            # 2. Filter users to only those still in chat
            active_users = []
            for u in users:
                if is_user_in_chat(chat_id, u.telegram_id):
                    active_users.append(u)
            users = active_users
            
        internal_ids = [u.id for u in users]
        
        requesting_user_index = -1
        try:
            requesting_user_index = internal_ids.index(current_user.id)
        except ValueError:
            pass
        
        if not internal_ids:
            print(f"DEBUG: No internal users found for TG IDs: {tg_ids}")
            return {"free_slots": [], "debug": f"no_users_found_for_ids_{tg_ids}"}

        # 3. Fetch all cached busy slots for these users for next 14 days
        start = datetime.utcnow()
        end = start + timedelta(days=30)
        
        busy_slots_per_user = []
        for uid in internal_ids:
            user_busy = db.query(BusySlot).filter(
                BusySlot.user_id == uid,
                BusySlot.end_time >= start,
                BusySlot.start_time <= end
            ).all()
            busy_slots_per_user.append([(s.start_time, s.end_time) for s in user_busy])
            
        # 4. Fetch User Availabilities (Working Hours)
        user_availabilities = []
        for uid in internal_ids:
            avail = db.query(models.UserAvailability).filter(models.UserAvailability.user_id == uid).all()
            if not avail:
                # Default: 9-18
                u_dict = {i: {"start": 9, "end": 18, "enabled": True} for i in range(7)}
            else:
                u_dict = {}
                for a in avail:
                    # Parse "HH:MM" to int hour
                    try:
                        h_start = int(a.start_time.split(":")[0])
                        h_end = int(a.end_time.split(":")[0])
                        u_dict[a.day_of_week] = {"start": h_start, "end": h_end, "enabled": bool(a.is_enabled)}
                    except:
                        u_dict[a.day_of_week] = {"start": 9, "end": 18, "enabled": True}
            user_availabilities.append(u_dict)

        # 5. Find intersections
        from calendar_service import find_common_free_slots
        tz_offset = data.get("tz_offset", 0)
        print(f"DEBUG: Finding slots for TG IDs: {tg_ids} Offset: {tz_offset}")
        
        free_windows = find_common_free_slots(
            busy_slots_per_user,
            start_date=start,
            end_date=end,
            user_availabilities=user_availabilities,
            tz_offset_hours=tz_offset,
            requesting_user_index=requesting_user_index
        )
        
        print(f"DEBUG: Found {len(free_windows)} free windows")
        return {"free_slots": free_windows}
        
    except Exception as e:
        import traceback
        print(f"ERROR in get_free_slots: {str(e)}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/users")
async def get_all_users(db: Session = Depends(get_db)):
    """Returns a list of all registered users (for group selection)."""
    users = db.query(User).all()
    return [{
        "id": u.id,
        "telegram_id": u.telegram_id,
        "username": u.username,
        "first_name": u.first_name,
        "photo_url": u.photo_url
    } for u in users]

@app.post("/meeting/create")
async def create_meeting(data: dict, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Creates a meeting in both Google and Apple calendars if connected."""
    summary = data.get("title", "Smart Scheduler Meeting")
    start_str = data.get("start")
    end_str = data.get("end")
    location = data.get("location", "")
    idempotency_key = data.get("idempotency_key")
    attendee_emails = data.get("attendee_emails", [])
    meeting_type = data.get("meeting_type", "online")  # 'online' or 'offline'
    
    if not start_str or not end_str:
        raise HTTPException(status_code=400, detail="Start and End times are required")
        
    try:
        # Robust UTC parsing: handle Z and offsets, convert to UTC, then store as naive
        s_raw = str(start_str).replace('Z', '+00:00')
        e_raw = str(end_str).replace('Z', '+00:00')
        start_time = datetime.fromisoformat(s_raw).astimezone(pytz.utc).replace(tzinfo=None)
        end_time = datetime.fromisoformat(e_raw).astimezone(pytz.utc).replace(tzinfo=None)
    except Exception as e:
        print(f"DEBUG: Error parsing dates {start_str}/{end_str}: {e}")
        raise HTTPException(status_code=400, detail=f"Invalid date format: {e}")
    
    # Check Idempotency
    if idempotency_key:
        existing = db.query(models.GroupMeeting).filter(models.GroupMeeting.idempotency_key == idempotency_key).first()
        if existing:
            return {"status": "success", "message": "already_exists", "id": existing.id}

    # 4. Conflict Check: Is this slot already booked in our GroupMeeting DB or BusySlot?
    # (Checking if any meeting starts before this one ends AND ends after this one starts)
    conflict = db.query(models.GroupMeeting).filter(
        models.GroupMeeting.user_id == current_user.id,
        models.GroupMeeting.start_time < end_time,
        models.GroupMeeting.end_time > start_time
    ).first()
    
    if not conflict:
        # Also check BusySlot (synced external calendars)
        conflict = db.query(models.BusySlot).filter(
            models.BusySlot.user_id == current_user.id,
            models.BusySlot.start_time < end_time,
            models.BusySlot.end_time > start_time
        ).first()
    
    if conflict:
        print(f"DEBUG: Conflict detected for user {current_user.id} at {start_time}")
        raise HTTPException(status_code=409, detail="Time slot already booked")

    results = {}
    google_event_id = None
    
    for conn in current_user.connections:
        if not conn.is_active: continue
        
        # 1. Google
        if conn.provider == 'google':
            try:
                refresh_token = decrypt_token(conn.auth_data)
                g_service = GoogleCalendarService(refresh_token)
                g_event = await g_service.create_event(summary, start_time, end_time, attendees=attendee_emails, location=location, meeting_type=meeting_type)
                # Store the last successful google event ID (or we might need to store multiple in the future)
                google_event_id = g_event.get('id')
                results[f"google_{conn.id}"] = "success"
            except Exception as e:
                results[f"google_{conn.id}"] = f"error: {str(e)}"
                
        # 2. Apple
        elif conn.provider == 'apple':
            try:
                apple_data = json.loads(decrypt_token(conn.auth_data))
                a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                a_service.create_event(summary, start_time, end_time, location)
                results[f"apple_{conn.id}"] = "success"
            except Exception as e:
                results[f"apple_{conn.id}"] = f"error: {str(e)}"
            
    # Save to our DB history
    group_id = None
    if idempotency_key and "group_" in idempotency_key:
        try:
            # Extract chat_id from group_CHATID_TIMESTAMP
            parts = idempotency_key.split("_")
            if len(parts) >= 2:
                tg_chat_id = parts[1]
                group = db.query(models.Group).filter(models.Group.telegram_chat_id == tg_chat_id).first()
                if group:
                    group_id = group.id
        except Exception as e:
            print(f"DEBUG: Failed to extract chat_id from idempotency_key: {e}")

    try:
        new_meeting = models.GroupMeeting(
            group_id=group_id,
            user_id=current_user.id, # Now tracked
            title=summary,
            start_time=start_time,
            end_time=end_time,
            location=location,
            idempotency_key=idempotency_key,
            google_event_id=google_event_id
        )
        db.add(new_meeting)
        db.flush() # Get new_meeting.id without full commit

        # Create Invites for participants
        invited_users = []
        if invited_telegram_ids:
            invited_users_db = db.query(models.User).filter(models.User.telegram_id.in_(invited_telegram_ids)).all()
            for u in invited_users_db:
                if u.id != current_user.id:
                    invite = models.MeetingInvite(
                        meeting_id=new_meeting.id,
                        user_id=u.id,
                        status="pending"
                    )
                    db.add(invite)
                    invited_users.append(u)
        
        # Creator is automatically accepted and gets the google_event_id
        creator_invite = models.MeetingInvite(
            meeting_id=new_meeting.id,
            user_id=current_user.id,
            status="accepted",
            google_event_id=google_event_id
        )
        db.add(creator_invite)
        
        db.commit()
    except Exception as e:
        db.rollback()
        print(f"DEBUG: Failed to insert meeting or invites: {e}")
        raise HTTPException(status_code=500, detail="Database insertion failed")

    # Send Telegram Notification to the Group (ASYNCHRONOUSLY IDEALLY, but at least non-blocking for the response)
    def send_notifications():
        if not tg_chat_id: return
        bot_token = os.getenv("BOT_TOKEN")
        if not bot_token: return
        
        try:
            # Group IDs must be integers for the Telegram API
            clean_chat_id = tg_chat_id
            if str(clean_chat_id).startswith("n"):
                clean_chat_id = str(clean_chat_id).replace("n", "-")
            try:
                target_chat = int(clean_chat_id)
            except ValueError:
                target_chat = str(clean_chat_id)
            
            # Fetch bot username for deep linking
            bot_username = "smartschedulertime_bot"
            try:
                bot_resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getMe", timeout=2).json()
                if bot_resp.get("ok"):
                    bot_username = bot_resp.get("result", {}).get("username", bot_username)
            except Exception as e:
                print(f"DEBUG: Failed to get bot username: {e}")

            # Mention users
            mentions = []
            for u in invited_users:
                if u.username:
                    mentions.append(f"@{u.username}")
                elif u.first_name:
                    mentions.append(f"[{u.first_name}](tg://user?id={u.telegram_id})")
            
            mentions_str = ", ".join(mentions)
            if not mentions_str:
                mentions_str = "коллеги"
            
            time_str = start_time.strftime("%d.%m %H:%M")
            
            # IMPORTANT: StartApp parameter CANNOT contain the minus (-) sign.
            app_chat_id = str(target_chat).replace("-", "n")
            web_app_url = f"https://t.me/{bot_username}/app?startapp=group_{app_chat_id}"

            group_text = (
                f"📅 **Новое приглашение на встречу от {current_user.first_name or current_user.username}!**\n\n"
                f"📍 Тема: {summary}\n"
                f"⏰ Время: **{time_str}**\n\n"
                f"🔔 Участники: {mentions_str}\n\n"
                f"Пожалуйста, зайдите в приложение и подтвердите или отклоните встречу."
            )
            
            reply_markup = {
                "inline_keyboard": [[{
                    "text": "📬 Открыть приглашения",
                    "url": web_app_url
                }]]
            }
            
            # Send to Group
            requests.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json={
                "chat_id": target_chat,
                "text": group_text,
                "parse_mode": "Markdown",
                "reply_markup": reply_markup
            }, timeout=3)
            
            # Send individual DMs to each invited participant
            for u in invited_users:
                if u.telegram_id:
                    dm_text = (
                        f"🔔 У вас новое приглашение на встречу!\n\n"
                        f"👤 От: {current_user.first_name or current_user.username}\n"
                        f"📍 Тема: {summary}\n"
                        f"⏰ Время: {time_str}\n\n"
                        f"Откройте приложение, чтобы подтвердить."
                    )
                    requests.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json={
                        "chat_id": u.telegram_id,
                        "text": dm_text,
                        "parse_mode": "Markdown",
                        "reply_markup": reply_markup
                    }, timeout=2)
                 
        except Exception as e:
            print(f"DEBUG: Error during Telegram notification: {e}")

    # Use FastAPI BackgroundTasks to make it non-blocking
    background_tasks.add_task(send_notifications)
    
    return {"status": "success", "results": results, "id": new_meeting.id}

@app.post("/meeting/finalize")
async def finalize_meeting(data: dict, db: Session = Depends(get_db)):
    """Finalizes meeting by updating/sending Telegram message with the final date/time."""
    chat_id = data.get("chat_id")
    time_str = data.get("time_str")
    
    if not chat_id or not time_str:
        raise HTTPException(status_code=400, detail="chat_id and time_str are required")
        
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == str(chat_id)).first()
    
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return {"status": "error", "message": "bot_token_missing"}
        
    # Deep link optimization (handle 'n' prefix for negative IDs)
    clean_param = str(chat_id).replace("-", "n")
    import time
    timestamp = str(int(time.time()))
    reply_markup = {
        "inline_keyboard": [[{
            "text": "📅 Посмотреть детали",
            "url": f"https://t.me/smartschedulertime_bot/app?startapp=group_{clean_param}&v={timestamp}"
        }]]
    }

    new_text = (
        f"📅 **Встреча назначена!**\n\n"
        f"📍 Тема: {group.title if group else 'Встреча'}\n"
        f"⏰ Время: **{time_str}**\n\n"
        "Добавлено в календари участников!"
    )

    try:
        # Safe int conversion for numeric chat_ids
        try:
            target_chat = int(chat_id)
        except:
            target_chat = str(chat_id)

        # 1. Try to EDIT existing message if possible
        if group and group.last_invite_message_id:
            print(f"DEBUG: Attempting to EDIT message {group.last_invite_message_id} in {target_chat}")
            edit_resp = requests.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
                "chat_id": target_chat,
                "message_id": int(group.last_invite_message_id),
                "text": new_text,
                "parse_mode": "Markdown",
                "reply_markup": json.dumps(reply_markup)
            }, timeout=3).json()
            
            if edit_resp.get("ok"):
                print("DEBUG: Successfully edited existing invitation message.")
                return {"status": "success", "action": "edited", "tg_response": edit_resp}
            else:
                print(f"DEBUG: Edit failed ({edit_resp.get('description')}), falling back to SENDING NEW message.")

        # 2. Fallback: Send a NEW message to the group
        send_resp = requests.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json={
            "chat_id": target_chat,
            "text": new_text,
            "parse_mode": "Markdown",
            "reply_markup": json.dumps(reply_markup)
        }, timeout=3).json()
        
        return {"status": "success", "action": "sent_new", "tg_response": send_resp}

    except Exception as e:
        print(f"ERROR in finalize_meeting: {e}")
        return {"status": "error", "message": str(e)}

# Serve the Flutter frontend
# IMPORTANT: Mount static files ONLY for non-API paths to avoid conflict!
STATIC_DIR = "frontend/build/web"

@app.on_event("startup")
def debug_paths():
    import os
    print(f"DEBUG WORKDIR: {os.getcwd()}")
    try:
        print(f"DEBUG ROOT FILES: {os.listdir('.')}")
        if os.path.exists('frontend'):
            print(f"DEBUG FRONTEND DIR: {os.listdir('frontend')}")
            if os.path.exists('frontend/build'):
                print(f"DEBUG FRONTEND/BUILD DIR: {os.listdir('frontend/build')}")
    except Exception as e:
        print(f"DEBUG ERR: {e}")

@app.get("/")
async def root():
    index_path = os.path.join(STATIC_DIR, "index.html")
    if os.path.exists(index_path):
        import time
        ts = str(int(time.time()))
        try:
            with open(index_path, "r", encoding="utf-8") as f:
                content = f.read()
            # Cache-busting: inject timestamp into JS asset URLs
            content = content.replace('main.dart.js', f'main.dart.js?v={ts}')
            content = content.replace('flutter_bootstrap.js', f'flutter_bootstrap.js?v={ts}')
            return HTMLResponse(
                content=content,
                headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"}
            )
        except Exception as e:
            print(f"Error serving dynamic index: {e}")
            return FileResponse(index_path)
            
    return {"status": "ok", "message": "API is running. Backend v5.6.7"}

# Mount static assets (JS, CSS, fonts etc) at /static-assets to avoid overriding API
# The key fix: we use a separate StaticFiles mount for assets onl
from fastapi.responses import Response as StarletteResponse
from starlette.staticfiles import StaticFiles as StarletteStaticFiles

if os.path.exists(STATIC_DIR):
    # Mount specific asset directories - NOT the root, to preserve API routes
    for sub in ["assets", "icons", "canvaskit"]:
        sub_path = os.path.join(STATIC_DIR, sub)
        if os.path.exists(sub_path):
            app.mount(f"/{sub}", StaticFiles(directory=sub_path), name=f"static_{sub}")
    
    # Serve individual frontend files explicitly
    @app.get("/flutter_bootstrap.js")
    async def flutter_bootstrap():
        return FileResponse(
            os.path.join(STATIC_DIR, "flutter_bootstrap.js"),
            headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"}
        )
    
    @app.get("/main.dart.js")
    async def main_dart_js():
        return FileResponse(
            os.path.join(STATIC_DIR, "main.dart.js"),
            headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"}
        )
    
    @app.get("/manifest.json")
    async def manifest():
        return FileResponse(os.path.join(STATIC_DIR, "manifest.json"))
    
    @app.get("/favicon.png")
    async def favicon():
        return FileResponse(os.path.join(STATIC_DIR, "favicon.png"))
    
    @app.get("/flutter.js")
    async def flutter_js():
        f = os.path.join(STATIC_DIR, "flutter.js")
        if os.path.exists(f): return FileResponse(f)
        return StarletteResponse(status_code=404)

    print(f"INFO: Frontend static assets mounted from {STATIC_DIR}")
else:
    print(f"WARNING: Static directory {STATIC_DIR} not found!")
