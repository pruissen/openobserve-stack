#!/bin/bash
source ./00-init.sh
setup_env
check_deps

log "Starting Infrastructure Installation..."

# ==============================================================================
# 1. DETECT OS & INSTALL MICROK8S
# ==============================================================================
OS="$(uname -s)"
case "${OS}" in
    Linux*)     
        if ! command -v microk8s &> /dev/null; then
            log "Detected Linux. Installing Microk8s via Snap..."
            sudo snap install microk8s --classic
            # Add user to group
            sudo usermod -a -G microk8s $USER
            mkdir -p ~/.kube
            sudo chown -f -R $USER ~/.kube
            # Reload group membership for current session (partial fix, user might need to relogin)
            newgrp microk8s << END
END
        else
            log "Microk8s already installed."
        fi
        ;;
    Darwin*)    
        if ! command -v microk8s &> /dev/null; then
            log "Detected Mac. Installing Microk8s via Brew..."
            brew install ubuntu/microk8s/microk8s
            microk8s install
        else
            log "Microk8s already installed."
        fi
        ;;
    *)          
        error "Unsupported OS: ${OS}"
        exit 1 
        ;;
esac

log "Waiting for Microk8s to be ready..."
microk8s status --wait-ready

log "Enabling Addons (DNS, Helm3)..."
microk8s enable dns helm3

# ==============================================================================
# 2. CLEANUP OLD ARGOCD
# ==============================================================================
log "Cleaning up old ArgoCD resources..."
pkill -f "kubectl port-forward.*svc/argocd-server" || true
lk delete ns argocd-system --ignore-not-found --wait=true

# ==============================================================================
# 3. INSTALL ARGOCD
# ==============================================================================
log "Creating ArgoCD Namespace..."
lk create ns argocd-system

log "Installing ArgoCD Manifest..."
lk apply -n argocd-system -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Waiting for ArgoCD server..."
lk wait --for=condition=available deployment/argocd-server -n argocd-system --timeout=300s

# Patch insecure
lk patch deployment argocd-server -n argocd-system --type json \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'

# Get Password
ARGO_PWD=$(lk -n argocd-system get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Port Forward
log "Starting ArgoCD Port Forward..."
screen -dmS argocd-pf bash -c 'while true; do microk8s kubectl port-forward svc/argocd-server -n argocd-system 8443:443; sleep 2; done'
sleep 5

success "Infrastructure Ready."
echo "ArgoCD: https://127.0.0.1:8443"
echo "User: admin"
echo "Pass: $ARGO_PWD"