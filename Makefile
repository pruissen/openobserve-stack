# Makefile for OpenObserve Stack
TF_FLAGS = -var="zo_root_password=$(ZO_ROOT_PASSWORD)"
ZO_ROOT_PASSWORD ?= ComplexPassword123!

.PHONY: help init plan apply plan-collectors apply-collectors start stop info clean install-microk8s remove-microk8s

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- CLUSTER MANAGEMENT ---

install-microk8s: ## Install Microk8s, enable addons, and configure access
	@echo "--- Installing Microk8s (Requires Sudo) ---"
	sudo snap install microk8s --classic
	@echo "--- Configuring Permissions ---"
	sudo usermod -a -G microk8s $(USER)
	sudo mkdir -p ~/.kube
	sudo chown -f -R $(USER) ~/.kube
	@echo "--- Waiting for Cluster to be Ready ---"
	sudo microk8s status --wait-ready
	@echo "--- Enabling Addons (dns, helm3, storage) ---"
	sudo microk8s enable dns helm3 storage
	@echo "--- Exporting Kubeconfig ---"
	# Using 'cat' to bypass potential snap stdout issues
	sudo microk8s config | cat > ~/.kube/config
	chmod 600 ~/.kube/config
	@echo "---------------------------------------------------"
	@echo "✅ Microk8s Ready. NOTE: You must run 'newgrp microk8s' or re-login to use kubectl commands without sudo."

remove-microk8s: ## Purge Microk8s and clean configuration
	@echo "--- Removing Microk8s ---"
	sudo snap remove microk8s --purge
	@rm -f ~/.kube/config
	@echo "✅ Microk8s Removed."

# --- CORE INFRASTRUCTURE ---

init: ## Initialize Core Terraform
	terraform init

plan: init ## Generate execution plan for Core Infra
	@echo "Planning Core Infrastructure..."
	terraform plan -out=core.tfplan $(TF_FLAGS)
	@echo "---------------------------------------------------"
	@echo "Plan saved to 'core.tfplan'. Run 'make apply' to deploy."

apply: ## Apply Core Infra (Requires 'make plan' first)
	@echo "Applying Core Infrastructure..."
	terraform apply core.tfplan
	@rm core.tfplan

# --- COLLECTORS (Run after Core is ready) ---

init-collectors:
	cd collectors && terraform init

plan-collectors: init-collectors ## Generate execution plan for Collectors
	@echo "Planning Collectors..."
	cd collectors && terraform plan -out=collectors.tfplan
	@echo "---------------------------------------------------"
	@echo "Plan saved to 'collectors/collectors.tfplan'. Run 'make apply-collectors' to deploy."

apply-collectors: ## Apply Collectors (Requires 'make plan-collectors' first)
	@echo "Applying Collectors..."
	cd collectors && terraform apply collectors.tfplan
	@rm collectors/collectors.tfplan

# --- MANAGEMENT ---

start: ## Start Port Forwards (Background)
	@chmod +x manage-local-connection.sh
	@./manage-local-connection.sh start

stop: ## Stop Port Forwards
	@chmod +x manage-local-connection.sh
	@./manage-local-connection.sh stop

restart: ## Restart Port Forwards
	@chmod +x manage-local-connection.sh
	@./manage-local-connection.sh restart

info: ## Show Service Credentials and URLs
	@chmod +x manage-local-connection.sh
	@./manage-local-connection.sh info

# --- CLEANUP ---

clean: ## Destroy Everything (Core + Collectors)
	@echo "Stopping port-forwards..."
	@./manage-local-connection.sh stop || true
	@echo "Destroying Collectors..."
	cd collectors && terraform destroy -auto-approve || true
	@echo "Destroying Core Infrastructure..."
	terraform destroy -auto-approve $(TF_FLAGS)
	@echo "Cleaning up plan files..."
	@rm -f core.tfplan collectors/collectors.tfplan
	@rm -f bootstrap_results.json