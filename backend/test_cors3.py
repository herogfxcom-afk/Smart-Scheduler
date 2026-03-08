import requests

# Test the debug endpoint to see deployed version
url_base = "https://web-production-ed04f.up.railway.app"

print("=== GET / ===")
r = requests.get(f"{url_base}/")
print("Status:", r.status_code)
print("Body:", r.text)

# Try a special debug endpoint to confirm if our new code is deployed
print("\n=== GET /cors-debug ===")
r2 = requests.get(f"{url_base}/cors-debug", headers={
    "Origin": "https://frontend-herogfxcom-5981s-projects.vercel.app"
})
print("Status:", r2.status_code)
print("Headers:", dict(r2.headers))
