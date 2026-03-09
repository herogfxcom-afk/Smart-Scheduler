import os
import httpx
from urllib.parse import urlencode
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse, HTMLResponse
from sqlalchemy.orm import Session
from database import get_db
from auth import get_current_user
from models import User
from encryption import encrypt_token
from dotenv import load_dotenv

load_dotenv()

router = APIRouter(prefix="/auth/google", tags=["google_oauth"])

# Google OAuth2 Config
CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET")
REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI")

SCOPES = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/calendar.readonly',
    'openid',
    'email',
    'profile'
]

@router.get("/url")
async def get_google_auth_url(current_user: User = Depends(get_current_user)):
    """Returns the Google OAuth2 authorization URL."""
    # Debug logging to identify why Google might see client_id as None
    client_id = os.getenv("GOOGLE_CLIENT_ID")
    redirect_uri = os.getenv("GOOGLE_REDIRECT_URI")
    print(f"DEBUG GOOGLE OAUTH: Fetching URL for user {current_user.id}")
    print(f"DEBUG GOOGLE OAUTH: CLIENT_ID starts with: {str(client_id)[:10]}... (len: {len(str(client_id)) if client_id else 0})")
    print(f"DEBUG GOOGLE OAUTH: REDIRECT_URI: {redirect_uri}")

    base_url = "https://accounts.google.com/o/oauth2/v2/auth"
    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "include_granted_scopes": "true",
        "state": str(current_user.telegram_id),
        "prompt": "select_account consent"  # Force account selector and ensure refresh token
    }
    auth_url = f"{base_url}?{urlencode(params)}"
    return {"url": auth_url}

@router.get("/callback")
async def google_oauth_callback(code: str, state: str, db: Session = Depends(get_db)):
    """Handles the Google OAuth2 callback and stores tokens."""
    token_url = "https://oauth2.googleapis.com/token"
    
    client_id = os.getenv("GOOGLE_CLIENT_ID")
    client_secret = os.getenv("GOOGLE_CLIENT_SECRET")
    redirect_uri = os.getenv("GOOGLE_REDIRECT_URI")
    
    data = {
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(token_url, data=data)
            tokens = response.json()
            
        if "error" in tokens:
            error_msg = tokens.get("error_description", tokens.get("error", "Unknown error"))
            raise HTTPException(status_code=400, detail=f"OAuth error: {error_msg}")
        
        refresh_token = tokens.get("refresh_token")
        telegram_id = int(state)
        user = db.query(User).filter(User.telegram_id == telegram_id).first()
        
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # Encrypt the refresh token before saving
        if refresh_token:
            user.google_refresh_token = encrypt_token(refresh_token)
            
            # Fetch user email
            try:
                user_info_url = "https://www.googleapis.com/oauth2/v3/userinfo"
                headers = {"Authorization": f"Bearer {tokens.get('access_token')}"}
                async with httpx.AsyncClient() as client:
                    info_resp = await client.get(user_info_url, headers=headers)
                    user_info = info_resp.json()
                    user.email = user_info.get("email")
            except Exception as e:
                print(f"Failed to fetch user email: {e}")
                
            db.commit()
            
            # Return success HTML page
            template_path = os.path.join(os.path.dirname(__file__), "templates", "success.html")
            try:
                with open(template_path, "r", encoding="utf-8") as f:
                    html_content = f.read()
                return HTMLResponse(content=html_content)
            except:
                return {"status": "success", "message": "Google account connected. Please return to the app."}
        else:
            return {"status": "error", "message": "No refresh token received. Try revoking access in Google settings and reconnecting."}
            
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=400, detail=f"Callback error: {str(e)}")
