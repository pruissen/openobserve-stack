terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
  config_path      = "~/.kube/config"
  load_config_file = true
}

# ============================================================================
# 1. CONFIGURATION & SECRETS
# ============================================================================

variable "admin_email" {
  default = "admin@platform.com"
}

resource "random_password" "admin_pass" {
  length  = 20
  special = false
}

locals {
  # This creates the Base64 encoded string "user:password"
  root_auth_token = base64encode("${var.admin_email}:${random_password.admin_pass.result}")
  tracing_header_val = "Basic ${base64encode("${var.admin_email}:${random_password.admin_pass.result}")}"
  builtin_dsn = "postgres://openobserve:${random_password.admin_pass.result}@openobserve-postgres-rw.o2-system.svc:5432/app"
}

resource "kubernetes_namespace" "ns" {
  for_each = toset([
    "o2-system", "argocd-system",
    "cert-manager-system", "openobserve-collector-system", 
    "opentelemetry-operator-system", "devteam-1"
  ])
  metadata { name = each.key }
}

resource "kubernetes_secret" "o2_platform_secret" {
  for_each = toset(["o2-system", "argocd-system", "openobserve-collector-system"])
  metadata {
    name      = "o2-platform-secret"
    namespace = each.key
  }
  
  data = {
    "admin.password" = bcrypt(random_password.admin_pass.result)
    password         = base64encode(random_password.admin_pass.result)
    rootUser          = "admin"
    rootPassword      = random_password.admin_pass.result
    "root-user"       = "admin"
    "root-password"   = random_password.admin_pass.result
    accessKey         = "admin"
    secretKey         = random_password.admin_pass.result
    "postgres-password" = random_password.admin_pass.result
    ROOT_AUTH             = local.root_auth_token
    ZO_ROOT_USER_EMAIL    = var.admin_email
    ZO_ROOT_USER_PASSWORD = random_password.admin_pass.result
    ZO_ROOT_USER_TOKEN    = "" 
    ZO_META_POSTGRES_DSN    = local.builtin_dsn
    ZO_S3_ACCESS_KEY        = "admin"
    ZO_S3_SECRET_KEY        = random_password.admin_pass.result
    ZO_TRACING_HEADER_KEY   = "Authorization"
    ZO_TRACING_HEADER_VALUE = local.tracing_header_val
  }
  depends_on = [kubernetes_namespace.ns]
}

# ============================================================================
# 2. ARGOCD
# ============================================================================

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd-system"
  version          = "7.6.12"
  values           = [file("${path.module}/k8s/values/argocd.yaml")]
  depends_on       = [kubernetes_secret.o2_platform_secret]
}

resource "null_resource" "patch_argo_secret" {
  depends_on = [helm_release.argocd]
  triggers = {
    password_change = random_password.admin_pass.result
  }
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = pathexpand("~/.kube/config")
    }
    command = <<EOT
      kubectl -n argocd-system patch secret argocd-secret \
      -p '{"stringData": { "admin.password": "${bcrypt(random_password.admin_pass.result)}", "admin.passwordMtime": "'$(date +%FT%T%Z)'" }}'
    EOT
  }
}

# ============================================================================
# 3. CORE INFRA & DATA STORE
# ============================================================================

resource "kubectl_manifest" "cnpg" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: cloudnative-pg, namespace: argocd-system }
spec:
  project: default
  source:
    repoURL: https://github.com/cloudnative-pg/cloudnative-pg
    targetRevision: release-1.24
    path: releases
    directory: { include: 'cnpg-1.24.0.yaml' }
  destination: { server: https://kubernetes.default.svc, namespace: cnpg-system }
  syncPolicy: { automated: { prune: true, selfHeal: true }, syncOptions: [ServerSideApply=true] }
YAML
  depends_on = [helm_release.argocd]
}

resource "null_resource" "wait_for_cnpg" {
  depends_on = [kubectl_manifest.cnpg]
  provisioner "local-exec" {
    environment = { KUBECONFIG = pathexpand("~/.kube/config") }
    command = <<EOT
      echo "⏳ Waiting for CNPG Operator..."
      until kubectl get deployment -n cnpg-system cnpg-controller-manager >/dev/null 2>&1; do sleep 2; done
      kubectl wait --for=condition=available --timeout=120s deployment/cnpg-controller-manager -n cnpg-system
      echo "✅ CNPG Operator Ready."
    EOT
  }
}

