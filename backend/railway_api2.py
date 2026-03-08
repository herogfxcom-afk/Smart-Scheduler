"""
Use Railway GraphQL API to list deployments and force activate the latest
"""
import requests
import json

TOKEN = "rw_Fe26.2**3205df43fc50cfe63c0a4785226c4eaa41498241e98da8fcca223ad30931ba17*Hhvi0QE2Ir2CTFwF_kMh8Q*t0L9MDTrVwPol9uhrIZQns28DtUNDh4KFTLJ-gcRe-FbC0aooAtsDkMyot5ihj5COtdGa2Uoxc9Zr0a2S-O9xA*1775570350782*bcb3478ff08892e3f70803ccd8ed7a4081fa51210a99008f74f73af3f18b531b*PaWs0i3GpPhlrg1aOJKvCPWvJX-cdRYSfm-HYJarz7o"

PROJECT_ID = "95010755-d4e6-4f6a-914a-b2c7b54c737e"
SERVICE_ID = "a96ff229-d455-45b3-9fff-59befbcd9c55"
ENV_ID = "14cdd09e-808a-4f25-9eb1-565aea1ca454"

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

# List deployments
query = """
query {
  deployments(input: { serviceId: "%s", environmentId: "%s" }) {
    edges {
      node {
        id
        status
        createdAt
        buildId
      }
    }
  }
}
""" % (SERVICE_ID, ENV_ID)

print("=== Listing deployments ===")
resp = requests.post(
    "https://backboard.railway.com/graphql/v2",
    json={"query": query},
    headers=headers
)
print("Status:", resp.status_code)
data = resp.json()
print(json.dumps(data, indent=2)[:4000])
