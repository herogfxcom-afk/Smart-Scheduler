import requests

url = "http://127.0.0.1:9999/auth/me"
headers = {
    "Origin": "https://frontend-herogfxcom-5981s-projects.vercel.app",
    "Access-Control-Request-Method": "GET"
}

resp = requests.options(url, headers=headers)
print("OPTIONS status code:", resp.status_code)
print("OPTIONS headers:", dict(resp.headers))
