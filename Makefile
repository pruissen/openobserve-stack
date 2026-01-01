# Makefile for OpenObserve K3s Stack

KUBECONFIG := $(HOME)/.kube/config
export KUBECONFIG

# Terraform Targets - Prerequisites
TF_PREREQS := -target=kubernetes_namespace.ns \
              -target=kubernetes_secret.o2_platform_secret \
              -target=helm_release.argocd \
              -target=null_resource.patch_argo_secret \
              -target=kubectl_manifest.cnpg \
              -target=kubectl_manifest.cert_manager \
              -target=kubectl_manifest.otel_operator \
              -target=kubectl_manifest.prometheus_crds \
              -target=kubectl_manifest.minio

# Target the ArgoCD Application for OpenObserve
TF_O2      := -target=kubectl_manifest.openobserve

# Single Collector Target
TF_COLL    := -target=kubectl_manifest.o2_collector

# Demo Application
TF_DEMO    := -target=kubectl_manifest.otel_demo

.PHONY: all help install-core init uninstall-core install-prereqs uninstall-prereqs install-o2 uninstall-o2 install-o2-collector uninstall-o2-collector install-demo uninstall-demo install-platform nuke info start stop show bootstrap

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'

# --- 1. CORE (K3s + TF Init) ---

install-core: ## Install K3s and Init Terraform
	@echo "--- Installing K3s ---"
	curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -
	@echo "--- Waiting for K3s ---"
	@sleep 10
	mkdir -p ~/.kube
	sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
	sudo chown $(USER) ~/.kube/config
	@chmod 600 ~/.kube/config
	@make init

init: ## Init Terraform with Upgrade
	@echo "--- Initializing Terraform (Upgrading Providers) ---"
	terraform init --upgrade

uninstall-core: ## Uninstall K3s
	@echo "--- Removing K3s ---"
	/usr/local/bin/k3s-uninstall.sh || true
	rm -rf ~/.kube

# --- 2. PREREQUISITES ---

install-prereqs: ## Plan & Apply Prerequisites (Includes MinIO App)
	@echo "--- Planning Prerequisites ---"
	terraform plan $(TF_PREREQS) -out=prereqs.tfplan
	@echo "--- Applying Prerequisites ---"
	terraform apply prereqs.tfplan
	@rm -f prereqs.tfplan
	@echo "⏳ Waiting for MinIO ArgoCD App to sync..."
	@timeout 60s bash -c "until kubectl get application minio -n argocd-system >/dev/null 2>&1; do sleep 2; done"
	@echo "⏳ Waiting for MinIO pods to be ready..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n o2-system --timeout=300s || echo "⚠️  MinIO wait timed out"

uninstall-prereqs: ## Destroy Prerequisites
	@echo "--- Destroying Prerequisites ---"
	terraform destroy -auto-approve $(TF_PREREQS)

# --- 3. OPENOBSERVE ---

install-o2: ## Plan & Apply OpenObserve
	@echo "--- Planning OpenObserve ---"
	terraform plan $(TF_O2) -out=o2.tfplan
	@echo "--- Applying OpenObserve ---"
	terraform apply o2.tfplan
	@rm -f o2.tfplan
	
	@echo "⏳ [1/4] Waiting for OpenObserve Application..."
	@timeout 120s bash -c "until kubectl get application openobserve -n argocd-system >/dev/null 2>&1; do sleep 2; done"
	
	@echo "⏳ [2/4] Waiting for ArgoCD to create workloads (Router & Ingester)..."
	@timeout 180s bash -c "until kubectl get deployment openobserve-router -n o2-system >/dev/null 2>&1; do sleep 5; done"
	@timeout 180s bash -c "until kubectl get statefulset openobserve-ingester -n o2-system >/dev/null 2>&1; do sleep 5; done"
	
	@echo "⏳ [3/4] Waiting for Ingester (Write Path) to be Ready..."
	@kubectl rollout status statefulset/openobserve-ingester -n o2-system --timeout=300s
	
	@echo "⏳ [4/4] Waiting for Router (Read Path) to be Available..."
	@kubectl wait --for=condition=available deployment/openobserve-router -n o2-system --timeout=300s
	
	@echo "✅ OpenObserve is Fully Ready."

