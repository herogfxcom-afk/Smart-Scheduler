import sys
import os
import traceback

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from main import app
except Exception as e:
    error_msg = traceback.format_exc()
    # Create a fallback ASGI app that returns the error message
    async def app(scope, receive, send):
        assert scope['type'] == 'http'
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
