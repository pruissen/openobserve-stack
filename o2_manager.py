#!/usr/bin/env python3
import requests
import sys
import json
import base64
import subprocess
import time

# --- CONFIG ---
# Using 'localhost' to match your working curl command
O2_URL = "http://localhost:5080"
ADMIN_EMAIL = "admin@platform.com"

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

ORGS = [
    {"name": "platform_k8s", "desc": "All K8s Systems Data"},
    {"name": "platform_obs", "desc": "Observability Stack Data"},
    {"name": "devteam_1",    "desc": "Astronomy Demo Team"}
]

# --- HELPERS ---

def get_admin_password():
    try:
        cmd = "kubectl get secret o2-platform-secret -n o2-system -o jsonpath='{.data.ZO_ROOT_USER_PASSWORD}' | base64 -d"
        return subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
    except:
        print("❌ Could not fetch password from Kubernetes.")
        sys.exit(1)

ADMIN_PASSWORD = get_admin_password()

def get_auth():
    return (ADMIN_EMAIL, ADMIN_PASSWORD)

def api_request(method, endpoint, json_data=None):
    url = f"{O2_URL}/api/{endpoint.lstrip('/')}"
    try:
        if method == "POST":
            r = requests.post(url, auth=get_auth(), json=json_data)
        elif method == "GET":
            r = requests.get(url, auth=get_auth())
        
        if 200 <= r.status_code < 300:
            return True, r.json()
        return False, f"Status: {r.status_code} | Msg: {r.text}"
    except Exception as e:
        return False, str(e)

def wait_for_api():
    print(f"⏳ Connecting to {O2_URL} (User: {ADMIN_EMAIL})...")
    for i in range(30):
        try:
            r_health = requests.get(f"{O2_URL}/healthz", timeout=1)
            if r_health.status_code == 200:
                print(f"   ✅ Healthz OK.")
                r_ver = requests.get(f"{O2_URL}/api/version", auth=get_auth(), timeout=1)
                if r_ver.status_code == 200:
                    print(f"   ✅ Auth OK.")
                    return True
                elif r_ver.status_code == 401:
                    print(f"\n❌ Auth Failed. Password mismatch.")
                    return False
                else:
                    print(f"   ⚠️  API reachable but returned {r_ver.status_code}. Proceeding...")
                    return True
        except:
            pass
        time.sleep(2)
        print(".", end="", flush=True)
    print("\n❌ API unreachable.")
    return False

def import_dashboards(org_id, org_name):
    print(f"   🎨 Importing Dashboards for {org_name}...")
    for category, urls in DASHBOARDS.items():
        for url in urls:
            try:
                r = requests.get(url)
                if r.status_code != 200: continue
                dashboard_json = r.json()
                if 'dashboardId' in dashboard_json: del dashboard_json['dashboardId']
                
                success, resp = api_request("POST", f"{org_id}/dashboards", dashboard_json)
                if success:
                    print(f"        ✅ Imported: {dashboard_json.get('title','Unknown')}")
                elif "already exists" not in str(resp):
                    print(f"        ❌ Failed: {resp}")
            except:
                pass

def get_role_for_org(org_id):
    success, resp = api_request("GET", f"{org_id}/roles")
    if success and 'data' in resp:
        for role in resp['data']:
            if role['name'].lower() in ['member', 'viewer']:
                return role['identifier']
        if len(resp['data']) > 0:
            return resp['data'][0]['identifier']
    return "admin"

def bootstrap():
    if not wait_for_api(): sys.exit(1)
    print(f"\n🔑 Using Admin: {ADMIN_EMAIL}")
    
    # 1. SETUP DEFAULT ORG (Important for Full Observability)
    print("\n🏢 Processing Org: default...")
    import_dashboards("default", "default")

    # 2. SETUP TENANT ORGS
    existing_orgs = {}
    s, resp = api_request("GET", "organizations")
    if s and 'data' in resp:
        for o in resp['data']:
            existing_orgs[o['name']] = o['identifier']

    for org in ORGS:
        name = org['name']
        org_id = existing_orgs.get(name)

        print(f"\n🏢 Processing Org: {name}...")
        
        if org_id:
            print(f"   ℹ️  Organization exists ({org_id}). Updating...")
        else:
            success, resp = api_request("POST", "organizations", {"name": name})
            if success:
                if 'data' in resp and 'identifier' in resp['data']:
                    org_id = resp['data']['identifier']
                elif 'identifier' in resp:
                    org_id = resp['identifier']
                print(f"   ✅ Created Organization ({org_id})")
            else:
                print(f"   ❌ Failed to create: {resp}")
                continue

        if org_id:
            import_dashboards(org_id, name)

    # 3. USER CREATION
    print("\n👤 Creating DevTeam User...")
    s, resp = api_request("GET", "organizations")
    if s and 'data' in resp:
        org_id = next((o['identifier'] for o in resp['data'] if o['name'] == 'devteam_1'), None)
        
        if org_id:
            role_id = get_role_for_org(org_id)
            user_payload = {
                "email": "dev@devteam-1.com", "first_name": "Dev", "last_name": "User",
                "password": "DevTeamPass123!", "role": role_id
            }
            s, r = api_request("POST", f"{org_id}/users", user_payload)
            if s: print(f"   ✅ User created.")
            elif "already exists" in str(r): print(f"   ℹ️  User already exists.")
            else: print(f"   ❌ Failed: {r}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "bootstrap":
        bootstrap()
    else:
        print("Usage: python3 o2_manager.py bootstrap")