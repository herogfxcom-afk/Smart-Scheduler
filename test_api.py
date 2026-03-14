import os
import time
import json
import datetime
from urllib.parse import urlencode
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch

# Mock env vars before importing app
os.environ["BOT_TOKEN"] = "12345:ABCDE"
os.environ["DATABASE_URL"] = "sqlite:///./test.db"
os.environ["ENCRYPTION_KEY"] = "8n-zI7Y9f_l4o0MhO1vD3w2Q5jK8uB5sH_xZbGcLvV4=" # valid 32 byte base64 fernet key

import hmac
import hashlib

def generate_mock_init_data(bot_token, user_id=12345, username="testuser"):
    user = {
        "id": user_id,
        "first_name": "Test",
        "last_name": "User",
        "username": username,
        "language_code": "en",
        "allows_write_to_pm": True
    }
    vals = {
        "auth_date": int(time.time()),
        "query_id": "AAHd_E0_AAAAAN38TT8",
        "user": json.dumps(user)
    }
    data_check_string = "\n".join([f"{k}={v}" for k, v in sorted(vals.items())])
    secret_key = hmac.new("WebAppData".encode(), bot_token.encode(), hashlib.sha256).digest()
    h = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
    vals["hash"] = h
    return urlencode(vals)

# Import app and database
from main import app
from database import engine, get_db
import models
from sqlalchemy.orm import sessionmaker

# Setup test DB
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
models.Base.metadata.create_all(bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

class TestReport:
    def __init__(self):
        self.results = []
    
    def add(self, name, success, error=None):
        self.results.append({"name": name, "success": success, "error": error})
        status = "PASSED" if success else "FAILED"
        print(f"[{status}] {name}")
        if error: print(f"      Error: {error}")

    def show_summary(self):
        print("\n" + "="*40)
        print("          TEST SUMMARY REPORT")
        print("="*40)
        passed = sum(1 for r in self.results if r["success"])
        total = len(self.results)
        for r in self.results:
            mark = "✅" if r["success"] else "❌"
            print(f"{mark} {r['name']}")
        print("="*40)
        print(f"TOTAL: {total} | PASSED: {passed} | FAILED: {total-passed}")
        print("="*40 + "\n")

report = TestReport()

def test_auth_me():
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        response = client.get("/auth/me", headers={"init-data": valid_init_data})
        assert response.status_code == 200
        data = response.json()
        assert data["username"] == "testuser"
        report.add("Auth: /auth/me profile load", True)
    except Exception as e:
        report.add("Auth: /auth/me profile load", False, str(e))

def test_apple_connect():
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        payload = {"email": "test@icloud.com", "password": "abcd-efgh-ijkl-mnop"}
        response = client.post("/auth/apple/connect", headers={"init-data": valid_init_data}, json=payload)
        assert response.status_code == 200
        report.add("Auth: Apple Calendar connection", True)
    except Exception as e:
        report.add("Auth: Apple Calendar connection", False, str(e))

async def test_meeting_lifecycle():
    """Tests full cycle: Create (mocked sync) -> Check DB -> Delete -> Check Cleanup"""
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        
        # 1. Setup mock connections in DB for the test user
        db = next(override_get_db())
        user = db.query(models.User).filter(models.User.telegram_id == 12345).first()
        
        # Add a mock Apple connection to trigger that logic
        apple_conn = models.CalendarConnection(
            user_id=user.id,
            provider="apple",
            auth_data=json.dumps({"email": "test@apple.com", "password": "pass"}),
            is_active=1
        )
        db.add(apple_conn)
        db.commit()

        # 2. Mock external services
        with patch("caldav_service.AppleCalendarService.create_event", return_value="https://icloud.com/event/123"):
            with patch("caldav_service.AppleCalendarService.delete_event", return_value=True):
                
                # A. CREATE MEETING
                start = (datetime.datetime.now() + datetime.timedelta(days=1)).isoformat()
                end = (datetime.datetime.now() + datetime.timedelta(days=1, hours=1)).isoformat()
                
                payload = {
                    "summary": "Lifecycle Test",
                    "start_time": start,
                    "end_time": end,
                    "attendees": [],
                    "idempotency_key": f"test_{int(time.time())}"
                }
                
                response = client.post("/api/meetings/create", headers={"init-data": valid_init_data}, json=payload)
                assert response.status_code == 200
                meeting_id = response.json()["meeting_id"]
                report.add("Lifecycle: Create Meeting (Backend + Apple Sync)", True)

                # B. VERIFY DB RECORD & IDs
                db.expire_all()
                meeting = db.query(models.GroupMeeting).get(meeting_id)
                assert meeting.apple_event_id == "https://icloud.com/event/123"
                report.add("Lifecycle: Database ID Verification (apple_event_id stored)", True)

                # C. SOFT DELETE (Creator)
                # First call to delete_meeting should mark is_cancelled=True
                response = client.delete(f"/api/meetings/{meeting_id}", headers={"init-data": valid_init_data})
                assert response.status_code == 200
                
                db.expire_all()
                meeting = db.query(models.GroupMeeting).get(meeting_id)
                assert meeting.is_cancelled is True
                assert meeting.apple_event_id is None # Should be cleared after first delete attempt
                report.add("Lifecycle: Soft Delete & External Cleanup (apple_event_id cleared)", True)

                # D. HARD DELETE
                response = client.delete(f"/api/meetings/{meeting_id}", headers={"init-data": valid_init_data})
                assert response.status_code == 200
                
                db.expire_all()
                meeting = db.query(models.GroupMeeting).get(meeting_id)
                assert meeting is None
                report.add("Lifecycle: Hard Delete from Database", True)

    except Exception as e:
        report.add("Lifecycle: Full meeting flow", False, str(e))

if __name__ == "__main__":
    import asyncio
    print("Starting Advanced Backend Lifecycle Tests...\n")
    test_auth_me()
    test_apple_connect()
    
    # Run async lifecycle test using modern asyncio.run()
    asyncio.run(test_meeting_lifecycle())
    
    report.show_summary()
