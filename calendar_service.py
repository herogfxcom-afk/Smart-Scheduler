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

    async def create_event(self, summary: str, start_time: datetime, end_time: datetime, attendees: list[str] = None, location: str = ""):
        """Creates a calendar event with attendees and Google Meet link."""
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
            'conferenceData': {
                'createRequest': {
                    'requestId': f"meet_{int(datetime.utcnow().timestamp())}",
                    'conferenceSolutionKey': {'type': 'hangoutsMeet'}
                }
            },
        }
        
        event = self.service.events().insert(
            calendarId='primary', 
            body=event,
            conferenceDataVersion=1,
            sendUpdates='all'
        ).execute()
        return event

def find_common_free_slots(
    busy_slots_per_user: list[list[tuple[datetime, datetime]]], 
    start_date: datetime, 
    end_date: datetime,
    user_availabilities: list[dict] = None
) -> list[dict]:
    """
    Finds time slots where everyone OR most users are free, respecting per-user working hours.
    user_availabilities: list of dicts. each dict is {day_of_week (0-6): {"start": hour_int, "end": hour_int, "enabled": bool}}
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
                
                if segment_start < start_date:
                    continue
                if segment_start >= end_date:
                    break
                
                # Count availability for this specific segment
                active_users_in_segment = 0
                busy_count = 0
                
                for i in range(num_users):
                    u_avail = user_availabilities[i].get(weekday, {"start": 7, "end": 23, "enabled": True})
                    
                    # Is this user "at work" during this segment?
                    # We check if segment is within u_avail["start"] and u_avail["end"]
                    is_working = u_avail["enabled"] and \
                                 segment_start.hour >= u_avail["start"] and \
                                 segment_end.hour <= u_avail["end"]
                    
                    # Boundary edge case: if end is 18:00, segment 17:30-18:00 is working, but 18:00-18:30 is not.
                    if u_avail["enabled"]:
                         if segment_start.hour < u_avail["start"]: is_working = False
                         elif segment_end.hour > u_avail["end"]: is_working = False
                         elif segment_end.hour == u_avail["end"] and segment_end.minute > 0: is_working = False
                    
                    if not is_working:
                        continue # User not available for meetings now
                    
                    active_users_in_segment += 1
                    
                    # Check if user is busy with a calendar event
                    is_busy = False
                    for b_start, b_end in busy_slots_per_user[i]:
                        if max(segment_start, b_start) < min(segment_end, b_end):
                            is_busy = True
                            break
                    if is_busy:
                        busy_count += 1
                
                if active_users_in_segment > 0:
                    free_count = active_users_in_segment - busy_count
                    availability = free_count / active_users_in_segment
                    
                    # For heatmap, we show segments where at least some active users are free
                    if free_count > 0:
                        if availability == 1.0:
                            type_label = "match"
                        elif availability >= 0.75:
                            type_label = "high"
                        elif availability >= 0.5:
                            type_label = "partial"
                        else:
                            type_label = "low"
                        
                        if free_slots and free_slots[-1]["type"] == type_label and \
                           free_slots[-1]["end"] == segment_start.isoformat() + "Z" and \
                           free_slots[-1].get("availability") == availability and \
                           free_slots[-1].get("total_count") == active_users_in_segment:
                            free_slots[-1]["end"] = segment_end.isoformat() + "Z"
                        else:
                            free_slots.append({
                                "start": segment_start.isoformat() + "Z",
                                "end": segment_end.isoformat() + "Z",
                                "type": type_label,
                                "free_count": free_count,
                                "total_count": active_users_in_segment,
                                "availability": availability
                            })
            
        current += timedelta(days=1)
        
    return free_slots
