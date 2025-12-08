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

# Permissions definition (List of Objects)
TENANT_ROLE_PERMISSIONS = [
    {"object": "stream:_all_default", "permission": "AllowList"},
    {"object": "stream:_all_default", "permission": "AllowGet"},
    {"object": "function:_all_default", "permission": "AllowAll"},
    {"object": "dfolder:_all_default", "permission": "AllowAll"},
    {"object": "template:_all_default", "permission": "AllowList"},
    {"object": "template:_all_default", "permission": "AllowGet"},
    {"object": "destination:_all_default", "permission": "AllowList"},
    {"object": "destination:_all_default", "permission": "AllowGet"},
    {"object": "user:_all_default", "permission": "AllowList"},
    {"object": "user:_all_default", "permission": "AllowGet"},
    {"object": "role:_all_default", "permission": "AllowList"},
    {"object": "role:_all_default", "permission": "AllowGet"},
    {"object": "group:_all_default", "permission": "AllowList"},
    {"object": "group:_all_default", "permission": "AllowGet"},
    {"object": "enrichment_table:_all_default", "permission": "AllowAll"},
    {"object": "settings:_all_default", "permission": "AllowGet"},
    {"object": "kv:_all_default", "permission": "AllowList"},
    {"object": "kv:_all_default", "permission": "AllowGet"},
    {"object": "syslog-route:_all_default", "permission": "AllowList"},
    {"object": "syslog-route:_all_default", "permission": "AllowGet"},
    {"object": "summary:_all_default", "permission": "AllowList"},
    {"object": "summary:_all_default", "permission": "AllowGet"},
    {"object": "passcode:_all_default", "permission": "AllowList"},
    {"object": "passcode:_all_default", "permission": "AllowGet"},
    {"object": "rumtoken:_all_default", "permission": "AllowList"},
    {"object": "rumtoken:_all_default", "permission": "AllowGet"},
    {"object": "savedviews:_all_default", "permission": "AllowList"},
    {"object": "savedviews:_all_default", "permission": "AllowGet"},
    {"object": "metadata:_all_default", "permission": "AllowList"},
    {"object": "metadata:_all_default", "permission": "AllowGet"},
    {"object": "report:_all_default", "permission": "AllowList"},
    {"object": "report:_all_default", "permission": "AllowGet"},
    {"object": "pipeline:_all_default", "permission": "AllowList"},
    {"object": "pipeline:_all_default", "permission": "AllowGet"},
    {"object": "service_accounts:_all_default", "permission": "AllowList"},
    {"object": "service_accounts:_all_default", "permission": "AllowGet"},
    {"object": "search_jobs:_all_default", "permission": "AllowList"},
    {"object": "search_jobs:_all_default", "permission": "AllowGet"},
    {"object": "cipher_keys:_all_default", "permission": "AllowList"},
    {"object": "cipher_keys:_all_default", "permission": "AllowGet"},
    {"object": "action_scripts:_all_default", "permission": "AllowList"},
    {"object": "action_scripts:_all_default", "permission": "AllowGet"},
    {"object": "afolder:_all_default", "permission": "AllowList"},
    {"object": "afolder:_all_default", "permission": "AllowGet"},
    {"object": "ratelimit:_all_default", "permission": "AllowList"},
    {"object": "ratelimit:_all_default", "permission": "AllowGet"},
    {"object": "ai:_all_default", "permission": "AllowList"},
    {"object": "ai:_all_default", "permission": "AllowGet"},
    {"object": "re_patterns:_all_default", "permission": "AllowList"},
    {"object": "re_patterns:_all_default", "permission": "AllowGet"},
    {"object": "license:_all_default", "permission": "AllowList"},
    {"object": "license:_all_default", "permission": "AllowGet"}
]

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

