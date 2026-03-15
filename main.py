from fastapi import FastAPI, Depends, HTTPException, Header, Request as FastAPIRequest, Request, Query, BackgroundTasks
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from sqlalchemy import text
from sqlalchemy.orm import Session, joinedload
import datetime as dt_module
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
import os
import httpx
import json
import asyncio
import re
import time
from zoneinfo import ZoneInfo
import logging
import sys

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("smart-scheduler")

from aiogram import Bot, Dispatcher, types, F
from aiogram.types import InlineQuery, InlineQueryResultArticle, InputTextMessageContent, InlineKeyboardMarkup, InlineKeyboardButton, WebAppInfo
from aiogram.utils.keyboard import InlineKeyboardBuilder

# Sentry initialization
SENTRY_DSN = os.getenv("SENTRY_DSN", "https://c4f2ee07b69a9b590d740d35220ef5a0@o4511041169391616.ingest.de.sentry.io/4511041208123472")
sentry_sdk.init(
    dsn=SENTRY_DSN,
    integrations=[FastApiIntegration()],
    traces_sample_rate=0.1,
    environment=os.getenv("RAILWAY_ENVIRONMENT_NAME", "production")
)

from auth import get_current_user
from google_oauth import router as google_auth_router
from outlook_oauth import router as outlook_auth_router
from models import User, BusySlot
from database import get_db
from encryption import decrypt_token, encrypt_token
from calendar_service import GoogleCalendarService, find_common_free_slots
from caldav_service import AppleCalendarService

def parse_ms_datetime(dt_str: str) -> datetime:
    # Microsoft returns 7 decimal places for microseconds: 2026-03-12T07:00:00.0000000Z
    # Python fromisoformat supports max 6 -> ValueError -> slot is lost
    dt_str = re.sub(r'(\.\d{6})\d+', r'\1', dt_str)
    dt_str = dt_str.replace('Z', '+00:00')
    return datetime.fromisoformat(dt_str)

app = FastAPI(title="Smart Scheduler API")

# Initialize Rate Limiter
limiter = Limiter(key_func=lambda request: request.headers.get("init-data", "anon"))
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    import traceback
    error_msg = traceback.format_exc()
    print(f"GLOBAL ERROR: {error_msg}")
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc), "traceback": error_msg}
    )

@app.get("/api/debug/diag")
async def diagnostic_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        db_status = "ok"
    except Exception as e:
        db_status = f"error: {str(e)}"
    
    return {
        "db": db_status,
        "env": os.getenv("RAILWAY_ENVIRONMENT_NAME", "unknown"),
        "python": sys.version,
        "now": datetime.now(timezone.utc).isoformat()
    }

# Transaction Health Middleware - Removed for Vercel performance optimization
# (Connection health is now handled by pool_pre_ping=True in database.py)

# Create database tables
from database import engine
import models
# metadata.create_all moved inside migrate_db for safer startup

# Production Migration: Ensure columns exist
@app.on_event("startup")
def migrate_db():
    from sqlalchemy import inspect
    try:
        models.Base.metadata.create_all(bind=engine)
        print("Database tables ensured.")
        
        inspector = inspect(engine)
        with engine.begin() as conn:
            # Migration for group_meetings
            columns = [c['name'] for c in inspector.get_columns('group_meetings')]
            if 'is_cancelled' not in columns:
                print("Adding is_cancelled to group_meetings...")
                if engine.url.drivername.startswith('sqlite'):
                    conn.execute(text("ALTER TABLE group_meetings ADD COLUMN is_cancelled BOOLEAN DEFAULT 0"))
                else:
                    conn.execute(text("ALTER TABLE group_meetings ADD COLUMN is_cancelled BOOLEAN DEFAULT FALSE"))
            
            # Migration for calendar_connections
            columns = [c['name'] for c in inspector.get_columns('calendar_connections')]
            if 'last_sync_status' not in columns:
                print("Adding last_sync_status to calendar_connections...")
                if engine.url.drivername.startswith('sqlite'):
                    conn.execute(text("ALTER TABLE calendar_connections ADD COLUMN last_sync_status TEXT"))
                else:
                    conn.execute(text("ALTER TABLE calendar_connections ADD COLUMN last_sync_status VARCHAR(100)"))
            
            if 'last_sync_at' not in columns:
                print("Adding last_sync_at to calendar_connections...")
                if engine.url.drivername.startswith('sqlite'):
                    conn.execute(text("ALTER TABLE calendar_connections ADD COLUMN last_sync_at DATETIME"))
                else:
                    conn.execute(text("ALTER TABLE calendar_connections ADD COLUMN last_sync_at TIMESTAMP WITH TIME ZONE"))
        print("Migrations check complete.")
    except Exception as e:
        print(f"Database Initialization Error: {e}")

FRONTEND_URL = os.getenv("FRONTEND_URL", "https://frontend-git-main-herogfxcom-5981s-projects.vercel.app")
API_URL = os.getenv("API_URL", "")
BOT_USERNAME_FALLBACK = os.getenv("BOT_USERNAME", "smartschedulertime_bot")

# Initialize Aiogram
bot = Bot(token=os.getenv("BOT_TOKEN", ""))
dp = Dispatcher()

@dp.inline_query()
async def handle_inline_query(inline_query: InlineQuery):
    print(f"🔥 [INLINE_HANDLER] Query from {inline_query.from_user.id}: {inline_query.query}")

    result = InlineQueryResultArticle(
        id="open_scheduler",
        title="Smart Scheduler Time Pro",
        description="Открыть планировщик встреч",
        input_message_content=InputTextMessageContent(
            message_text="Открываю Smart Scheduler..."
        ),
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(
                text="📅 Открыть приложение",
                url="https://t.me/smartschedulertime_bot/app"
            )
        ]])
    )

    await inline_query.answer(results=[result], cache_time=0)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        FRONTEND_URL,
        "https://t.me",
        "https://web.telegram.org",
        "http://localhost:8080"
    ],
    allow_origin_regex=r"https://.*\.vercel\.app",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Exception Logging Middleware
@app.middleware("http")
async def log_exceptions_middleware(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        import traceback
        import sys
        error_msg = traceback.format_exc()
        print(f"CRITICAL EXCEPTION IN REQUEST {request.method} {request.url.path}:")
        print(error_msg)
        sys.stdout.flush()
        
        # return detailed error for debugging on Vercel
        if request.url.path.startswith(("/auth", "/api", "/groups", "/meeting")):
            try:
                from fastapi.responses import JSONResponse
                return JSONResponse(
                    status_code=500,
                    content={
                        "error": str(e),
                        "traceback": error_msg,
                        "info": "Middleware catch-all"
                    }
                )
            except:
                import json
                from starlette.responses import Response
                return Response(
                    content=json.dumps({"error": str(e), "traceback": error_msg}),
                    status_code=500,
                    media_type="application/json"
                )
        raise e

# ─────────────────── TELEGRAM HELPERS ───────────────────
from cachetools import TTLCache

_membership_cache = TTLCache(maxsize=512, ttl=60)

async def is_user_in_chat(chat_id: str, user_telegram_id: int) -> bool:
    """Checks if a user is still a member of a Telegram chat with 60s caching."""
    cache_key = f"{chat_id}:{user_telegram_id}"
    if cache_key in _membership_cache:
        return _membership_cache[cache_key]
        
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return "ok" # Fallback if bot not configured
    
    try:
        # Handle "n" prefix for negative chat IDs (e.g. n5773826244 -> -5773826244)
        clean_chat_id = chat_id
        if isinstance(clean_chat_id, str) and clean_chat_id.startswith('n'):
            clean_chat_id = '-' + clean_chat_id[1:]
            
        try:
            target_chat = int(clean_chat_id)
        except:
            target_chat = str(clean_chat_id)

        async with httpx.AsyncClient(timeout=5) as client:
            resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getChatMember", params={
                "chat_id": target_chat,
                "user_id": int(user_telegram_id)
            })).json()
        
        if not resp.get("ok"):
            desc = resp.get('description', '')
            if 'chat not found' in desc.lower():
                result = "bot_not_in_chat"
            else:
                print(f"DEBUG: is_user_in_chat API Error: {desc}")
                result = "error"
        else:
            status = resp.get("result", {}).get("status")
            # Allowed statuses
            if status in ["member", "administrator", "creator", "restricted"]:
                result = "ok"
            else:
                result = "not_member"
                
    except Exception as e:
        print(f"TRACE: is_user_in_chat system error: {e}")
        result = "ok" # Soft fail on network error
        
    _membership_cache[cache_key] = result
    return result

