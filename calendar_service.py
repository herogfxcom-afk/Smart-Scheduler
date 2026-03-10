import os
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
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
        self.service = build('calendar', 'v3', credentials=self.creds)

    async def get_busy_slots(self, start_time: datetime, end_time: datetime) -> list:
        """Fetches busy slots for all calendars in the user's calendar list."""
        try:
            # 1. Get list of all calendars
            calendar_list = self.service.calendarList().list().execute()
            calendar_ids = [item['id'] for item in calendar_list.get('items', [])]
            
            if not calendar_ids:
                calendar_ids = ['primary']

            # 2. Query freebusy for all calendars
            body = {
                "timeMin": start_time.isoformat() + "Z",
                "timeMax": end_time.isoformat() + "Z",
                "items": [{"id": cid} for cid in calendar_ids]
            }
            
            print(f"DEBUG: Querying FreeBusy for calendars: {calendar_ids}")
            events_result = self.service.freebusy().query(body=body).execute()
            
            all_busy = []
            for cal_id, cal_data in events_result.get('calendars', {}).items():
                busy = cal_data.get('busy', [])
                print(f"DEBUG: Calendar {cal_id} has {len(busy)} busy slots")
                all_busy.extend(busy)
                
            return all_busy
        except Exception as e:
            print(f"DEBUG: Error in get_busy_slots: {str(e)}")
            return []

    async def create_event(self, summary: str, start_time: datetime, end_time: datetime, attendees: list[str] = None, location: str = "", meeting_type: str = "online"):
        """Creates a calendar event with attendees and optionally a Google Meet link."""
        event = {
            'summary': summary,
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
        if meeting_type == 'online':
            event['conferenceData'] = {
                'createRequest': {
                    'requestId': f"meet_{int(datetime.utcnow().timestamp())}",
                    'conferenceSolutionKey': {'type': 'hangoutsMeet'}
                }
            }
        
        insert_kwargs = {
            'calendarId': 'primary',
            'body': event,
            'sendUpdates': 'all',
        }
        if meeting_type == 'online':
            insert_kwargs['conferenceDataVersion'] = 1
            
        event = self.service.events().insert(**insert_kwargs).execute()
        return event

    async def delete_event(self, event_id: str):
        """Deletes a specific calendar event by ID."""
        try:
            self.service.events().delete(calendarId='primary', eventId=event_id).execute()
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
    requesting_user_index: int = -1
) -> list[dict]:
    """
    Finds time slots and categorizes them as match, my_busy, or others_busy.
    user_availabilities: list of dicts. each dict is {day_of_week (0-6): {"start": hour_int, "end": hour_int, "enabled": bool}}
    tz_offset_hours: The timezone offset of the user (e.g. +2 for UTC+2), used to align UTC loop with local working hours.
    requesting_user_index: Index of the current user in the busy_slots_per_user list to determine "my_busy".
    """
    num_users = len(busy_slots_per_user)
    if num_users == 0:
        return []

    # Default availability if not provided (7:00 - 23:00 for everyone)
    if not user_availabilities:
        default_day = {"start": 7, "end": 23, "enabled": True}
        user_availabilities = [{d: default_day for d in range(7)} for _ in range(num_users)]

    free_slots = []
    # Start searching from the beginning of the day of start_date
    curr_day_start = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
    last_day = end_date.replace(hour=0, minute=0, second=0, microsecond=0)
    
    current = curr_day_start
    while current <= last_day:
        weekday = current.weekday() # 0 = Monday
        
        # Check every 30-minute block of the 24h day
        # But we only care about blocks that are within AT LEAST ONE user's work hours
        for hour in range(24):
            for minute in [0, 30]:
                segment_start = current.replace(hour=hour, minute=minute)
                segment_end = segment_start + timedelta(minutes=30)
                
                # Adjust segment_start to LOCAL time for working hours check
                local_segment_start = segment_start + timedelta(hours=tz_offset_hours)
                local_segment_end = segment_end + timedelta(hours=tz_offset_hours)
                local_weekday = local_segment_start.weekday()
                
                if segment_start < start_date:
                    continue
                if segment_start >= end_date:
                    break
                
                # Count availability for this specific segment
                active_users_in_segment = 0
                working_but_busy_count = 0
                requesting_user_busy = False
                
                for i in range(num_users):
                    u_avail = user_availabilities[i].get(local_weekday, {"start": 7, "end": 23, "enabled": True})
                    
                    # Is this user "at work" during this segment?
                    is_working = u_avail["enabled"] and \
                                 local_segment_start.hour >= u_avail["start"] and \
                                 local_segment_end.hour <= u_avail["end"]
                    
                    if u_avail["enabled"]:
                         if local_segment_start.hour < u_avail["start"]: is_working = False
                         elif local_segment_end.hour > u_avail["end"]: is_working = False
                         elif local_segment_end.hour == u_avail["end"] and local_segment_end.minute > 0: is_working = False
                    
                    # Check if user is busy with a calendar event
                    is_busy = False
                    for b_start, b_end in busy_slots_per_user[i]:
                        if max(segment_start, b_start) < min(segment_end, b_end):
                            is_busy = True
                            break
                    
                    if is_busy and i == requesting_user_index:
                        requesting_user_busy = True

                    if not is_working:
                        continue # User not available for meetings now
                    
                    active_users_in_segment += 1
                    if is_busy:
                        working_but_busy_count += 1
                
                # Render logic: Only include slots if someone is working OR if I am busy (to paint it blue).
                if active_users_in_segment > 0 or requesting_user_busy:
                    if requesting_user_busy:
                        type_label = "my_busy"
                        availability = 0.0
                    elif active_users_in_segment > 0:
                        free_count = active_users_in_segment - working_but_busy_count
                        if free_count == active_users_in_segment:
                            type_label = "match"
                            availability = 1.0
                        else:
                            type_label = "others_busy"
                            availability = free_count / active_users_in_segment
                    else:
                        type_label = "others_busy"
                        availability = 0.0
                    
                    total_c = max(active_users_in_segment, 1)
                    
                    if free_slots and free_slots[-1]["type"] == type_label and \
                       free_slots[-1]["end"] == segment_start.isoformat() + "Z" and \
                       free_slots[-1].get("availability") == availability and \
                       free_slots[-1].get("total_count") == total_c:
                        free_slots[-1]["end"] = segment_end.isoformat() + "Z"
                    else:
                        free_slots.append({
                            "start": segment_start.isoformat() + "Z",
                            "end": segment_end.isoformat() + "Z",
                            "type": type_label,
                            "free_count": max(active_users_in_segment - working_but_busy_count, 0),
                            "total_count": total_c,
                            "availability": availability
                        })
            
        current += timedelta(days=1)
        
    return free_slots
