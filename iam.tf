resource "null_resource" "openobserve_iam" {
  depends_on = [kubectl_manifest.openobserve]

  triggers = {
    orgs = "${var.org_team}-${var.org_platform}"
  }

  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting for OpenObserve to be ready..."
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=openobserve -n openobserve-system --timeout=300s
      
      # Start a background port-forward
      kubectl port-forward svc/openobserve-router -n openobserve-system 5080:5080 > /dev/null 2>&1 &
      PF_PID=$!
      
      sleep 5
      
      AUTH_TOKEN=$(echo -n "${var.zo_root_email}:${var.zo_root_password}" | base64)
      
      echo "Creating Organization: ${var.org_team}"
      curl -s -X POST "http://127.0.0.1:5080/api/organizations" \
        -H "Authorization: Basic $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${var.org_team}\"}"
      
      echo "Creating Organization: ${var.org_platform}"
      curl -s -X POST "http://127.0.0.1:5080/api/organizations" \
        -H "Authorization: Basic $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${var.org_platform}\"}"
        
      kill $PF_PID
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}