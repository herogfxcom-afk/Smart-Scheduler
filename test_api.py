import os
import time
import json
import datetime
from urllib.parse import urlencode
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch, AsyncMock

# Mock env vars before importing app
os.environ["BOT_TOKEN"] = "12345:ABCDE"
os.environ["DATABASE_URL"] = "sqlite:///./test.db"
os.environ["ENCRYPTION_KEY"] = "8n-zI7Y9f_l4o0MhO1vD3w2Q5jK8uB5sH_xZbGcLvV4=" # valid 32 byte base64 fernet key
os.environ["WEBHOOK_SECRET"] = "testsecret"

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
from encryption import encrypt_token
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
            mark = "[OK]" if r["success"] else "[FAIL]"
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

def test_multiple_apple_connect():
    """Regression test for IntegrityError when connecting multiple Apple IDs."""
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        
        # 1. Connect first account
        payload1 = {"email": "account1@icloud.com", "password": "abcd-efgh-ijkl-mnop"}
        response1 = client.post("/auth/apple/connect", headers={"init-data": valid_init_data}, json=payload1)
        assert response1.status_code == 200
        
        # 2. Connect second account (different email)
        payload2 = {"email": "account2@icloud.com", "password": "mnop-qrst-uvwx-yz12"}
        response2 = client.post("/auth/apple/connect", headers={"init-data": valid_init_data}, json=payload2)
        assert response2.status_code == 200
        
        # 3. Verify both exist in DB
        db = next(override_get_db())
        user = db.query(models.User).filter(models.User.telegram_id == 12345).first()
        conns = db.query(models.CalendarConnection).filter_by(user_id=user.id, provider='apple').all()
        assert len(conns) >= 2
        emails = [c.email for c in conns]
        assert "account1@icloud.com" in emails
        assert "account2@icloud.com" in emails
        
        report.add("Auth: Multiple Apple connections (Integrity Fix)", True)
    except Exception as e:
        report.add("Auth: Multiple Apple connections (Integrity Fix)", False, str(e))

async def test_dst_transition():
    """Verifies that meeting creation works during DST transition (March 29, 2026)"""
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        
        # 1. Europe/London DST: 2026-03-29 01:00 AM -> 02:00 AM
        # Meeting at 12:00 PM local time
        # In London: 
        # Before 1 AM: UTC+0
        # After 1 AM: UTC+1
        # So 12:00 PM local is 11:00 AM UTC
        
        start_dst = "2026-03-29T11:00:00.000Z" # 12:00 local
        end_dst = "2026-03-29T12:00:00.000Z"   # 13:00 local
        
        payload = {
            "title": "DST London Test",
            "start": start_dst,
            "end": end_dst,
            "attendee_emails": [],
            "idempotency_key": f"dst_test_{int(time.time())}",
            "tz_offset": 1.0 # London is UTC+1 after transition
        }
        
        response = client.post("/meeting/create", headers={"init-data": valid_init_data}, json=payload)
        assert response.status_code == 200
        report.add("DST: London Transition (After shift)", True)
        
        # 2. Test boundary: Just before shift (e.g. 00:30 AM local = 00:30 AM UTC)
        start_before = "2026-03-29T00:30:00.000Z"
        end_before = "2026-03-29T00:45:00.000Z"
        
        payload_before = {
            "title": "DST Before shift",
            "start": start_before,
            "end": end_before,
            "attendee_emails": [],
            "idempotency_key": f"dst_before_{int(time.time())}",
            "tz_offset": 0.0 # London is UTC+0 before transition
        }
        
        # This might fail working hours check if they are e.g. 09-18
        # Since it's 00:30 AM, it SHOULD be outside working hours.
        response = client.post("/meeting/create", headers={"init-data": valid_init_data}, json=payload_before)
        assert response.status_code == 400
        assert response.json()["detail"] == "outside_working_hours"
        report.add("DST: Correctly identifies night time before shift", True)

        # 3. Non-existent hour test (The Gap)
        # In London: 01:00 AM -> 02:00 AM. 
        # If we send a time that *would* be 01:30 AM local, but we use a fixed offset.
        # 00:30 UTC + 1.0 Offset = 01:30 Local (Non-existent)
        missing_start = "2026-03-29T00:30:00.000Z"
        missing_end = "2026-03-29T00:45:00.000Z"
        
        payload_missing = {
            "title": "DST Missing Hour Test",
            "start": missing_start,
            "end": missing_end,
            "attendee_emails": [],
            "idempotency_key": f"dst_gap_{int(time.time())}",
            "tz_offset": 1.0 # If frontend already switched to BST offset prematurely or user forced it
        }
        
        # System treats it as 01:30 local. Working hours are 09-18.
        # It should still be REJECTED as outside working hours (01:30 < 09:00).
        response = client.post("/meeting/create", headers={"init-data": valid_init_data}, json=payload_missing)
        assert response.status_code == 400
        assert response.json()["detail"] == "outside_working_hours"
        report.add("DST: Non-existent hour (gap) handled by working hours check", True)

    except Exception as e:
        report.add("DST: Transition verify", False, str(e))

