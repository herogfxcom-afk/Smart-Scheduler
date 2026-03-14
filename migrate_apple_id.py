import os
import sqlalchemy
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

def migrate():
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("DATABASE_URL not found")
        return

    # Handle Postgres/Postgresql prefix for SQLAlchemy
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql://", 1)

    engine = create_engine(database_url)
    
    with engine.connect() as conn:
        print("Checking for apple_event_id columns...")
        
        # 1. Meeting invite apple_event_id
        try:
            conn.execute(text("ALTER TABLE meeting_invites ADD COLUMN apple_event_id VARCHAR(255)"))
            conn.commit()
            print("Successfully added apple_event_id to meeting_invites")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("apple_event_id already exists in meeting_invites")
            else:
                print(f"Error adding to meeting_invites: {e}")

        # 2. Group meeting apple_event_id
        try:
            conn.execute(text("ALTER TABLE group_meetings ADD COLUMN apple_event_id VARCHAR(255)"))
            conn.commit()
            print("Successfully added apple_event_id to group_meetings")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("apple_event_id already exists in group_meetings")
            else:
                print(f"Error adding to group_meetings: {e}")

if __name__ == "__main__":
    migrate()
