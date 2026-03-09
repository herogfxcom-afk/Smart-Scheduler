import requests

url = "https://web-production-ed04f.up.railway.app/auth/me"

# Proper preflight with ALL required headers
headers = {
    "Origin": "https://frontend-herogfxcom-5981s-projects.vercel.app",
    "Access-Control-Request-Method": "GET",
    "Access-Control-Request-Headers": "Content-Type, Authorization",
}

print("=== PROPER PREFLIGHT (OPTIONS) ===")
resp = requests.options(url, headers=headers)
print("Status:", resp.status_code)
for k, v in resp.headers.items():
    print(f"  {k}: {v}")

print("\n=== GET with origin ===")
resp2 = requests.get(url, headers={
    "Origin": "https://frontend-herogfxcom-5981s-projects.vercel.app"
})
print("Status:", resp2.status_code)
for k, v in resp2.headers.items():
    print(f"  {k}: {v}")
