import os
import asyncio
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import CommandStart, Command
from aiogram.utils.keyboard import InlineKeyboardBuilder
from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
APP_URL = os.getenv("APP_URL", "https://smart-scheduler-production-2006.up.railway.app")

from .database import SessionLocal
from . import models
from sqlalchemy.orm import Session

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

@dp.message(CommandStart())
async def cmd_start(message: types.Message):
    """Handles /start and deep linking."""
    args = message.text.split()
    bot_info = await bot.get_me()
    if len(args) > 1 and args[1].startswith("group_"):
        chat_id = args[1].replace("group_", "")
        await message.answer(
            f"👋 Welcome! I'll help you find time for your group.\n\n"
            f"Click the button below to join the sync!",
            reply_markup=InlineKeyboardBuilder().button(
                text="🚀 Open Mini App",
                url=f"https://t.me/{bot_info.username}/app?startapp=group_{chat_id}"
            ).as_markup()
        )
    else:
        await message.answer("Hello! Add me to a group and type /sync to find the best time for everyone.")

@dp.message(Command("sync"))
async def cmd_sync(message: types.Message):
    """Triggered in groups to start the Magic Sync."""
    if message.chat.type not in ["group", "supergroup"]:
        await message.answer("This command only works in groups!")
        return

    chat_id = message.chat.id
    bot_info = await bot.get_me()
    builder = InlineKeyboardBuilder()
    # Use direct deep link instead of web_app for better group persistence
    builder.button(
        text="📊 Magic Sync",
        url=f"https://t.me/{bot_info.username}/app?startapp=group_{chat_id}"
    )
    
    msg = await message.answer(
        f"📊 **Ищу общее время для встречи: {message.chat.title}**\n\n"
        "Нажмите кнопку ниже, чтобы присоединиться к поиску и синхронизировать свой календарь.",
        parse_mode="Markdown",
        reply_markup=builder.as_markup()
    )
    
    # Save message_id to Group
    with SessionLocal() as db:
        group = db.query(models.Group).filter(models.Group.telegram_chat_id == chat_id).first()
        if not group:
            group = models.Group(telegram_chat_id=chat_id, title=message.chat.title or "Group")
            db.add(group)
        group.last_invite_message_id = msg.message_id
        db.commit()

@dp.inline_query()
async def inline_handler(inline_query: types.InlineQuery):
    """Handles inline queries to search for free time."""
    query = inline_query.query.strip() or "Новая встреча"
    bot_user = await bot.get_me()
    
    # Format: startapp=inline_[encoded_title]
    # For now keep it simple: group_ID or just open app
    sync_url = f"https://t.me/{bot_user.username}/app?startapp=new_meeting"
    
    builder = InlineKeyboardBuilder()
    builder.button(
        text="🗓 Open Scheduler",
        url=sync_url
    )
    
    result = types.InlineQueryResultArticle(
        id=f"sync_{inline_query.id}",
        title=f"📅 Встреча: {query}",
        description="Создать карточку синхронизации для выбора времени",
        input_message_content=types.InputTextMessageContent(
            message_text=f"📊 **Найти лучшее время для встречи: {query}**\n\n"
                         "Нажмите кнопку ниже, чтобы синхронизировать календари!",
            parse_mode="Markdown"
        ),
        reply_markup=builder.as_markup()
    )
    
    await inline_query.answer([result], is_personal=True, cache_time=0)

async def main():
    print("Bot is starting...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
