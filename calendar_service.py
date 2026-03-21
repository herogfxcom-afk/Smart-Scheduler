import os
import datetime as dt_module
import httpx
import asyncio
import urllib.parse
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

SCOPES = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events', 
    'https://www.googleapis.com/auth/calendar.readonly'
]

class GoogleCalendarService:
    def __init__(self, refresh_token: str):
        self._refresh_token = refresh_token
        self._client_id = os.getenv("GOOGLE_CLIENT_ID")
        self._client_secret = os.getenv("GOOGLE_CLIENT_SECRET")
        self._access_token = None

    def _ensure_token(self):
        """Fetches a fresh access token using the refresh token via direct httpx call.
        Avoids google.auth.transport.urllib3 which triggers MustDowngradeError on Vercel Lambda.
        """
        if self._access_token is None:
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(
                    "https://oauth2.googleapis.com/token",
                    data={
                        "client_id": self._client_id,
                        "client_secret": self._client_secret,
                        "refresh_token": self._refresh_token,
                        "grant_type": "refresh_token",
                    }
                )
                resp.raise_for_status()
                self._access_token = resp.json()["access_token"]
        return self._access_token

    def _get_calendar_list(self):
        token = self._ensure_token()
        url = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
        headers = {"Authorization": f"Bearer {token}"}
        with httpx.Client(timeout=15.0) as client:
            response = client.get(url, headers=headers)
            response.raise_for_status()
            return response.json()

    def _list_events(self, calendar_id, time_min, time_max):
        token = self._ensure_token()
        safe_cid = urllib.parse.quote(calendar_id)
        url = f"https://www.googleapis.com/calendar/v3/calendars/{safe_cid}/events"
        headers = {"Authorization": f"Bearer {token}"}
        params = {
            "timeMin": time_min,
            "timeMax": time_max,
            "singleEvents": True,
            "orderBy": "startTime"
        }
        with httpx.Client(timeout=15.0) as client:
            response = client.get(url, headers=headers, params=params)
            response.raise_for_status()
            return response.json()

    def _insert_event(self, calendar_id, body, conference_data_version=None, send_updates='all'):
        token = self._ensure_token()
        safe_cid = urllib.parse.quote(calendar_id)
        url = f"https://www.googleapis.com/calendar/v3/calendars/{safe_cid}/events"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        params = {"sendUpdates": send_updates}
        if conference_data_version is not None:
            params["conferenceDataVersion"] = str(conference_data_version)
            
        with httpx.Client(timeout=15.0) as client:
            response = client.post(url, headers=headers, params=params, json=body)
            response.raise_for_status()
            return response.json()

    def _delete_event_sync(self, calendar_id, event_id):
        token = self._ensure_token()
        safe_cid = urllib.parse.quote(calendar_id)
        url = f"https://www.googleapis.com/calendar/v3/calendars/{safe_cid}/events/{event_id}"
        headers = {"Authorization": f"Bearer {token}"}
        with httpx.Client(timeout=15.0) as client:
            response = client.delete(url, headers=headers)
            response.raise_for_status()
            return True
    async def get_busy_slots(self, start_time: datetime, end_time: datetime) -> list:
        # 1. Fetch all calendars
        loop = asyncio.get_event_loop()
        try:
            calendar_list = await loop.run_in_executor(None, self._get_calendar_list)
            calendar_ids = [entry['id'] for entry in calendar_list.get('items', [])]
        except Exception as e:
            print(f"DEBUG: Failed to fetch calendar list: {e}", flush=True)
            calendar_ids = ['primary']

        # 2. Query Events for each calendar
        time_min_str = start_time.strftime('%Y-%m-%dT%H:%M:%SZ') if start_time.tzinfo else start_time.isoformat() + 'Z'
        time_max_str = end_time.strftime('%Y-%m-%dT%H:%M:%SZ') if end_time.tzinfo else end_time.isoformat() + 'Z'
        
        all_busy = []
        for cid in calendar_ids:
            try:
                events_result = await loop.run_in_executor(None, self._list_events, cid, time_min_str, time_max_str)
                events = events_result.get('items', [])
                

                for event in events:
                    # Skip 'free' events
                    if event.get('transparency') == 'transparent':
                        continue
                    
                    start = event.get('start', {}).get('dateTime') or event.get('start', {}).get('date')
                    end = event.get('end', {}).get('dateTime') or event.get('end', {}).get('date')
                    
                    if start and end:
                        # Convert all-day events (date only) to datetime
                        if 'T' not in start:
                            start = f"{start}T00:00:00Z"
                        if 'T' not in end:
                            end = f"{end}T23:59:59Z"
                            
                        all_busy.append({
                            'start': start,
                            'end': end,
                            'summary': event.get('summary', 'Busy'),
                            'id': event.get('id')
                        })
            except Exception as e:
                import sys
                print(f"DEBUG: Failed to list events for calendar {cid}: {e}")
                sys.stdout.flush()
                
        return all_busy

    async def create_event(self, summary: str, start_time: datetime, end_time: datetime, attendees: list[str] = None, location: str = "", meeting_type: str = "online", description: str = ""):
        """Creates a calendar event with attendees and optionally a Google Meet link."""
        event = {
            'summary': summary,
            'description': description,
            'location': location,
            'start': {
                'dateTime': start_time.isoformat(),
                'timeZone': 'UTC',
            },
            'end': {
                'dateTime': end_time.isoformat(),
                'timeZone': 'UTC',
            },
            'attendees': [{'email': email} for email in (attendees or [])],
        }
        
        # Only add Google Meet for online meetings
        conference_data_version = None
        if meeting_type == 'online':
            event['conferenceData'] = {
                'createRequest': {
                    'requestId': f"meet_{int(datetime.now(timezone.utc).timestamp())}",
                    'conferenceSolutionKey': {'type': 'hangoutsMeet'}
                }
            }
            conference_data_version = 1
        
        loop = asyncio.get_event_loop()
        try:
            event_result = await loop.run_in_executor(None, self._insert_event, 'primary', event, conference_data_version)
            return event_result.get('id')
        except Exception as e:
            print(f"DEBUG: Error creating Google Event: {e}")
            return None

    async def delete_event(self, event_id: str):
        """Deletes a specific calendar event by ID, searching all user's calendars."""
        loop = asyncio.get_event_loop()
        
        # Try primary calendar first (fast path)
        try:
            await loop.run_in_executor(None, self._delete_event_sync, 'primary', event_id)
            print(f"DEBUG: Deleted Google Event {event_id} from primary calendar")
            return True
        except Exception as e:
            # 404 means it's not in primary, try other calendars
            if '404' not in str(e) and 'notFound' not in str(e):
                print(f"DEBUG: Non-404 error deleting from primary: {e}")

        # Search all other calendars
        try:
            calendar_list = await loop.run_in_executor(None, self._get_calendar_list)
            calendar_ids = [entry['id'] for entry in calendar_list.get('items', []) if entry['id'] != 'primary']
            for cid in calendar_ids:
                try:
                    await loop.run_in_executor(None, self._delete_event_sync, cid, event_id)
                    print(f"DEBUG: Deleted Google Event {event_id} from calendar {cid}")
                    return True
                except Exception:
                    pass  # Not in this calendar, try next
        except Exception as e:
            print(f"DEBUG: Error fetching calendar list for deletion: {e}")
        
        print(f"DEBUG: Could not delete Google Event {event_id} from any calendar")
        return False

