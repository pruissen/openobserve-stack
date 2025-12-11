#!/usr/bin/env python3
# o2_manager.py

import argparse
import requests
import json
import secrets
import string
import sys

# --- CONFIGURATION ---
O2_URL = "http://127.0.0.1:5080" 
ADMIN_EMAIL = "admin@example.com"
ADMIN_PASSWORD = "ComplexPassword123!"

STREAMS_CONFIG = [
    {"name": "short_term", "retention": 24},   # 1 Day
    {"name": "default",    "retention": 240},  # 10 Days
    {"name": "long_term",  "retention": 840}   # 35 Days
]

BOOTSTRAP_ORGS = ["platform_observability", "platform_kubernetes", "team1", "team2"]

# Dashboard Sources
DASHBOARD_SOURCES = {
    "kubernetes": [
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20%20_%20Namespace%20(Pod).dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20%20_%20Namespace%20(Pods).dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20%20_%20Namespaces.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20%20_%20Nodes.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20Nodes%20Pressure.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20_%20Events.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20_%20Namespace%20(Objects).dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Kubernetes(openobserve-collector)/Kubernetes%20_%20Node%20(Pods).dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/ArgoCD/ArgoCD%20Monitoring.dashboard.json"
    ],
    "openobserve": [
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/OpenObserve/OpenObserve%20Infrastructure.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/OpenObserve/OpenObserve%20Internals.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Usage/Usage%20_%20Org.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Usage/Usage%20_%20Overall.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/hostmetrics/Host%20Metrics.dashboard.json",
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Uptime_Monitor/Uptime_Monitoring_Dashboard.json"
    ],
    "github": [
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/Github/Github.dashboard.json"
    ],
    "postgres": [
        "https://raw.githubusercontent.com/openobserve/dashboards/refs/heads/main/PostgreSQL%20Metrics/PostgreSQL.dashboard.json"
    ]
}

# --- HELPERS ---

def get_auth():
    return (ADMIN_EMAIL, ADMIN_PASSWORD)

def generate_password(length=16):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for i in range(length))

def check_response(r, context="API Request"):
    if 200 <= r.status_code < 300:
        return True, None
    try:
        error_msg = json.dumps(r.json(), indent=2)
    except:
        error_msg = r.text
    print(f"      ❌ {context} Failed [{r.status_code}]")
    print(f"         Msg: {error_msg}")
    return False, error_msg

# --- DATA FETCHERS ---

def get_all_orgs_raw():
    try:
        r = requests.get(f"{O2_URL}/api/organizations", auth=get_auth())
        success, _ = check_response(r, "List Orgs")
        if not success: return []
        data = r.json()
        return data['data'] if 'data' in data else data
    except Exception as e:
        print(f"      ❌ Connection Error listing orgs: {e}")
        return []

def get_org_id(org_name):
    """
    Resolves an Organization Name to its ID (identifier).
    Returns None if not found.
    """
    all_orgs = get_all_orgs_raw()
    for o in all_orgs:
        if o.get('name') == org_name:
            return o.get('identifier') or o.get('id')
    return None

