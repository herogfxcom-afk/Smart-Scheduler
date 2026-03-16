import os
import time
import json
import datetime
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch, AsyncMock
from zoneinfo import ZoneInfo

# Mock env vars
os.environ["BOT_TOKEN"] = "12345:ABCDE"
os.environ["DATABASE_URL"] = "sqlite:///./test_fixes.db"
os.environ["ENCRYPTION_KEY"] = "8n-zI7Y9f_l4o0MhO1vD3w2Q5jK8uB5sH_xZbGcLvV4="
os.environ["WEBHOOK_SECRET"] = "testsecret"

from main import app
from database import engine, get_db
import models
from encryption import encrypt_token, decrypt_token
from sqlalchemy.orm import sessionmaker

TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
models.Base.metadata.drop_all(bind=engine)
models.Base.metadata.create_all(bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

def generate_mock_init_data():
    from test_api import generate_mock_init_data as gen_init
    return gen_init(os.environ["BOT_TOKEN"])

def test_grid_alignment():
    """Проверка округления времени начала в /calendar/free-slots до 30 минут."""
    print("Testing grid alignment rounding...")
    db = next(override_get_db())
    # Pre-create user to avoid auth.py trying to INSERT and failing due to mocks
    if not db.query(models.User).filter_by(telegram_id=12345).first():
        user = models.User(telegram_id=12345, username="testuser", first_name="Test")
        db.add(user)
        db.commit()

    init_data = generate_mock_init_data()
    
    # Мокаем текущее время (напр. 17:36)
    mock_now = datetime.datetime(2026, 3, 16, 17, 36, 45, tzinfo=datetime.timezone.utc)
    
    # Патчим только в main.py, чтобы не ломать SQLAlchemy/models
    with patch("main.datetime") as mock_main_dt:
        mock_main_dt.now.return_value = mock_now
        # Сохраняем оригинальные методы, которые могут понадобиться
        mock_main_dt.fromisoformat = datetime.datetime.fromisoformat
        mock_main_dt.combine = datetime.datetime.combine
        mock_main_dt.min = datetime.datetime.min
        mock_main_dt.max = datetime.datetime.max
        
        with patch("main.is_user_in_chat", new_callable=AsyncMock) as mock_is_member:
            mock_is_member.return_value = "ok"
            
            response = client.post("/calendar/free-slots", 
                headers={"init-data": init_data}, 
                json={
                    "telegram_ids": [12345], 
                    "timezone": "UTC",
                    "chat_id": "n12345678" # Trigger group mode (snap_to_local=False)
                }
            )
        
        if response.status_code != 200:
            print(f"[FAIL] Server returned {response.status_code}: {response.text}")
            assert response.status_code == 200

        slots = response.json()["free_slots"]
        if slots:
            first_slot_start = slots[0]["start"]
            print(f"DEBUG: First slot start: {first_slot_start}")
            # Должно быть 17:30, а не 17:36
            assert "17:30:00Z" in first_slot_start or "17:30:00+00:00" in first_slot_start
            print("[OK] Grid alignment: Start time rounded correctly to 17:30:00")
        else:
            print("[SKIP] No slots found to verify (working hours?)")

async def test_participant_id_storage():
    """Проверка корректного сохранения google_event_id как строки для участников."""
    print("Testing participant ID storage (string vs None error)...")
    db = next(override_get_db())
    
    # 1. Получаем или создаем пользователя
    user = db.query(models.User).filter_by(telegram_id=12345).first()
    if not user:
        user = models.User(telegram_id=12345, username="test", timezone="UTC")
        db.add(user)
        db.commit()
    
    meeting = models.GroupMeeting(
        user_id=user.id,
        title="Test Meeting",
        start_time=datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
        end_time=datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1, hours=1),
        idempotency_key=f"test_id_storage_{int(time.time())}"
    )
    db.add(meeting)
    db.commit()
    
    invite = models.MeetingInvite(meeting_id=meeting.id, user_id=user.id, status="pending")
    db.add(invite)
    
    conn = models.CalendarConnection(
        user_id=user.id,
        provider="google",
        auth_data=encrypt_token("mock_refresh"),
        is_active=1
    )
    db.add(conn)
    db.commit()
    
    # 2. Мокаем Google API
    init_data = generate_mock_init_data()
    with patch("calendar_service.GoogleCalendarService.create_event", new_callable=AsyncMock) as mock_create:
        # Важно: сервис теперь возвращает СТРОКУ (ID), а не словарь
        mock_create.return_value = "google_event_id_string_123"
        
        response = client.post(f"/api/invites/{invite.id}/respond", 
            headers={"init-data": init_data}, 
            json={"status": "accepted"}
        )
        assert response.status_code == 200
        
        # 3. Проверяем БД
        db.refresh(invite)
        assert invite.google_event_id == "google_event_id_string_123"
        assert invite.google_event_id is not None
        print("[OK] Participant ID storage: google_event_id saved correctly as string")

async def test_participant_deletion_api_call():
    """Проверка, что при удалении встречи участником вызывается API с верным ID."""
    print("Testing participant external deletion call...")
    db = next(override_get_db())
    user = db.query(models.User).filter_by(telegram_id=12345).first()
    
    # Создаем отмененную встречу с сохраненным ID
    meeting = models.GroupMeeting(
        user_id=999, # Создатель другой
        title="Cancelled Meeting",
        start_time=datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
        end_time=datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1, hours=1),
        is_cancelled=True
    )
    db.add(meeting)
    db.commit()
    
    invite = models.MeetingInvite(
        meeting_id=meeting.id, 
        user_id=user.id, 
        status="cancelled", 
        google_event_id="delete_me_id_123"
    )
    db.add(invite)
    db.commit()
    
    init_data = generate_mock_init_data()
    with patch("calendar_service.GoogleCalendarService.delete_event", new_callable=AsyncMock) as mock_delete:
        mock_delete.return_value = True
        
        # Участник нажимает "Удалить" (окончательная очистка)
        response = client.delete(f"/api/meetings/{meeting.id}", headers={"init-data": init_data})
        assert response.status_code == 200
        
        # Проверяем, что мок был вызван именно с нашим ID
        mock_delete.assert_called_with("delete_me_id_123")
        print("[OK] Participant deletion: External API called with correct event ID")

if __name__ == "__main__":
    import asyncio
    print("\nStarting Stability Tests v1.0.3...\n")
    
    test_grid_alignment()
    
    async def run_async():
        await test_participant_id_storage()
        await test_participant_deletion_api_call()
    
    asyncio.run(run_async())
    print("\nAll Fixes Verified Successfully!\n")
