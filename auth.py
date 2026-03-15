import hmac
import hashlib
import json
import os
from urllib.parse import parse_qs
from fastapi import Header, HTTPException, Depends
from sqlalchemy.orm import Session, joinedload
from database import get_db
from models import User
from dotenv import load_dotenv

load_dotenv()

def validate_telegram_init_data(init_data: str) -> dict:
    """Verifies Telegram Web App initData using HMAC-SHA256."""
    import sys
    print(f"DEBUG AUTH: validate_telegram_init_data START. Len: {len(init_data)}", flush=True)
    current_bot_token = os.getenv("BOT_TOKEN")
    print(f"DEBUG AUTH: BOT_TOKEN status: {bool(current_bot_token)}", flush=True)
    if not current_bot_token:
        print("DEBUG AUTH: BOT_TOKEN is missing!", flush=True)
        raise HTTPException(status_code=500, detail="BOT_TOKEN not configured")
    
    try:
        print("DEBUG AUTH: Beginning parse_qs...", flush=True)
        vals = {k: v[0] for k, v in parse_qs(init_data).items()}
        print(f"DEBUG AUTH: vals keys: {list(vals.keys())}", flush=True)
        
        if "hash" not in vals:
            print("DEBUG AUTH: Hash missing from init_data", flush=True)
            raise HTTPException(status_code=403, detail="Missing hash")
        
        auth_hash = vals.pop("hash")
        data_check_string = "\n".join([f"{k}={v}" for k, v in sorted(vals.items())])
        
        print("DEBUG AUTH: Computing HMAC...", flush=True)
        secret_key = hmac.new("WebAppData".encode(), current_bot_token.encode(), hashlib.sha256).digest()
        print("DEBUG AUTH: secret_key computed", flush=True)
        h = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
        print(f"DEBUG AUTH: HMAC computed: {h[:5]}...", flush=True)
        
        if h != auth_hash:
            print(f"DEBUG AUTH: Hash mismatch! Expected {auth_hash}, got {h}", flush=True)
            raise HTTPException(status_code=403, detail="Invalid hash")
            
        import time
        auth_date = int(vals.get("auth_date", 0))
        print(f"DEBUG AUTH: auth_date: {auth_date}, current: {time.time()}", flush=True)
        if time.time() - auth_date > 86400:
            print("DEBUG AUTH: init_data expired", flush=True)
            raise HTTPException(status_code=403, detail="InitData expired")
        
        print("DEBUG AUTH: Parsing user JSON...", flush=True)
        user_raw = vals.get("user", "{}")
        print(f"DEBUG AUTH: user_raw: {user_raw[:50]}...", flush=True)
        user_data = json.loads(user_raw)
        print("DEBUG AUTH: validate_telegram_init_data successful", flush=True)
        return user_data
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"DEBUG AUTH CRASH in validate_telegram_init_data: {str(e)}", flush=True)
        print(traceback.format_exc(), flush=True)
        raise HTTPException(status_code=403, detail=f"Auth error: {str(e)}")

from typing import Optional

from database import SessionLocal

def get_current_user(init_data: Optional[str] = Header(None)):
    """Dependency to get or create user based on Telegram initData."""
    print(f"AUTH: get_current_user called. InitData present: {bool(init_data)}", flush=True)
    bot_token_val = os.getenv("BOT_TOKEN")
    print(f"AUTH: BOT_TOKEN present: {bool(bot_token_val)} (len: {len(bot_token_val) if bot_token_val else 0})", flush=True)
    
    if not init_data:
        raise HTTPException(status_code=403, detail="init-data header missing")
        
    user_info = validate_telegram_init_data(init_data)
    telegram_id = user_info.get("id")
    
    if not telegram_id:
        raise HTTPException(status_code=401, detail="User ID missing in initData")
    
    print(f"AUTH: Success extracting ID {telegram_id}. Connecting to DB...")
    
    with SessionLocal() as db:
        try:
            db.rollback() # Self-healing for poisoned connections
            print(f"AUTH: Querying DB for telegram_id={telegram_id}")
            user = db.query(User).options(joinedload(User.connections)).filter(User.telegram_id == telegram_id).first()
            if not user:
                print("AUTH: Creating new user record")
                user = User(
                    telegram_id=telegram_id,
                    username=user_info.get("username"),
                    first_name=user_info.get("first_name"),
                    photo_url=user_info.get("photo_url")
                )
                db.add(user)
                db.commit()
                db.refresh(user)
            else:
                print(f"AUTH: Updating existing user {user.id}")
                user.username = user_info.get("username")
                user.first_name = user_info.get("first_name")
                user.photo_url = user_info.get("photo_url")
                db.commit()
                # Reload to ensure joinedload is handled correctly
                user = db.query(User).options(joinedload(User.connections)).filter(User.telegram_id == telegram_id).first()
                
            db.expunge(user)
            print("AUTH: get_current_user returning user object")
            return user
        except Exception as e:
            print(f"AUTH: DB Operation failed: {str(e)}")
            db.rollback()
            raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
