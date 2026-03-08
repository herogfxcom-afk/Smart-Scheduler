import hmac
import hashlib
import time
import json
from urllib.parse import urlencode

# Mock BOT_TOKEN for testing - MUST BE SET BEFORE IMPORTING auth
import os
os.environ["BOT_TOKEN"] = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"

from backend.auth import validate_init_data

def test_validate_init_data():
    # Example data from Telegram docs (modified for test)
    user_data = {
        "id": 1234567,
        "first_name": "Test",
        "last_name": "User",
        "username": "testuser",
        "language_code": "en"
    }
    
    init_data_dict = {
        "auth_date": str(int(time.time())),
        "query_id": "AAHdF6IQAAAAAN0XohD9Vp1f",
        "user": json.dumps(user_data)
    }
    
    # Sort and create data_check_string
    data_check_string = "\n".join([f"{k}={v}" for k, v in sorted(init_data_dict.items())])
    
    # Calculate hash
    secret_key = hmac.new("WebAppData".encode(), os.environ["BOT_TOKEN"].encode(), hashlib.sha256).digest()
    auth_hash = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
    
    # Create full init_data string
    init_data_dict["hash"] = auth_hash
    init_data_str = urlencode(init_data_dict)
    
    # Validate
    result = validate_init_data(init_data_str)
    assert result["id"] == 1234567
    assert result["username"] == "testuser"