def find_common_free_slots(
    busy_slots_per_user: list[list[dict]], 
    start_date: datetime, 
    end_date: datetime,
    user_availabilities: list[dict] = None,
    user_timezones: list[str] = None,
    viewer_tz: str = "UTC",
    snap_to_local: bool = True,
    requesting_user_index: int = -1,
    user_ids: list[str] = None
) -> list[dict]:
    """
    Finds common free time slots among multiple users.
    Categorizes them as 'match' (all available), 'my_busy', or 'others_busy'.
    """
    num_users = len(busy_slots_per_user)
    if num_users == 0:
        return []

    if not user_availabilities:
        default_day = {"start": 9, "end": 18, "enabled": True}
        user_availabilities = [{d: default_day for d in range(7)} for _ in range(num_users)]
    
    if not user_timezones:
        user_timezones = ["UTC"] * num_users

    free_slots = []
    
    if snap_to_local:
        try:
            v_tz = ZoneInfo(viewer_tz)
        except:
            v_tz = ZoneInfo("UTC")
        
        local_now = start_date.astimezone(v_tz)
        local_midnight = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
        current_utc = local_midnight.astimezone(dt_module.timezone.utc)
    else:
        current_utc = start_date.astimezone(dt_module.timezone.utc)
    
    end_utc_limit = end_date.astimezone(dt_module.timezone.utc)

    while current_utc < end_utc_limit:
        segment_start = current_utc
        segment_end = current_utc + timedelta(minutes=30)
        
        active_users_in_segment = 0
        working_but_busy_count = 0
        requesting_user_busy = False
        requesting_user_summary = None
        requesting_user_is_external = False
        
        busy_user_id = None
        busy_user_count = 0

        for i in range(num_users):
            user_tz_str = user_timezones[i] if i < len(user_timezones) else "UTC"
            try:
                u_tz = ZoneInfo(user_tz_str)
            except:
                u_tz = ZoneInfo("UTC")
            
            local_segment_start = segment_start.astimezone(u_tz)
            local_segment_end = segment_end.astimezone(u_tz)
            local_weekday = local_segment_start.weekday()

            # 1. Busy check (Always check for all users to catch meetings outside working hours)
            is_busy_with_event = False
            current_summary = None
            current_is_external = False

            for b_slot in busy_slots_per_user[i]:
                # Handle both dicts and legacy tuples
                if isinstance(b_slot, dict):
                    b_start = b_slot['start']
                    b_end = b_slot['end']
                    summary = b_slot.get('summary')
                    is_ext = b_slot.get('is_external', False)
                else:
                    b_start, b_end = b_slot
                    summary = None
                    is_ext = False

                b_s = b_start if b_start.tzinfo else b_start.replace(tzinfo=dt_module.timezone.utc)
                b_e = b_end if b_end.tzinfo else b_end.replace(tzinfo=dt_module.timezone.utc)
                
                if max(segment_start, b_s) < min(segment_end, b_e):
                    is_busy_with_event = True
                    current_summary = summary
                    current_is_external = is_ext
                    break

            # 2. Working hours check
            is_working = False
            u_avail = user_availabilities[i].get(local_weekday, {"start": 9, "end": 18, "enabled": True})
            
            if u_avail["enabled"]:
                h_start = local_segment_start.hour
                m_start = local_segment_start.minute
                total_min_start = h_start * 60 + m_start
                total_min_end = total_min_start + 30
                
                avail_start = u_avail["start"] * 60
                avail_end = u_avail["end"] * 60
                
                if total_min_start >= avail_start and total_min_end <= avail_end:
                    is_working = True
            
            # Update counts based on both status and working hours
            if is_working:
                active_users_in_segment += 1
                if is_busy_with_event:
                    working_but_busy_count += 1
            
            # Even if NOT working, if the REQUESTING user is busy, we mark it as my_busy
            if is_busy_with_event:
                busy_user_count += 1
                if user_ids and i < len(user_ids):
                    busy_user_id = user_ids[i]
                if i == requesting_user_index:
                    requesting_user_busy = True
                    requesting_user_summary = current_summary
                    requesting_user_is_external = current_is_external

        # Determine type
        # For a group, a "match" should strictly mean ALL participants are available and free.
        # However, to avoid a completely empty heatmap when not all are in working hours,
        # we calculate availability relative to the total number of participants.
        
        free_count = active_users_in_segment - working_but_busy_count
        
        # Determine the type label based on the requesting user's status and group availability
        if requesting_user_busy:
            type_label = "my_busy"
            availability = 0.0
            if user_ids and requesting_user_index != -1:
                source_user_id = user_ids[requesting_user_index]
        elif active_users_in_segment == num_users and working_but_busy_count == 0:
            type_label = "match"
            availability = 1.0
            source_user_id = None
            requesting_user_summary = None
            requesting_user_is_external = False
        else:
            type_label = "others_busy"
            # Availability is the fraction of total participants who are both working and free
            availability = free_count / num_users if num_users > 0 else 0
            source_user_id = busy_user_id if busy_user_count == 1 else None
            requesting_user_summary = None
            requesting_user_is_external = False

        # Combine adjacent segments if they are the same type AND same summary
        if free_slots and free_slots[-1]["type"] == type_label and \
           free_slots[-1]["end"] == segment_start.isoformat().replace('+00:00', 'Z') and \
           free_slots[-1].get("availability") == availability and \
           free_slots[-1].get("source_user_id") == source_user_id and \
           free_slots[-1].get("summary") == requesting_user_summary:
            free_slots[-1]["end"] = segment_end.isoformat().replace('+00:00', 'Z')
        else:
            free_slots.append({
                "start": segment_start.isoformat().replace('+00:00', 'Z'),
                "end": segment_end.isoformat().replace('+00:00', 'Z'),
                "type": type_label,
                "free_count": free_count,
                "total_count": num_users,
                "availability": availability,
                "source_user_id": source_user_id,
                "summary": requesting_user_summary,
                "is_external": requesting_user_is_external
            })
            
        current_utc += timedelta(minutes=30)
        
    return free_slots
