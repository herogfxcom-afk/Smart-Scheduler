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
            # Scope is intentionally omitted. Microsoft usually issues the new 
            # token with all previously granted scopes if omitted.
        }
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(self.token_url, data=data)
            if resp.status_code != 200:
                print(f"DEBUG: Token refresh failed: {resp.status_code} - {resp.text}")
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

            print(f"DEBUG OUTLOOK: Fetching {start_str} to {end_str}")

            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.get(
                    f"{self.base_url}/me/calendarView",
                    headers=headers,
                    params=params,
                )
                if resp.status_code != 200:
                     print(f"DEBUG OUTLOOK ERROR: {resp.status_code} - {resp.text}")
                resp.raise_for_status()
                data = resp.json()

            busy_slots = []
            events = data.get("value", [])
            print(f"DEBUG OUTLOOK: Got {len(events)} events from API")
            
            for event in events:
                subject = event.get("subject", "No Subject")
                # Skip events marked as free (e.g. tentative/OOF/busy)
                show_as = event.get("showAs", "busy")
                if show_as == "free":
                    print(f"DEBUG OUTLOOK: Skipping {subject} because showAs=free")
                    continue

                # Skip all-day events to avoid blocking the entire day
                if event.get("isAllDay", False):
                    print(f"DEBUG OUTLOOK: Skipping {subject} because isAllDay=True")
                    continue

                start_dt = event.get("start", {}).get("dateTime")
                end_dt = event.get("end", {}).get("dateTime")

                if start_dt and end_dt:
                    print(f"DEBUG OUTLOOK: Keeping {subject} | {start_dt} -> {end_dt}")
                    # Ensure UTC 'Z' suffix so the caller can parse correctly
                    if not start_dt.endswith("Z"):
                        start_dt += "Z"
                    if not end_dt.endswith("Z"):
                        end_dt += "Z"
                    busy_slots.append({"start": start_dt, "end": end_dt})
                else:
                    print(f"DEBUG OUTLOOK: Missing dateTime for {subject}")

            print(f"DEBUG OUTLOOK: Sync returned {len(busy_slots)} busy slots after filtering.")
            return busy_slots

        except Exception as e:
            print(f"DEBUG OUTLOOK: Exception -> {e}")
            raise Exception(f"Outlook sync failed: {str(e)}")
