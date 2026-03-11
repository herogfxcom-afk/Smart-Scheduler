import os
import httpx
from datetime import datetime

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
            "scope": "offline_access openid profile https://graph.microsoft.com/Calendars.Read",
        }
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(self.token_url, data=data)
            resp.raise_for_status()
            return resp.json().get("access_token")

    async def get_busy_slots(self, start_time: datetime, end_time: datetime):
        """
        Fetches busy calendar events from Outlook using the calendarView API.
        This is the correct approach — getSchedule requires an email address
        and doesn't work with 'me' as a schedule identifier.
        """
        if not self.client_id or not self.client_secret:
            print("DEBUG: Outlook credentials missing. Skipping sync.")
            return []

        try:
            access_token = await self._get_access_token()
            if not access_token:
                print("DEBUG: Outlook — failed to get access token.")
                return []

            headers = {
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
                "Prefer": 'outlook.timezone="UTC"',
            }

            # Format datetimes as ISO 8601 strings required by Microsoft Graph
            start_str = start_time.strftime("%Y-%m-%dT%H:%M:%S")
            end_str = end_time.strftime("%Y-%m-%dT%H:%M:%S")

            # /me/calendarView returns all calendar events in the given range.
            # This is simpler and more reliable than getSchedule.
            params = {
                "startDateTime": start_str,
                "endDateTime": end_str,
                "$select": "subject,start,end,showAs,isAllDay",
                "$top": 100,
            }

            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.get(
                    f"{self.base_url}/me/calendarView",
                    headers=headers,
                    params=params,
                )
                resp.raise_for_status()
                data = resp.json()

            busy_slots = []
            for event in data.get("value", []):
                # Skip events marked as free (e.g. tentative/OOF/busy)
                show_as = event.get("showAs", "busy")
                if show_as == "free":
                    continue

                # Skip all-day events to avoid blocking the entire day
                if event.get("isAllDay", False):
                    continue

                start_dt = event.get("start", {}).get("dateTime")
                end_dt = event.get("end", {}).get("dateTime")

                if start_dt and end_dt:
                    # Ensure UTC 'Z' suffix so the caller can parse correctly
                    if not start_dt.endswith("Z"):
                        start_dt += "Z"
                    if not end_dt.endswith("Z"):
                        end_dt += "Z"
                    busy_slots.append({"start": start_dt, "end": end_dt})

            print(f"DEBUG: Outlook sync returned {len(busy_slots)} busy slots.")
            return busy_slots

        except Exception as e:
            print(f"DEBUG: Outlook sync failed: {e}")
            return []
