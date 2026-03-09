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
    work_start_hour: int = 9, 
    work_end_hour: int = 19
) -> list[dict]:
    """
    Finds time slots where everyone OR most users are free.
    """
    num_users = len(busy_slots_per_user)
    if num_users == 0:
        return []

    free_slots = []
    curr_day_start = start_date.replace(hour=0, minute=0, second=0, microsecond=0)
    last_day = end_date.replace(hour=0, minute=0, second=0, microsecond=0)
    
    current = curr_day_start
    while current <= last_day:
        work_start = current.replace(hour=work_start_hour)
        work_end = current.replace(hour=work_end_hour)
        
        # We'll check every 30-minute block for simplicity and precision
        segment_start = max(work_start, start_date)
        while segment_start < work_end:
            segment_end = segment_start + timedelta(minutes=30)
            if segment_end > work_end:
                segment_end = work_end
            
            # Count how many users are busy during this specific segment
            busy_count = 0
            for user_busy in busy_slots_per_user:
                is_busy = False
                for b_start, b_end in user_busy:
                    # Check for overlap
                    if max(segment_start, b_start) < min(segment_end, b_end):
                        is_busy = True
                        break
                if is_busy:
                    busy_count += 1
            
            free_count = num_users - busy_count
            availability = free_count / num_users if num_users > 0 else 1.0
            
            # For heatmap, we show everything above 0% to allow picking "mostly free" slots
            if free_count > 0:
                # Type label based on availability percentage
                if availability == 1.0:
                    type_label = "match"
                elif availability >= 0.75:
                    type_label = "high"
                elif availability >= 0.5:
                    type_label = "partial"
                else:
                    type_label = "low"
                
                # We always create new slots for heatmap to preserve per-segment availability
                # unless they are exactly the same and contiguous
                if free_slots and free_slots[-1]["type"] == type_label and \
                   free_slots[-1]["end"] == segment_start.isoformat() and \
                   free_slots[-1].get("availability") == availability:
                    free_slots[-1]["end"] = segment_end.isoformat()
                else:
                    free_slots.append({
                        "start": segment_start.isoformat() + "Z",
                        "end": segment_end.isoformat() + "Z",
                        "type": type_label,
                        "free_count": free_count,
                        "total_count": num_users,
                        "availability": availability
                    })
            
            segment_start = segment_end
            
        current += timedelta(days=1)
        
    return free_slots
