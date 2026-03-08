"""
Get build logs for a specific failed deployment
"""
import requests
import json

TOKEN = "rw_Fe26.2**3205df43fc50cfe63c0a4785226c4eaa41498241e98da8fcca223ad30931ba17*Hhvi0QE2Ir2CTFwF_kMh8Q*t0L9MDTrVwPol9uhrIZQns28DtUNDh4KFTLJ-gcRe-FbC0aooAtsDkMyot5ihj5COtdGa2Uoxc9Zr0a2S-O9xA*1775570350782*bcb3478ff08892e3f70803ccd8ed7a4081fa51210a99008f74f73af3f18b531b*PaWs0i3GpPhlrg1aOJKvCPWvJX-cdRYSfm-HYJarz7o"

# Most recent failed deployment
DEPLOYMENT_ID = "8cbce2d9-1f4c-413b-8924-269142b5c52b"

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

query = """
query {
  deployment(id: "%s") {
    id
    status
    createdAt
    staticUrl
    canRollback
    environmentId
    serviceId
  }
  deploymentLogs(deploymentId: "%s", limit: 200) {
    message
    severity
    timestamp
  }
}
""" % (DEPLOYMENT_ID, DEPLOYMENT_ID)

resp = requests.post(
    "https://backboard.railway.com/graphql/v2",
    json={"query": query},
    headers=headers
)
resp = requests.post(
    "https://backboard.railway.com/graphql/v2",
    json={"query": query},
    headers=headers
)
data = resp.json()
if "errors" in data:
    print("Errors:", json.dumps(data["errors"], indent=2))
else:
    dep = data.get("data", {}).get("deployment", {})
    print(f"Deployment ID: {dep.get('id')}")
    print(f"Status: {dep.get('status')}")
    print(f"Static URL: {dep.get('staticUrl')}")
    
    logs = data.get("data", {}).get("deploymentLogs", [])
    print(f"\nTotal log entries: {len(logs)}")
    for log in logs:
        print(f"[{log.get('severity', '?')}] {log.get('message', '')[:200]}")
