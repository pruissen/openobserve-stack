# collectors/main.tf

# 1. READ EXISTING SECRETS (From Core Infra)
data "kubernetes_secret" "openobserve_creds" {
  metadata {
    name      = "openobserve-creds"
    namespace = "openobserve-system"
  }
}

locals {
  # Decode secrets to build the auth token
  zo_user = data.kubernetes_secret.openobserve_creds.data["ZO_ROOT_USER_EMAIL"]
  zo_pass = data.kubernetes_secret.openobserve_creds.data["ZO_ROOT_USER_PASSWORD"]
  # Base64 encode User:Pass for Basic Auth
  zo_auth_token = base64encode("${local.zo_user}:${local.zo_pass}")
}

# 2. OTEL OPERATOR
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
}

# 3. OPENOBSERVE COLLECTOR
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
    targetRevision: 0.4.1
    helm:
      values: |
        k8sCluster: "microk8s-cluster"
        exporters:
          "otlphttp/openobserve":
            endpoint: "http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/default"
            headers:
              Authorization: "Basic ${local.zo_auth_token}"
          "otlphttp/openobserve_k8s_events":
            endpoint: "http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/default"
            headers:
              Authorization: "Basic ${local.zo_auth_token}"
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
  depends_on = [kubectl_manifest.otel_operator]
}