def get_org_users(org):
    try:
        r = requests.get(f"{O2_URL}/api/{org}/users", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('data', []) if isinstance(data, dict) else data
        return []
    except: return []

def get_org_service_accounts(org):
    try:
        r = requests.get(f"{O2_URL}/api/{org}/service_accounts", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('data', []) if isinstance(data, dict) else data
        return []
    except: return []

def get_org_roles(org):
    try:
        r = requests.get(f"{O2_URL}/api/{org}/roles", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('data', []) if isinstance(data, dict) else data
        return []
    except: return []

def get_org_streams(org):
    try:
        r = requests.get(f"{O2_URL}/api/{org}/streams", auth=get_auth())
        if r.status_code == 200:
            data = r.json()
            return data.get('list', []) if isinstance(data, dict) else data
        return []
    except: return []

# --- RESOURCE MANAGEMENT ---

def configure_stream(org, stream_name, retention_hours):
    url = f"{O2_URL}/api/{org}/streams/{stream_name}"
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

def ensure_custom_role(org, role_name, permissions):
    """Creates or updates a custom role using the specific schema provided."""
    url = f"{O2_URL}/api/{org}/roles"
    
    # NEW PAYLOAD SCHEMA
    payload = {
        "role": role_name,
        "custom_role": permissions # Passing the list of permission objects here
    }
    
    try:
        current_roles = get_org_roles(org)
        
        role_exists = False
        role_id = None
        
        for r in current_roles:
            if isinstance(r, str):
                if r == role_name: 
                    role_exists = True
                    break 
            elif isinstance(r, dict):
                # Check 'role' key as per new schema, fall back to 'name'
                if r.get('role') == role_name or r.get('name') == role_name:
                    role_exists = True
                    role_id = r.get('id')
                    break

        if role_exists:
            # Update
            target = str(role_id) if role_id else role_name
            url = f"{O2_URL}/api/{org}/roles/{target}"
            r = requests.put(url, auth=get_auth(), json=payload)
            success, _ = check_response(r, f"Update Role {role_name}")
            return success
        else:
            # Create
            r = requests.post(url, auth=get_auth(), json=payload)
            success, _ = check_response(r, f"Create Role {role_name}")
            return success
    except Exception as e:
        print(f"      ❌ Role Error: {e}")
        return False

def ensure_user(org, email, role):
    url = f"{O2_URL}/api/{org}/users"
    password = generate_password()
    
    # NEW USER PAYLOAD SCHEMA
    payload = {
        "email": email,
        "first_name": "User", 
        "last_name": "Team",
        "is_external": False,
        "password": password,
        "role": role,
        "custom_role": [] # Empty list as we are using the named 'role'
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

def ensure_service_account(org, name, role="admin"):
    url = f"{O2_URL}/api/{org}/service_accounts"
    
    sa_email = f"{name}@{org}.serviceaccount"
    
    payload = {
        "name": name, 
        "email": sa_email,
        "role": role
    }
    
    try:
        existing = get_org_service_accounts(org)
        for sa in existing:
            if sa.get('name') == name:
                 return {"name": name, "status": "Exists (Credentials Hidden)"}

        r = requests.post(url, auth=get_auth(), json=payload)
        success, msg = check_response(r, f"Create Service Account {name}")
        if success:
            data = r.json()
            creds = data.get('data', data)
            return {
                "name": name, 
                "email": sa_email,
                "status": "Created",
                "client_id": creds.get('client_id'),
                "client_secret": creds.get('client_secret')
            }
        else:
            return {"name": name, "status": f"Failed: {msg}"}
    except Exception as e:
        return {"name": name, "status": f"Conn Error: {e}"}

# --- CORE ACTIONS ---

def apply_org(org_name, create_users=False):
    print(f"\n🚀 Processing: {org_name}")
    report = {"org": org_name, "streams": [], "roles": [], "users": [], "service_accounts": []}

    # 1. Create Org
    all_orgs = get_all_orgs_raw()
    existing_names = [o['name'] for o in all_orgs]
    
    if org_name not in existing_names:
        try:
            r = requests.post(f"{O2_URL}/api/organizations", auth=get_auth(), json={"name": org_name})
            check_response(r, "Create Organization")
            print("   ✅ Organization Created")
        except Exception as e:
            print(f"   ❌ Org Connection Error: {e}")
            return report
    else:
        print(f"   ℹ️  Organization '{org_name}' already exists.")

    # 2. Streams
    for s in STREAMS_CONFIG:
        ok = configure_stream(org_name, s['name'], s['retention'])
        report["streams"].append(f"{s['name']}: {'OK' if ok else 'FAIL'}")

    # 3. Custom Roles (tenant-role)
    role_ok = ensure_custom_role(org_name, "tenant-role", TENANT_ROLE_PERMISSIONS)
    report["roles"].append(f"tenant-role: {'OK' if role_ok else 'FAIL'}")

    # 4. Service Account (sa-gitops)
    report["service_accounts"].append(ensure_service_account(org_name, "sa-gitops", "admin"))
    
    # 5. Standard Users (assigned tenant-role)
    if create_users:
        print("   👥 Ensuring sample users...")
        for i in range(1, 4):
            report["users"].append(ensure_user(org_name, f"user{i}-{org_name}@example.com", "tenant-role"))

    return report

def clean_org_resources(org_name, no_confirm=False):
    if not no_confirm:
        check = input(f"🔥 PURGE RESOURCES for '{org_name}'? Type 'CONFIRM': ")
        if check != "CONFIRM": return

    print(f"   🧹 Cleaning resources in: {org_name}")

    # 1. Delete Service Accounts
    sas = get_org_service_accounts(org_name)
    for sa in sas:
        sa_name = sa.get('name')
        if sa_name:
            try:
                requests.delete(f"{O2_URL}/api/{org_name}/service_accounts/{sa_name}", auth=get_auth())
                print(f"      - Deleted SA: {sa_name}")
            except: pass

    # 2. Delete Users (Skip Self)
    users = get_org_users(org_name)
    for u in users:
        email = u.get('email')
        if email and email != ADMIN_EMAIL:
            try:
                requests.delete(f"{O2_URL}/api/{org_name}/users/{email}", auth=get_auth())
                print(f"      - Deleted User: {email}")
            except: pass

    # 3. Delete Custom Roles
    SYSTEM_ROLES = ['admin', 'editor', 'member', 'viewer']
    roles = get_org_roles(org_name)
    for r in roles:
        if isinstance(r, str):
            r_name = r
            r_id = r
        else:
            # Check 'role' first (new schema) then 'name'
            r_name = r.get('role') or r.get('name')
            r_id = r.get('id', r_name)

        if r_name and r_name not in SYSTEM_ROLES:
            try:
                requests.delete(f"{O2_URL}/api/{org_name}/roles/{r_id}", auth=get_auth())
                print(f"      - Deleted Role: {r_name}")
            except: pass

    # 4. Delete Streams
    streams = get_org_streams(org_name)
    for s in streams:
        s_name = s.get('name')
        if s_name and not s_name.startswith('_'):
            try:
                requests.delete(f"{O2_URL}/api/{org_name}/streams/{s_name}", auth=get_auth())
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

def run_show_all():
    print("🔍 Scanning all organizations...")
    all_orgs = get_all_orgs_raw()
    
    overview = {}
    
    for o in all_orgs:
        name = o.get('name')
        if name == '_meta': continue
        
        print(f"   ... scanning {name}")
        
        raw_roles = get_org_roles(name)
        safe_roles = []
        for r in raw_roles:
            if isinstance(r, str): safe_roles.append(r)
            elif isinstance(r, dict): safe_roles.append(r.get('role') or r.get('name', 'unknown'))
            
        overview[name] = {
            "streams": [s.get('name') for s in get_org_streams(name)],
            "roles": safe_roles,
            "users": [f"{u.get('email')} ({u.get('role')})" for u in get_org_users(name)],
            "service_accounts": [sa.get('name') for sa in get_org_service_accounts(name)]
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
    elif args.command == "apply": 
        print(json.dumps(apply_org(args.org_name, args.users), indent=2))
    elif args.command == "purge-org": 
        clean_org_resources(args.org_name)

if __name__ == "__main__":
    main()