async def test_meeting_lifecycle():
    """Tests full cycle: Create (mocked sync) -> Check DB -> Delete -> Check Cleanup"""
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        
        # 1. Setup mock connections in DB for the test user
        db = next(override_get_db())
        user = db.query(models.User).filter(models.User.telegram_id == 12345).first()
        
        # Cleanup any leftover meetings/slots from previous failed test runs
        db.query(models.MeetingInvite).filter(models.MeetingInvite.user_id == user.id).delete()
        db.query(models.GroupMeeting).filter(models.GroupMeeting.user_id == user.id).delete()
        db.query(models.BusySlot).filter(models.BusySlot.user_id == user.id).delete()
        db.commit()
        
        # Add a mock Apple connection to trigger that logic
        apple_conn = models.CalendarConnection(
            user_id=user.id,
            provider="apple",
            auth_data=encrypt_token(json.dumps({"email": "test@apple.com", "password": "pass"})),
            is_active=1
        )
        db.add(apple_conn)
        db.commit()

        # 2. Mock external services
        with patch("caldav_service.AppleCalendarService.create_event", return_value="https://icloud.com/event/123"):
            with patch("caldav_service.AppleCalendarService.delete_event", return_value=True):
                from unittest.mock import AsyncMock
                with patch("calendar_service.GoogleCalendarService.create_event", new_callable=AsyncMock) as mock_google_create:
                    mock_google_create.return_value = "g_event_456"
                    with patch("calendar_service.GoogleCalendarService.delete_event", return_value=True):
                        # A. CREATE MEETING
                        print("DEBUG: Starting meeting creation...")
                        # Use a time that is within working hours (9-18)
                        # Setting to a highly unique future date to avoid any 409 Conflicts in SQLite
                        import random
                        future_days_offset = random.randint(100, 500)
                        future = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=future_days_offset)
                        start_dt = future.replace(hour=12, minute=0, second=0, microsecond=0)
                        end_dt = start_dt + datetime.timedelta(hours=1)
                        
                        start = start_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
                        end = end_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
                        
                        payload = {
                            "title": "Lifecycle Test",
                            "start": start,
                            "end": end,
                            "attendee_emails": [],
                            "idempotency_key": f"test_{int(time.time())}_{random.randint(100,999)}",
                            "tz_offset": 0
                        }
                        
                        # Add a mock Google connection too
                        google_conn = models.CalendarConnection(
                            user_id=user.id,
                            provider="google",
                            auth_data=encrypt_token(json.dumps({"email": "test@gmail.com", "token": "abc"})),
                            is_active=1
                        )
                        db.add(google_conn)
                        db.commit()
                        
                        with patch("httpx.AsyncClient.post", return_value=MagicMock(status_code=200)):
                            response = client.post("/meeting/create", headers={"init-data": valid_init_data}, json=payload)
                            if response.status_code != 200:
                                print(f"DEBUG: Create meeting failed: {response.status_code} - {response.text}")
                            assert response.status_code == 200
                        meeting_id = response.json().get("id")
                        assert meeting_id is not None
                        
                        # Create a simulate persistent BusySlot for this meeting
                        # This simulates what happens after a sync or manual entry
                        busy_sim = models.BusySlot(
                            user_id=user.id,
                            start_time=start_dt,
                            end_time=end_dt,
                            summary="Lifecycle Test",
                            is_external=False
                        )
                        db.add(busy_sim)
                        db.commit()
                        
                        report.add("Lifecycle: Create Meeting (Backend + Sync)", True)

                        # B. VERIFY DB RECORD & IDs
                        print("DEBUG: Verifying database record...")
                        db.expire_all()
                        meeting = db.query(models.GroupMeeting).get(meeting_id)
                        assert meeting.apple_event_id == "https://icloud.com/event/123"
                        assert meeting.google_event_id == "g_event_456"
                        report.add("Lifecycle: Database ID Verification (apple and google IDs stored)", True)

                # C. SOFT DELETE (Creator)
                print("DEBUG: Starting soft delete...")
                response = client.delete(f"/api/meetings/{meeting_id}", headers={"init-data": valid_init_data})
                assert response.status_code == 200
                
                db.expire_all()
                meeting = db.query(models.GroupMeeting).get(meeting_id)
                assert meeting.is_cancelled is True
                assert meeting.apple_event_id is None
                assert meeting.google_event_id is None
                
                # VERIFY BusySlot is PURGED
                busy_check = db.query(models.BusySlot).filter_by(user_id=user.id, start_time=start_dt, end_time=end_dt).first()
                assert busy_check is None
                report.add("Lifecycle: Soft Delete & Atomic BusySlot Purge", True)

                # D. HARD DELETE
                print("DEBUG: Starting hard delete...")
                response = client.delete(f"/api/meetings/{meeting_id}", headers={"init-data": valid_init_data})
                assert response.status_code == 200
                
                db.expire_all()
                meeting = db.query(models.GroupMeeting).get(meeting_id)
                assert meeting is None
                report.add("Lifecycle: Hard Delete from Database", True)

    except Exception as e:
        import traceback
        traceback.print_exc()
        report.add("Lifecycle: Full meeting flow", False, str(e))