uninstall-o2: ## Destroy OpenObserve (Forcefully)
	@echo "--- Destroying OpenObserve ---"
	-terraform destroy -auto-approve $(TF_O2)
	
	@echo "🧹 Force cleaning o2-system namespace..."
	-kubectl delete application openobserve -n argocd-system --timeout=10s --wait=false
	-kubectl delete application minio -n argocd-system --timeout=10s --wait=false
	-kubectl delete statefulset --all -n o2-system --timeout=10s --wait=false
	-kubectl delete deployment --all -n o2-system --timeout=10s --wait=false
	-kubectl delete pvc --all -n o2-system --timeout=10s --wait=false
	-kubectl delete pod --all -n o2-system --force --grace-period=0
	
	-for res in statefulsets deployments pvc secrets configmaps applications; do \
		kubectl -n o2-system patch $$res --all --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true; \
		kubectl -n argocd-system patch $$res openobserve --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true; \
		kubectl -n argocd-system patch $$res minio --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true; \
	done

	@echo "✅ OpenObserve Uninstall Complete."

# --- 4. COLLECTOR ---

install-o2-collector: ## Install OpenObserve Collector
	@echo "--- Installing OpenObserve Collector ---"
	terraform plan $(TF_COLL) -out=collector.tfplan
	terraform apply collector.tfplan
	@rm -f collector.tfplan

uninstall-o2-collector: ## Uninstall OpenObserve Collector
	@echo "--- Destroying OpenObserve Collector ---"
	terraform destroy -auto-approve $(TF_COLL)

# --- 5. DEMO ---

install-demo: ## Plan & Apply OTel Demo
	@echo "--- Planning OTel Demo ---"
	terraform plan $(TF_DEMO) -out=demo.tfplan
	@echo "--- Applying OTel Demo ---"
	terraform apply demo.tfplan
	@rm -f demo.tfplan

uninstall-demo: ## Destroy OTel Demo
	terraform destroy -auto-approve $(TF_DEMO)

# --- 6. META ---

# FIX: Added 'install-core' back to the chain so K3s is actually installed before we try to deploy apps
install-platform: install-core install-prereqs install-o2 start bootstrap install-o2-collector ## Install Full Platform

all: install-platform

nuke: ## DESTROY EVERYTHING (Forcefully)
	@echo "🔥 NUCLEAR LAUNCH DETECTED 🔥"
	@make stop
	-terraform destroy -auto-approve
	
	@echo "🧹 Force Cleaning Webhooks & APIServices..."
	-kubectl delete mutatingwebhookconfigurations --all --timeout=10s --wait=false
	-kubectl delete validatingwebhookconfigurations --all --timeout=10s --wait=false
	-kubectl delete apiservices -l app.kubernetes.io/managed-by=Helm --timeout=10s --wait=false

	@echo "💀 Force Cleaning Namespaces..."
	-for ns in o2-system argocd-system cnpg-system cert-manager-system openobserve-collector-system opentelemetry-operator-system devteam-1; do \
		if kubectl get ns $$ns >/dev/null 2>&1; then \
			echo "   - Cleaning $$ns..."; \
			kubectl patch ns $$ns -p '{"metadata":{"finalizers":null}}' --type=merge || true; \
			kubectl delete ns $$ns --timeout=10s --wait=false || true; \
		fi; \
	done

	@echo "🗑️  Uninstalling K3s..."
	@make uninstall-core
	rm -rf terraform.tfstate* .terraform .terraform.lock.hcl *.tfplan
	@echo "✅ Nuke Complete."

# --- 7. OPERATIONS ---

start: ## Start Port Forwarding
	@chmod +x scripts/*.sh
	@./scripts/port-forward-all.sh start
	@echo "⏳ Waiting for tunnels to stabilize..."
	@sleep 5

stop: ## Stop Port Forwarding
	@chmod +x scripts/*.sh
	@./scripts/port-forward-all.sh stop

show: ## Show URLs and Credentials
	@chmod +x scripts/*.sh
	@./scripts/port-forward-all.sh show

bootstrap: ## Configure Tenants in OpenObserve
	@echo "--- Bootstrapping Tenants & Importing Dashboards ---"
	python3 o2_manager.py bootstrap