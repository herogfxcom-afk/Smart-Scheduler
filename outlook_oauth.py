from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import User, CalendarConnection
from auth import get_current_user
import os

router = APIRouter(prefix="/auth/outlook", tags=["auth"])

@router.get("/login")
async def outlook_login():
    """Generates the Microsoft OAuth login URL."""
    client_id = os.getenv("MICROSOFT_CLIENT_ID")
    redirect_uri = os.getenv("MICROSOFT_REDIRECT_URI")
    scope = "https://graph.microsoft.com/Calendars.Read offline_access"
    
    if not client_id or not redirect_uri:
        return {"error": "Microsoft OAuth not configured"}

    url = (
        f"https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        f"?client_id={client_id}"
        f"&response_type=code"
        f"&redirect_uri={redirect_uri}"
        f"&response_mode=query"
        f"&scope={scope}"
    )
    return {"url": url}

# Callback would go here, similar to Google
