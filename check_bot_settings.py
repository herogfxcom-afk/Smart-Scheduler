import os
import requests
import json
from dotenv import load_dotenv

load_dotenv()

def check_bot():
    token = os.getenv("BOT_TOKEN")
    if not token:
        print("Error: BOT_TOKEN not found in .env")
        return

    print(f"Checking bot settings for token: {token[:10]}...")
    
    # 1. getMe
    r = requests.get(f"https://api.telegram.org/bot{token}/getMe")
    me = r.json()
    print(f"\n[getMe]:\n{json.dumps(me, indent=2)}")
    
    if me.get("ok"):
        result = me.get("result", {})
        if not result.get("supports_inline_queries"):
            print("\n!!! WARNING: Inline Mode is DISABLED in @BotFather. You MUST enable it!")
        else:
            print("\nInline Mode is ENABLED in @BotFather. Good.")

    # 2. getWebhookInfo
    r = requests.get(f"https://api.telegram.org/bot{token}/getWebhookInfo")
    info = r.json()
    print(f"\n[getWebhookInfo]:\n{json.dumps(info, indent=2)}")
    
    if info.get("ok"):
        res = info.get("result", {})
        allowed = res.get("allowed_updates", [])
        if "inline_query" not in allowed:
            print("\n!!! WARNING: 'inline_query' is MISSING from allowed_updates!")
        else:
            print("\n'inline_query' is present in allowed_updates. Good.")

if __name__ == "__main__":
    check_bot()
