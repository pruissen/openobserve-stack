
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
  version          = "7.7.0"

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
      - ServerSideApply=true
YAML
  depends_on = [helm_release.argocd]
}

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
    # Chart Version 0.20.1 maps to AppVersion v0.20.1 (Enterprise Ready)
    targetRevision: 0.20.1
    helm:
      values: |
        postgresql:
          enabled: false
        statefulSet:
          enabled: true
          replicas: 2 
        config:
          ZO_S3_SERVER_URL: 'http://minio.minio-system.svc:9000'
          ZO_S3_BUCKET_NAME: 'openobserve-data'
          ZO_S3_REGION_NAME: 'eu-central-1'
          ZO_HA_MODE: 'true'
          ZO_META_STORE: 'etcd'
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
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
  depends_on = [helm_release.argocd, kubernetes_secret.openobserve_creds]
}

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

resource "kubectl_manifest" "prometheus_operator" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-operator
  namespace: argocd
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
YAML
  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "otel_operator" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: opentelemetry-operator
  namespace: argocd
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
        admissionWebhooks:
          certManager:
            enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: opentelemetry-operator-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
YAML
  depends_on = [kubectl_manifest.cert_manager, kubectl_manifest.prometheus_operator]
}

resource "kubectl_manifest" "openobserve_collector" {
    yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openobserve-collector
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.openobserve.ai
    chart: openobserve-collector
    # Chart Version 0.4.1 (AppVersion 0.136.0) as requested
    targetRevision: 0.4.1
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
YAML
  depends_on = [kubectl_manifest.openobserve]
}