import re

with open("main.py", "r", encoding="utf-8") as f:
    code = f.read()

# 1. Update is_user_in_chat definition
code = code.replace(
    'def is_user_in_chat(chat_id: str, user_telegram_id: int) -> bool:',
    'async def is_user_in_chat(chat_id: str, user_telegram_id: int) -> bool:'
)

code = code.replace(
    '''        resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getChatMember", params={
            "chat_id": target_chat,
            "user_id": int(user_telegram_id)
        }, timeout=5).json()''',
    '''        async with httpx.AsyncClient(timeout=5) as client:\n            resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getChatMember", params={\n                "chat_id": target_chat,\n                "user_id": int(user_telegram_id)\n            })).json()'''
)

# 2. Update is_user_in_chat callers
code = code.replace(
    'membership_status = is_user_in_chat(chat_id, current_user.telegram_id)',
    'membership_status = await is_user_in_chat(chat_id, current_user.telegram_id)'
)
code = code.replace(
    'status = is_user_in_chat(chat_id, u.telegram_id)',
    'status = await is_user_in_chat(chat_id, u.telegram_id)'
)
code = code.replace(
    'if is_user_in_chat(chat_id, current_user.telegram_id) != "ok":',
    'if await is_user_in_chat(chat_id, current_user.telegram_id) != "ok":'
)
code = code.replace(
    'if is_user_in_chat(chat_id, u.telegram_id) == "ok":',
    'if await is_user_in_chat(chat_id, u.telegram_id) == "ok":'
)

# 3. Update _setup_bot_ui
code = code.replace(
    'resp = requests.post(f"https://api.telegram.org/bot{bot_token}/setWebhook", json={"url": webhook_url, "drop_pending_updates": True}).json()',
    'async with httpx.AsyncClient(timeout=5) as client:\n            resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/setWebhook", json={"url": webhook_url, "drop_pending_updates": True})).json()'
)
code = code.replace(
    '''    menu_resp = requests.post(f"https://api.telegram.org/bot{bot_token}/setChatMenuButton", json={''',
    '''    async with httpx.AsyncClient(timeout=5) as client:\n        menu_resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/setChatMenuButton", json={'''
)
code = code.replace("        }\n    }).json()\n    print(f\"MENU BUTTON SETUP: {menu_resp}\")", "        }\n    })).json()\n        print(f\"MENU BUTTON SETUP: {menu_resp}\")")


# 4. _handle_inline_query
code = code.replace(
    'bot_info_resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getMe").json()',
    'async with httpx.AsyncClient(timeout=5) as client:\n            bot_info_resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getMe")).json()'
)
code = code.replace(
    '''        requests.post(f"https://api.telegram.org/bot{bot_token}/answerInlineQuery", json={''',
    '''        async with httpx.AsyncClient(timeout=5) as client:\n            await client.post(f"https://api.telegram.org/bot{bot_token}/answerInlineQuery", json={'''
)


# 5. _send_sync_invite
code = code.replace(
    '''def _send_sync_invite(bot_token: str, chat_id: int, chat_title: str, db: Session):''',
    '''async def _send_sync_invite(bot_token: str, chat_id: int, chat_title: str, db: Session):'''
)
code = code.replace(
    '''    bot_username = bot_info_resp.get("result", {}).get("username", BOT_USERNAME_FALLBACK)''',
    '''        bot_username = bot_info_resp.get("result", {}).get("username", BOT_USERNAME_FALLBACK)'''
)

code = code.replace(
    '''    result = requests.post(
        f"https://api.telegram.org/bot{bot_token}/sendMessage",
        json=payload
    ).json()''',
    '''    async with httpx.AsyncClient(timeout=5) as client:\n        result = (await client.post(\n            f"https://api.telegram.org/bot{bot_token}/sendMessage",\n            json=payload\n        )).json()'''
)


# 6. invite_group_sync calls _send_sync_invite
code = code.replace(
    '''        _send_sync_invite(bot_token, chat_id, chat_title, db)''',
    '''        await _send_sync_invite(bot_token, chat_id, chat_title, db)'''
)

# 7. invite_group_sync getting bot info and editing message
code = code.replace(
    '''            bot_resp = requests.get(f"https://api.telegram.org/bot{bot_token}/getMe").json()''',
    '''            async with httpx.AsyncClient(timeout=5) as client:\n                bot_resp = (await client.get(f"https://api.telegram.org/bot{bot_token}/getMe")).json()'''
)
code = code.replace(
    '''            resp = requests.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={''',
    '''            async with httpx.AsyncClient(timeout=5) as client:\n                resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={'''
)

# 8. finalize_meeting editing and sending message
code = code.replace(
    '''            edit_resp = requests.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={''',
    '''            async with httpx.AsyncClient(timeout=5) as client:\n                edit_resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/editMessageText", json={'''
)
code = code.replace(
    '''        send_resp = requests.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json={''',
    '''        async with httpx.AsyncClient(timeout=5) as client:\n            send_resp = (await client.post(f"https://api.telegram.org/bot{bot_token}/sendMessage", json={'''
)

with open("main_new.py", "w", encoding="utf-8") as f:
    f.write(code)

print("Done generating main_new.py")
