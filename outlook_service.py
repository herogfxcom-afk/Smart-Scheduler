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
        if not self.client_id or not self.client_secret:
            raise Exception("Microsoft OAuth credentials missing in environment.")

        data = {
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "grant_type": "refresh_token",
            "refresh_token": self.refresh_token,
        }
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(self.token_url, data=data)
            if resp.status_code != 200:
                print(f"DEBUG: Token refresh failed: {resp.status_code} - {resp.text}")
                # This exception will trigger 'requires login'/status='error' in main.py
                raise Exception(f"Token refresh failed: {resp.text}")
            return resp.json().get("access_token")

    async def get_busy_slots(self, start_time: datetime, end_time: datetime):
        """
        Fetches busy calendar events from Outlook using the calendarView API.
        Filters out 'free' availability and all-day events.
        """
        if not self.client_id or not self.client_secret:
            print("DEBUG: Outlook credentials missing. Skipping sync.")
            return []

        try:
            access_token = await self._get_access_token()
            headers = {
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
                "Prefer": 'outlook.timezone="UTC"',
            }

            # Format datetimes as ISO 8601 strings required by Microsoft Graph
            start_str = start_time.strftime("%Y-%m-%dT%H:%M:%S")
            end_str = end_time.strftime("%Y-%m-%dT%H:%M:%S")

            # /me/calendarView returns all calendar events in the given range.
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
                if resp.status_code != 200:
                    print(f"DEBUG OUTLOOK ERROR: {resp.status_code} - {resp.text}")
                    raise Exception(f"Outlook API error: {resp.text}")
                
                data = resp.json()
                events = data.get('value', [])
                
                busy_slots = []
                for event in events:
                    subject = event.get("subject", "No Subject")
                    # Skip events marked as free
                    show_as = event.get("showAs", "busy")
                    if show_as == "free":
                        continue

                    # Skip all-day events to avoid blocking the entire day
                    if event.get("isAllDay", False):
                        continue

                    start_dt = event.get("start", {}).get("dateTime")
                    end_dt = event.get("end", {}).get("dateTime")

                    if start_dt and end_dt:
                        # Ensure UTC 'Z' suffix
                        if not start_dt.endswith("Z"):
                            start_dt += "Z"
                        if not end_dt.endswith("Z"):
                            end_dt += "Z"
                        busy_slots.append({"start": start_dt, "end": end_dt})
                
                return busy_slots

        except Exception as e:
            print(f"DEBUG: Outlook get_busy_slots failed: {e}")
            raise

    async def create_event(self, summary: str, start_time: datetime, end_time: datetime, location: str = "", description: str = ""):
        """Creates a calendar event in Outlook via Microsoft Graph."""
        if not self.client_id or not self.client_secret:
            print("DEBUG: Outlook credentials missing. Skipping create.")
            return {}
        try:
            access_token = await self._get_access_token()
            headers = {
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            }
            body = {
                "subject": summary,
                "body": {
                    "contentType": "Text",
                    "content": description or ""
                },
                "start": {
                    "dateTime": start_time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "timeZone": "UTC"
                },
                "end": {
                    "dateTime": end_time.strftime("%Y-%m-%dT%H:%M:%S"),
                    "timeZone": "UTC"
                },
                "location": {"displayName": location or ""}
            }
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.post(
                    f"{self.base_url}/me/events",
                    headers=headers,
                    json=body
                )
                if resp.status_code not in [200, 201]:
                    print(f"DEBUG OUTLOOK ERROR: {resp.status_code} - {resp.text}")
                    raise Exception(f"Outlook create event error: {resp.text}")
                
                result = resp.json()
                print(f"DEBUG OUTLOOK: Created event '{summary}' id={result.get('id')}")
                return result
        except Exception as e:
            print(f"DEBUG OUTLOOK: create_event failed: {e}")
            raise

    async def delete_event(self, event_id: str):
        """Deletes a calendar event in Outlook via Microsoft Graph."""
        if not self.client_id or not self.client_secret:
            print("DEBUG: Outlook credentials missing. Skipping delete.")
            return False
            
        try:
            access_token = await self._get_access_token()
            headers = {
                "Authorization": f"Bearer {access_token}"
            }
            async with httpx.AsyncClient(timeout=15) as client:
                resp = await client.delete(
                    f"{self.base_url}/me/events/{event_id}",
                    headers=headers
                )
                if resp.status_code != 204:
                    print(f"DEBUG OUTLOOK ERROR: {resp.status_code} - {resp.text}")
                    raise Exception(f"Outlook delete event error: {resp.text}")
                
                print(f"DEBUG OUTLOOK: Deleted event id={event_id}")
                return True
        except Exception as e:
            print(f"DEBUG OUTLOOK: delete_event failed: {e}")
            raise
