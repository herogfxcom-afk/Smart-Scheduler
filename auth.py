import hmac
import hashlib
import json
import os
from urllib.parse import parse_qs
from fastapi import Header, HTTPException, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import User
from dotenv import load_dotenv

load_dotenv()

def validate_init_data(init_data: str) -> dict:
    """Verifies Telegram Web App initData using HMAC-SHA256."""
    current_bot_token = os.getenv("BOT_TOKEN")
    if not current_bot_token:
        print("AUTH ERROR: BOT_TOKEN is missing from environment variables!")
        raise HTTPException(status_code=500, detail="BOT_TOKEN not configured")
    
    try:
        vals = {k: v[0] for k, v in parse_qs(init_data).items()}
        if "hash" not in vals:
            raise HTTPException(status_code=401, detail="Missing hash")
        
        auth_hash = vals.pop("hash")
        # Data-check-string: alphabetical order
        data_check_string = "\n".join([f"{k}={v}" for k, v in sorted(vals.items())])
        
        # secret_key = HMAC_SHA256("WebAppData", bot_token)
        secret_key = hmac.new("WebAppData".encode(), current_bot_token.encode(), hashlib.sha256).digest()
        # hash = HMAC_SHA256(secret_key, data_check_string)
        h = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
        
        if h != auth_hash:
            print(f"AUTH ERROR: Hash mismatch. Expected {auth_hash}, got {h}")
            raise HTTPException(status_code=401, detail="Invalid hash")
            
        # Prevent replay attacks: check auth_date (timestamp)
        import time
        auth_date = int(vals.get("auth_date", 0))
        if time.time() - auth_date > 86400: # 24 hours
            raise HTTPException(status_code=401, detail="InitData expired")
        
        user_data = json.loads(vals.get("user", "{}"))
        return user_data
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Auth error: {str(e)}")

from typing import Optional

def get_current_user(init_data: Optional[str] = Header(None), db: Session = Depends(get_db)):
    """Dependency to get or create user based on Telegram initData."""
    if not init_data:
        raise HTTPException(status_code=401, detail="init-data header missing")
    user_info = validate_init_data(init_data)
    telegram_id = user_info.get("id")
    
    if not telegram_id:
        raise HTTPException(status_code=401, detail="User ID missing in initData")
    
    user = db.query(User).filter(User.telegram_id == telegram_id).first()
    if not user:
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
        # Update user info if changed
        user.username = user_info.get("username")
        user.first_name = user_info.get("first_name")
        user.photo_url = user_info.get("photo_url")
        db.commit()
        
    return user
