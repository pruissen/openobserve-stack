#!/bin/bash
source ./00-init.sh
setup_env

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

log "Restarting Screen Sessions..."

# 1. Kill existing sessions (matching pattern)
pkill -f "kubectl port-forward.*svc/argocd-server" || true
pkill -f "kubectl port-forward.*svc/openobserve" || true
pkill -f "kubectl port-forward.*svc/minio" || true
screen -wipe || true

log "Old sessions cleared."

# 2. Restart ArgoCD (Port 8443)
log "Starting ArgoCD PF (8443)..."
screen -dmS argocd-pf bash -c 'while true; do microk8s kubectl port-forward svc/argocd-server -n argocd-system --address 0.0.0.0 8443:443; sleep 2; done'

# 3. Restart OpenObserve (Port 5080)
log "Starting OpenObserve PF (5080)..."
screen -dmS zo-pf bash -c 'while true; do microk8s kubectl port-forward svc/openobserve-router -n openobserve-system --address 0.0.0.0 5080:5080; sleep 2; done'

# 4. Restart MinIO (Port 9001 - Console)
HAS_MINIO=false
# Check for minio-console service first (standard in newer charts)
if lk get svc minio-console -n minio-system &> /dev/null; then
    log "Starting MinIO Console PF (9001)..."
    screen -dmS minio-pf bash -c 'while true; do microk8s kubectl port-forward svc/minio-console -n minio-system --address 0.0.0.0 9001:9001; sleep 2; done'
    HAS_MINIO=true
# Fallback check for single minio service
elif lk get svc minio -n minio-system &> /dev/null; then
    log "Starting MinIO PF (9001)..."
    screen -dmS minio-pf bash -c 'while true; do microk8s kubectl port-forward svc/minio -n minio-system --address 0.0.0.0 9001:9001; sleep 2; done'
    HAS_MINIO=true
else
    log "MinIO service not found, skipping port forward."
fi

sleep 3
log "Sessions running:"
screen -ls

# ==============================================================================
# RETRIEVE & DISPLAY CREDENTIALS
# ==============================================================================

# Retrieve Argo Password
ARGO_PWD_B64=$(lk -n argocd-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null)
ARGO_PWD=$(echo "$ARGO_PWD_B64" | decode_base64)

echo ""
echo "=================================================================="
echo "ACCESS INFORMATION"
echo "=================================================================="
echo "ArgoCD:"
echo "  URL:  https://127.0.0.1:8443"
echo "  User: admin"
echo "  Pass: $ARGO_PWD"
echo ""
echo "OpenObserve:"
echo "  URL:  http://127.0.0.1:5080"
echo "  User: $ZO_ROOT_EMAIL"
echo "  Pass: $ZO_ROOT_PASSWORD"
echo ""

if [ "$HAS_MINIO" = true ]; then
echo "MinIO:"
echo "  URL:  http://127.0.0.1:9001"
echo "  User: $MINIO_ROOT_USER"
echo "  Pass: $MINIO_ROOT_PASSWORD"
else
echo "MinIO:"
echo "  (Service not found or not deployed)"
fi
echo "=================================================================="