#!/bin/bash
source ./00-init.sh
setup_env

log "Deploying OTel Astronomy Shop Demo..."

# Cleanup
lk delete application -n argocd-system otel-demo-astronomy --ignore-not-found --wait=true
lk delete ns observability-tst --ignore-not-found --wait=true

# Namespace & Secret
lk create ns observability-tst --dry-run=client -o yaml | lk apply -f -

ZO_AUTH_TOKEN=$(echo -n "$ZO_ROOT_EMAIL:$ZO_ROOT_PASSWORD" | base64 -w0)

lk create secret generic zo-demo-creds -n observability-tst \
  --from-literal=ZO_ENDPOINT="http://openobserve-router.openobserve-system.svc:5080" \
  --from-literal=ZO_AUTH="Basic $ZO_AUTH_TOKEN" \
  --from-literal=ZO_ORG="$ORG_TEAM" \
  --dry-run=client -o yaml | lk apply -f -

# Deployment
echo "apiVersion: argoproj.io/v1alpha1
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
      selfHeal: true" | lk apply -f -

success "Test App Deployed."