resource "kubectl_manifest" "minio" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "minio"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://charts.min.io"
        chart          = "minio"
        targetRevision = "5.3.0"
        helm = { values = file("${path.module}/k8s/values/minio.yaml") }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "o2-system"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
        syncOptions = ["ServerSideApply=true"]
      }
    }
  })
  depends_on = [kubernetes_secret.o2_platform_secret, helm_release.argocd]
}

resource "null_resource" "wait_for_minio_healthy" {
  depends_on = [kubectl_manifest.minio]
  provisioner "local-exec" {
    environment = { KUBECONFIG = pathexpand("~/.kube/config") }
    command = <<EOT
      echo "⏳ Waiting for MinIO..."
      timeout 30s bash -c "until kubectl get application minio -n argocd-system >/dev/null 2>&1; do sleep 2; done"
      timeout 60s bash -c "until kubectl get service minio -n o2-system >/dev/null 2>&1; do sleep 2; done"
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n o2-system --timeout=120s
      echo "✅ MinIO Ready."
    EOT
  }
}

resource "kubectl_manifest" "cert_manager" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: cert-manager, namespace: argocd-system }
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.2
    helm: { values: "installCRDs: true" }
  destination: { server: https://kubernetes.default.svc, namespace: cert-manager-system }
  syncPolicy: { automated: { prune: true, selfHeal: true } }
YAML
  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "prometheus_crds" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-operator-crds
  namespace: argocd-system
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
    automated: { prune: true, selfHeal: true }
    syncOptions: [ServerSideApply=true, Replace=true]
YAML
  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "otel_operator" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: opentelemetry-operator, namespace: argocd-system }
spec:
  project: default
  source:
    repoURL: https://github.com/openobserve/openobserve-helm-chart
    targetRevision: main
    path: .
    directory:
      include: 'opentelemetry-operator.yaml'
  destination: { server: https://kubernetes.default.svc, namespace: opentelemetry-operator-system }
  syncPolicy: { automated: { prune: true, selfHeal: true }, syncOptions: [ServerSideApply=true] }
YAML
  depends_on = [helm_release.argocd]
}

# ============================================================================
# 4. OPENOBSERVE (ArgoCD Application)
# ============================================================================

resource "kubectl_manifest" "openobserve" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "openobserve"
      namespace  = "argocd-system"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://charts.openobserve.ai"
        chart          = "openobserve"
        targetRevision = "0.20.1" 
        helm = {
          values = yamlencode(merge(
            yamldecode(file("${path.module}/k8s/values/openobserve.yaml")),
            { postgres = { spec = { password = random_password.admin_pass.result } } }
          ))
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "o2-system"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
        syncOptions = ["ServerSideApply=true"]
      }
    }
  })
  depends_on = [
    kubernetes_secret.o2_platform_secret,
    null_resource.wait_for_cnpg,
    null_resource.wait_for_minio_healthy
  ]
}

# ============================================================================
# 5. COLLECTOR (Single Application)
# ============================================================================

resource "kubectl_manifest" "o2_collector" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: openobserve-collector, namespace: argocd-system }
spec:
  project: default
  source:
    repoURL: https://charts.openobserve.ai
    chart: openobserve-collector
    targetRevision: 0.4.1
    helm:
      values: |
        ${indent(8, templatefile("${path.module}/k8s/values/collector.yaml", {
          root_auth = local.root_auth_token
        }))}
  destination: { server: https://kubernetes.default.svc, namespace: openobserve-collector-system }
  syncPolicy: { automated: { prune: true, selfHeal: true }, syncOptions: [ServerSideApply=true] }
YAML
  depends_on = [kubectl_manifest.openobserve, kubectl_manifest.otel_operator]
}

# ============================================================================
# 6. DEMO APP
# ============================================================================
resource "kubectl_manifest" "otel_demo" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: otel-demo, namespace: argocd-system }
spec:
  project: default
  source:
    repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
    chart: opentelemetry-demo
    targetRevision: 0.33.2
    helm:
      # Load the external values file
      values: |
        ${indent(8, file("${path.module}/k8s/values/astronomy-shop.yaml"))}
  destination: { server: https://kubernetes.default.svc, namespace: devteam-1 }
  syncPolicy: { automated: { prune: true, selfHeal: true } }
YAML
  depends_on = [kubectl_manifest.o2_collector]
}