# OpenObserve Stack on Microk8s

A modular bash-based automation suite to deploy a full High-Availability Observability stack on a local Microk8s cluster using GitOps principles (ArgoCD).


![Screenshot of OpenObserve](/images/openobserve.png)

## Components

* **Orchestration**: Microk8s, ArgoCD

* **Storage**: MinIO (S3-compatible), CloudNativePG (PostgreSQL), Etcd

* **Observability Backend**: OpenObserve (HA Mode)

* **Collection**: Cert Manager, OpenTelemetry Collector, Prometheus Operator (CRDs)

* **Demo App**: OpenTelemetry Astronomy Shop

## Prerequisites
* Ubuntu Linux or macOS (Intel/Apple Silicon)
* `jq` installed (`sudo apt install jq` or `brew install jq`)
* Internet connection for pulling Helm charts and Images

## Deployment Steps
Run the scripts in the following order:

#### 00-init.sh
* Prompts for configuration (passwords, org names).
* Generates `config.env`.

#### 01-install-infra.sh
* Installs/Checks Microk8s.
* Enables DNS/Helm.
* Installs ArgoCD and starts port-forwarding (https://localhost:8443)../

#### 02-openobserve_core.sh
* Deploys MinIO, Postgres (CNPG), and OpenObserve HA.
* Waits for health checks.

#### 03-openobserve_otel_coll.sh
* Installs Prometheus/OTel Operators.
* Deploys OpenObserve Collector.

####  04-openobserve_iam.sh
* Configures OpenObserve Organizations (`observability_team`, `observability_platform`) via API.

####  05-otel-testapp.sh
* Deploys the OTel Astronomy Demo sending traces to the Team org.

####  06-restart-screen-sessions.sh
* Print info & Restart Port-Forwards