# ─────────────────── BOT USERNAME CACHE ───────────────────
_bot_username_cache = None

async def get_bot_username() -> str:
    global _bot_username_cache
    if _bot_username_cache:
        return _bot_username_cache
        
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return BOT_USERNAME_FALLBACK
        
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getMe")).json()
        if resp.get("ok"):
            _bot_username_cache = resp.get("result", {}).get("username")
            return _bot_username_cache
    except Exception as e:
        print(f"DEBUG: Failed to get bot username: {e}")
        
    return BOT_USERNAME_FALLBACK

async def send_telegram_notification(chat_id: str, text: str, reply_markup: dict = None):
    """Sends a markdown notification to a Telegram chat."""
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token: return
    
    # Handle 'n' prefix for group IDs
    target_chat = str(chat_id)
    if target_chat.startswith("n"):
        target_chat = "-" + target_chat[1:]
    
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            payload = {
                "chat_id": target_chat,
                "text": text,
                "parse_mode": "Markdown"
            }
            if reply_markup:
                payload["reply_markup"] = reply_markup
            await client.post(url, json=payload)
    except Exception as e:
        print(f"TRACE: send_telegram_notification fail: {e}")

# ─────────────────── ROUTERS ───────────────────
app.include_router(google_auth_router)
app.include_router(outlook_auth_router)

# ─────────────────── TELEGRAM BOT WEBHOOK ───────────────────
# Bot runs as a webhook inside FastAPI - no separate process needed!

async def _setup_bot_ui():
    """Registers the webhook and sets up the bot menu button."""
async def _setup_bot_ui():
    """Sets up the bot menu button only. Webhook is managed manually via setup_webhook.py."""
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        print("BOT UI SETUP: Skipping - BOT_TOKEN not set")
        return

    try:
        async with httpx.AsyncClient(timeout=5) as client:
            # Set Main Menu Button only — webhook is NOT set here to prevent resets
            menu_resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/setChatMenuButton", json={
                "menu_button": {
                    "type": "web_app",
                    "text": "📅 Open Scheduler",
                    "web_app": {
                        "url": f"{FRONTEND_URL}/"
                    }
                }
            })).json()
            print(f"MENU BUTTON SETUP: {menu_resp}")
    except Exception as e:
        print(f"BOT UI SETUP Error: {e}")

# Removed `/users` and redundant startup logic for security/performance.
@app.on_event("startup")
async def on_startup_webhook():
    # Cache bot username and setup UI
    await get_bot_username()
    asyncio.create_task(_setup_bot_ui())

@app.post("/webhook/bot")
@limiter.limit("60/minute") # Protect from webhook spam
async def telegram_webhook(
    request: Request, 
    db: Session = Depends(get_db),
    x_telegram_bot_api_secret_token: str = Header(None)
):
    """Receives Telegram updates and handles /sync command."""
    # Verify Webhook Secret if configured
    webhook_secret = os.getenv("WEBHOOK_SECRET")
    if webhook_secret and x_telegram_bot_api_secret_token != webhook_secret:
        print(f"WEBHOOK ERROR: Unauthorized access attempt to bot webhook!")
        raise HTTPException(status_code=403, detail="Unauthorized")
    
    bot_token = os.getenv("BOT_TOKEN")
    if not bot_token:
        return {"ok": False}
    
    try:
        update = await request.json()
        print(f"📩 BOT UPDATE: {json.dumps(update, ensure_ascii=True)}")
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

    # 3. Handle Inline Query (@botname) - Direct HTTP call, no Aiogram overhead
    if update.get("inline_query"):
        iq = update["inline_query"]
        iq_id = iq["id"]
        user_id = iq.get("from", {}).get("id", "?")
        print(f"🔍 [INLINE] Query from user {user_id}, id={iq_id}")
        try:
            answer_payload = {
                "inline_query_id": iq_id,
                "cache_time": 0,
                "results": [{
                    "type": "article",
                    "id": "open_scheduler",
                    "title": "Smart Scheduler Time Pro",
                    "description": "Открыть планировщик встреч",
                    "input_message_content": {
                        "message_text": "Открываю Smart Scheduler..."
                    },
                    "reply_markup": {
                        "inline_keyboard": [[{
                            "text": "📅 Открыть приложение",
                            "url": "https://t.me/smartschedulertime_bot/app"
                        }]]
                    }
                }]
            }
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.post(
                    f"https://api.telegram.org/bot{bot_token}/answerInlineQuery",
                    json=answer_payload
                )
                print(f"✅ [INLINE] answerInlineQuery response: {resp.text}")
        except Exception as e:
            print(f"❌ [INLINE ERROR] {e}")
        return {"ok": True}

    # 4. Handle Callback Queries (Inline Buttons)
    callback_query = update.get("callback_query")
    if callback_query:
        await _handle_callback_query(callback_query, bot_token, db)
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
    elif text.startswith("/start") and chat_type == "private":
        first_name = message.get("from", {}).get("first_name", "User")
        bot_username = await get_bot_username()
        
        welcome_text = (
            f"Hi {first_name}! 🚀\n\n"
            f"I can help you find free time that works for everyone in your group.\n\n"
            f"1. Add me to a group 👥\n"
            f"2. Use /sync to connect your calendars\n"
            f"3. Find the best slot for meeting!\n\n"
            f"Click the button below to open the Mini App."
        )
        
        payload = {
            "chat_id": chat_id,
            "text": welcome_text,
            "parse_mode": "Markdown",
            "reply_markup": json.dumps({
                "inline_keyboard": [[{
                    "text": "📊 Open Scheduler",
                    "web_app": {"url": f"{FRONTEND_URL}/"}
                }]]
            })
        }
        async with httpx.AsyncClient(timeout=5) as client:
            await client.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json=payload)

    return {"ok": True}

async def _send_sync_invite(bot_token: str, chat_id: int, chat_title: str, db: Session):
    """Internal helper to send the Magic Sync button to a chat."""
    async with httpx.AsyncClient(timeout=5) as client:
        bot_info_resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getMe")).json()
        bot_username = bot_info_resp.get("result", {}).get("username", BOT_USERNAME_FALLBACK)
    
    # IMPORTANT: StartApp parameter CANNOT contain the minus (-) sign.
    # Replace negative ID prefix with 'n'
    clean_chat_id = str(chat_id).replace("-", "n")
    deep_link = f"https://t.me/{bot_username}/app?startapp=group_{clean_chat_id}"
    
    # Build the web_app URL — pass group chat_id as query param
    # The frontend reads window.location.search or Telegram's startParam for group context
    # For the invite link, we need the frontend URL.
    # In production, this can be different from the API URL.
    global FRONTEND_URL
    web_app_url = f"{FRONTEND_URL}/?startapp=group_{clean_chat_id}"

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
    
    async with httpx.AsyncClient(timeout=5) as client:
        result = (await client.post(
            f"https://api.telegram.org/bot{bot_token}/sendMessage",
            json=payload
        )).json()
    print(f"INVITE SEND: {result}")
    
    # Save group to DB
    import models as _models
    group = db.query(_models.Group).filter(_models.Group.telegram_chat_id == str(chat_id)).first()
    if not group:
        group = _models.Group(telegram_chat_id=str(chat_id), title=chat_title)
        db.add(group)
    db.commit()
    print(f"BOT: Sent Magic Sync to {chat_title} (chat_id={chat_id}), link={deep_link}")
    
    return {"ok": True}

