# OpenObserve HA Stack on Microk8s (Terraform + ArgoCD)

A fully declarative, modular automation suite to deploy a High-Availability Observability stack on a local Microk8s cluster using Terraform and GitOps principles (ArgoCD).

![Screenshot of OpenObserve](images/openobserve.png)

## 🏗 Architecture

* **Orchestration**: Microk8s (Kubernetes), ArgoCD (GitOps Controller)
* **Storage**: 
    * **Object Store**: MinIO (S3-compatible)
    * **Metadata Store**: PostgreSQL (via CloudNativePG Operator)
* **Observability Backend**: OpenObserve (HA Mode v0.20.1 - Enterprise Ready)
* **Collection**: Cert Manager, OpenTelemetry Collector, Prometheus Operator (CRDs)
* **Infrastructure as Code**: Terraform + Helm

## 📋 Prerequisites

* **OS**: Ubuntu Linux or macOS (Intel/Apple Silicon)
* **Microk8s**: Installed and running (See setup below)
* **Tools**:
    * `terraform` (>= 1.0)
    * `kubectl`
    * `make` (Required for workflow management)

## 🚀 Quick Start Guide

### 1. Prepare Microk8s
Ensure your cluster is running and the config is exported where Terraform can find it.

```bash
# Wait for cluster
microk8s status --wait-ready

# Enable required addons
microk8s enable dns helm3 storage

# Export config for Terraform
mkdir -p ~/.kube
microk8s config > ~/.kube/config
chmod 600 ~/.kube/config
```

### 2. Deploy Core Infrastructure
This installs ArgoCD, MinIO, CloudNativePG, and OpenObserve.

```bash
# Initialize
make init

# Plan (Preview changes)
make plan

# Apply (Deploy)
make apply
```

### 3. Access & Configuration (Manual Step)
Terraform runs locally, so we use a script to manage port-forwards.

**A. Start Access:**
```bash
make start
```

**B. Get Credentials:**
```bash
make info
```

| Service | URL | User | Password |
| :--- | :--- | :--- | :--- |
| **ArgoCD** | `https://127.0.0.1:8443` | `admin` | Run `make info` |
| **OpenObserve** | `http://127.0.0.1:5080` | `admin@example.com` | Run `make info` |
| **MinIO Console** | `http://127.0.0.1:9001` | `minioadmin` | Run `make info` |

**C. Create Organization (IMPORTANT):**
1. Open `http://127.0.0.1:5080` in your browser.
2. Login with the credentials from `make info`.
3. Go to **Settings** -> **Organizations**.
4. Create a new organization named **`observability_team`**.
   *(This is required before the Collectors can push data).*

### 4. Deploy Collectors
Once the Core is running and the Organization exists, deploy the OpenTelemetry Collectors.

```bash
# Plan Collectors
make plan-collectors

# Apply Collectors
make apply-collectors
```

## 📂 Project Structure

```text
.
├── main.tf              # Core Infra (Argo, MinIO, OpenObserve, Postgres, CertManager)
├── variables.tf         # Core Configuration
├── providers.tf         # Terraform Providers
├── Makefile             # Workflow Automation
├── manage.sh            # Port-forwarding & Credential extraction script
└── collectors/          # Sub-module for Agents
    ├── main.tf          # OTel Operator & Collector Deployments
    └── providers.tf     # Collector Providers
```

## 🛠 Configuration Details

### OpenObserve v0.20.1
* **HA Mode**: Enabled (2 Replicas).
* **Meta Store**: **PostgreSQL** (Managed by CloudNativePG Operator).
* **Storage**: MinIO (S3).

### CloudNativePG
* **Version**: v1.22.1
* **Deployment**: Installed via raw manifest from the official repository to support the Operator lifecycle.

### ArgoCD
* **Version**: v9.1.5
* **Mode**: Secure (HTTPS enabled).

## 🧹 Cleanup

To remove the entire stack (Collectors + Core):

```bash
make clean
```
*This stops port-forwards and destroys all Terraform resources in the correct order.*