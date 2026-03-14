
import os
import asyncio
import httpx
from dotenv import load_dotenv

load_dotenv()

async def test_notification():
    bot_token = os.getenv("BOT_TOKEN")
    chat_id = os.getenv("TELEGRAM_CHAT_ID") or "-1002361132629" # Example from previous context
    
    if not bot_token:
        print("Error: BOT_TOKEN not found in .env")
        return

    print(f"Testing notification to {chat_id}...")
    
    # Simple version of the helper
    def clean_id(cid):
        cid = str(cid)
        if cid.startswith("n"):
            return "-" + cid[1:]
        return cid

    target = clean_id(chat_id)
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {
        "chat_id": target,
        "text": "🤖 *Diagnostic:* Система уведомлений проверена и работает!\n\nЭто сообщение подтверждает, что теперь я смогу уведомлять участников об отмене встреч.",
        "parse_mode": "Markdown"
    }

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(url, json=payload)
            print(f"Response Status: {resp.status_code}")
            print(f"Response: {resp.text}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_notification())
