#!/bin/bash
source ./00-init.sh
setup_env

log "Starting OpenObserve OTel Collector Deployment..."

# ==============================================================================
# 1. CLEANUP
# ==============================================================================
lk delete application -n argocd-system openobserve-collector opentelemetry-operator prometheus-operator --ignore-not-found --wait=true
lk delete ns openobserve-collector-system --ignore-not-found --wait=true

log "Creating Namespace & Secret..."
lk create ns openobserve-collector-system --dry-run=client -o yaml | lk apply -f -

ZO_AUTH_TOKEN=$(echo -n "$ZO_ROOT_EMAIL:$ZO_ROOT_PASSWORD" | base64 -w0)

lk create secret generic zo-collector-creds -n openobserve-collector-system \
  --from-literal=ZO_ENDPOINT="http://openobserve-router.openobserve-system.svc:5080" \
  --from-literal=ZO_AUTH="Basic $ZO_AUTH_TOKEN" \
  --from-literal=ZO_ORG="default" \
  --dry-run=client -o yaml | lk apply -f -

# ==============================================================================
# 2. OPERATORS (Prometheus & OTel)
# ==============================================================================
log "Deploying Prometheus Operator (CRDs only)..."
echo "apiVersion: argoproj.io/v1alpha1
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
      - ServerSideApply=true" | lk apply -f -

log "Deploying OpenTelemetry Operator..."
echo "apiVersion: argoproj.io/v1alpha1
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
            enabled: false
          autoGenerateCert:
            enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true" | lk apply -f -

# ==============================================================================
# 3. OPENOBSERVE COLLECTOR (Agents & Gateway)
# ==============================================================================
log "Deploying OpenObserve Collector..."
# Note: mode 'deployment' usually creates a Gateway. 
# To get agents (DaemonSet) AND Gateway, the chart typically requires specific config 
# or deployment of two release instances. 
# Below uses the standard opinionated chart config which typically sets up a pipeline.
echo "apiVersion: argoproj.io/v1alpha1
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
        k8sCluster: 'microk8s-cluster'
        exporters:
          'otlphttp/openobserve':
            endpoint: 'http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/default'
            headers:
              Authorization: 'Basic $ZO_AUTH_TOKEN'
          'otlphttp/openobserve_k8s_events':
            endpoint: 'http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/default'
            headers:
              Authorization: 'Basic $ZO_AUTH_TOKEN'
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true" | lk apply -f -

success "Collector Deployment Applied."