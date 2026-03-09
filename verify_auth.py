import hmac
import hashlib
import json
import time
from urllib.parse import urlencode

def generate_mock_init_data(bot_token, user_id=12345, username="testuser"):
    """Generates a valid-looking Telegram initData string for testing."""
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
    
    # Data-check-string
    data_check_string = "\n".join([f"{k}={v}" for k, v in sorted(vals.items())])
    
    # Secret Key
    secret_key = hmac.new("WebAppData".encode(), bot_token.encode(), hashlib.sha256).digest()
    
    # Hash
    h = hmac.new(secret_key, data_check_string.encode(), hashlib.sha256).hexdigest()
    
    vals["hash"] = h
    return urlencode(vals)

if __name__ == "__main__":
    # Example usage for manual testing with curl/Postman
    TOKEN = "YOUR_BOT_TOKEN_HERE" # Replace with real token if testing real backend
    print("Mock init-data Header Value:")
    print(generate_mock_init_data(TOKEN))
