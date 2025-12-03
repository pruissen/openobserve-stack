# Makefile for OpenObserve Stack
TF_FLAGS = -var="zo_root_password=$(ZO_ROOT_PASSWORD)"
ZO_ROOT_PASSWORD ?= ComplexPassword123!

.PHONY: help init plan apply plan-collectors apply-collectors start stop info clean

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

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
	@chmod +x manage.sh
	@./manage.sh start

stop: ## Stop Port Forwards
	@chmod +x manage.sh
	@./manage.sh stop

restart: ## Restart Port Forwards
	@chmod +x manage.sh
	@./manage.sh restart

info: ## Show Service Credentials and URLs
	@chmod +x manage.sh
	@./manage.sh info

# --- CLEANUP ---

clean: ## Destroy Everything (Core + Collectors)
	@echo "Stopping port-forwards..."
	@./manage.sh stop
	@echo "Destroying Collectors..."
	cd collectors && terraform destroy -auto-approve || true
	@echo "Destroying Core Infrastructure..."
	terraform destroy -auto-approve $(TF_FLAGS)
	@echo "Cleaning up plan files..."
	@rm -f core.tfplan collectors/collectors.tfplan