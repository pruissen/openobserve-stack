#!/bin/bash
# Filename: 04-openobserve_iam.sh
source ./00-init.sh
setup_env
check_deps

log "Starting IAM & Stream Configuration..."

# ==============================================================================
# HELPER: PORTABLE BASE64
# ==============================================================================
decode_base64() {
    local input=${1:-$(cat)}
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$input" | base64 -D
    else
        echo "$input" | base64 -d
    fi
}

encode_base64() {
    local input=${1:-$(cat)}
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -n "$input" | base64
    else
        echo -n "$input" | base64 -w0
    fi
}

# ==============================================================================
# 1. LOAD CREDENTIALS
# ==============================================================================
log "Fetching credentials from Kubernetes Secret..."

SECRET_EMAIL_B64=$(microk8s kubectl -n openobserve-system get secret openobserve-creds -o jsonpath='{.data.ZO_ROOT_USER_EMAIL}' 2>/dev/null)
SECRET_PASS_B64=$(microk8s kubectl -n openobserve-system get secret openobserve-creds -o jsonpath='{.data.ZO_ROOT_USER_PASSWORD}' 2>/dev/null)

SECRET_EMAIL=$(echo "$SECRET_EMAIL_B64" | decode_base64)
SECRET_PASS=$(echo "$SECRET_PASS_B64" | decode_base64)

if [ -n "$SECRET_EMAIL" ] && [ -n "$SECRET_PASS" ]; then
    # Use Cluster Credentials
    ZO_USER="$SECRET_EMAIL"
    ZO_PASS="$SECRET_PASS"
    log "Loaded credentials from Cluster Secret."
else
    # Fallback to Config
    log "WARNING: Could not fetch secrets from cluster. Using local config.env."
    ZO_USER="$ZO_ROOT_EMAIL"
    ZO_PASS="$ZO_ROOT_PASSWORD"
fi

ZO_API="http://127.0.0.1:5080/api"

# ==============================================================================
# 2. CONNECTIVITY CHECK
# ==============================================================================
if ! curl -s --max-time 2 "$ZO_API/default/status" > /dev/null; then
    log "API unreachable at localhost:5080."
    log "Attempting temporary port-forward in background..."
    
    pkill -f "kubectl port-forward.*svc/openobserve-router" || true
    
    screen -dmS zo-iam-pf bash -c 'while true; do microk8s kubectl port-forward svc/openobserve-router -n openobserve-system --address 0.0.0.0 5080:5080; sleep 2; done'
    
    log "Waiting for API to become available..."
    count=0
    until curl -s --max-time 2 "$ZO_API/default/status" > /dev/null; do
        echo -n "."
        sleep 2
        count=$((count+1))
        if [ $count -ge 15 ]; then
            echo ""
            error "Timed out waiting for API. Please check if OpenObserve is running."
            exit 1
        fi
    done
    echo ""
fi

# ==============================================================================
# 3. PREPARE AUTH HEADERS
# ==============================================================================
AUTH_STRING=$(encode_base64 "$ZO_USER:$ZO_PASS")
AUTH_HEADER="Authorization: Basic $AUTH_STRING"

log "Verifying credentials against API..."
CHECK_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$ZO_API/default/users")

if [ "$CHECK_AUTH" != "200" ]; then
    error "Authentication Failed (HTTP $CHECK_AUTH)."
    echo "Attempted User: $ZO_USER"
    exit 1
else
    success "Authentication verified."
fi

# ==============================================================================
# 4. CREATE ORGANIZATIONS
# ==============================================================================
create_org() {
    local NAME=$1
    log "Processing Organization: $NAME"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ZO_API/organizations" \
      -H "$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$NAME\"}")
    
    CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n -1)
    
    if [ "$CODE" == "200" ] || [ "$CODE" == "201" ]; then
        success "Created $NAME"
    elif [ "$CODE" == "409" ] || [[ "$BODY" == *"already exists"* ]]; then
        log "Organization '$NAME' likely already exists (Code: $CODE)."
    else
        error "Failed to create organization '$NAME'. HTTP Code: $CODE"
        echo "Response: $BODY"
    fi
}

create_org "$ORG_TEAM"
create_org "$ORG_PLATFORM"

echo ""
success "IAM Configuration Complete."