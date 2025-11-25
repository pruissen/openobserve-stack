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
# Delete namespaces
lk delete ns openobserve-collector-system --ignore-not-found --wait=true
# Note: We usually don't delete cert-manager ns to avoid stuck CRD finalizers, but for clean reinstall we can try:
# lk delete ns cert-manager --ignore-not-found --wait=true

log "Creating Namespaces & Secrets..."
lk create ns cert-manager --dry-run=client -o yaml | lk apply -f -
lk create ns openobserve-collector-system --dry-run=client -o yaml | lk apply -f -

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
    until [ "$(lk get application -n argocd-system $APP_NAME -o jsonpath='{.status.health.status}' 2>/dev/null)" == "Healthy" ]; do
        echo -n "."
        sleep 5
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
    namespace: cert-manager
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

log "Deploying OpenTelemetry Operator..."
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
        admissionWebhooks:
          certManager:
            enabled: true
          autoGenerateCert:
            enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
)
deploy_app "opentelemetry-operator" "$OTEL_OPERATOR_YAML"

log "Restarting OTel Operator to ensure Webhook Certs are loaded..."
# Fix: Dynamically find the deployment name instead of guessing
OTEL_DEP_NAME=$(lk get deployment -n openobserve-collector-system -l app.kubernetes.io/name=opentelemetry-operator -o jsonpath='{.items[0].metadata.name}')

if [ -n "$OTEL_DEP_NAME" ]; then
    log "Found Deployment: $OTEL_DEP_NAME. Restarting..."
    lk rollout restart deployment "$OTEL_DEP_NAME" -n openobserve-collector-system
    lk rollout status deployment "$OTEL_DEP_NAME" -n openobserve-collector-system --timeout=60s
    log "Waiting for Webhook to be ready..."
    sleep 10
else
    log "WARNING: Could not find OTel Operator deployment to restart. Webhooks might fail."
fi

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
EOF
)
deploy_app "openobserve-collector" "$COLLECTOR_YAML"

success "Collector Deployment Applied."