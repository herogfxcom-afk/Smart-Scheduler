import sys
import os
import traceback

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

async def app(scope, receive, send):
    try:
        # Lazy import so errors happen at runtime and can be caught here
        print(f"DEBUG: Vercel Entry Point. Env keys: {list(os.environ.keys())}", flush=True)
        from main import app as main_app
        return await main_app(scope, receive, send)
    except Exception as e:
        error_msg = traceback.format_exc()
        if scope['type'] == 'http':
            response_body = f"Initialization Error:\n\n{error_msg}".encode('utf-8')
            await send({
                'type': 'http.response.start',
                'status': 500,
                'headers': [
                    (b'content-type', b'text/plain'),
                    (b'content-length', str(len(response_body)).encode())
                ]
            })
            await send({
                'type': 'http.response.body',
                'body': response_body
            })
