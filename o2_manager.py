#!/usr/bin/env python3
import requests
import sys
import json
import base64
import subprocess
import time

# --- CONFIG ---
O2_URL = "http://localhost:5080"
ADMIN_EMAIL = "admin@platform.com"

# Dashboard Templates (Official OpenObserve GitHub)
DASHBOARDS = {
    "kubernetes": [
        "https://raw.githubusercontent.com/openobserve/dashboards/main/Kubernetes(openobserve-collector)/Kubernetes%20%20_%20Namespace%20(Pod).dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/main/Kubernetes(openobserve-collector)/Kubernetes%20%20_%20Nodes.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/main/Kubernetes(openobserve-collector)/Kubernetes%20_%20Events.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/main/Kubernetes(openobserve-collector)/Kubernetes%20_%20Node%20(Pods).dashboard.json"
    ],
    "host": [
        "https://raw.githubusercontent.com/openobserve/dashboards/main/hostmetrics/Host%20Metrics.dashboard.json"
    ]
}

# Organizations to create
ORGS = [
    {"name": "platform-k8s", "desc": "All K8s Systems Data"},
    {"name": "platform-obs", "desc": "Observability Stack Data"},
    {"name": "devteam-1",    "desc": "Astronomy Demo Team"}
]

# --- HELPERS ---

def get_admin_password():
    try:
        # UPDATED: Now points to o2-platform-secret
        cmd = "kubectl get secret o2-platform-secret -n o2-system -o jsonpath='{.data.ZO_ROOT_USER_PASSWORD}' | base64 -d"
        return subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
    except:
        print("❌ Could not fetch password from Kubernetes.")
        sys.exit(1)

ADMIN_PASSWORD = get_admin_password()

def get_auth():
    return (ADMIN_EMAIL, ADMIN_PASSWORD)

def api_request(method, endpoint, json_data=None):
    url = f"{O2_URL}/api/{endpoint}"
    try:
        if method == "POST":
            r = requests.post(url, auth=get_auth(), json=json_data)
        elif method == "GET":
            r = requests.get(url, auth=get_auth())
        
        if 200 <= r.status_code < 300:
            return True, r.json()
        return False, r.text
    except Exception as e:
        return False, str(e)

def wait_for_api():
    print("⏳ Waiting for OpenObserve API to be reachable...")
    for i in range(10):
        try:
            r = requests.get(f"{O2_URL}/api/version", auth=get_auth())
            if r.status_code == 200:
                print("✅ API is UP.")
                return True
        except:
            pass
        time.sleep(2)
        print(".", end="", flush=True)
    print("\n❌ API unreachable. Is port-forward running?")
    return False

def import_dashboards(org_id, org_name):
    print(f"   🎨 Importing Dashboards for {org_name}...")
    for category, urls in DASHBOARDS.items():
        for url in urls:
            try:
                # 1. Download JSON
                r = requests.get(url)
                if r.status_code != 200:
                    print(f"       ⚠️  Download failed: {url}")
                    continue
                dashboard_json = r.json()
                
                # 2. Prepare payload (Remove ID to force create new)
                if 'dashboardId' in dashboard_json:
                    del dashboard_json['dashboardId']
                
                # 3. Post to Org
                # URL format: /api/{org_identifier}/dashboards
                success, resp = api_request("POST", f"{org_id}/dashboards", dashboard_json)
                if success:
                    title = dashboard_json.get('title', 'Unknown')
                    print(f"       ✅ Imported: {title}")
                else:
                    print(f"       ❌ Failed to import: {resp}")
            except Exception as e:
                print(f"       ❌ Error: {e}")

def bootstrap():
    if not wait_for_api():
        sys.exit(1)

    print(f"\n🔑 Using Admin: {ADMIN_EMAIL}")
    
    # 1. Create Orgs & Import Dashboards
    for org in ORGS:
        print(f"\n🏢 Processing Org: {org['name']}...")
        success, resp = api_request("POST", "organizations", {"name": org['name']})
        
        # Resolve Org ID
        if success:
            org_id = resp['data']['identifier']
            print(f"   ✅ Organization Ready ({org_id})")
        else:
            # If exists, we need to look it up to get the ID for dashboard imports
            if "already exists" in str(resp):
                print(f"   ℹ️  Organization exists.")
                # Lookup ID
                s, list_resp = api_request("GET", "organizations")
                org_id = next((o['identifier'] for o in list_resp['data'] if o['name'] == org['name']), None)
            else:
                print(f"   ❌ Failed to create org: {resp}")
                continue

        # Import Dashboards if we have an ID
        if org_id:
            import_dashboards(org_id, org['name'])

    # 2. Setup DevTeam-1 specific User (Example)
    print("\n👤 Creating DevTeam User...")
    dev_email = "dev@devteam-1.com"
    dev_pass = "DevTeamPass123!" 
    
    # Get Org ID for devteam-1
    success, resp = api_request("GET", "organizations")
    org_id = next((o['identifier'] for o in resp['data'] if o['name'] == 'devteam-1'), None)
    
    if org_id:
        user_payload = {
            "email": dev_email,
            "first_name": "Dev", "last_name": "User",
            "password": dev_pass,
            "role": "member"
        }
        s, r = api_request("POST", f"{org_id}/users", user_payload)
        if s: print(f"   ✅ User created: {dev_email} / {dev_pass}")
        else: print(f"   ℹ️  User creation status: {r}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "bootstrap":
        bootstrap()
    else:
        print("Usage: python3 o2_manager.py bootstrap")