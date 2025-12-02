# Makefile for OpenObserve Stack

# Default variables
TF_FLAGS = -var="zo_root_password=$(ZO_ROOT_PASSWORD)"
KUBECTL_CMD = kubectl

# Defaults if not provided
ZO_ROOT_PASSWORD ?= ComplexPassword123!

.PHONY: help init plan apply destroy info port-forward clean

help: ## Show this help message
	@echo "Usage: make [target]"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	terraform init

plan: ## Plan the deployment
	terraform plan -out=tfplan $(TF_FLAGS)

apply: ## Apply the deployment
	terraform apply tfplan

up: init plan apply info ## Run init, plan, apply, and show info

destroy: ## Destroy all resources (Cleanup)
	@echo "destroying infrastructure..."
	terraform destroy -auto-approve $(TF_FLAGS)
	@echo "Cleaning up local port-forward processes..."
	@pkill -f "kubectl port-forward" || true

clean: destroy ## Alias for destroy

info: ## Show URLs and Credentials
	@echo ""
	@echo "=================================================================="
	@echo "ACCESS INFORMATION"
	@echo "=================================================================="
	@echo ""
	@echo "1. ArgoCD (Secure Mode Enabled)"
	@echo "   URL:  https://127.0.0.1:8443"
	@echo "   User: admin"
	@echo -n "   Pass: "
	@$(KUBECTL_CMD) -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}' 2>/dev/null || echo "Not found"
	@echo ""
	@echo ""
	@echo "2. OpenObserve"
	@echo "   URL:  http://127.0.0.1:5080"
	@echo -n "   User: "
	@$(KUBECTL_CMD) -n openobserve-system get secret openobserve-creds -o go-template='{{.data.ZO_ROOT_USER_EMAIL | base64decode}}' 2>/dev/null || echo "Not found"
	@echo -n "   Pass: "
	@$(KUBECTL_CMD) -n openobserve-system get secret openobserve-creds -o go-template='{{.data.ZO_ROOT_USER_PASSWORD | base64decode}}' 2>/dev/null || echo "Not found"
	@echo ""
	@echo ""
	@echo "3. MinIO"
	@echo "   URL:  http://127.0.0.1:9001"
	@echo -n "   User: "
	@$(KUBECTL_CMD) -n minio-system get secret minio-creds -o go-template='{{.data.rootUser | base64decode}}' 2>/dev/null || echo "Not found"
	@echo -n "   Pass: "
	@$(KUBECTL_CMD) -n minio-system get secret minio-creds -o go-template='{{.data.rootPassword | base64decode}}' 2>/dev/null || echo "Not found"
	@echo ""
	@echo "=================================================================="

port-forward: ## Start background port-forwards
	@echo "Starting port-forwards in background..."
	@pkill -f "kubectl port-forward" || true
	# Note: argocd namespace used here
	@nohup $(KUBECTL_CMD) port-forward svc/argocd-server -n argocd 8443:443 >/dev/null 2>&1 &
	@nohup $(KUBECTL_CMD) port-forward svc/openobserve-router -n openobserve-system 5080:5080 >/dev/null 2>&1 &
	@nohup $(KUBECTL_CMD) port-forward svc/minio-console -n minio-system 9001:9001 >/dev/null 2>&1 &
	@echo "Ports opened: ArgoCD(8443), OpenObserve(5080), MinIO(9001)"