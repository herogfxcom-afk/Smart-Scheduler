import os
import httpx
from datetime import datetime
import pytz

class OutlookCalendarService:
    def __init__(self, refresh_token: str):
        self.client_id = os.getenv("MICROSOFT_CLIENT_ID")
        self.client_secret = os.getenv("MICROSOFT_CLIENT_SECRET")
        self.refresh_token = refresh_token
        self.token_url = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        self.base_url = "https://graph.microsoft.com/v1.0"

    async def _get_access_token(self):
        """Exchange refresh token for a fresh access token."""
        data = {
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "grant_type": "refresh_token",
            "refresh_token": self.refresh_token,
            "scope": "https://graph.microsoft.com/Calendars.Read offline_access"
        }
        async with httpx.AsyncClient() as client:
            resp = await client.post(self.token_url, data=data)
            resp.raise_for_status()
            return resp.json().get("access_token")

    async def get_busy_slots(self, start_time: datetime, end_time: datetime):
        """
        Fetches busy slots from Outlook using the 'getSchedule' API.
        This is a placeholder that will work once credentials are provided.
        """
        if not self.client_id or not self.client_secret:
            print("DEBUG: Outlook credentials missing. Skipping sync.")
            return []

        try:
            access_token = await self._get_access_token()
            headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
            
            # getSchedule endpoint returns availability for a specific period
            payload = {
                "Schedules": ["me"],
                "StartTime": {"dateTime": start_time.isoformat(), "timeZone": "UTC"},
                "EndTime": {"dateTime": end_time.isoformat(), "timeZone": "UTC"},
                "AvailabilityViewInterval": 30 # minutes
            }
            
            async with httpx.AsyncClient() as client:
                resp = await client.post(f"{self.base_url}/me/calendar/getSchedule", headers=headers, json=payload)
                resp.raise_for_status()
                data = resp.json()
                
                busy_slots = []
                for schedule in data.get("value", []):
                    for item in schedule.get("scheduleItems", []):
                        if item.get("status") != "free":
                            busy_slots.append({
                                "start": item["start"]["dateTime"],
                                "end": item["end"]["dateTime"]
                            })
                return busy_slots
        except Exception as e:
            print(f"DEBUG: Outlook sync failed: {e}")
            return []
