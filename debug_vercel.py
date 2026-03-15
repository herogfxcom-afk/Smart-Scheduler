import requests
import json

token = "vcp_REMOVED_FOR_SECURITY"

def get_deployments():
    url = "https://api.vercel.com/v6/deployments?limit=10"
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json().get("deployments", [])
    else:
        print(f"Error fetching deployments: {response.status_code} - {response.text}")
        return []

def get_deployment_logs(deployment_id):
    # Note: Vercel API for logs might require specific permissions or project ID
    # This is a simplified fetch
    url = f"https://api.vercel.com/v2/deployments/{deployment_id}/events"
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error fetching logs for {deployment_id}: {response.status_code} - {response.text}")
        return []

if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    deployments = get_deployments()
    if deployments:
        # Sort by createdAt descending
        deployments.sort(key=lambda x: x['createdAt'], reverse=True)
        latest = deployments[0]
        print(f"\n--- Fetching Events for {latest['uid']} ({latest['url']}) ---")
        
        url = f"https://api.vercel.com/v2/deployments/{latest['uid']}/events?direction=backward&limit=100"
        headers = {"Authorization": f"Bearer {token}"}
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            events = response.json()
            with open("vercel_events.json", "w", encoding="utf-8") as f:
                json.dump(events, f, indent=2)
            print(f"Dumped {len(events)} events to vercel_events.json")
            
            for event in reversed(events):
                evt_type = event.get("type", "unknown")
                payload = event.get("payload", {})
                text = payload.get("text", "") or event.get("text", "")
                if text:
                    print(f"[{evt_type.upper()}] {text}")
        else:
            print(f"Error: {response.status_code} - {response.text}")