async def _handle_callback_query(callback_query: dict, bot_token: str, db: Session):
    """Handles inline button presses (e.g., Cancel & Delete vs Keep)."""
    cb_id = callback_query.get("id")
    from_user = callback_query.get("from", {})
    user_tg_id = str(from_user.get("id"))
    data = callback_query.get("data", "")
    message = callback_query.get("message", {})
    chat_id = message.get("chat", {}).get("id")
    message_id = message.get("message_id")

    answer_text = "Действие выполнено"
    
    if data.startswith("delmtg_"):
        try:
            _, action, meeting_id = data.split("_")
            meeting_id = int(meeting_id)
            
            user = db.query(models.User).filter(models.User.telegram_id == user_tg_id).first()
            if not user:
                answer_text = "Пользователь не найден"
            else:
                invite = db.query(models.MeetingInvite).filter(
                    models.MeetingInvite.meeting_id == meeting_id,
                    models.MeetingInvite.user_id == user.id
                ).first()
                
                if invite:
                    if action == "keep":
                        invite.status = "cancelled_kept"
                        db.commit()
                        answer_text = "Встреча оставлена в календаре"
                        
                        # Update original message to remove buttons
                        async with httpx.AsyncClient() as client:
                            await client.post(f"https://api.telegram.org/bot{bot_token}/editMessageReplyMarkup", json={
                                "chat_id": chat_id,
                                "message_id": message_id,
                                "reply_markup": {"inline_keyboard": []}
                            })
                            
                    elif action == "remove":
                        # Full participant removal via the existing logic
                        from fastapi import BackgroundTasks
                        await delete_meeting(meeting_id, BackgroundTasks(), user, db)
                        answer_text = "Встреча полностью удалена"
                        
                        # Update original message
                        async with httpx.AsyncClient() as client:
                            await client.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
                                "chat_id": chat_id,
                                "message_id": message_id,
                                "text": message.get("text", "") + "\n\n✅ *Удалено из ваших календарей*",
                                "parse_mode": "Markdown",
                                "reply_markup": {"inline_keyboard": []}
                            })
                else:
                    answer_text = "Приглашение не найдено или уже обработано"
        except Exception as e:
            print(f"DEBUG: Callback query error: {e}")
            answer_text = "Произошла ошибка"

    # Important: Always answer callback query to remove loading state
    async with httpx.AsyncClient(timeout=5) as client:
        await client.post(f"https://api.telegram.org/bot{bot_token}/answerCallbackQuery", json={
            "callback_query_id": cb_id,
            "text": answer_text
        })

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
async def get_me(user_timezone: str = Query(None, alias="timezone"), current_user: User = Depends(get_current_user)):
    """Returns the current user profile including all connected calendars."""
    print(f"DEBUG /auth/me: Processing for user {current_user.id}")
    from database import SessionLocal
    
    try:
        with SessionLocal() as db:
            print(f"DEBUG /auth/me: Session created for user {current_user.id}")
            db.rollback() # Recover from poisoned connection
            # Re-fetch user in the local session context to handle relations and updates
            user = db.query(User).options(joinedload(User.connections)).filter(User.id == current_user.id).first()
            if not user:
                print(f"DEBUG /auth/me ERROR: User {current_user.id} not found in DB")
                raise HTTPException(status_code=404, detail="User not found")
                
            if user_timezone and user.timezone != user_timezone:
                print(f"DEBUG /auth/me: Updating timezone to {user_timezone}")
                user.timezone = user_timezone
                db.commit()

            print(f"DEBUG /auth/me: Constructing response for user {user.id}")
            result = {
                "id": user.id,
                "telegram_id": user.telegram_id,
                "username": user.username,
                "first_name": user.first_name,
                "email": user.email,
                "timezone": user.timezone,
                "is_connected": any(c.provider == 'google' and c.is_active for c in user.connections),
                "is_apple_connected": any(c.provider == 'apple' and c.is_active for c in user.connections),
                "connections": [
                    {
                        "id": c.id,
                        "provider": c.provider,
                        "email": c.email,
                        "status": c.status,
                        "last_sync_status": c.last_sync_status,
                        "is_active": bool(c.is_active),
                        "last_sync_at": c.last_sync_at.astimezone(ZoneInfo("UTC")).isoformat().replace('+00:00', '') + "Z" if c.last_sync_at else None
                    } for c in user.connections
                ]
            }
            print(f"DEBUG /auth/me: Success for user {user.id}")
            return result
    except Exception as e:
        import traceback
        print(f"DEBUG /auth/me CRASH: {str(e)}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

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
    membership_status = await is_user_in_chat(chat_id, current_user.telegram_id)
    if membership_status != "ok":
        print(f"DEBUG: Denying group sync - user {current_user.telegram_id} status {membership_status} in chat {chat_id}")
        # If user was a participant, remove them
        if participant:
            db.delete(participant)
            db.commit()
        raise HTTPException(status_code=403, detail="You are not a member of this Telegram group")

    if not participant:
        try:
            participant = models.GroupParticipant(
                group_id=group.id,
                user_id=current_user.id,
                is_synced=1 if any(c.is_active for c in current_user.connections) else 0
            )
            db.add(participant)
            db.flush() # Catches UniqueConstraint before commit
        except Exception as e:
            db.rollback()
            print(f"DEBUG: GroupParticipant already exists, recovering: {e}")
            participant = db.query(models.GroupParticipant).filter_by(
                group_id=group.id, user_id=current_user.id
            ).first()
            if participant:
                participant.is_synced = 1 if any(c.is_active for c in current_user.connections) else 0
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
            async with httpx.AsyncClient(timeout=5) as client:
                bot_resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getMe")).json()
                bot_username = bot_resp.get("result", {}).get("username", BOT_USERNAME_FALLBACK)

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
            
            async with httpx.AsyncClient(timeout=3) as client:
                resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
                    "chat_id": target_chat,
                    "message_id": int(group.last_invite_message_id),
                    "text": new_text,
                    "parse_mode": "Markdown",
                    "reply_markup": json.dumps(reply_markup)
                })).json()
            print(f"DEBUG: Message update result: {resp}")
        except Exception as e:
            print(f"TRACE: Failed to update TG message for chat {chat_id}: {e}")

    return {"status": "success", "group_id": group.id}

