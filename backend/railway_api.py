"""
Use Railway GraphQL API to list and redeploy latest deployment
"""
import requests
import os

# Railway token from environment or config file
# Check common config locations
import pathlib
import json

token = None
config_paths = [
    pathlib.Path.home() / ".railway" / "config.json",
    pathlib.Path.home() / "AppData" / "Roaming" / "railway" / "config.json",
    pathlib.Path.home() / "AppData" / "Local" / "railway" / "config.json",
]

for p in config_paths:
    if p.exists():
        print(f"Found config at: {p}")
        with open(p) as f:
            data = json.load(f)
            token = data.get("token") or data.get("railwayToken")
            print("Token found:", bool(token))
        break
else:
    print("No Railway config file found in:", [str(p) for p in config_paths])
    # Try env
    token = os.environ.get("RAILWAY_TOKEN")
    print("From env RAILWAY_TOKEN:", bool(token))

if token:
    print("\nToken starts with:", token[:20], "...")
    
    # List deployments
    PROJECT_ID = "95010755-d4e6-4f6a-914a-b2c7b54c737e"
    SERVICE_ID = "a96ff229-d455-45b3-9fff-59befbcd9c55"
    ENV_ID = "14cdd09e-808a-4f25-9eb1-565aea1ca454"
    
    query = """
    query {
      deployments(input: { serviceId: "%s", environmentId: "%s" }) {
        edges {
          node {
            id
            status
            createdAt
            url
          }
        }
      }
    }
    """ % (SERVICE_ID, ENV_ID)
    
    resp = requests.post(
        "https://backboard.railway.com/graphql/v2",
        json={"query": query},
        headers={"Authorization": f"Bearer {token}"}
    )
    print("\nDeployments response:", resp.status_code)
    data = resp.json()
    print(json.dumps(data, indent=2)[:3000])
