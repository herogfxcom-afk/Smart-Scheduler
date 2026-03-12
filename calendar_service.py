import os
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
import googleapiclient.discovery
import asyncio
from datetime import datetime, timedelta

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
                    'requestId': f"meet_{int(datetime.utcnow().timestamp())}",
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
    tz_offset_hours: float = 0,
    requesting_user_index: int = -1,
    user_ids: list[str] = None
) -> list[dict]:
    """
    Finds time slots and categorizes them as match, my_busy, or others_busy.
    user_ids: optional list of string IDs corresponding to the users in busy_slots_per_user.
    """
    if not (-12 <= tz_offset_hours <= 14):
        print(f"DEBUG: Invalid timezone offset: {tz_offset_hours}")
        tz_offset_hours = 0.0
        
    num_users = len(busy_slots_per_user)
    if num_users == 0:
        return []

    if not user_availabilities:
        default_day = {"start": 9, "end": 18, "enabled": True}
        user_availabilities = [{d: default_day for d in range(7)} for _ in range(num_users)]

    free_slots = []
    curr_day_start = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
    last_day = end_date.replace(hour=0, minute=0, second=0, microsecond=0)
    
    current = curr_day_start
    while current <= last_day:
        weekday = current.weekday()
        
        for hour in range(24):
            for minute in [0, 30]:
                segment_start = current.replace(hour=hour, minute=minute)
                segment_end = segment_start + timedelta(minutes=30)
                
                local_segment_start = segment_start + timedelta(hours=tz_offset_hours)
                local_segment_end = segment_end + timedelta(hours=tz_offset_hours)
                local_weekday = local_segment_start.weekday()
                
                if segment_start < start_date:
                    continue
                if segment_start >= end_date:
                    break
                
                active_users_in_segment = 0
                working_but_busy_count = 0
                requesting_user_busy = False
                
                # NEW: Track which specific user is busy
                busy_user_id = None
                busy_user_count = 0

                for i in range(num_users):
                    is_busy_with_event = False
                    for b_start, b_end in busy_slots_per_user[i]:
                        if max(segment_start, b_start) < min(segment_end, b_end):
                            is_busy_with_event = True
                            break
                    
                    if is_busy_with_event:
                        busy_user_count += 1
                        if user_ids and i < len(user_ids):
                            busy_user_id = user_ids[i]
                        
                        if i == requesting_user_index:
                            requesting_user_busy = True

                    u_avail = user_availabilities[i].get(local_weekday, {"start": 9, "end": 18, "enabled": True})
                    is_working = u_avail["enabled"]
                    if is_working:
                        h_start = local_segment_start.hour
                        h_end = local_segment_end.hour
                        m_end = local_segment_end.minute
                        if h_end == 0 and m_end == 0 and local_segment_start.date() != local_segment_end.date():
                            h_end = 24
                        if h_start < u_avail["start"] or h_end > u_avail["end"] or (h_end == u_avail["end"] and m_end > 0):
                            is_working = False
                    
                    if not is_working: continue
                    
                    active_users_in_segment += 1
                    if is_busy_with_event:
                        working_but_busy_count += 1
                
                # Logic for type and source identity
                source_user_id = None
                if requesting_user_busy:
                    type_label = "my_busy"
                    availability = 0.0
                    if user_ids and requesting_user_index != -1:
                        source_user_id = user_ids[requesting_user_index]
                elif active_users_in_segment > 0:
                    free_count = active_users_in_segment - working_but_busy_count
                    if free_count == active_users_in_segment:
                        type_label = "match"
                        availability = 1.0
                    else:
                        type_label = "others_busy"
                        availability = free_count / active_users_in_segment
                        # If exactly one other person is busy, we can identify them
                        if busy_user_count == 1:
                            source_user_id = busy_user_id
                else:
                    type_label = "others_busy"
                    availability = 0.0
                
                total_c = max(active_users_in_segment, 1)
                
                # Combine adjacent segments with same properties
                if free_slots and free_slots[-1]["type"] == type_label and \
                   free_slots[-1]["end"] == segment_start.isoformat() + "Z" and \
                   free_slots[-1].get("availability") == availability and \
                   free_slots[-1].get("source_user_id") == source_user_id:
                    free_slots[-1]["end"] = segment_end.isoformat() + "Z"
                else:
                    free_slots.append({
                        "start": segment_start.isoformat() + "Z",
                        "end": segment_end.isoformat() + "Z",
                        "type": type_label,
                        "free_count": max(active_users_in_segment - working_but_busy_count, 0),
                        "total_count": total_c,
                        "availability": availability,
                        "source_user_id": source_user_id
                    })
            
        current += timedelta(days=1)
        
    return free_slots

            
        current += timedelta(days=1)
        
    return free_slots