@app.get("/groups/{chat_id}/participants")
async def get_group_participants(chat_id: str, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns list of participants who are currently members of the Telegram chat."""
    group = db.query(models.Group).filter(models.Group.telegram_chat_id == chat_id).first()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
        
    participants = db.query(models.GroupParticipant).filter_by(group_id=group.id).all()
    
    # NEW: Run membership checks in parallel!
    checks = await asyncio.gather(*[
        is_user_in_chat(chat_id, p.user.telegram_id) for p in participants
    ])
    
    active_participants = []
    for p, status in zip(participants, checks):
        u = p.user
        try:
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
                print(f"DEBUG: Ghost participant {u.telegram_id} (status: {status}) - Removing from DB")
                db.delete(p)
                db.commit()
            else:
                print(f"DEBUG: Status {status} for {u.telegram_id}, excluding but NOT deleting yet.")
        except Exception as e:
            print(f"TRACE: Error processing participant {u.telegram_id}: {e}")
            # Fallback: include if we failed to check status
            active_participants.append({
                "id": u.id,
                "telegram_id": u.telegram_id,
                "username": u.username,
                "first_name": u.first_name,
                "photo_url": u.photo_url,
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
    encrypted = encrypt_token(auth_payload)
    
    # Check if a connection already exists
    conn = db.query(models.CalendarConnection).filter_by(
        user_id=current_user.id, provider='apple', email=apple_email
    ).first()
    if conn:
        conn.auth_data = encrypted
        conn.email = apple_email
        conn.is_active = True
    else:
        conn = models.CalendarConnection(
            user_id=current_user.id, provider='apple',
            email=apple_email, auth_data=encrypted, is_active=True
        )
        db.add(conn)
    db.commit()
    
    return {"status": "success"}

async def perform_calendar_sync(current_user: User, db: Session):
    """
    Internal helper to sync busy slots from all connected calendars to the database.
    NOTE: Calling code should ideally use an isolated Session for this to prevent 
    transaction poisoning in the main request handler on systems like Neon.
    """
    total_slots = 0
    active_connections = [c for c in current_user.connections if c.is_active]
    
    if not active_connections:
        logger.info(f"Sync skipped: No active connections for user {current_user.id}")
        return 0

    # No more begin_nested()! We rely on the caller providing an isolated session.
    try:
        # Use a Postgres advisory lock instead of FOR UPDATE NOWAIT.
        # Advisory locks return False on collision instead of raising an exception,
        # which prevents the transaction from being "aborted" on Neon/PgBouncer.
        lock_id = 9991000 + current_user.id
        lock_result = db.execute(text("SELECT pg_try_advisory_xact_lock(:id)"), {"id": lock_id}).scalar()
        
        if not lock_result:
            logger.info(f"Sync skipped: Advisory lock held for user {current_user.id}")
            return 0
            
        # If we have the lock, proceed to clear old external slots.
        db.query(BusySlot).filter(BusySlot.user_id == current_user.id, BusySlot.connection_id.isnot(None)).delete()
        db.flush()
    except Exception as e:
        logger.warning(f"Sync setup failed for user {current_user.id}: {e}")
        return 0
    
    # Track seen slots to prevent UniqueConstraint violations
    seen_slots = set()
    manual_slots = db.query(BusySlot).filter(BusySlot.user_id == current_user.id, BusySlot.connection_id.is_(None)).all()
    for ms in manual_slots:
        st = ms.start_time.replace(tzinfo=None) if ms.start_time.tzinfo else ms.start_time
        et = ms.end_time.replace(tzinfo=None) if ms.end_time.tzinfo else ms.end_time
        seen_slots.add((st, et))
    
    # Start looking 2 days in the past
    sync_start = datetime.now(timezone.utc) - timedelta(days=2)
    sync_end = sync_start + timedelta(days=21)

    # Fetch ACTIVE invites to skip
    known_external_ids = set()
    meetings = db.query(models.GroupMeeting).filter(
        models.GroupMeeting.user_id == current_user.id,
        models.GroupMeeting.is_cancelled == False
    ).all()
    for m in meetings:
        if m.google_event_id: known_external_ids.add(m.google_event_id)
        if m.outlook_event_id: known_external_ids.add(m.outlook_event_id)
    invites = db.query(models.MeetingInvite).filter(
        models.MeetingInvite.user_id == current_user.id,
        models.MeetingInvite.status.in_(['accepted', 'pending'])
    ).all()
    for i in invites:
        if i.google_event_id: known_external_ids.add(i.google_event_id)
        if i.outlook_event_id: known_external_ids.add(i.outlook_event_id)

    async def fetch_one(conn):
        try:
            slots = []
            if conn.provider == 'google':
                refresh_token = decrypt_token(conn.auth_data)
                g_service = GoogleCalendarService(refresh_token)
                slots = await g_service.get_busy_slots(sync_start, sync_end)
            elif conn.provider == 'apple':
                apple_data = json.loads(decrypt_token(conn.auth_data))
                a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                # Apple service is synchronous, but we can run it in executor if needed.
                # For now just call it, it's usually fast enough compared to Google/Outlook APIs.
                slots = a_service.get_busy_slots(sync_start, sync_end)
            elif conn.provider == 'outlook':
                from outlook_service import OutlookCalendarService
                refresh_token = decrypt_token(conn.auth_data)
                o_service = OutlookCalendarService(refresh_token)
                slots = await o_service.get_busy_slots(sync_start, sync_end)
            return conn.id, slots, None
        except Exception as e:
            return conn.id, [], str(e)

    # Parallel fetch!
    results = await asyncio.gather(*[fetch_one(c) for c in active_connections])

    for conn_id, slots, error in results:
        conn = next(c for c in active_connections if c.id == conn_id)
        if error:
            print(f"DEBUG: Connection {conn.id} ({conn.provider}) sync failed: {error}")
            conn.status = "error"
            conn.last_sync_at = datetime.now(dt_module.timezone.utc)
            conn.last_sync_status = "500_api_error"
            conn.last_error = error
            continue

        # Success - process slots
        conn.last_sync_at = datetime.now(dt_module.timezone.utc)
        conn.last_sync_status = "success"
        conn.status = "active"
        conn.last_error = None

        for slot in slots:
            try:
                ext_id = slot.get('id')
                if ext_id and ext_id in known_external_ids:
                    continue

                s_out = slot['start'].replace('Z', '+00:00')
                e_out = slot['end'].replace('Z', '+00:00')
                
                st_aware = parse_ms_datetime(s_out).astimezone(ZoneInfo("UTC"))
                et_aware = parse_ms_datetime(e_out).astimezone(ZoneInfo("UTC"))
                st_naive = st_aware.replace(tzinfo=None)
                et_naive = et_aware.replace(tzinfo=None)
                
                slot_key = (st_naive, et_naive)
                if slot_key not in seen_slots:
                    seen_slots.add(slot_key)
                    new_slot = BusySlot(
                        user_id=current_user.id,
                        connection_id=conn.id,
                        start_time=st_aware,
                        end_time=et_aware,
                        summary=slot.get('summary'),
                        external_id=ext_id,
                        is_external=True
                    )
                    db.add(new_slot)
                    total_slots += 1
                else:
                    existing = db.query(BusySlot).filter_by(user_id=current_user.id, start_time=st_aware, end_time=et_aware).first()
                    if existing and not existing.summary:
                        existing.summary = slot.get('summary')
                        existing.external_id = ext_id
                        existing.is_external = True
            except Exception as parse_e:
                print(f"DEBUG: Error parsing slot {slot}: {parse_e}")

    # Re-verify session is still active and commit the whole request transition
    # Let it raise to the caller if commit fails.
    db.commit()

    return total_slots

@app.get("/calendar/sync")
@limiter.limit("5/minute")
async def sync_calendar(request: Request, current_user: User = Depends(get_current_user)):
    """Syncs busy slots from all connected calendars to the database."""
    from database import SessionLocal
    # Use isolated session for sync
    with SessionLocal() as sync_db:
        sync_db.rollback() # Protect sync from dirty connections
        try:
            # Re-fetch user in the new session
            user_in_sync = sync_db.query(User).filter(User.id == current_user.id).first()
            if not user_in_sync:
                raise HTTPException(status_code=404, detail="User not found in sync session")
                
            total_slots = await perform_calendar_sync(user_in_sync, sync_db)
            sync_db.commit() # Explicitly commit the isolated sync
            return {"status": "success", "synced_count": total_slots}
        except Exception as e:
            logger.error(f"Isolated sync_calendar fail: {e}")
            sync_db.rollback()
            raise HTTPException(status_code=500, detail=f"Sync failed: {str(e)}")

# Removed duplicate finalize_meeting to prevent conflicts

@app.get("/calendar/busy-slots")
async def get_busy_slots(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Returns a list of all busy slots for the current user, filtered to recent/upcoming to improve performance."""
    now = datetime.now(timezone.utc)
    # Filter to 1 day ago and 30 days ahead
    recent_limit = now - timedelta(days=1)
    
    slots = db.query(BusySlot).filter(
        BusySlot.user_id == current_user.id,
        BusySlot.end_time >= recent_limit,
        BusySlot.start_time <= now + timedelta(days=30)
    ).all()
    return [
        {
            "start": s.start_time.isoformat().replace('+00:00', '') + "Z", 
            "end": s.end_time.isoformat().replace('+00:00', '') + "Z",
            "summary": s.summary or "Busy",
            "is_external": bool(s.is_external)
        } 
        for s in slots
    ]

@app.get("/api/scheduler/solo")
async def get_solo_scheduler(
    current_user: User = Depends(get_current_user), 
    user_tz: str = Query(None, alias="timezone"),
    tz_offset: float = Query(default=0.0),
    force_sync: bool = Query(default=False)
):
    """Returns 7-day busy/free segments for the current user's personal heatmap."""
    from database import SessionLocal
    
    # Fully isolated session for the entire request
    with SessionLocal() as db:
        db.rollback() # Critical: clear potential aborted state from pool
        try:
            # Re-fetch user in the local session context
            current_user = db.query(User).filter(User.id == current_user.id).first()
            if not current_user:
                raise HTTPException(status_code=404, detail="User not found")
            
            # Defensive rollback
            db.rollback()
            
            if force_sync:
                logger.info(f"Forced sync triggered for user {current_user.id}")
                # perform_calendar_sync uses its own internal isolated session if called correctly, 
                # but we can also use our 'db' here since it IS isolated from the pool.
                try:
                    await perform_calendar_sync(current_user, db)
                    db.commit() # Ensure sync is committed
                except Exception as sync_e:
                    logger.error(f"Sync fail in solo_scheduler: {sync_e}")
                    db.rollback()

            # The rest of the logic remains the same, but using our local 'db'
            user_tz_name = user_tz or current_user.timezone or "UTC"
            try:
                u_tz = ZoneInfo(user_tz_name)
            except:
                u_tz = ZoneInfo("UTC")

            # Range: from user's local midnight (today 00:00 in user TZ) to 7 days later.
            utc_now = datetime.now(timezone.utc)
            user_local_now = utc_now.astimezone(u_tz)
            user_local_midnight = user_local_now.replace(hour=0, minute=0, second=0, microsecond=0)
            start_date = user_local_midnight.astimezone(timezone.utc)
            end_date = start_date + timedelta(days=7)
            
            # Get user's working hours in the format expected by find_common_free_slots
            avail = db.query(models.UserAvailability).filter(models.UserAvailability.user_id == current_user.id).all()
            
            # Initialize with default 9-18 for all days
            user_avail = {i: {"start": 9, "end": 18, "enabled": True} for i in range(7)}
            
            # Override with user settings where available
            for a in avail:
                # Handle start/end time with minute precision (store as hour + minute/60.0)
                try:
                    s_parts = a.start_time.split(":")
                    e_parts = a.end_time.split(":")
                    
                    h_start = int(s_parts[0]) + int(s_parts[1]) / 60.0
                    h_end = int(e_parts[0]) + int(e_parts[1]) / 60.0
                    
                    user_avail[a.day_of_week] = {
                        "start": h_start,
                        "end": h_end,
                        "enabled": bool(a.is_enabled)
                    }
                except:
                    continue
                    
            db_slots = db.query(models.BusySlot).filter(models.BusySlot.user_id == current_user.id).all()
            busy_slots = []
            for s in db_slots:
                st = s.start_time if s.start_time.tzinfo else s.start_time
                et = s.end_time if s.end_time.tzinfo else s.end_time
                busy_slots.append({
                    "start": st,
                    "end": et,
                    "summary": s.summary,
                    "is_external": bool(s.is_external)
                })
            
            # Добавляем встречи созданные в приложении как занятые слоты
            meeting_invites = db.query(models.MeetingInvite).filter(
                models.MeetingInvite.user_id == current_user.id,
                models.MeetingInvite.status.in_(["accepted", "pending"])
            ).all()
            for mi in meeting_invites:
                m = mi.meeting
                if m:
                    st = m.start_time if m.start_time.tzinfo else m.start_time
                    et = m.end_time if m.end_time.tzinfo else m.end_time
                    busy_slots.append({
                        "start": st,
                        "end": et,
                        "summary": m.title,
                        "is_external": False
                    })

            print(f"DEBUG SOLO: {len(db_slots)} synced slots + {len(meeting_invites)} meeting invites for user {current_user.id}")
            # We use find_common_free_slots for a single user
            segments = find_common_free_slots(
                [busy_slots], 
                start_date, 
                end_date, 
                [user_avail],
                user_timezones=[user_tz_name],
                viewer_tz=user_tz_name,
                requesting_user_index=0,
                user_ids=[str(current_user.id)]
            )
            
            return segments
        except HTTPException:
            raise
        except Exception as e:
            import traceback
            print(f"ERROR in get_solo_scheduler: {str(e)}")
            print(traceback.format_exc())
            raise HTTPException(status_code=500, detail=f"Solo scheduler error: {str(e)}")

@app.post("/api/busy-slots")
async def add_busy_slot(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Creates a personal busy slot manualy from the app."""
    try:
        start_time = parse_ms_datetime(data["start"])
        end_time = parse_ms_datetime(data["end"])
        
        # Check if identical slot already exists
        exists = db.query(models.BusySlot).filter_by(
            user_id=current_user.id,
            start_time=start_time,
            end_time=end_time
        ).first()
        
        if not exists:
            new_slot = models.BusySlot(
                user_id=current_user.id,
                connection_id=None, # Manual entry
                start_time=start_time,
                end_time=end_time
            )
            db.add(new_slot)
            db.commit()
            print(f"DEBUG: Created manual busy slot for user {current_user.id}")
            
        return {"status": "success"}
    except Exception as e:
        print(f"ERROR adding busy slot: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to add slot: {str(e)}")

@app.delete("/api/busy-slots")
async def delete_busy_slot(start: str, end: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Deletes personal busy slots within a time range."""
    try:
        start_time = parse_ms_datetime(start)
        end_time = parse_ms_datetime(end)
        
        # Delete only manual slots (connection_id is NULL) or any slot in this range?
        # User wants to "free" time, so we delete slots that START precisely here
        deleted = db.query(models.BusySlot).filter(
            models.BusySlot.user_id == current_user.id,
            models.BusySlot.start_time == start_time,
            models.BusySlot.end_time == end_time
        ).delete()
        
        db.commit()
        print(f"DEBUG: Deleted {deleted} busy slots for user {current_user.id}")
        return {"status": "success", "count": deleted}
    except Exception as e:
        print(f"ERROR deleting busy slot: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to delete slot: {str(e)}")

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
        # Ensure naive UTC datetimes (strip tzinfo if present) before adding Z
        s_time = m.start_time if m.start_time.tzinfo else m.start_time
        e_time = m.end_time if m.end_time.tzinfo else m.end_time
        result.append({
            "id": m.id,
            "title": m.title,
            "start": s_time.isoformat().replace('+00:00', '') + "Z",
            "end": e_time.isoformat().replace('+00:00', '') + "Z",
            "location": m.location,
            "group_id": m.group_id,
            "group_title": m.group.title if m.group else None,
            "is_creator": m.user_id == current_user.id,
            "is_cancelled": bool(m.is_cancelled),
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
        
    # If moving from accepted to declined, clean up external calendars
    if status == "declined" and invite.status == "accepted":
        for conn in current_user.connections:
            if not conn.is_active: continue
            try:
                from encryption import decrypt_token
                if conn.provider == 'google' and invite.google_event_id:
                    from calendar_service import GoogleCalendarService
                    g_service = GoogleCalendarService(decrypt_token(conn.auth_data))
                    await g_service.delete_event(invite.google_event_id)
                    invite.google_event_id = None
                elif conn.provider == 'outlook' and invite.outlook_event_id:
                    from outlook_service import OutlookCalendarService
                    o_service = OutlookCalendarService(decrypt_token(conn.auth_data))
                    await o_service.delete_event(invite.outlook_event_id)
                    invite.outlook_event_id = None
                elif conn.provider == 'apple' and invite.apple_event_id:
                    from caldav_service import AppleCalendarService
                    import json
                    apple_data = json.loads(decrypt_token(conn.auth_data))
                    a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                    a_service.delete_event(invite.apple_event_id)
                    invite.apple_event_id = None
            except Exception as e:
                print(f"DEBUG: Failed to cleanup declined meeting on {conn.provider}: {e}")

    invite.status = status
    
    # If accepted, try to add to Google/Apple Calendar
    if status == "accepted":
        meeting = invite.meeting
        for conn in current_user.connections:
            if not conn.is_active: continue
            if conn.provider == 'google' and not invite.google_event_id:
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
                        location=meeting.location,
                        description=meeting.description
                    )
                    invite.google_event_id = g_event.get('id')
                except Exception as e:
                    print(f"DEBUG: Failed to sync accepted meeting to Google: {e}")
            elif conn.provider == 'outlook' and not invite.outlook_event_id:
                try:
                    from outlook_service import OutlookCalendarService
                    from encryption import decrypt_token
                    refresh_token = decrypt_token(conn.auth_data)
                    o_service = OutlookCalendarService(refresh_token)
                    o_event = await o_service.create_event(
                        meeting.title, 
                        meeting.start_time, 
                        meeting.end_time,
                        location=meeting.location,
                        description=meeting.description
                    )
                    invite.outlook_event_id = o_event.get('id')
                except Exception as e:
                    print(f"DEBUG: Failed to sync accepted meeting to Outlook: {e}")
            elif conn.provider == 'apple' and not invite.apple_event_id:
                try:
                    from caldav_service import AppleCalendarService
                    from encryption import decrypt_token
                    import json
                    apple_data = json.loads(decrypt_token(conn.auth_data))
                    a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                    # Store the URL as the unique ID
                    apple_event_id = a_service.create_event(
                        meeting.title, 
                        meeting.start_time, 
                        meeting.end_time,
                        location=meeting.location
                    )
                    invite.apple_event_id = str(apple_event_id)
                except Exception as e:
                    print(f"DEBUG: Failed to sync accepted meeting to Apple: {e}")
            
    db.commit()
    return {"status": "success"}

@app.delete("/api/meetings/{meeting_id}")
async def delete_meeting(meeting_id: int, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Handles both soft-cancellation and final removal of meetings."""
    meeting = db.query(models.GroupMeeting).filter(models.GroupMeeting.id == meeting_id).first()
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
        
    is_creator = (meeting.user_id == current_user.id)
    invite = db.query(models.MeetingInvite).filter(
        models.MeetingInvite.meeting_id == meeting_id,
        models.MeetingInvite.user_id == current_user.id
    ).first()

    # Case 1: Creator is cancelling or deleting
    if is_creator:
        if not meeting.is_cancelled:
            # First time: Soft-cancel for everyone
            meeting.is_cancelled = True
            db.query(models.MeetingInvite).filter(models.MeetingInvite.meeting_id == meeting_id).update({"status": "cancelled"})
            
            # Creator's own BusySlot cleanup (creator also has a BusySlot)
            db.query(models.BusySlot).filter(
                models.BusySlot.user_id == current_user.id,
                models.BusySlot.start_time == meeting.start_time,
                models.BusySlot.end_time == meeting.end_time
            ).delete(synchronize_session=False)
            
            # Creator's own external cleanup
            for conn in current_user.connections:
                if not conn.is_active: continue
                try:
                    from encryption import decrypt_token
                    refresh_token = decrypt_token(conn.auth_data)
                    
                    # 1. Cleanup via Meeting ID
                    # 1. Cleanup via Meeting ID
                    if conn.provider == 'google' and meeting.google_event_id:
                        from calendar_service import GoogleCalendarService
                        g_service = GoogleCalendarService(refresh_token)
                        # Ensure we try to delete from ALL calendars if primary fails, 
                        # but start with primary and the stored ID.
                        deleted_ok = await g_service.delete_event(meeting.google_event_id)
                        if not deleted_ok:
                            print(f"DEBUG: Failed to delete Google event {meeting.google_event_id} from primary, trying to find it in other calendars...")
                            # Optional: fetch calendar list and try each. But delete_event already has a flaw.
                        meeting.google_event_id = None
                    elif conn.provider == 'outlook' and meeting.outlook_event_id:
                        from outlook_service import OutlookCalendarService
                        o_service = OutlookCalendarService(refresh_token)
                        await o_service.delete_event(meeting.outlook_event_id)
                        meeting.outlook_event_id = None
                        
                    # 2. ALSO Cleanup via Invite ID (creator also has an invite)
                    if invite:
                        if conn.provider == 'google' and invite.google_event_id:
                            from calendar_service import GoogleCalendarService
                            g_service = GoogleCalendarService(refresh_token)
                            await g_service.delete_event(invite.google_event_id)
                            invite.google_event_id = None
                        elif conn.provider == 'outlook' and invite.outlook_event_id:
                            from outlook_service import OutlookCalendarService
                            o_service = OutlookCalendarService(refresh_token)
                            await o_service.delete_event(invite.outlook_event_id)
                            invite.outlook_event_id = None
                    
                    # 3. Apple Cleanup
                    if conn.provider == 'apple':
                        from caldav_service import AppleCalendarService
                        import json
                        apple_data = json.loads(decrypt_token(conn.auth_data))
                        a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                        if meeting.apple_event_id:
                            a_service.delete_event(meeting.apple_event_id)
                            meeting.apple_event_id = None
                        if invite and invite.apple_event_id:
                            a_service.delete_event(invite.apple_event_id)
                            invite.apple_event_id = None
                except Exception as e: 
                    print(f"DEBUG: Creator cleanup fail on {conn.provider}: {e}")
            
            # NOTIFY GROUP AND PARTICIPANTS
            user_tz_name = current_user.timezone or "UTC"
            try:
                user_tz = ZoneInfo(user_tz_name)
                if meeting.start_time.tzinfo is None:
                    utc_time = meeting.start_time.replace(tzinfo=ZoneInfo("UTC"))
                else:
                    utc_time = meeting.start_time
                display_time = utc_time.astimezone(user_tz).strftime('%d.%m %H:%M')
            except Exception as e:
                print(f"DEBUG: Notify time format fail: {e}")
                display_time = meeting.start_time.strftime('%d.%m %H:%M')
            
            creator_name = current_user.first_name or current_user.username or "Создатель"
            
            # Send group notification
            if meeting.group and meeting.group.telegram_chat_id:
                group_text = f"❌ *Встреча отменена*\n\n👤 {creator_name} отменил встречу: *{meeting.title}*\n⏰ Время: {display_time} ({user_tz_name})\n\n*(Участникам отправлены уведомления для очистки личных календарей)*"
                background_tasks.add_task(send_telegram_notification, meeting.group.telegram_chat_id, group_text)

            # Send individual participant notifications
            for inv in meeting.invites:
                if inv.user_id != current_user.id and inv.user and inv.user.telegram_id:
                    dm_text = (
                        f"❌ *Встреча отменена*\n\n"
                        f"{creator_name} отменил встречу *{meeting.title}* ({display_time}).\n\n"
                        f"Вы можете оставить эту встречу в своём календаре или удалить её через приложение."
                    )
                    background_tasks.add_task(send_telegram_notification, str(inv.user.telegram_id), dm_text)
            
            db.commit()
            return {"status": "cancelled", "message": "Meeting cancelled for all"}
        else:
            # Second time (or confirm): Hard delete for everyone
            # Ensure BusySlots are also purged just in case (e.g. if they weren't caught during soft cancel)
            participant_ids = [invite.user_id for invite in meeting.invites]
            participant_ids.append(meeting.user_id)
            db.query(models.BusySlot).filter(
                models.BusySlot.user_id.in_(participant_ids),
                models.BusySlot.start_time == meeting.start_time,
                models.BusySlot.end_time == meeting.end_time
            ).delete(synchronize_session=False)

            db.delete(meeting)
            db.commit()
            return {"status": "deleted", "message": "Meeting fully removed"}

    # Case 2: Participant is leaving or performing a full cleanup of a cancelled meeting
    if invite:
        if meeting.is_cancelled:
            # If the meeting is already cancelled by the creator, doing "Delete"
            # should trigger both BusySlot purge AND external calendar cleanup immediately.
            
            # 1. Atomic BusySlot cleanup for this participant
            db.query(models.BusySlot).filter(
                models.BusySlot.user_id == current_user.id,
                models.BusySlot.start_time == meeting.start_time,
                models.BusySlot.end_time == meeting.end_time
            ).delete(synchronize_session=False)

            # 2. External cleanup
            for conn in current_user.connections:
                if not conn.is_active: continue
                try:
                    from encryption import decrypt_token
                    refresh_token = decrypt_token(conn.auth_data)
                    if conn.provider == 'google' and invite.google_event_id:
                        from calendar_service import GoogleCalendarService
                        g_service = GoogleCalendarService(refresh_token)
                        await g_service.delete_event(invite.google_event_id)
                        invite.google_event_id = None
                    elif conn.provider == 'outlook' and invite.outlook_event_id:
                        from outlook_service import OutlookCalendarService
                        o_service = OutlookCalendarService(refresh_token)
                        await o_service.delete_event(invite.outlook_event_id)
                        invite.outlook_event_id = None
                    elif conn.provider == 'apple' and invite.apple_event_id:
                        from caldav_service import AppleCalendarService
                        import json
                        apple_data = json.loads(decrypt_token(conn.auth_data))
                        a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                        a_service.delete_event(invite.apple_event_id)
                        invite.apple_event_id = None
                except Exception as e:
                    print(f"DEBUG: Participant cleanup fail on {conn.provider}: {e}")

            # 3. Mark invite as fully cancelled/removed (status for UI logic)
            invite.status = "declined" # Or a specific "removed" status
            db.commit()
            return {"status": "deleted", "message": "Meeting removed from your calendars"}

        if invite.status != "cancelled":
            # First time for an ACTIVE meeting: Participant-side soft cancel
            invite.status = "cancelled"
            
            # Atomic BusySlot cleanup for this participant only
            db.query(models.BusySlot).filter(
                models.BusySlot.user_id == current_user.id,
                models.BusySlot.start_time == meeting.start_time,
                models.BusySlot.end_time == meeting.end_time
            ).delete(synchronize_session=False)
            
            db.commit()
            return {"status": "cancelled", "message": "You left the meeting"}
        else:
            # Second time (confirm): Final removal and external cleanup
            for conn in current_user.connections:
                if not conn.is_active: continue
                try:
                    from encryption import decrypt_token
                    refresh_token = decrypt_token(conn.auth_data)
                    if conn.provider == 'google' and invite.google_event_id:
                        from calendar_service import GoogleCalendarService
                        g_service = GoogleCalendarService(refresh_token)
                        await g_service.delete_event(invite.google_event_id)
                    elif conn.provider == 'outlook' and invite.outlook_event_id:
                        from outlook_service import OutlookCalendarService
                        o_service = OutlookCalendarService(refresh_token)
                        await o_service.delete_event(invite.outlook_event_id)
                    elif conn.provider == 'apple' and invite.apple_event_id:
                        from caldav_service import AppleCalendarService
                        import json
                        apple_data = json.loads(decrypt_token(conn.auth_data))
                        a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                        a_service.delete_event(invite.apple_event_id)
                except Exception as e:
                    print(f"DEBUG: Participant cleanup fail on {conn.provider}: {e}")
            
            db.delete(invite)
            db.commit()
            return {"status": "deleted", "message": "Meeting removed from your list"}

    return {"status": "error", "message": "Nothing to delete"}

@app.post("/api/meetings/{meeting_id}/confirm-cancel")
async def confirm_cancel_meeting(meeting_id: int, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Allows a participant to acknowledge a cancellation and cleanup their calendar."""
    return await delete_meeting(meeting_id, background_tasks, current_user, db)

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
        meeting.start_time = datetime.fromisoformat(s_raw).astimezone(ZoneInfo("UTC"))
    if "end" in data: 
        e_raw = data["end"].replace('Z', '+00:00')
        meeting.end_time = datetime.fromisoformat(e_raw).astimezone(ZoneInfo("UTC"))
    
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
            if (await is_user_in_chat(chat_id, current_user.telegram_id)) != "ok":
                 return {"free_slots": [], "debug": "forbidden_not_in_chat"}
            
            # 2. Filter users to only those still in chat
            active_users = []
            for u in users:
                if (await is_user_in_chat(chat_id, u.telegram_id)) == "ok":
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
        start = datetime.now(dt_module.timezone.utc)
        end = start + timedelta(days=30)
        
        busy_slots_per_user = []
        for uid in internal_ids:
            user_busy = db.query(BusySlot).filter(
                BusySlot.user_id == uid,
                BusySlot.end_time >= start,
                BusySlot.start_time <= end
            ).all()
            user_slots = [
                {
                    "start": s.start_time, 
                    "end": s.end_time, 
                    "summary": s.summary, 
                    "is_external": bool(s.is_external)
                } for s in user_busy
            ]
            
            # FIX: Also include GroupMeeting records (app-created meetings) as busy slots
            meeting_invites = db.query(models.MeetingInvite).filter(
                models.MeetingInvite.user_id == uid,
                models.MeetingInvite.status.in_(["accepted", "pending"])
            ).all()
            for mi in meeting_invites:
                m = mi.meeting
                if m and m.start_time >= start and m.end_time <= end:
                    user_slots.append({
                        "start": m.start_time, 
                        "end": m.end_time,
                        "summary": m.title,
                        "is_external": False
                    })
            
            busy_slots_per_user.append(user_slots)
            
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
                    try:
                        s_parts = a.start_time.split(":")
                        e_parts = a.end_time.split(":")
                        
                        h_start = int(s_parts[0]) + int(s_parts[1]) / 60.0
                        h_end = int(e_parts[0]) + int(e_parts[1]) / 60.0
                        
                        u_dict[a.day_of_week] = {"start": h_start, "end": h_end, "enabled": bool(a.is_enabled)}
                    except:
                        u_dict[a.day_of_week] = {"start": 9, "end": 18, "enabled": True}
            user_availabilities.append(u_dict)

        # 5. Find intersections
        from calendar_service import find_common_free_slots
        
        user_timezones = [u.timezone or "UTC" for u in users]
        snap_to_local = not bool(chat_id)
        
        # Use explicit timezone from body if present, fallback to current_user
        viewer_tz = data.get("timezone") or current_user.timezone or "UTC"

        print(f"DEBUG: Finding slots | Group: {bool(chat_id)} | Snap: {snap_to_local}")
        
        free_windows = find_common_free_slots(
            busy_slots_per_user,
            start_date=start,
            end_date=end,
            user_availabilities=user_availabilities,
            user_timezones=user_timezones,
            viewer_tz=viewer_tz,
            snap_to_local=snap_to_local,
            requesting_user_index=requesting_user_index,
            user_ids=[str(u.telegram_id) for u in users]
        )
        
        print(f"DEBUG: Found {len(free_windows)} free windows")
        return {"free_slots": free_windows}
        
    except Exception as e:
        import traceback
        print(f"ERROR in get_free_slots: {str(e)}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

# Removed insecure /users endpoint due to data leak concerns.
# Use group-specific member endpoints instead.

@app.post("/meeting/create")
async def create_meeting(data: dict, background_tasks: BackgroundTasks, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Creates a meeting in both Google and Apple calendars if connected."""
    summary = data.get("title", "Smart Scheduler Meeting")
    start_str = data.get("start")
    end_str = data.get("end")
    location = data.get("location", "")
    description = data.get("description", "")
    idempotency_key = data.get("idempotency_key")
    attendee_emails = data.get("attendee_emails", [])
    meeting_type = data.get("meeting_type", "online")  # 'online' or 'offline'
    # FIX: extract invited participants and chat id from payload
    invited_telegram_ids = data.get("invited_telegram_ids", [])
    chat_id_from_payload = data.get("chat_id")  # explicit chat_id sent by frontend
    
    if not start_str or not end_str:
        raise HTTPException(status_code=400, detail="Start and End times are required")
        
    try:
        # Robust UTC parsing: handle Z and offsets, convert to UTC, then store as naive
        s_raw = str(start_str).replace('Z', '+00:00')
        e_raw = str(end_str).replace('Z', '+00:00')
        start_time = datetime.fromisoformat(s_raw).astimezone(ZoneInfo("UTC"))
        end_time = datetime.fromisoformat(e_raw).astimezone(ZoneInfo("UTC"))
    except Exception as e:
        print(f"DEBUG: Error parsing dates {start_str}/{end_str}: {e}")
        raise HTTPException(status_code=400, detail=f"Invalid date format: {e}")
    
    tz_offset_hours = data.get("tz_offset", 0.0)

    # 3. Working Hours Boundary Check
    # Validate that the meeting falls within the requesting user's working hours
    start_local = start_time + timedelta(hours=tz_offset_hours)
    end_local = end_time + timedelta(hours=tz_offset_hours)
    
    u_avail = db.query(models.UserAvailability).filter(
        models.UserAvailability.user_id == current_user.id,
        models.UserAvailability.day_of_week == start_local.weekday()
    ).first()
    
    # Use defaults if not found, same as the heatmap grid logic
    if u_avail:
        is_enabled = u_avail.is_enabled
        try:
            u_h_start = int(u_avail.start_time.split(":")[0])
            u_h_end = int(u_avail.end_time.split(":")[0])
            u_m_end = int(u_avail.end_time.split(":")[1])
        except:
            u_h_start, u_h_end, u_m_end = 9, 18, 0
    else:
        is_enabled = True
        u_h_start, u_h_end, u_m_end = 9, 18, 0
        
    if is_enabled:
        h_start = start_local.hour
        h_end = end_local.hour
        m_end = end_local.minute
        
        if h_end == 0 and m_end == 0 and start_local.date() != end_local.date():
            h_end = 24
            
        if h_start < u_h_start or h_end > u_h_end or (h_end == u_h_end and m_end > u_m_end):
            print(f"DEBUG: Booking outside working hours: {h_start}:00 to {h_end}:{m_end} (Working from {u_h_start}:00 to {u_h_end}:{u_m_end})")
            raise HTTPException(status_code=400, detail="outside_working_hours")
    else:
        # If explicitly disabled, assume non-working day
        print(f"DEBUG: Booking on disabled availability: {start_local.weekday()}")
        raise HTTPException(status_code=400, detail="outside_working_hours")

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
        # If the conflict is with another GroupMeeting, we strictly block it.
        # But if it's only a BusySlot (external sync), we allow it - the user might want to double-book their own calendar.
        if isinstance(conflict, models.GroupMeeting):
            print(f"DEBUG: Conflict detected for user {current_user.id} at {start_time} (Existing GroupMeeting)")
            raise HTTPException(status_code=409, detail="Time slot already booked in this app")
        else:
            print(f"DEBUG: Soft conflict with external BusySlot for user {current_user.id} at {start_time}. Allowing.")

    results = {}
    google_event_id = None
    outlook_event_id = None
    apple_event_id = None
    
    for conn in current_user.connections:
        if not conn.is_active: continue
        
        # 1. Google
        if conn.provider == 'google':
            try:
                refresh_token = decrypt_token(conn.auth_data)
                g_service = GoogleCalendarService(refresh_token)
                g_event = await g_service.create_event(summary, start_time, end_time, attendees=attendee_emails, location=location, meeting_type=meeting_type, description=description)
                # create_event returns the event ID string directly (not a dict)
                google_event_id = g_event  # g_event is already the string ID
                results[f"google_{conn.id}"] = "success"
                conn.last_sync_status = "success"
                conn.last_sync_at = datetime.now(timezone.utc)
            except Exception as e:
                results[f"google_{conn.id}"] = f"error: {str(e)}"
                conn.last_sync_at = datetime.now(timezone.utc)
                if "401" in str(e): conn.last_sync_status = "401_unauthorized"
                else: conn.last_sync_status = "500_api_error"
                
        # 2. Apple
        elif conn.provider == 'apple':
            try:
                apple_data = json.loads(decrypt_token(conn.auth_data))
                a_service = AppleCalendarService(apple_data['email'], apple_data['password'])
                apple_event_id = a_service.create_event(summary, start_time, end_time, location)
                # Store the event URL as ID
                apple_event_id = str(apple_event_id)
                results[f"apple_{conn.id}"] = "success"
                conn.last_sync_status = "success"
                conn.last_sync_at = datetime.now(timezone.utc)
            except Exception as e:
                results[f"apple_{conn.id}"] = f"error: {str(e)}"
                conn.last_sync_at = datetime.now(timezone.utc)
                conn.last_sync_status = "500_api_error"
        elif conn.provider == 'outlook':
            try:
                from outlook_service import OutlookCalendarService
                refresh_token = decrypt_token(conn.auth_data)
                o_service = OutlookCalendarService(refresh_token)
                o_event = await o_service.create_event(
                    summary, start_time, end_time, location, description=description
                )
                outlook_event_id = o_event.get('id')
                results[f"outlook_{conn.id}"] = "success"
                conn.last_sync_status = "success"
                conn.last_sync_at = datetime.now(timezone.utc)
            except Exception as e:
                results[f"outlook_{conn.id}"] = f"error: {str(e)}"
                conn.last_sync_at = datetime.now(timezone.utc)
                if "401" in str(e): conn.last_sync_status = "401_unauthorized"
                else: conn.last_sync_status = "500_api_error"
            
    # Save to our DB history
    # FIX: tg_chat_id and group_id initialized early (in scope for send_notifications)
    group_id = None
    tg_chat_id = None  # this will be used in send_notifications

    # Try to get chat_id from explicit payload first, then from idempotency_key
    if chat_id_from_payload:
        tg_chat_id = str(chat_id_from_payload)
        group = db.query(models.Group).filter(models.Group.telegram_chat_id == tg_chat_id).first()
        if group:
            group_id = group.id
    elif idempotency_key and "group_" in idempotency_key:
        try:
            parts = idempotency_key.split("_")
            if len(parts) >= 2:
                tg_chat_id = parts[1].replace("n", "-")
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
            description=description,
            start_time=start_time,
            end_time=end_time,
            location=location,
            idempotency_key=idempotency_key,
            google_event_id=google_event_id,
            outlook_event_id=outlook_event_id,
            apple_event_id=apple_event_id
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
            google_event_id=google_event_id,
            outlook_event_id=outlook_event_id,
            apple_event_id=apple_event_id
        )
        db.add(creator_invite)
        
        db.commit()
    except Exception as e:
        db.rollback()
        print(f"DEBUG: Failed to insert meeting or invites: {e}")
        raise HTTPException(status_code=500, detail="Database insertion failed")

    # Send Telegram Notification to the Group (fully async, concurrent dispatch)
    async def send_notifications():
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
            bot_username = BOT_USERNAME_FALLBACK
            try:
                async with httpx.AsyncClient(timeout=5) as client:
                    bot_resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getMe")).json()
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
            
            # Group notification: use creator's timezone
            user_tz_name = current_user.timezone or "UTC"
            try:
                from zoneinfo import ZoneInfo
                user_tz = ZoneInfo(user_tz_name)
                from_time = start_time.astimezone(user_tz)
                to_time = end_time.astimezone(user_tz)
                time_str = f"{from_time.strftime('%d.%m.%Y с %H:%M')} до {to_time.strftime('%H:%M')}"
            except Exception as e:
                print(f"DEBUG: Failed to format time with {user_tz_name}: {e}")
                time_str = start_time.strftime("%d.%m %H:%M") # fallback to UTC if fail
            
            # IMPORTANT: StartApp parameter CANNOT contain the minus (-) sign.
            app_chat_id = str(target_chat).replace("-", "n")
            web_app_url = f"https://t.me/{bot_username}/app?startapp=group_{app_chat_id}"

            creator_name = current_user.first_name or current_user.username
            group_text = (
                f"Smart Scheduler\n"
                f"📅 **Новое приглашение на встречу от {creator_name}!**\n\n"
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
            
            async with httpx.AsyncClient(timeout=8) as client:
                # Build list of coroutines: group message + one DM per participant
                tg_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                
                tasks = [
                    client.post(tg_url, json={
                        "chat_id": target_chat,
                        "text": group_text,
                        "parse_mode": "Markdown",
                        "reply_markup": reply_markup
                    })
                ]
                
                for u in invited_users:
                    if u.telegram_id:
                        # Convert meeting time to target user's local timezone
                        try:
                            from zoneinfo import ZoneInfo
                            u_tz_name = u.timezone or "UTC"
                            u_tz = ZoneInfo(u_tz_name)
                            u_from_time = start_time.astimezone(u_tz)
                            u_to_time = end_time.astimezone(u_tz)
                            u_time_str = f"{u_from_time.strftime('%d.%m.%Y с %H:%M')} до {u_to_time.strftime('%H:%M')}"
                        except Exception as e:
                            print(f"DEBUG: Failed to format DM time for user {u.id}: {e}")
                            u_time_str = time_str # Fallback to default (creator's or UTC)
                            
                        tasks.append(
                            client.post(tg_url, json={
                                "chat_id": u.telegram_id,
                                "text": (
                                    f"Smart Scheduler\n"
                                    f"🔔 У вас новое приглашение на встречу!\n\n"
                                    f"👤 От: {creator_name}\n"
                                    f"📍 Тема: {summary}\n"
                                    f"⏰ Время: {u_time_str}\n\n"
                                    f"Откройте приложение, чтобы подтвердить."
                                ),
                                "parse_mode": "Markdown",
                                "reply_markup": reply_markup
                            })
                        )
                
                # Fire all messages concurrently — group + all DMs at once
                results_tg = await asyncio.gather(*tasks, return_exceptions=True)
                
                for i, r in enumerate(results_tg):
                    if isinstance(r, Exception):
                        print(f"DEBUG: Notification task {i} failed: {r}")
                    else:
                        print(f"DEBUG: Notification task {i} → HTTP {r.status_code}")
                 
        except Exception as e:
            print(f"DEBUG: Error during Telegram notification: {e}")

    # Use FastAPI BackgroundTasks to make it non-blocking
    background_tasks.add_task(send_notifications)
    
    return {"status": "success", "results": results, "id": new_meeting.id}

@app.post("/meeting/finalize")
async def finalize_meeting(data: dict, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
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
            "url": f"https://t.me/{BOT_USERNAME_FALLBACK}/app?startapp=group_{clean_param}&v={timestamp}"
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
            async with httpx.AsyncClient(timeout=3) as client:
                edit_resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={
                    "chat_id": target_chat,
                    "message_id": int(group.last_invite_message_id),
                    "text": new_text,
                    "parse_mode": "Markdown",
                    "reply_markup": json.dumps(reply_markup)
                })).json()
            
            if edit_resp.get("ok"):
                print("DEBUG: Successfully edited existing invitation message.")
                return {"status": "success", "action": "edited", "tg_response": edit_resp}
            else:
                print(f"DEBUG: Edit failed ({edit_resp.get('description')}), falling back to SENDING NEW message.")

        # 2. Fallback: Send a NEW message to the group
        async with httpx.AsyncClient(timeout=3) as client:
            send_resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json={
                "chat_id": target_chat,
                "text": new_text,
                "parse_mode": "Markdown",
                "reply_markup": json.dumps(reply_markup)
            })).json()
        
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