async def test_cancellation_interactive():
    """Verifies that the new _handle_callback_query parses cancellation keeping/removing."""
    try:
        db = next(override_get_db())
        user = db.query(models.User).filter(models.User.telegram_id == 12345).first()
        
        # 1. Create a dummy meeting and invite for this user
        dummy_meeting = models.GroupMeeting(
            group_id=None,
            user_id=user.id,
            title="Interactive Cancel Test",
            start_time=datetime.datetime.now(datetime.timezone.utc),
            end_time=datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=1),
            location="Remote",
            idempotency_key=f"ic_{int(time.time())}"
        )
        db.add(dummy_meeting)
        db.commit()
        
        dummy_invite = models.MeetingInvite(
            meeting_id=dummy_meeting.id,
            user_id=user.id,
            status="pending"
        )
        db.add(dummy_invite)
        db.commit()

        # 2. Mock a callback query from Telegram
        from main import _handle_callback_query
        
        mock_cb = {
            "id": "123456",
            "from": {"id": 12345},
            "message": {"chat": {"id": 12345}, "message_id": 999},
            "data": f"delmtg_keep_{dummy_meeting.id}"
        }
        
        # We need to mock httpx.AsyncClient to prevent actual HTTP calls to Telegram API during test
        with patch("httpx.AsyncClient.post", return_value=MagicMock(status_code=200)):
            await _handle_callback_query(mock_cb, "fake_token", db)
        
        db.expire_all()
        check_invite = db.query(models.MeetingInvite).get(dummy_invite.id)
        assert check_invite.status == "cancelled_kept"
        report.add("Webhook: Interactive Telegram Cancellation (Keep)", True)
        
        # 3. Clean up
        db.delete(check_invite)
        db.delete(dummy_meeting)
        db.commit()
        
    except Exception as e:
        report.add("Webhook: Interactive Telegram Cancellation", False, str(e))

async def test_inline_query_handler():
    """Verifies that inline queries send direct HTTP requests to answerInlineQuery."""
    try:
        from main import telegram_webhook
        
        mock_update = {
            "update_id": 12345,
            "inline_query": {
                "id": "query_123",
                "from": {"id": 12345},
                "query": "",
                "offset": ""
            }
        }
        
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value.status_code = 200
            
            response = client.post(
                "/webhook/bot", 
                json=mock_update, 
                headers={"X-Telegram-Bot-Api-Secret-Token": "testsecret"}
            )
            assert response.status_code == 200
            assert response.json() == {"ok": True}
            
            # Verify httpx.post was called with answerInlineQuery
            mock_post.assert_called_once()
            args, kwargs = mock_post.call_args
            assert "answerInlineQuery" in args[0]
            assert kwargs["json"]["inline_query_id"] == "query_123"
            
            # Verify the button is a URL button (not web_app) for inline
            results = kwargs["json"]["results"]
            assert len(results) == 1
            button = results[0]["reply_markup"]["inline_keyboard"][0][0]
            assert "url" in button
            
            report.add("Webhook: Inline Query direct HTTP handler", True)
    except Exception as e:
        report.add("Webhook: Inline Query direct HTTP handler", False, str(e))

