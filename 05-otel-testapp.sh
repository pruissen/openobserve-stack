#!/bin/bash
# Filename: 05-otel-testapp.sh
source ./00-init.sh
setup_env

log "Deploying OTel Astronomy Shop Demo..."

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
# 1. LOAD CREDENTIALS (SYNC WITH CLUSTER)
# ==============================================================================
log "Fetching credentials from Kubernetes Secret..."

SECRET_EMAIL_B64=$(microk8s kubectl -n openobserve-system get secret openobserve-creds -o jsonpath='{.data.ZO_ROOT_USER_EMAIL}' 2>/dev/null)
SECRET_PASS_B64=$(microk8s kubectl -n openobserve-system get secret openobserve-creds -o jsonpath='{.data.ZO_ROOT_USER_PASSWORD}' 2>/dev/null)

SECRET_EMAIL=$(echo "$SECRET_EMAIL_B64" | decode_base64)
SECRET_PASS=$(echo "$SECRET_PASS_B64" | decode_base64)

if [ -n "$SECRET_EMAIL" ] && [ -n "$SECRET_PASS" ]; then
    ZO_USER="$SECRET_EMAIL"
    ZO_PASS="$SECRET_PASS"
    log "Loaded credentials from Cluster Secret."
else
    log "WARNING: Could not fetch secrets from cluster. Using local config.env."
    ZO_USER="$ZO_ROOT_EMAIL"
    ZO_PASS="$ZO_ROOT_PASSWORD"
fi

# Generate Auth Token for Test App
ZO_AUTH_TOKEN=$(encode_base64 "$ZO_USER:$ZO_PASS")

# ==============================================================================
# 2. CLEANUP & PREPARE
# ==============================================================================
deploy_app() {
    local APP_NAME=$1
    local MANIFEST=$2
    log "Deploying $APP_NAME..."
    echo "$MANIFEST" | lk apply -f -
    log "Waiting for $APP_NAME to be Healthy..."
    until [ "$(lk get application -n argocd-system $APP_NAME -o jsonpath='{.status.health.status}' 2>/dev/null)" == "Healthy" ]; do
        echo -n "."
        sleep 5
    done
    echo ""
    success "$APP_NAME is Healthy."
}

# Cleanup
lk delete application -n argocd-system otel-demo-astronomy --ignore-not-found --wait=true
lk delete ns observability-tst --ignore-not-found --wait=true

# Namespace & Secret
lk create ns observability-tst --dry-run=client -o yaml | lk apply -f -

lk create secret generic zo-demo-creds -n observability-tst \
  --from-literal=ZO_ENDPOINT="http://openobserve-router.openobserve-system.svc:5080" \
  --from-literal=ZO_AUTH="Basic $ZO_AUTH_TOKEN" \
  --from-literal=ZO_ORG="$ORG_TEAM" \
  --dry-run=client -o yaml | lk apply -f -

# ==============================================================================
# 3. DEPLOY DEMO APP
# ==============================================================================
# Using OpenObserve Router endpoint for export
DEMO_YAML=$(cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: otel-demo-astronomy
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
    chart: opentelemetry-demo
    targetRevision: 0.33.2
    helm:
      values: |
        default:
          env:
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: 'http://openobserve-router.openobserve-system.svc:5080/api/$ORG_TEAM'
            - name: OTEL_EXPORTER_OTLP_HEADERS
              value: 'Authorization=Basic $ZO_AUTH_TOKEN'
        opentelemetry-collector:
          config:
            exporters:
              otlphttp:
                endpoint: 'http://openobserve-router.openobserve-system.svc:5080/api/$ORG_TEAM'
                headers: 
                  Authorization: 'Basic $ZO_AUTH_TOKEN'
  destination:
    server: https://kubernetes.default.svc
    namespace: observability-tst
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
)
deploy_app "otel-demo-astronomy" "$DEMO_YAML"

success "Test App Deployed."