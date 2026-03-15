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
    current_bot_token = os.getenv("BOT_TOKEN")
    if not current_bot_token:
        print("AUTH: BOT_TOKEN is missing!")
        raise HTTPException(status_code=500, detail="BOT_TOKEN not configured")
    
    try:
        print("AUTH: Beginning validation...")
        vals = {k: v[0] for k, v in parse_qs(init_data).items()}
        if "hash" not in vals:
            print("AUTH: Hash missing from init_data")
            raise HTTPException(status_code=403, detail="Missing hash")
        
        auth_hash = vals.pop("hash")
        data_check_string = "\n".join([f"{k}={v}" for k, v in sorted(vals.items())])
        
        print("AUTH: Computing HMAC...")
        secret_key = hmac.new("WebAppData".encode(), current_bot_token.encode(), hashlib.sha256).digest()
        h = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
        
        if h != auth_hash:
            print(f"AUTH: Hash mismatch! Expected {auth_hash}, got {h}")
            raise HTTPException(status_code=403, detail="Invalid hash")
            
        import time
        auth_date = int(vals.get("auth_date", 0))
        if time.time() - auth_date > 86400:
            print("AUTH: init_data expired")
            raise HTTPException(status_code=403, detail="InitData expired")
        
        print("AUTH: Validation successful, parsing user JSON...")
        user_data = json.loads(vals.get("user", "{}"))
        return user_data
    except HTTPException:
        raise
    except Exception as e:
        print(f"AUTH: Validation exception: {str(e)}")
        raise HTTPException(status_code=403, detail=f"Auth error: {str(e)}")

from typing import Optional

from database import SessionLocal

def get_current_user(init_data: Optional[str] = Header(None)):
    """Dependency to get or create user based on Telegram initData."""
    print(f"AUTH: get_current_user called. InitData present: {bool(init_data)}")
    
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
