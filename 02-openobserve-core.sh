#!/bin/bash
source ./00-init.sh
setup_env

log "Starting OpenObserve Core Deployment..."

# ==============================================================================
# 1. CLEANUP
# ==============================================================================
pkill -f "kubectl port-forward.*svc/openobserve" || true
# Delete apps first to stop sync
lk delete application -n argocd-system cloudnative-pg minio openobserve --ignore-not-found --wait=true
# Delete namespaces
lk delete ns cnpg-system minio-system openobserve-system --ignore-not-found --wait=true

# ==============================================================================
# 2. NAMESPACES & SECRETS
# ==============================================================================
log "Creating Namespaces & Secrets..."
lk create ns cnpg-system --dry-run=client -o yaml | lk apply -f -
lk create ns minio-system --dry-run=client -o yaml | lk apply -f -
lk create ns openobserve-system --dry-run=client -o yaml | lk apply -f -

lk create secret generic minio-creds -n minio-system \
  --from-literal=rootUser=$MINIO_ROOT_USER \
  --from-literal=rootPassword=$MINIO_ROOT_PASSWORD \
  --from-literal=accessKey=$MINIO_ROOT_USER \
  --from-literal=secretKey=$MINIO_ROOT_PASSWORD \
  --dry-run=client -o yaml | lk apply -f -

lk create secret generic openobserve-creds -n openobserve-system \
  --from-literal=ZO_ROOT_USER_EMAIL=$ZO_ROOT_EMAIL \
  --from-literal=ZO_ROOT_USER_PASSWORD=$ZO_ROOT_PASSWORD \
  --from-literal=ZO_S3_ACCESS_KEY=$MINIO_ROOT_USER \
  --from-literal=ZO_S3_SECRET_KEY=$MINIO_ROOT_PASSWORD \
  --dry-run=client -o yaml | lk apply -f -

# ==============================================================================
# 3. DEPLOYMENTS
# ==============================================================================

# --- CNPG ---
log "Deploying CloudNativePG..."
echo "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudnative-pg
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://cloudnative-pg.github.io/charts
    chart: cloudnative-pg
    targetRevision: 0.22.0
  destination:
    server: https://kubernetes.default.svc
    namespace: cnpg-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true" | lk apply -f -

# --- MinIO ---
log "Deploying MinIO..."
echo "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: minio
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://charts.min.io/
    chart: minio
    targetRevision: 5.3.0
    helm:
      values: |
        mode: standalone
        replicas: 1
        existingSecret: minio-creds
        persistence:
          enabled: true
          size: 10Gi
        buckets:
          - name: openobserve-data
            policy: none
            purge: false
          - name: observability-team-stream
            policy: none
            purge: false
          - name: observability-platform-stream
            policy: none
            purge: false
  destination:
    server: https://kubernetes.default.svc
    namespace: minio-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: true" | lk apply -f -

# --- OpenObserve HA ---
log "Deploying OpenObserve HA..."
echo "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openobserve
  namespace: argocd-system
spec:
  project: default
  source:
    repoURL: https://charts.openobserve.ai
    chart: openobserve
    targetRevision: 0.16.2
    helm:
      values: |
        statefulSet:
          enabled: true
          replicas: 2 
        config:
          ZO_S3_SERVER_URL: 'http://minio.minio-system.svc:9000'
          ZO_S3_BUCKET_NAME: 'openobserve-data'
          ZO_S3_REGION_NAME: 'eu-central-1'
          ZO_HA_MODE: 'true'
        extraEnv:
          - name: ZO_ROOT_USER_EMAIL
            valueFrom:
              secretKeyRef:
                name: openobserve-creds
                key: ZO_ROOT_USER_EMAIL
          - name: ZO_ROOT_USER_PASSWORD
            valueFrom:
              secretKeyRef:
                name: openobserve-creds
                key: ZO_ROOT_USER_PASSWORD
          - name: ZO_S3_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: openobserve-creds
                key: ZO_S3_ACCESS_KEY
          - name: ZO_S3_SECRET_KEY
            valueFrom:
              secretKeyRef:
                name: openobserve-creds
                key: ZO_S3_SECRET_KEY
        etcd:
          enabled: true
          replicaCount: 1
          auth:
            rbac:
              create: false
          image:
            registry: public.ecr.aws
            repository: bitnami/etcd
            tag: 3.6.6-debian-12-r0
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true" | lk apply -f -

# Wait loop
log "Waiting for OpenObserve to be Healthy in ArgoCD..."
until [ "$(lk get application -n argocd-system openobserve -o jsonpath='{.status.health.status}' 2>/dev/null)" == "Healthy" ]; do
    echo -n "."
    sleep 5
done
echo ""

# Port Forward
log "Setting up Port Forward..."
screen -dmS zo-pf bash -c 'while true; do microk8s kubectl port-forward svc/openobserve-router -n openobserve-system 5080:5080; sleep 2; done'
sleep 5

success "Core Deployment Complete."