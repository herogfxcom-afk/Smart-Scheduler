from fastapi import FastAPI, Depends, HTTPException, Header, Request as FastAPIRequest
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from auth import get_current_user
from google_oauth import router as google_auth_router
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
    columns = [col['name'] for col in inspector.get_columns('users')]
    
    if 'email' not in columns:
        with engine.connect() as conn:
            try:
                # Standard SQL
                conn.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR(255)"))
                conn.commit()
                print("Migration: Added email column to users table.")
            except Exception as e:
                print(f"Migration Error: {e}")
    else:
        print("Migration Check: 'email' column already exists.")

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

# Connect Routers
app.include_router(google_auth_router)

# ─────────────────── TELEGRAM BOT WEBHOOK ───────────────────
# Bot runs as a webhook inside FastAPI - no separate process needed!

async def _setup_webhook():
    """Registers the webhook URL with Telegram on startup."""
    bot_token = os.getenv("BOT_TOKEN")
    api_url = os.getenv("API_URL", "")
    if not bot_token or not api_url:
        print("BOT WEBHOOK: Skipping - BOT_TOKEN or API_URL not set")
        return
    webhook_url = f"{api_url.rstrip('/')}/webhook/bot"
    resp = requests.post(
        f"https://api.telegram.org/bot{bot_token}/setWebhook",
        json={"url": webhook_url, "drop_pending_updates": True}
    )
    print(f"BOT WEBHOOK: setWebhook → {resp.json()}")

@app.on_event("startup")
async def on_startup_webhook():
    asyncio.create_task(_setup_webhook())

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
    
    payload = {
        "chat_id": chat_id,
        "text": f"📊 *Синхронизация календарей для: {chat_title}*\n\n"
                "Нажмите кнопку ниже, чтобы синхронизировать свой календарь и найти общее время!",
        "parse_mode": "Markdown",
        "reply_markup": json.dumps({
            "inline_keyboard": [[{
                "text": "📊 Magic Sync",
                "url": deep_link
            }]]
        })
    }
    
    result = requests.post(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        json=payload
    ).json()
    
    # Save group to DB
    import models as _models
    group = db.query(_models.Group).filter(_models.Group.telegram_chat_id == chat_id).first()
    if not group:
        group = _models.Group(telegram_chat_id=chat_id, title=chat_title)
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
        "status": "ok", 
        "message": "Smart Scheduler API", 
        "version": "2.4-webhook-fixed",
        "bot_webhook": bool(os.getenv("BOT_TOKEN") and os.getenv("API_URL"))
    }

@app.get("/cors-debug")
async def cors_debug():
    return {"cors": "enabled", "middleware": "CORSEverywhere"}

@app.get("/auth/me")
async def get_me(current_user: User = Depends(get_current_user)):
    """Returns the current user profile."""
    return {
        "id": current_user.id,
        "telegram_id": current_user.telegram_id,
        "username": current_user.username,
        "first_name": current_user.first_name,
        "email": current_user.email,
        "is_connected": bool(current_user.google_refresh_token),
        "is_apple_connected": bool(current_user.apple_auth_data)
    }

