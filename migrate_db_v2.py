import os
from sqlalchemy import text
from sqlalchemy.orm import Session
from database import engine

def migrate():
    print(f"Connecting to {engine.url.drivername}...")
    with engine.connect() as conn:
        # Check if column exists
        try:
            if engine.url.drivername.startswith('sqlite'):
                # SQLite check
                info = conn.execute(text("PRAGMA table_info(group_meetings)")).fetchall()
                cols = [i[1] for i in info]
                if 'is_cancelled' not in cols:
                    print("Adding is_cancelled to group_meetings (SQLite)...")
                    conn.execute(text("ALTER TABLE group_meetings ADD COLUMN is_cancelled BOOLEAN DEFAULT 0"))
                    conn.commit()
                else:
                    print("is_cancelled already exists.")
            else:
                # Postgres check
                print("Checking for column in Postgres...")
                query = text("""
                    SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name='group_meetings' AND column_name='is_cancelled'
                """)
                res = conn.execute(query).fetchone()
                if not res:
                    print("Adding is_cancelled to group_meetings (Postgres)...")
                    conn.execute(text("ALTER TABLE group_meetings ADD COLUMN is_cancelled BOOLEAN DEFAULT FALSE"))
                    conn.commit()
                else:
                    print("is_cancelled already exists.")
        except Exception as e:
            print(f"Migration error: {e}")

if __name__ == "__main__":
    migrate()
