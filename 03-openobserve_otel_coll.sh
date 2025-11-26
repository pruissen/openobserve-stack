#!/bin/bash
# Filename: 03-openobserve_otel_coll.sh
source ./00-init.sh
setup_env

log "Starting OpenObserve OTel Collector Deployment..."

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
    ZO_USER="$SECRET_EMAIL"
    ZO_PASS="$SECRET_PASS"
    log "Loaded credentials from Cluster Secret."
else
    log "WARNING: Could not fetch secrets from cluster. Using local config.env."
    ZO_USER="$ZO_ROOT_EMAIL"
    ZO_PASS="$ZO_ROOT_PASSWORD"
fi

ZO_AUTH_TOKEN=$(encode_base64 "$ZO_USER:$ZO_PASS")

# ==============================================================================
# 2. CLEANUP & PREPARE
# ==============================================================================
# Delete apps to stop sync
lk delete application -n argocd-system openobserve-collector opentelemetry-operator prometheus-operator cert-manager --ignore-not-found --wait=true

# Force delete Webhook Configurations to prevent "Service not found" errors during cleanup
# This unblocks the 'patch' commands below if the operator service is already gone
log "Removing OTel Webhook Configurations to unblock cleanup..."
# Aggressively find and delete any webhooks related to opentelemetry to ensure the API server stops calling them
# Note: using 'microk8s kubectl' explicitly for xargs compatibility
lk get mutatingwebhookconfiguration -o name | grep opentelemetry | xargs -r microk8s kubectl delete
lk get validatingwebhookconfiguration -o name | grep opentelemetry | xargs -r microk8s kubectl delete

log "Waiting for Webhook cleanup to sync..."
sleep 5

log "Forcing cleanup of stuck OpenTelemetry resources (removing finalizers)..."
# This prevents the namespace deletion from hanging if the operator is dead
for cr in $(microk8s kubectl get opentelemetrycollector -n openobserve-collector-system -o name 2>/dev/null); do
    log "Patching finalizer for $cr"
    microk8s kubectl patch $cr -n openobserve-collector-system -p '{"metadata":{"finalizers":[]}}' --type=merge
done

for cr in $(microk8s kubectl get instrumentations -n openobserve-collector-system -o name 2>/dev/null); do
    log "Patching finalizer for $cr"
    microk8s kubectl patch $cr -n openobserve-collector-system -p '{"metadata":{"finalizers":[]}}' --type=merge
done

log "Deleting namespaces..."
# Delete namespaces
lk delete ns opentelemetry-operator-system openobserve-collector-system cert-manager cert-manager-system --ignore-not-found --wait=true

# FIX: Explicitly delete the conflicting ServiceMonitor that causes Operator crash loops
lk delete servicemonitor -n openobserve-collector-system opentelemetry-operator-metrics-monitor --ignore-not-found

log "Creating Namespaces & Secrets..."
lk create ns cert-manager --dry-run=client -o yaml | lk apply -f -
lk create ns openobserve-collector-system --dry-run=client -o yaml | lk apply -f -
lk create ns opentelemetry-operator-system --dry-run=client -o yaml | lk apply -f -

lk create secret generic zo-collector-creds -n openobserve-collector-system \
  --from-literal=ZO_ENDPOINT="http://openobserve-router.openobserve-system.svc:5080" \
  --from-literal=ZO_AUTH="Basic $ZO_AUTH_TOKEN" \
  --from-literal=ZO_ORG="default" \
  --dry-run=client -o yaml | lk apply -f -

deploy_app() {
    local APP_NAME=$1
    local MANIFEST=$2
    log "Deploying $APP_NAME..."
    echo "$MANIFEST" | lk apply -f -
    log "Waiting for $APP_NAME to be Healthy..."
    local count=0
    until [ "$(lk get application -n argocd-system $APP_NAME -o jsonpath='{.status.health.status}' 2>/dev/null)" == "Healthy" ]; do
        echo -n "."
        sleep 5
        count=$((count+1))
        # If it takes too long (approx 3 min), break to run diagnostics
        if [ $count -ge 36 ]; then
            echo ""
            error "$APP_NAME is not Healthy yet. Continuing to diagnostics..."
            return 1
        fi
    done
    echo ""
    success "$APP_NAME is Healthy."
}

