import asyncio
import logging
import os
import time
from aiogram import Bot, Dispatcher, types
from aiogram.types import InlineQuery, InlineQueryResultArticle, InputTextMessageContent

# Load from .env if exists
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)

BOT_TOKEN = os.getenv("BOT_TOKEN", "8748943521:AAF_kdSY0RAYJFwDAkQi8OCL18Ce0TrilYA")
FRONTEND_URL = os.getenv("FRONTEND_URL", "https://frontend-2dv3bjo5x-herogfxcom-5981s-projects.vercel.app")

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

@dp.inline_query()
async def test_inline(inline_query: InlineQuery):
    print(f"\n{'='*50}")
    print(f"🎯 INLINE QUERY RECEIVED!")
    print(f"User: {inline_query.from_user.id}")
    print(f"Query: '{inline_query.query}'")
    print(f"{'='*50}\n")
    
    unique_id = f"test_{inline_query.from_user.id}_{int(time.time())}"
    
    try:
        await bot.answer_inline_query(
            inline_query.id,
            results=[
                InlineQueryResultArticle(
                    id=unique_id,
                    title="✨ Magic Sync (DEBUG MODE)",
                    description="If you see this, your inline setting is ON!",
                    input_message_content=InputTextMessageContent(
                        message_text="📊 *Magic Sync: Тестовый запуск*\n\nКликните ниже.",
                        parse_mode="Markdown"
                    ),
                    reply_markup=types.InlineKeyboardMarkup(inline_keyboard=[[
                        types.InlineKeyboardButton(
                            text="🚀 Open App",
                            web_app=types.WebAppInfo(url=f"{FRONTEND_URL}/?startapp=inline_{inline_query.from_user.id}")
                        )
                    ]])
                )
            ],
            cache_time=0,
            is_personal=True
        )
        print("✅ Answer sent successfully!")
    except Exception as e:
        print(f"❌ ERROR sending response: {e}")

async def main():
    bot_info = await bot.get_me()
    print(f"🚀 Starting test poll for @{bot_info.username}...")
    print("WARNING: This will temporarily intercept updates if the webhook is not disabled.")
    print("Now open any Telegram chat and type the bot's name.")
    
    # Delete webhook to allow polling
    await bot.delete_webhook()
    
    try:
        await dp.start_polling(bot)
    finally:
        await bot.session.close()

if __name__ == "__main__":
    if not BOT_TOKEN:
        print("Error: BOT_TOKEN not found in environment!")
    else:
        asyncio.run(main())
