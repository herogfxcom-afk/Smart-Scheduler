import os
import time
import json
from urllib.parse import urlencode
from fastapi.testclient import TestClient

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

# Now we can import app and database
from backend.main import app
from backend.database import engine, get_db
from backend.models import Base
from sqlalchemy.orm import sessionmaker

# Setup test DB
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)

def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

client = TestClient(app)

def test_auth_me():
    valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
    
    # Test valid
    response = client.get("/auth/me", headers={"init-data": valid_init_data})
    assert response.status_code == 200
    data = response.json()
    assert data["username"] == "testuser"
    assert data["telegram_id"] == 12345
    print("test_auth_me: SUCCESS")

def test_apple_connect():
    valid_init_data = generate_mock_init_data(os.environ["BOT_TOKEN"])
    
    payload = {
        "email": "test@icloud.com",
        "password": "abcd-efgh-ijkl-mnop"
    }
    response = client.post("/auth/apple/connect", headers={"init-data": valid_init_data}, json=payload)
    assert response.status_code == 200
    assert response.json() == {"status": "success"}
    print("test_apple_connect: SUCCESS")

def test_users_endpoint():
    response = client.get("/users")
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    assert len(response.json()) > 0
    print("test_users_endpoint: SUCCESS")

if __name__ == "__main__":
    print("Running tests...")
    test_auth_me()
    test_apple_connect()
    test_users_endpoint()
    print("All tests passed.")
