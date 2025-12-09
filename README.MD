# OpenObserve HA Stack KubeCon 2026

![Screenshot of OpenObserve](images/openobserve.png)

> **⚠️ DISCLAIMER: WORK IN PROGRESS (Target: KubeCon 2026)**
> This is a Pre-Alpha Proof of Concept. Security settings are relaxed for local demonstration. API contracts are subject to change.

## 🎯 Introduction & Goal

Most local observability stacks are "toys"—single containers that bear no resemblance to production.

**The Goal:** Prove that you can run a **High-Availability, Multi-Tenant Observability stack** on a laptop using the exact same toolchain used in enterprise clusters.

This demo uses **Terraform** to bootstrap **ArgoCD**, which then manages complex stateful workloads (PostgreSQL/MinIO Operators) and **OpenObserve HA**, while a custom **Python** layer automates multi-tenant onboarding.

## 🏗 Tech Stack
* **Orchestration:** Microk8s & ArgoCD (GitOps)
* **Backing Services:** MinIO (S3) & CloudNativePG (PostgreSQL)
* **Observability:** OpenObserve (HA Mode)
* **Automation:** Terraform & Python (`o2_manager.py`)

## ⚡ Quick Start

### 1. Prerequisites
* **OS**: Linux or macOS (Intel/Apple Silicon)
    * **Tested on:** Ubuntu 24.04.3 LTS
* **Microk8s** (Running with `dns`, `helm3`, `storage` enabled)
* **Terraform** (>= 1.0) & **Python 3**
* **Make**

### 2. Cluster Prep
Export your Microk8s config so Terraform can access the cluster.

```bash
make install-microk8s
```
*(Or manually: `microk8s config | cat > ~/.kube/config`)*

### 3. Deploy Core Infrastructure
Initialize Terraform and deploy the core services (ArgoCD, MinIO, DB, OpenObserve).

```bash
make init
make apply
```

### 4. Connect & Bootstrap
Establish local port-forwards and use the Python automation to create Organizations, Service Accounts, and Roles.

```bash
# 1. Open tunnels to the cluster
make start

# 2. Bootstrap Tenants (creates orgs, users, roles)
python3 o2_manager.py bootstrap
```

### 5. Access Credentials
Retrieve generated passwords for ArgoCD, MinIO, and OpenObserve.

```bash
make info
```

### 6. Deploy Collectors
Now that tenants exist, deploy the OpenTelemetry Collectors.

```bash
make apply-collectors
```

---

## 🧠 Automation Reference: `o2_manager.py`

This Python script automates the "Day 2" operations that Terraform cannot easily handle (dynamic API tokens, internal O2 logic).

### Created Resources (Bootstrap Mode)

Running `python3 o2_manager.py bootstrap` creates the following multi-tenant structure:

| Resource Type | Created Items | Details |
| :--- | :--- | :--- |
| **Organizations** | `platform_observability`<br>`platform_kubernetes`<br>`team1`<br>`team2` | Isolated tenants for different teams. |
| **Streams** | `{org}_short_term` (24h)<br>`{org}_default` (10d)<br>`{org}_long_term` (35d) | Log retention policies prefixed with the Org name. |
| **Custom Roles** | `tenant-role` | A restrictive role allowing Read-Only access to streams and dashboards (assigned to users). |
| **Service Accounts** | `sa-gitops` | Used by OTel Collectors for ingestion.<br>**Email:** `sa-gitops-{org}@example.com` |
| **Users** | `user1-{org}@example.com`<br>`user2-{org}@example.com`<br>`user3-{org}@example.com` | Sample team members assigned the `tenant-role`. |

### Commands

| Command | Description |
| :--- | :--- |
| `bootstrap` | Creates all the resources listed above. |
| `show-all` | Displays a JSON overview of all Orgs, Users, Roles, and Service Accounts. |
| `cleanup-all` | **Destructive**: Purges all Streams, Users, and Roles from all Organizations (keeps the Org shell). |
| `apply <org>` | Applies configuration to a single specific Organization. |

## 📂 Structure
* `main.tf`: Core Infrastructure (Argo/O2/MinIO)
* `collectors/`: OTel Collector configurations (Split Architecture: Standalone Operator + Standalone Collector)
* `o2_manager.py`: Multi-tenant API automation
* `manage-local-connection.sh`: Connectivity helper

## 📄 License
Licensed under the Apache License, Version 2.0.