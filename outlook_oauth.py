import os
import httpx
from urllib.parse import urlencode
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from database import get_db
from auth import get_current_user
from models import User, CalendarConnection
from encryption import encrypt_token
from dotenv import load_dotenv

load_dotenv()

router = APIRouter(prefix="/auth/outlook", tags=["outlook_oauth"])

TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
AUTH_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
GRAPH_ME_URL = "https://graph.microsoft.com/v1.0/me"

# Scopes: offline_access for refresh token, openid/profile for identity,
# Calendars.Read for reading the user's calendar events.
SCOPES = "offline_access openid profile https://graph.microsoft.com/Calendars.ReadWrite"


@router.get("/url")
async def get_outlook_auth_url(current_user: User = Depends(get_current_user)):
    """Returns the Microsoft OAuth2 authorization URL."""
    client_id = os.getenv("MICROSOFT_CLIENT_ID")
    redirect_uri = os.getenv("MICROSOFT_REDIRECT_URI")

    if not client_id or not redirect_uri:
        raise HTTPException(status_code=500, detail="Microsoft OAuth not configured on server")

    params = {
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "response_mode": "query",
        "scope": SCOPES,
        "state": str(current_user.telegram_id),
        "prompt": "select_account",  # Always show account picker
    }
    url = f"{AUTH_URL}?{urlencode(params)}"
    print(f"DEBUG OUTLOOK OAUTH: URL built for user {current_user.id}, redirect={redirect_uri}")
    return {"url": url}


@router.get("/callback")
async def outlook_oauth_callback(code: str, state: str, db: Session = Depends(get_db)):
    """Handles the Microsoft OAuth2 callback and stores encrypted refresh token."""
    client_id = os.getenv("MICROSOFT_CLIENT_ID")
    client_secret = os.getenv("MICROSOFT_CLIENT_SECRET")
    redirect_uri = os.getenv("MICROSOFT_REDIRECT_URI")

    if not client_id or not client_secret or not redirect_uri:
        raise HTTPException(status_code=500, detail="Microsoft OAuth not configured on server")

    # 1. Exchange authorization code for tokens
    token_data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
        "scope": SCOPES,
    }

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            token_resp = await client.post(TOKEN_URL, data=token_data)
            tokens = token_resp.json()

        if "error" in tokens:
            error_msg = tokens.get("error_description", tokens.get("error", "Unknown error"))
            print(f"DEBUG OUTLOOK OAUTH: Token exchange failed: {error_msg}")
            raise HTTPException(status_code=400, detail=f"OAuth error: {error_msg}")

        refresh_token = tokens.get("refresh_token")
        access_token = tokens.get("access_token")

        if not refresh_token:
            raise HTTPException(
                status_code=400,
                detail="No refresh_token received. Make sure offline_access scope is requested.",
            )

        # 2. Fetch user email from Microsoft Graph
        # Microsoft may return 'mail' OR 'userPrincipalName' depending on account type
        user_email = None
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                me_resp = await client.get(
                    GRAPH_ME_URL,
                    headers={"Authorization": f"Bearer {access_token}"},
                )
                me_data = me_resp.json()
                user_email = me_data.get("mail") or me_data.get("userPrincipalName")
                print(f"DEBUG OUTLOOK OAUTH: Fetched email={user_email}")
        except Exception as e:
            print(f"DEBUG OUTLOOK OAUTH: Failed to fetch user email: {e}")

        # 3. Find the user by telegram_id (passed as OAuth state)
        telegram_id = int(state)
        user = db.query(User).filter(User.telegram_id == telegram_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        # 4. Encrypt and upsert the CalendarConnection
        encrypted_token = encrypt_token(refresh_token)

        conn = db.query(CalendarConnection).filter_by(
            user_id=user.id,
            provider="outlook",
            email=user_email,
        ).first()

        if conn:
            conn.auth_data = encrypted_token
            conn.is_active = 1
            conn.status = "active"
            conn.last_error = None
        else:
            conn = CalendarConnection(
                user_id=user.id,
                provider="outlook",
                email=user_email,
                auth_data=encrypted_token,
                is_active=1,
                status="active",
            )
            db.add(conn)

        db.commit()
        print(f"DEBUG OUTLOOK OAUTH: Saved Outlook connection for user {user.id} ({user_email})")

        # 5. Return success page (same as Google flow)
        template_path = os.path.join(os.path.dirname(__file__), "templates", "success.html")
        try:
            with open(template_path, "r", encoding="utf-8") as f:
                html_content = f.read()
            return HTMLResponse(content=html_content)
        except Exception:
            return {"status": "success", "message": "Outlook account connected. Please return to the app."}

    except HTTPException:
        raise
    except Exception as e:
        print(f"DEBUG OUTLOOK OAUTH: Callback error: {e}")
        raise HTTPException(status_code=400, detail=f"Callback error: {str(e)}")
