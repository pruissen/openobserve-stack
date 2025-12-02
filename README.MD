# OpenObserve HA Stack on Microk8s (Terraform + ArgoCD)

A fully declarative, modular automation suite to deploy a High-Availability Observability stack on a local Microk8s cluster using Terraform and GitOps principles (ArgoCD).

![Screenshot of OpenObserve](images/openobserve.png)

## 🏗 Architecture

* **Orchestration**: Microk8s (Kubernetes), ArgoCD (GitOps Controller)
* **Storage**: MinIO (S3-compatible Object Storage), Etcd (Meta store), CloudNativePG (PostgreSQL - Optional)
* **Observability Backend**: OpenObserve (HA Mode v0.20.1)
* **Collection**: Cert Manager, OpenTelemetry Collector, Prometheus Operator (CRDs)
* **Infrastructure as Code**: Terraform + Helm

## 📋 Prerequisites

* **OS**: Ubuntu Linux or macOS (Intel/Apple Silicon)
* **Microk8s**: Installed and running (See setup below)
* **Tools**:
    * `terraform` (>= 1.0)
    * `kubectl`
    * `make` (Optional, for easy commands)

## 🚀 Quick Start

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

### 2. Deployment
We use a Makefile to simplify the Terraform workflow.

```bash
# Initialize Terraform and download providers
make init

# Plan, Apply, and Show Credentials (The "Do It All" command)
make up
```

**Note:** You can customize the root password by passing environment variables:

```bash
make up ZO_ROOT_PASSWORD="MySecretPassword!"
```

### 3. Accessing the UI
Terraform runs locally, so port-forwarding is handled via a helper command.

```bash
# Start background port-forwards for ArgoCD, OpenObserve, and MinIO
make port-forward
```

| Service | URL | User | Password |
| :--- | :--- | :--- | :--- |
| **ArgoCD** | `https://127.0.0.1:8443` | `admin` | Run `make info` |
| **OpenObserve** | `http://127.0.0.1:5080` | `admin@example.com` | Run `make info` |
| **MinIO Console** | `http://127.0.0.1:9001` | `minioadmin` | Run `make info` |

To see the passwords at any time:
```bash
make info
```

## 📂 Project Structure

* `main.tf`: Core logic. Installs namespaces, Secrets, ArgoCD, and the App-of-Apps (Manifests).
* `providers.tf`: Configuration for Kubernetes, Helm, and Kubectl providers.
* `iam.tf`: Configures OpenObserve Organizations via API after deployment.
* `variables.tf`: Default settings for user/pass/orgs.
* `Makefile`: Shortcut commands for the workflow.

## 🛠 Configuration Details

### OpenObserve v0.20.1
* **HA Mode**: Enabled (2 Replicas).
* **Meta Store**: Configured to use Etcd (bundled) to avoid conflicts with Postgres.
* **Storage**: Uses MinIO as the S3 backend.

### ArgoCD
* **Secure Mode**: HTTPS is enabled (self-signed).
* **Resource Tweak**: Tuned for local development (Low replicas, High Availability Redis disabled).
* **Namespace**: `argocd`.

## 🧹 Cleanup

To remove the entire stack:

```bash
make clean
```
*This runs `terraform destroy` and kills any background port-forwarding processes.*

## ⚠️ Troubleshooting

**Terraform Lock Error?**
If `terraform init` fails due to lock file changes across OS versions:
```bash
rm .terraform.lock.hcl
terraform init -upgrade
```

**Port Forward Fails?**
Ensure no other process is using ports 8443, 5080, or 9001.
```bash
pkill -f "kubectl port-forward"
make port-forward
```