def get_org_users(org_id):
    try:
        r = requests.get(f"{O2_URL}/api/{org_id}/users", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('data', []) if isinstance(data, dict) else data
        return []
    except: return []

def get_org_service_accounts(org_id):
    try:
        r = requests.get(f"{O2_URL}/api/{org_id}/service_accounts", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('data', []) if isinstance(data, dict) else data
        return []
    except: return []

def get_org_roles(org_id):
    try:
        r = requests.get(f"{O2_URL}/api/{org_id}/roles", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('data', []) if isinstance(data, dict) else data
        return []
    except: return []

def get_org_streams(org_id):
    try:
        r = requests.get(f"{O2_URL}/api/{org_id}/streams", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('list', []) if isinstance(data, dict) else data
        return []
    except: return []

# --- RESOURCE MANAGEMENT ---

def configure_stream(org_id, stream_name, retention_hours):
    url = f"{O2_URL}/api/{org_id}/streams/{stream_name}"
    params = {"type": "logs"} 
    payload = {
        "fields": [],
        "settings": {
            "approx_partition": True,
            "bloom_filter_fields": [],
            "data_retention": retention_hours, 
            "defined_schema_fields": [],
            "distinct_value_fields": [],
            "enable_distinct_fields": True,
            "enable_log_patterns_extraction": True,
            "extended_retention_days": [],
            "full_text_search_keys": [],
            "index_all_values": True,
            "index_fields": [],
            "index_original_data": True,
            "partition_keys": [], 
            "partition_time_level": "hourly", 
            "store_original_data": True
        }
    }
    try:
        r = requests.post(url, auth=get_auth(), params=params, json=payload)
        success, _ = check_response(r, f"Config Stream '{stream_name}'")
        return success
    except Exception as e:
        print(f"      ❌ Connection Error: {e}")
        return False

def ensure_user(org_id, email, role):
    url = f"{O2_URL}/api/{org_id}/users"
    password = generate_password()
    
    payload = {
        "email": email,
        "first_name": "User", 
        "last_name": "Team",
        "is_external": False,
        "password": password,
        "role": role, # Built-in role (admin, member, etc.)
        "custom_role": []
    }
    
    try:
        r = requests.post(url, auth=get_auth(), json=payload)
        if r.status_code == 409:
             return {"email": email, "password": "<Existing>", "status": "Exists", "role": role}
        success, msg = check_response(r, f"Create User {email}")
        if success:
            return {"email": email, "password": password, "status": "Created", "role": role}
        else:
            return {"email": email, "status": f"Failed: {msg}"}
    except Exception as e:
        return {"email": email, "status": f"Conn Error: {e}"}

def get_service_account_token(org_id, email):
    """Fetches the token for an existing service account."""
    url = f"{O2_URL}/api/{org_id}/service_accounts/{email}"
    try:
        r = requests.get(url, auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            if 'data' in data:
                return data['data'].get('token')
            return data.get('token')
        return None
    except:
        return None

def ensure_service_account(org_name, org_id, name, role="admin"):
    url = f"{O2_URL}/api/{org_id}/service_accounts"
    
    # We keep the human readable org name in the email for clarity
    sa_email = f"{name}-{org_name}@example.com"
    
    payload = {
        "name": name, 
        "email": sa_email,
        "role": role
    }
    
    try:
        created = False
        
        # Check existing accounts
        existing = get_org_service_accounts(org_id)
        existing_sa = next((sa for sa in existing if sa.get('name') == name), None)

        if existing_sa:
            # 1. Update Role if needed
            current_role = existing_sa.get('role')
            if current_role != role:
                print(f"      🔄 Updating SA '{name}' role from '{current_role}' to '{role}'...")
                sa_id_target = existing_sa.get('email') or existing_sa.get('id')
                
                update_url = f"{url}/{sa_id_target}"
                update_payload = {"name": name, "role": role}
                
                r_up = requests.put(update_url, auth=get_auth(), json=update_payload)
                success, msg = check_response(r_up, f"Update SA Role")
                if not success:
                      return {"name": name, "status": f"Role Update Failed: {msg}"}
        else:
            # 2. Create if not exists
            r = requests.post(url, auth=get_auth(), json=payload)
            success, msg = check_response(r, f"Create Service Account {name}")
            if success:
                created = True
            else:
                return {"name": name, "status": f"Failed: {msg}"}
        
        # 3. Retrieve Token
        token = get_service_account_token(org_id, sa_email)
        
        if token:
             return {
                "name": name, 
                "email": sa_email,
                "status": "Created" if created else "Exists/Updated",
                "token": token
            }
        else:
            return {"name": name, "status": "Failed to retrieve Token"}

    except Exception as e:
        return {"name": name, "status": f"Conn Error: {e}"}

def import_dashboards_to_org(org_name, org_id):
    print(f"\n   📦 Importing dashboards to {org_name}...")
    
    url = f"{O2_URL}/api/{org_id}/dashboards"
    
    for category, links in DASHBOARD_SOURCES.items():
        print(f"      📂 Category: {category}")
        for link in links:
            try:
                # 1. Download Dashboard JSON
                dash_resp = requests.get(link)
                if dash_resp.status_code != 200:
                    print(f"         ❌ Failed to download: {link}")
                    continue
                
                dashboard_data = dash_resp.json()
                dashboard_title = dashboard_data.get("title", "Unknown")
                
                # 2. Post to OpenObserve
                # Note: O2 will create a new dashboard. If ID exists, behavior depends on version (usually conflict or create new)
                # We strip ID to ensure creation of a fresh copy or let O2 handle it.
                if 'dashboardId' in dashboard_data:
                    del dashboard_data['dashboardId']

                r = requests.post(url, auth=get_auth(), json=dashboard_data)
                if r.status_code in [200, 201]:
                     print(f"         ✅ Imported: {dashboard_title}")
                else:
                     print(f"         ⚠️ Failed to import '{dashboard_title}': {r.status_code}")
            except Exception as e:
                print(f"         ❌ Error importing {link}: {e}")

# --- CORE ACTIONS ---

def apply_org(org_name, create_users=False):
    print(f"\n🚀 Processing: {org_name}")
    report = {"org": org_name, "streams": [], "users": [], "service_accounts": []}

    # 1. Create/Get Org ID
    all_orgs = get_all_orgs_raw()
    existing_org = next((o for o in all_orgs if o.get('name') == org_name), None)
    
    org_id = None

    if existing_org:
        print(f"   ℹ️  Organization '{org_name}' already exists.")
        org_id = existing_org.get('identifier') or existing_org.get('id')
    else:
        try:
            r = requests.post(f"{O2_URL}/api/organizations", auth=get_auth(), json={"name": org_name})
            success, _ = check_response(r, "Create Organization")
            if not success: return report
            print("   ✅ Organization Created")
            org_id = get_org_id(org_name)
        except Exception as e:
            print(f"   ❌ Org Connection Error: {e}")
            return report

    if not org_id:
        print(f"   ❌ FATAL: Could not resolve ID for organization '{org_name}'")
        return report

    # 2. Streams (PREFIXED WITH ORG NAME)
    for s in STREAMS_CONFIG:
        prefixed_name = f"{org_name}_{s['name']}"
        ok = configure_stream(org_id, prefixed_name, s['retention'])
        report["streams"].append(f"{prefixed_name}: {'OK' if ok else 'FAIL'}")

    # 3. Service Account (sa-gitops) -> RESTORED TO ADMIN
    report["service_accounts"].append(ensure_service_account(org_name, org_id, "sa-gitops", "admin"))
    
    # 4. Standard Users -> RESTORED TO ADMIN (per request for admin rights within org)
    if create_users:
        print("   👥 Ensuring sample users...")
        for i in range(1, 4):
            report["users"].append(ensure_user(org_id, f"user{i}-{org_name}@example.com", "admin"))

    return report

def clean_org_resources(org_name, no_confirm=False):
    org_id = get_org_id(org_name)
    if not org_id:
        print(f"❌ Organization '{org_name}' not found. Cannot purge.")
        return

    if not no_confirm:
        check = input(f"🔥 PURGE RESOURCES for '{org_name}' (ID: {org_id})? Type 'CONFIRM': ")
        if check != "CONFIRM": return

    print(f"   🧹 Cleaning resources in: {org_name}")

    # 1. Delete Service Accounts
    sas = get_org_service_accounts(org_id)
    for sa in sas:
        target = sa.get('email') or sa.get('name')
        if target:
            try:
                requests.delete(f"{O2_URL}/api/{org_id}/service_accounts/{target}", auth=get_auth())
                print(f"      - Deleted SA: {target}")
            except: pass

    # 2. Delete Users (Skip Self)
    users = get_org_users(org_id)
    for u in users:
        email = u.get('email')
        if email and email != ADMIN_EMAIL:
            try:
                requests.delete(f"{O2_URL}/api/{org_id}/users/{email}", auth=get_auth())
                print(f"      - Deleted User: {email}")
            except: pass

    # 3. Delete Streams
    streams = get_org_streams(org_id)
    for s in streams:
        s_name = s.get('name')
        if s_name and not s_name.startswith('_'):
            try:
                requests.delete(f"{O2_URL}/api/{org_id}/streams/{s_name}", auth=get_auth())
                print(f"      - Deleted Stream: {s_name}")
            except: pass
    
    print(f"   ✅ {org_name} Purged.")

def run_cleanup_all():
    print("🧹 Fetching Organization List...")
    all_orgs = get_all_orgs_raw()
    targets = [o.get('name') for o in all_orgs if o.get('name') != '_meta']
    
    if not targets:
        print("✅ No organizations found.")
        return

    print("\n⚠️  WARNING: ALL users, SAs, roles, and streams will be deleted in:")
    for name in targets:
        print(f"   - {name}")
    
    check = input("\n🔥 Type 'NUKE' to proceed: ")
    if check == "NUKE":
        for name in targets:
            clean_org_resources(name, no_confirm=True)
        print("\n✨ Cleanup Complete.")
    else:
        print("❌ Aborted.")

def run_import_dashboards():
    print("🎨 Starting Dashboard Import...")
    # Import into all bootstrapped orgs
    
    # 1. Get IDs for Bootstrap Orgs
    all_orgs = get_all_orgs_raw()
    
    # Map name -> ID
    org_map = {o.get('name'): (o.get('identifier') or o.get('id')) for o in all_orgs}
    
    targets = BOOTSTRAP_ORGS
    
    for org_name in targets:
        if org_name in org_map:
            import_dashboards_to_org(org_name, org_map[org_name])
        else:
            print(f"⚠️  Skipping dashboard import for {org_name}: Org not found (run bootstrap first?)")

def run_show_all():
    print("🔍 Scanning all organizations...")
    all_orgs = get_all_orgs_raw()
    
    overview = {}
    
    for o in all_orgs:
        name = o.get('name')
        if name == '_meta': continue
        
        # Use ID for lookups
        org_id = o.get('identifier') or o.get('id')
        if not org_id: continue

        print(f"   ... scanning {name} ({org_id})")
        
        raw_roles = get_org_roles(org_id)
        safe_roles = []
        for r in raw_roles:
            if isinstance(r, str): safe_roles.append(r)
            elif isinstance(r, dict): safe_roles.append(r.get('role') or r.get('name', 'unknown'))
            
        overview[name] = {
            "id": org_id,
            "streams": [s.get('name') for s in get_org_streams(org_id)],
            "roles": safe_roles,
            "users": [f"{u.get('email')} ({u.get('role')})" for u in get_org_users(org_id)],
            "service_accounts": [sa.get('name') for sa in get_org_service_accounts(org_id)]
        }
    
    print("\n" + json.dumps(overview, indent=2))

def run_bootstrap():
    full_report = [apply_org(org, True) for org in BOOTSTRAP_ORGS]
    print(json.dumps(full_report, indent=2))
    with open("bootstrap_results.json", "w") as f: 
        json.dump(full_report, f, indent=2)
    print("\n📄 Credentials saved to bootstrap_results.json")

# --- CLI ---

def main():
    parser = argparse.ArgumentParser(description="OpenObserve Multi-Tenant Manager")
    subparsers = parser.add_subparsers(dest="command", required=True, help="Command to run")
    
    subparsers.add_parser("bootstrap", help="Setup default teams, users and service accounts")
    subparsers.add_parser("cleanup-all", help="Delete resources in ALL organizations (keeps orgs)")
    subparsers.add_parser("show-all", help="Show overview of all organizations and resources")
    subparsers.add_parser("import-dashboards", help="Import standard dashboards into all bootstrapped orgs")

    p_apply = subparsers.add_parser("apply", help="Configure a specific Org")
    p_apply.add_argument("org_name", help="Name of the organization")
    p_apply.add_argument("--users", action="store_true", help="Generate sample users")

    p_del = subparsers.add_parser("purge-org", help="Clean resources in a specific Org")
    p_del.add_argument("org_name", help="Name of the organization")

    args = parser.parse_args()

    if args.command == "bootstrap": 
        run_bootstrap()
    elif args.command == "cleanup-all":
        run_cleanup_all()
    elif args.command == "show-all":
        run_show_all()
    elif args.command == "import-dashboards":
        run_import_dashboards()
    elif args.command == "apply": 
        print(json.dumps(apply_org(args.org_name, args.users), indent=2))
    elif args.command == "purge-org": 
        clean_org_resources(args.org_name)

if __name__ == "__main__":
    main()