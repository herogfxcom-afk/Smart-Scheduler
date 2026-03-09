import caldav
from caldav.elements import dav, cdav
from datetime import datetime, timedelta
import pytz

class AppleCalendarService:
    def __init__(self, username, password):
        self.username = username
        self.password = password
        self.client = caldav.DAVClient(
            url="https://caldav.icloud.com",
            username=username,
            password=password
        )

    def get_busy_slots(self, start_time: datetime, end_time: datetime) -> list:
        """
        Fetches busy slots from iCloud calendars.
        In CalDAV, 'busy' is usually derived from existing events.
        """
        principal = self.client.principal()
        calendars = principal.calendars()
        
        busy_slots = []
        for calendar in calendars:
            # Fetch events in the given range
            results = calendar.date_search(start_time, end_time)
            
            for event in results:
                # vobject/icalendar parsing is handled by the library
                ev = event.vobject_instance.vevent
                
                # Extract start and end
                s = ev.dtstart.value
                e = ev.dtend.value
                
                # Normalize to datetime (handle date-only events)
                if isinstance(s, datetime):
                    if s.tzinfo is None:
                        s = pytz.utc.localize(s)
                else: # date object
                    s = datetime.combine(s, datetime.min.time(), tzinfo=pytz.utc)
                    
                if isinstance(e, datetime):
                    if e.tzinfo is None:
                        e = pytz.utc.localize(e)
                else: # date object
                    e = datetime.combine(e, datetime.min.time(), tzinfo=pytz.utc)

                busy_slots.append({
                    "start": s.isoformat(),
                    "end": e.isoformat()
                })
        
        return busy_slots

    def create_event(self, summary: str, start_time: datetime, end_time: datetime, location: str = ""):
        """Creates an event in the primary/default iCloud calendar."""
        principal = self.client.principal()
        # Usually the first calendar is the main one, or we can look for specific types
        calendar = principal.calendars()[0] 
        
        event = calendar.save_event(
            dtstart=start_time,
            dtend=end_time,
            summary=summary,
            location=location
        )
        return event