# ==============================================================================
# 3. CERT MANAGER (Required for OTel Operator)
# ==============================================================================
log "Deploying Cert Manager..."
CERT_MANAGER_YAML=$(cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.0
    helm:
      values: |
        installCRDs: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
)
deploy_app "cert-manager" "$CERT_MANAGER_YAML"

log "Waiting for Cert Manager Webhook to spin up..."
sleep 30

# ==============================================================================
# 4. OPERATORS
# ==============================================================================
log "Deploying Prometheus Operator (CRDs only)..."
PROMETHEUS_OPERATOR_YAML=$(cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-operator
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 61.3.2
    helm:
      values: |
        defaultRules:
          create: false
        alertmanager:
          enabled: false
        grafana:
          enabled: false
        prometheus:
          enabled: false
        nodeExporter:
          enabled: false
        prometheusOperator:
          enabled: true
          tls:
            enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
EOF
)
deploy_app "prometheus-operator" "$PROMETHEUS_OPERATOR_YAML"

log "Deploying OpenTelemetry Operator (Standalone)..."
OTEL_OPERATOR_YAML=$(cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: opentelemetry-operator
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
    chart: opentelemetry-operator
    targetRevision: 0.74.0
    helm:
      values: |
        manager:
          collectorImage:
            repository: "otel/opentelemetry-collector-contrib"
            tag: "0.111.0"
          extraArgs:
            - "--zap-log-level=debug"
        admissionWebhooks:
          certManager:
            enabled: true
          autoGenerateCert:
            enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: opentelemetry-operator-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
EOF
)
deploy_app "opentelemetry-operator" "$OTEL_OPERATOR_YAML"


# ==============================================================================
# 5. OPENOBSERVE COLLECTOR
# ==============================================================================
log "Deploying OpenObserve Collector..."
COLLECTOR_YAML=$(cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openobserve-collector
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://charts.openobserve.ai
    chart: openobserve-collector
    targetRevision: 0.4.0
    helm:
      values: |
        k8sCluster: "microk8s-cluster"
        
        exporters:
          "otlphttp/openobserve":
            endpoint: "http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/default"
            headers:
              Authorization: "Basic $ZO_AUTH_TOKEN"
          "otlphttp/openobserve_k8s_events":
            endpoint: "http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/default"
            headers:
              Authorization: "Basic $ZO_AUTH_TOKEN"
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
EOF
)
deploy_app "openobserve-collector" "$COLLECTOR_YAML"

# ==============================================================================
# 6. DIAGNOSTICS (Runs if deployment is stalled)
# ==============================================================================
echo ""
echo "=================================================================="
echo "DIAGNOSTICS: Why are my pods not starting?"
echo "=================================================================="

# Check Collector Pods specifically
echo ">> 1. Collector Pod Status:"
lk get pods -n openobserve-collector-system -l app.kubernetes.io/instance=openobserve-collector -o wide

echo ""
echo ">> 2. Collector App Logs (Current & Previous):"
# Fetch logs from the collector container, including crashed instances
lk logs -n openobserve-collector-system -l app.kubernetes.io/instance=openobserve-collector --all-containers=true --tail=50 --prefix=true
echo "--- PREVIOUS INSTANCE LOGS (If crashed) ---"
lk logs -n openobserve-collector-system -l app.kubernetes.io/instance=openobserve-collector --all-containers=true --tail=50 --prefix=true --previous

echo ""
echo ">> 3. Operator Logs (Filtered Errors):"
OTEL_POD=$(lk get pods -n opentelemetry-operator-system -l app.kubernetes.io/name=opentelemetry-operator -o jsonpath='{.items[0].metadata.name}')
if [ -n "$OTEL_POD" ]; then
    lk logs -n opentelemetry-operator-system "$OTEL_POD" --tail=200 | grep -v '"level":"INFO"' | tail -n 50
else
    echo "Operator Pod NOT FOUND."
fi

echo ""
echo ">> 4. Recent Warnings in Namespace:"
lk get events -n openobserve-collector-system --field-selector type=Warning --sort-by='.lastTimestamp' | tail -n 10

echo ""
echo ">> 5. OpenTelemetryCollector CR Status (Summary):"
lk get opentelemetrycollector -n openobserve-collector-system -o wide

success "Collector Deployment Script Finished."