async def test_sync_command_in_group():
    """Verifies that /sync in a group sends a url button to avoid BUTTON_TYPE_INVALID."""
    try:
        from main import telegram_webhook
        
        mock_update = {
            "update_id": 67890,
            "message": {
                "message_id": 456,
                "from": {"id": 999},
                "chat": {
                    "id": -100123456789,
                    "title": "Test Group",
                    "type": "group"
                },
                "text": "/sync",
                "entities": [{"type": "bot_command", "offset": 0, "length": 5}]
            }
        }
        
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value.status_code = 200
            mock_post.return_value.json = MagicMock(return_value={"ok": True})
            
            # We also need to mock the getMe call inside _send_sync_invite
            with patch("httpx.AsyncClient.get", new_callable=AsyncMock) as mock_get:
                mock_get.return_value.json = MagicMock(return_value={"result": {"username": "testbot"}})
                
                response = client.post(
                    "/webhook/bot", 
                    json=mock_update, 
                    headers={"X-Telegram-Bot-Api-Secret-Token": "testsecret"}
                )
                assert response.status_code == 200
                assert response.json() == {"ok": True}
                
                # Verify httpx.post was called with sendMessage
                mock_post.assert_called_once()
                args, kwargs = mock_post.call_args
                assert "sendMessage" in args[0]
                assert kwargs["json"]["chat_id"] == -100123456789
                
                # Check that reply_markup is correct and uses 'url' and not 'web_app'
                reply_markup = json.loads(kwargs["json"]["reply_markup"])
                button = reply_markup["inline_keyboard"][0][0]
                assert "url" in button
                assert "web_app" not in button
                assert "startapp=group_n100123456789" in button["url"]
                
                report.add("Webhook: Group /sync command uses url deep link", True)
    except Exception as e:
        report.add("Webhook: Group /sync command uses url deep link", False, str(e))

def test_ics_export():
    """Verifies that the /api/meetings/{id}/ics endpoint works with a token in query params."""
    try:
        valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
        db = next(override_get_db())
        user = db.query(models.User).filter(models.User.telegram_id == 12345).first()
        
        # 1. Create a meeting
        start_dt = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)
        end_dt = start_dt + datetime.timedelta(hours=1)
        
        meeting = models.GroupMeeting(
            user_id=user.id,
            title="ICS Test Meeting",
            description="Testing backend ICS generation",
            start_time=start_dt,
            end_time=end_dt,
            idempotency_key=f"ics_test_{int(time.time())}"
        )
        db.add(meeting)
        db.commit()
        
        # 2. Request ICS with token in query params
        response = client.get(f"/api/meetings/{meeting.id}/ics", params={"token": valid_init_data})
        
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/calendar")
        assert "attachment" in response.headers["content-disposition"]
        assert f"meeting_{meeting.id}.ics" in response.headers["content-disposition"]
        
        content = response.text
        assert "BEGIN:VCALENDAR" in content
        assert "BEGIN:VEVENT" in content
        assert "SUMMARY:ICS Test Meeting" in content
        assert "DESCRIPTION:Testing backend ICS generation" in content
        
        report.add("API: Meeting ICS export (Query Param Auth)", True)
    except Exception as e:
        report.add("API: Meeting ICS export (Query Param Auth)", False, str(e))

if __name__ == "__main__":
    import asyncio
    print("Starting Advanced Backend Lifecycle Tests...\n")
    test_auth_me()
    test_multiple_apple_connect()
    test_ics_export()
    
    # Run async tests
    async def run_async_tests():
        await test_dst_transition()
        await test_meeting_lifecycle()
        await test_cancellation_interactive()
        await test_inline_query_handler()
        await test_sync_command_in_group()
        
    asyncio.run(run_async_tests())
    
    report.show_summary()
