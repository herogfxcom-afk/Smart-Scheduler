import os
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
import googleapiclient.discovery
import asyncio
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
import pytz

SCOPES = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events', 
    'https://www.googleapis.com/auth/calendar.readonly'
]

class GoogleCalendarService:
    def __init__(self, refresh_token: str):
        self.creds = Credentials(
            None,
            refresh_token=refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=os.getenv("GOOGLE_CLIENT_ID"),
            client_secret=os.getenv("GOOGLE_CLIENT_SECRET"),
            scopes=SCOPES
        )
        self.service = googleapiclient.discovery.build('calendar', 'v3', credentials=self.creds)

    def _get_calendar_list(self):
        return self.service.calendarList().list().execute()

    def _query_freebusy(self, body):
        return self.service.freebusy().query(body=body).execute()

    def _insert_event(self, calendar_id, body, conference_data_version=None, send_updates='all'):
        insert_kwargs = {
            'calendarId': calendar_id,
            'body': body,
            'sendUpdates': send_updates,
        }
        if conference_data_version is not None:
            insert_kwargs['conferenceDataVersion'] = conference_data_version
        return self.service.events().insert(**insert_kwargs).execute()

    def _delete_event_sync(self, calendar_id, event_id):
        return self.service.events().delete(calendarId=calendar_id, eventId=event_id).execute()

    async def get_busy_slots(self, start_time: datetime, end_time: datetime) -> list:
        # 1. Fetch all calendars as secondary calendars can also have events
        loop = asyncio.get_event_loop()
        try:
            calendar_list = await loop.run_in_executor(None, self._get_calendar_list)
            calendar_ids = [entry['id'] for entry in calendar_list.get('items', [])]
        except Exception as e:
            print(f"DEBUG: Failed to fetch calendar list: {e}")
            calendar_ids = ['primary']

        # 2. Query FreeBusy
        body = {
            "timeMin": start_time.isoformat() + 'Z',
            "timeMax": end_time.isoformat() + 'Z',
            "items": [{"id": cid} for cid in calendar_ids]
        }
        
        try:
            events_result = await loop.run_in_executor(None, self._query_freebusy, body)
            
            all_busy = []
            calendars_busy = events_result.get('calendars', {})
            for cal_id, cal_data in calendars_busy.items():
                busy = cal_data.get('busy', [])
                print(f"DEBUG: Calendar {cal_id} has {len(busy)} busy slots")
                all_busy.extend(busy)
                
            return all_busy
        except Exception as e:
            print(f"DEBUG: Error in get_busy_slots: {str(e)}")
            return []

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
        """Deletes a specific calendar event by ID."""
        loop = asyncio.get_event_loop()
        try:
            await loop.run_in_executor(None, self._delete_event_sync, 'primary', event_id)
            print(f"DEBUG: Deleted Google Event {event_id}")
            return True
        except Exception as e:
            print(f"DEBUG: Error deleting Google Event {event_id}: {e}")
            return False

def find_common_free_slots(
    busy_slots_per_user: list[list[tuple[datetime, datetime]]], 
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
        current_utc = local_midnight.astimezone(timezone.utc)
    else:
        current_utc = start_date.astimezone(timezone.utc)
    
    end_utc_limit = end_date.astimezone(timezone.utc)

    while current_utc < end_utc_limit:
        segment_start = current_utc
        segment_end = current_utc + timedelta(minutes=30)
        
        active_users_in_segment = 0
        working_but_busy_count = 0
        requesting_user_busy = False
        
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

            is_working = False
            u_avail = user_availabilities[i].get(local_weekday, {"start": 9, "end": 18, "enabled": True})
            
            if u_avail["enabled"]:
                h_start = local_segment_start.hour
                m_start = local_segment_start.minute
                # For half-hour increments, check if the segment is fully within the working window
                total_min_start = h_start * 60 + m_start
                total_min_end = total_min_start + 30
                
                avail_start = u_avail["start"] * 60
                avail_end = u_avail["end"] * 60
                
                if total_min_start >= avail_start and total_min_end <= avail_end:
                    is_working = True
            
            if not is_working:
                continue
            
            # Intersection check with busy slots
            is_busy_with_event = False
            for b_start, b_end in busy_slots_per_user[i]:
                b_s = b_start if b_start.tzinfo else b_start.replace(tzinfo=timezone.utc)
                b_e = b_end if b_end.tzinfo else b_end.replace(tzinfo=timezone.utc)
                
                if max(segment_start, b_s) < min(segment_end, b_e):
                    is_busy_with_event = True
                    break
            
            active_users_in_segment += 1
            if is_busy_with_event:
                working_but_busy_count += 1
                busy_user_count += 1
                if user_ids and i < len(user_ids):
                    busy_user_id = user_ids[i]
                if i == requesting_user_index:
                    requesting_user_busy = True

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
        else:
            type_label = "others_busy"
            # Availability is the fraction of total participants who are both working and free
            availability = free_count / num_users
            source_user_id = busy_user_id if busy_user_count == 1 else None

        # Combine adjacent segments
        if free_slots and free_slots[-1]["type"] == type_label and \
           free_slots[-1]["end"] == segment_start.isoformat().replace('+00:00', 'Z') and \
           free_slots[-1].get("availability") == availability and \
           free_slots[-1].get("source_user_id") == source_user_id:
            free_slots[-1]["end"] = segment_end.isoformat().replace('+00:00', 'Z')
        else:
            free_slots.append({
                "start": segment_start.isoformat().replace('+00:00', 'Z'),
                "end": segment_end.isoformat().replace('+00:00', 'Z'),
                "type": type_label,
                "free_count": free_count,
                "total_count": num_users,
                "availability": availability,
                "source_user_id": source_user_id
            })
            
        current_utc += timedelta(minutes=30)
        
    return free_slots