@app.post("/groups/sync")
async def sync_group(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Links user to a group via telegram_chat_id."""
    chat_id = data.get("chat_id")
    if not chat_id:
        raise HTTPException(status_code=400, detail="chat_id is required")
    
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
    
    if not participant:
        participant = models.GroupParticipant(
            group_id=group.id, 
            user_id=current_user.id,
            is_synced=1 if (current_user.google_refresh_token or current_user.apple_auth_data) else 0
        )
        db.add(participant)
    else:
        # Update sync status
        participant.is_synced = 1 if (current_user.google_refresh_token or current_user.apple_auth_data) else 0
        
    db.commit()
    
    # 3. Update Telegram Message (Dynamic Update)
    if group.last_invite_message_id:
        try:
            print(f"DEBUG: Attempting to update TG message for chat {chat_id}, msg {group.last_invite_message_id}")
            participants_count = db.query(models.GroupParticipant).filter(
                models.GroupParticipant.group_id == group.id,
                models.GroupParticipant.is_synced == 1
            ).count()
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
            reply_markup = {
                "inline_keyboard": [[{
                    "text": "📊 Magic Sync",
                    "url": f"https://t.me/{bot_username}/app?startapp=group_{chat_id}"
                }]]
            }
            
            resp = requests.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
                "chat_id": int(chat_id),
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
async def get_group_participants(chat_id: int, db: Session = Depends(get_db)):
    """Returns all participants in a group."""
    print(f"DEBUG: Fetching participants for chat_id: {chat_id}")
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == chat_id).first()
    if not group:
        print(f"DEBUG: Group not found in DB for chat_id: {chat_id}")
        return []
    
    participants = db.query(models.GroupParticipant).filter(models.GroupParticipant.group_id == group.id).all()
    print(f"DEBUG: Found {len(participants)} potential participants in DB")
    
    bot_token = os.getenv("BOT_TOKEN")
    active_participants = []
    
    for p in participants:
        u = p.user
        print(f"DEBUG: Checking membership for user {u.telegram_id} ({u.username}) in chat {chat_id}")
        try:
            resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getChatMember", params={
                "chat_id": int(chat_id),
                "user_id": int(u.telegram_id)
            }, timeout=3).json()
            
            if not resp.get("ok"):
                print(f"DEBUG: TG API Error for user {u.telegram_id}: {resp.get('description')}")
                # Fallback: if chat not found or other API error, we keep THEM as they were synced
                active_participants.append({
                    "id": u.id,
                    "telegram_id": u.telegram_id,
                    "username": u.username,
                    "first_name": u.first_name,
                    "photo_url": u.photo_url,
                    "email": u.email,
                    "is_synced": bool(p.is_synced)
                })
                continue

            status = resp.get("result", {}).get("status")
            print(f"DEBUG: User {u.telegram_id} status in chat: {status}")
            
            if status in ["member", "administrator", "creator", "restricted"]:
                active_participants.append({
                    "id": u.id,
                    "telegram_id": u.telegram_id,
                    "username": u.username,
                    "first_name": u.first_name,
                    "photo_url": u.photo_url,
                    "email": u.email,
                    "is_synced": bool(p.is_synced)
                })
            elif status in ["left", "kicked"]:
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
    """Syncs busy slots from Google Calendar to the database."""
    try:
        all_busy_slots = []
        
        # 1. Sync Google if connected
        if current_user.google_refresh_token:
            refresh_token = decrypt_token(current_user.google_refresh_token)
            g_service = GoogleCalendarService(refresh_token)
            start = datetime.utcnow()
            end = start + timedelta(days=14)
            google_busy = await g_service.get_busy_slots(start, end)
            all_busy_slots.extend(google_busy)
            
        # 2. Sync Apple if connected
        if current_user.apple_auth_data:
            print(f"DEBUG: Syncing Apple for user {current_user.id}")
            apple_data = json.loads(decrypt_token(current_user.apple_auth_data))
            a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
            start = datetime.utcnow()
            end = start + timedelta(days=14)
            apple_busy = a_service.get_busy_slots(start, end)
            print(f"DEBUG: Found {len(apple_busy)} slots from Apple")
            all_busy_slots.extend(apple_busy)
            
        if not all_busy_slots and not current_user.google_refresh_token and not current_user.apple_auth_data:
             print(f"DEBUG: No calendars connected for user {current_user.id}")
             raise HTTPException(status_code=400, detail="No calendars connected")

        # 3. Update DB (Clear old and insert new)
        db.query(BusySlot).filter(BusySlot.user_id == current_user.id).delete()
        
        for slot in all_busy_slots:
            try:
                # Better ISO parsing that handles 'Z' and offsets
                s_out = slot['start'].replace('Z', '+00:00')
                e_out = slot['end'].replace('Z', '+00:00')
                new_slot = BusySlot(
                    user_id=current_user.id,
                    start_time=datetime.fromisoformat(s_out),
                    end_time=datetime.fromisoformat(e_out)
                )
                db.add(new_slot)
            except Exception as parse_e:
                print(f"DEBUG: Error parsing slot {slot}: {parse_e}")
        
        db.commit()
        print(f"DEBUG: Successfully synced {len(all_busy_slots)} slots for user {current_user.id}")
        return {"status": "success", "synced_count": len(all_busy_slots)}
        
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Sync failed: {str(e)}")

@app.post("/meeting/finalize")
async def finalize_meeting(data: dict, db: Session = Depends(get_db)):
    """Updates the Telegram message to announce the chosen time."""
    chat_id = data.get("chat_id")
    time_str = data.get("time_str")
    
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == chat_id).first()
    if not group or not group.last_invite_message_id:
        return {"status": "error", "message": "Group or message ID not found"}

    bot_token = os.getenv("BOT_TOKEN")
    new_text = f"✅ **Время найдено!**\n\n📌 **{time_str}**\n\nПожалуйста, подтвердите своё участие нажатием кнопки!"
    
    from aiogram.utils.keyboard import InlineKeyboardBuilder
    builder = InlineKeyboardBuilder()
    builder.button(text="👍 Подтверждаю", callback_data=f"confirm_meet_{chat_id}")
    
    resp = requests.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
        "chat_id": int(chat_id),
        "message_id": int(group.last_invite_message_id),
        "text": new_text,
        "parse_mode": "Markdown",
        "reply_markup": builder.as_markup().model_dump()
    }, timeout=3).json()
    
    return {"status": "success", "tg_response": resp}

@app.get("/calendar/busy-slots")
async def get_busy_slots(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns cached busy slots for the user."""
    slots = db.query(BusySlot).filter(BusySlot.user_id == current_user.id).all()
    return [
        {"start": s.start_time.isoformat(), "end": s.end_time.isoformat()} 
        for s in slots
    ]

@app.post("/calendar/free-slots")
async def get_free_slots(data: dict, db: Session = Depends(get_db)):
    """
    Finds common free slots for a list of telegram user IDs.
    """
    try:
        # 1. Parse IDs
        tg_ids = data.get("telegram_ids", [])
        if not tg_ids:
            return {"free_slots": [], "debug": "no_tg_ids_provided"}
            
        # 2. Find internal user IDs
        users = db.query(User).filter(User.telegram_id.in_(tg_ids)).all()
        internal_ids = [u.id for u in users]
        
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
            
        # 4. Find intersections
        from calendar_service import find_common_free_slots
        print(f"DEBUG: Finding slots for TG IDs: {tg_ids} (Internal IDs: {internal_ids})")
        print(f"DEBUG: Search range: {start} to {end}")
        
        for i, slots in enumerate(busy_slots_per_user):
            print(f"DEBUG: User {internal_ids[i]} has {len(slots)} busy slots in range.")
            if len(slots) > 0:
                print(f"DEBUG: First busy slot for user {internal_ids[i]}: {slots[0]}")
        
        free_windows = find_common_free_slots(
            busy_slots_per_user,
            start_date=start,
            end_date=end,
            work_start_hour=7,
            work_end_hour=23 
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
async def create_meeting(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Creates a meeting in both Google and Apple calendars if connected."""
    summary = data.get("title", "Smart Scheduler Meeting")
    start_str = data.get("start")
    end_str = data.get("end")
    location = data.get("location", "")
    idempotency_key = data.get("idempotency_key")
    attendee_emails = data.get("attendee_emails", [])
    
    if not start_str or not end_str:
        raise HTTPException(status_code=400, detail="Start and End times are required")
        
    try:
        start_time = datetime.fromisoformat(str(start_str).replace('Z', '').split('+')[0])
        end_time = datetime.fromisoformat(str(end_str).replace('Z', '').split('+')[0])
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid date format")
    
    # Check Idempotency
    if idempotency_key:
        existing = db.query(models.GroupMeeting).filter(models.GroupMeeting.idempotency_key == idempotency_key).first()
        if existing:
            return {"status": "success", "message": "already_exists", "id": existing.id}

    results = {"google": "not_connected", "apple": "not_connected"}
    
    # 1. Google
    if current_user.google_refresh_token:
        try:
            refresh_token = decrypt_token(current_user.google_refresh_token)
            g_service = GoogleCalendarService(refresh_token)
            await g_service.create_event(summary, start_time, end_time, attendees=attendee_emails, location=location)
            results["google"] = "success"
        except Exception as e:
            results["google"] = f"error: {str(e)}"
            
    # 2. Apple
    if current_user.apple_auth_data:
        try:
            apple_data = json.loads(decrypt_token(current_user.apple_auth_data))
            a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
            # Apple doesn't easily support attendees via simple CalDAV as Google does, skipping for now
            a_service.create_event(summary, start_time, end_time, location)
            results["apple"] = "success"
        except Exception as e:
            results["apple"] = f"error: {str(e)}"
            
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

    new_meeting = models.GroupMeeting(
        group_id=group_id,
        title=summary,
        start_time=start_time,
        end_time=end_time,
        location=location,
        idempotency_key=idempotency_key
    )
    db.add(new_meeting)
    db.commit()
    
    return {"status": "success", "results": results, "id": new_meeting.id}

@app.post("/meeting/finalize")
async def finalize_meeting(data: dict, db: Session = Depends(get_db)):
    """Finalizes meeting by updating Telegram message with the final date/time."""
    chat_id = data.get("chat_id")
    time_str = data.get("time_str")
    
    if not chat_id or not time_str:
        raise HTTPException(status_code=400, detail="chat_id and time_str are required")
        
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == chat_id).first()
    if not group or not group.last_invite_message_id:
        return {"status": "error", "message": "group_not_found_or_no_message"}
        
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return {"status": "error", "message": "bot_token_missing"}
        
    try:
        new_text = (
            f"📅 **Встреча назначена!**\n\n"
            f"📍 Тема: {group.title or 'Встреча'}\n"
            f"⏰ Время: **{time_str}**\n\n"
            "Добавляйте в календарь!"
        )
        
        # Build a different keyboard or remove it
        reply_markup = {
            "inline_keyboard": [[{
                "text": "📅 Посмотреть детали",
                "url": f"https://t.me/smartschedulertime_bot/app?startapp=group_{chat_id}"
            }]]
        }
        
        resp = requests.post(
            f"https://api.telegram.org/bot{bot_token}/editMessageText",
            json={
                "chat_id": int(chat_id),
                "message_id": int(group.last_invite_message_id),
                "text": new_text,
                "parse_mode": "Markdown",
                "reply_markup": json.dumps(reply_markup)
            }
        ).json()
        
        return {"status": "success", "tg_response": resp}
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
    if os.path.exists(os.path.join(STATIC_DIR, "index.html")):
        return FileResponse(os.path.join(STATIC_DIR, "index.html"))
    return {"status": "ok", "message": "API is running. Backend v3.0"}

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
        return FileResponse(os.path.join(STATIC_DIR, "flutter_bootstrap.js"))
    
    @app.get("/main.dart.js")
    async def main_dart_js():
        return FileResponse(os.path.join(STATIC_DIR, "main.dart.js"))
    
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
