
import requests
import json
import os

token = "f04feebf-bb44-4eb8-8184-569b3531c7ad"

def fetch_logs(deployment_id):
    print(f"\nFetching logs for {deployment_id}...")
    log_query = """
    query deploymentLogs($deploymentId: String!) {
      deploymentLogs(deploymentId: $deploymentId) {
        message
        timestamp
        severity
      }
    }
    """
    try:
        response = requests.post(
            "https://backboard.railway.com/graphql/v2",
            json={"query": log_query, "variables": {"deploymentId": deployment_id}},
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            timeout=30
        )
        if response.status_code == 200:
            data = response.json()
            logs = data.get("data", {}).get("deploymentLogs", [])
            for log in logs:
                print(f"[{log['timestamp']}] {log['severity']}: {log['message']}")
        else:
            print(f"Log Error: {response.text}")
    except Exception as e:
        print(f"Log Exception: {e}")

def fetch_deployments(service_id):
    query = """
    query deployments($serviceId: String!) {
      deployments(input: { serviceId: $serviceId }) {
        edges {
          node {
            id
            status
            createdAt
            staticUrl
          }
        }
      }
    }
    """
    try:
        response = requests.post(
            "https://backboard.railway.com/graphql/v2",
            json={"query": query, "variables": {"serviceId": service_id}},
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            timeout=30
        )
        if response.status_code == 200:
            data = response.json()
            edges = data.get("data", {}).get("deployments", {}).get("edges", [])
            if edges:
                latest = edges[0]["node"]
                print(f"\nLatest Deployment for {service_id}: {latest['id']} Status: {latest['status']}")
                fetch_logs(latest['id'])
        else:
            print(f"Error Response for {service_id}: {response.text}")
    except Exception as e:
        print(f"Exception for {service_id}: {e}")

if __name__ == "__main__":
    service_id = "0910c855-cb15-4be1-83ae-492f9fda8168" # Smart-Scheduler
    print(f"\n--- Checking Smart-Scheduler ({service_id}) ---")
    fetch_deployments(service_id)
