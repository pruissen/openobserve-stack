# collectors/main.tf

# 1. READ BOOTSTRAP RESULTS
data "local_file" "bootstrap_results" {
  filename = "${path.module}/../bootstrap_results.json"
}

locals {
  bootstrap_data = jsondecode(data.local_file.bootstrap_results.content)
  
  org_config = [
    for org in local.bootstrap_data : org
    if org.org == "platform_kubernetes"
  ][0]

  sa_creds = [
    for sa in local.org_config.service_accounts : sa
    if sa.name == "sa-gitops"
  ][0]

  sa_auth_token = base64encode("${local.sa_creds.email}:${local.sa_creds.token}")
}

# 2. OTEL OPERATOR (Standalone)
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
            tag: "0.104.0"
  destination:
    server: https://kubernetes.default.svc
    namespace: opentelemetry-operator-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
YAML
}

# 3. HEALTH CHECK & FORCEFUL CLEANUP
resource "null_resource" "wait_for_operator" {
  # CREATE-TIME: Wait for Operator to be healthy
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      echo "⏳ (Create) Waiting for Operator Deployment..."
      until kubectl get deployment -n opentelemetry-operator-system opentelemetry-operator >/dev/null 2>&1; do 
        sleep 5
      done
      kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-operator -n opentelemetry-operator-system
    EOT
  }

  # DESTROY-TIME: Force remove finalizers to prevent hanging
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      echo "🧹 (Destroy) Force cleaning OpenTelemetry Collectors..."
      
      NAMESPACE="openobserve-collector-system"
      
      # 1. Identify existing collectors
      COLLECTORS=$(kubectl get opentelemetrycollector -n $NAMESPACE -o name 2>/dev/null)
      
      if [ -z "$COLLECTORS" ]; then
        echo "✅ No collectors found. Clean."
        exit 0
      fi

      echo "⚠️  Found collectors: $COLLECTORS"
      
      # 2. The 'Nuclear' Option: Patch finalizers to null
      # This tells K8s "don't wait for the operator, just delete it now"
      for col in $COLLECTORS; do
        echo "   - Patching finalizers for $col..."
        # This command removes the finalizer block
        kubectl patch $col -n $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge || true
        
        echo "   - Force deleting $col..."
        kubectl delete $col -n $NAMESPACE --ignore-not-found=true --wait=false
      done

      # 3. Short wait to verify they are gone (with timeout to prevent infinite hang)
      echo "⏳ Verifying deletion..."
      timeout 30 bash -c "while kubectl get opentelemetrycollector -n $NAMESPACE 2>/dev/null | grep -q .; do sleep 2; done" || echo "⚠️ Timeout waiting for verification, but finalizers are gone so K8s will clean up."
      
      echo "✅ Cleanup complete."
    EOT
  }

  depends_on = [kubectl_manifest.otel_operator]
}

# 4. OPENOBSERVE COLLECTOR (Standalone)
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
        
        opentelemetry-operator:
          enabled: false

        image:
          repository: "otel/opentelemetry-collector-contrib"
          tag: "0.104.0"

        exporters:
          "otlphttp/openobserve":
            endpoint: "http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/platform_kubernetes"
            headers:
              Authorization: "Basic ${local.sa_auth_token}"
          "otlphttp/openobserve_k8s_events":
            endpoint: "http://openobserve-router.openobserve-system.svc.cluster.local:5080/api/platform_kubernetes"
            headers:
              Authorization: "Basic ${local.sa_auth_token}"
  destination:
    server: https://kubernetes.default.svc
    namespace: openobserve-collector-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
YAML
  
  # Explicitly wait for the health check to pass
  depends_on = [null_resource.wait_for_operator]
}