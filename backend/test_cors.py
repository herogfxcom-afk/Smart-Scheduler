import requests

url = "https://web-production-ed04f.up.railway.app/auth/me"
headers = {
    "Origin": "https://frontend-herogfxcom-5981s-projects.vercel.app",
    "Access-Control-Request-Method": "GET"
}

resp = requests.options(url, headers=headers)
print("OPTIONS status code:", resp.status_code)
print("OPTIONS headers:", dict(resp.headers))

resp2 = requests.get(url, headers={"Origin": "https://frontend-herogfxcom-5981s-projects.vercel.app"})
print("GET status code:", resp2.status_code)
print("GET headers:", dict(resp2.headers))
