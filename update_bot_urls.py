import os
import requests
from dotenv import load_dotenv

load_dotenv()

bot_token = os.getenv("BOT_TOKEN")
new_url = "https://frontend-2bzsgebt0-herogfxcom-5981s-projects.vercel.app"

# 1. Update Chat Menu Button (for the attachment / bottom left button)
resp1 = requests.post(f"https://api.telegram.org/bot{bot_token}/setChatMenuButton", json={
    "menu_button": {
        "type": "web_app",
        "text": "Smart Scheduler",
        "web_app": {
            "url": new_url
        }
    }
})
print("Set Chat Menu Button Response:", resp1.json())

# Note: We can't update BotFather's "main" direct link app URL without BotFather, but the bottom menu button covers most cases!
