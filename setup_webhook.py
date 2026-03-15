import os
import requests
import json
from dotenv import load_dotenv

load_dotenv()

def setup_webhook():
    token = os.getenv("BOT_TOKEN")
    api_url = os.getenv("API_URL") # This should now be https://smart-scheduler-production-2006.up.railway.app
    secret = os.getenv("WEBHOOK_SECRET")
    
    if not token or not api_url:
        print(f"Error: Missing BOT_TOKEN ({bool(token)}) or API_URL ({bool(api_url)})")
        return

    webhook_url = f"{api_url.rstrip('/')}/webhook/bot"
    print(f"Setting webhook to: {webhook_url}")
    
    payload = {
        "url": webhook_url,
        "drop_pending_updates": True,
        "allowed_updates": ["message", "callback_query", "inline_query"]
    }
    
    if secret:
        payload["secret_token"] = secret
        print("Using WEBHOOK_SECRET for security.")

    r = requests.post(f"https://api.telegram.org/bot{token}/setWebhook", json=payload)
    print(f"Response: {r.json()}")

if __name__ == "__main__":
    setup_webhook()
