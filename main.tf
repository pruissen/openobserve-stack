# ============================================================================
# 1. NAMESPACES
# ============================================================================
resource "kubernetes_namespace" "ns" {
  for_each = toset([
    "cnpg-system",
    "minio-system",
    "openobserve-system",
    "cert-manager-system",
    "openobserve-collector-system",
    "opentelemetry-operator-system",
    "observability-tst"
  ])
  metadata {
    name = each.key
  }
}

# ============================================================================
# 2. SECRETS
# ============================================================================
resource "kubernetes_secret" "minio_creds" {
  metadata {
    name      = "minio-creds"
    namespace = "minio-system"
  }
  data = {
    rootUser     = var.minio_root_user
    rootPassword = var.minio_root_password
    accessKey    = var.minio_root_user
    secretKey    = var.minio_root_password
  }
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_secret" "openobserve_creds" {
  metadata {
    name      = "openobserve-creds"
    namespace = "openobserve-system"
  }
  data = {
    ZO_ROOT_USER_EMAIL    = var.zo_root_email
    ZO_ROOT_USER_PASSWORD = var.zo_root_password
    ZO_S3_ACCESS_KEY      = var.minio_root_user
    ZO_S3_SECRET_KEY      = var.minio_root_password
  }
  depends_on = [kubernetes_namespace.ns]
}

# ============================================================================
# 3. ARGOCD INSTALLATION
# ============================================================================
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "9.1.5"

  values = [
    <<-EOT
    server:
      service:
        type: ClusterIP
      replicas: 1
      extraArgs:
        - --insecure=false
    controller:
      replicas: 1
    repoServer:
      replicas: 1
    applicationSet:
      replicas: 1
    redis-ha:
      enabled: false
    redis:
      enabled: true
    configs:
      params:
        server.insecure: "false"
    EOT
  ]
}

# ============================================================================
# 4. GITOPS APPLICATIONS
# ============================================================================

# --- CLOUDNATIVE-PG ---
# Installs the Operator needed by OpenObserve's Postgres Cluster
resource "kubectl_manifest" "cnpg" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudnative-pg
  namespace: argocd 
spec:
  project: default
  source:
    repoURL: https://github.com/cloudnative-pg/cloudnative-pg
    targetRevision: release-1.22
    path: releases
    # Explicitly select the v1.22.1 manifest to avoid file size errors
    directory:
      include: 'cnpg-1.22.1.yaml'
  destination:
    server: https://kubernetes.default.svc
    namespace: cnpg-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
YAML
  depends_on = [helm_release.argocd]
}

# --- MINIO ---
resource "kubectl_manifest" "minio" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: minio
  namespace: argocd
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
  destination:
    server: https://kubernetes.default.svc
    namespace: minio-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
  depends_on = [helm_release.argocd, kubernetes_secret.minio_creds]
}

# --- OPENOBSERVE ---
# Configured to use Postgres (via CNPG) for Metadata
resource "kubectl_manifest" "openobserve" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openobserve
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.openobserve.ai
    chart: openobserve
    targetRevision: 0.20.1
    helm:
      values: |
        # ENABLE POSTGRES: This tells the chart to create a Cluster resource
        # which the CNPG Operator (installed above) will fulfill.
        postgresql:
          enabled: true
        
        # DISABLE ETCD: We are switching to Postgres for metadata
        etcd:
          enabled: false

        statefulSet:
          enabled: true
          replicas: 2 
        
        config:
          ZO_S3_SERVER_URL: 'http://minio.minio-system.svc:9000'
          ZO_S3_BUCKET_NAME: 'openobserve-data'
          ZO_S3_REGION_NAME: 'eu-central-1'
          ZO_HA_MODE: 'true'
          # Added usage reporting as requested
          ZO_USAGE_REPORTING_ENABLED: 'true'
          # ZO_META_STORE defaults to 'db' (Postgres) when not set to 'etcd'

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
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      # Validate=false allows Argo to sync the App even if the CNPG CRDs
      # are not fully registered by Kubernetes yet.
      - Validate=false
      - CreateNamespace=true
YAML
  
  # Strict dependency: CNPG Operator must be installed first
  depends_on = [
    helm_release.argocd, 
    kubernetes_secret.openobserve_creds,
    kubectl_manifest.cnpg
  ]
}

# --- CERT MANAGER ---
resource "kubectl_manifest" "cert_manager" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
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
YAML
  depends_on = [helm_release.argocd]
}

# --- PROMETHEUS CRDS ---
# Requisite for the OTel Operator (installed separately in collectors/ module)
resource "kubectl_manifest" "prometheus_crds" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-operator-crds
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: prometheus-operator-crds
    targetRevision: 25.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - Replace=true
YAML
  depends_on = [helm_release.argocd]
}