![Banner](./docs/images/banner.png)

> **🚀 Ready to deploy?** Skip to the [Deployment](#-deployment) section to start deploying the infrastructure with Terraform.

---

## Table of Contents

- [Getting Started](#getting-started)
- [Lab Introduction & Goals](#lab-introduction--goals)
- [Architecture Overview](#architecture-overview)
- [Observability Stack](#observability-stack---deep-dive)
  - [CloudWatch Container Insights](#cloudwatch-container-insights)
  - [Application Signals (APM)](#cloudwatch-application-signals-apm)
  - [Amazon Managed Prometheus](#amazon-managed-prometheus-amp)
  - [Amazon Managed Grafana (Optional)](#amazon-managed-grafana)
- [🚀 Deployment](#-deployment)
  - [Prerequisites](#prerequisites)
  - [Terraform Deployment Options](#terraform-deployment-options)
  - [Deploy the Full EKS Version](#deploy-the-full-eks-version)
  - [Configure kubectl Access](#configure-kubectl-access)
- [Application Access](#application-access-ui-service)
- [AWS DevOps Agent Integration](#aws-devops-agent-integration)
  - [Create an Agent Space](#create-an-agent-space)
  - [Configure EKS Access](#configure-eks-access-for-devops-agent-required)
  - [View Topology Graph](#view-topology-graph)
  - [Start an Investigation](#start-an-investigation)
- [Fault Injection Scenarios](#fault-injection-scenarios)
  - [Catalog Service Latency](#1-catalog-service-latency-injection)
  - [RDS Database Stress Test](#2-rds-database-stress-test)
  - [Network Partition (UI → Cart)](#3-network-partition-ui--cart)
  - [RDS Security Group Block](#4-rds-security-group-misconfiguration)
  - [Cart Memory Leak](#5-cart-memory-leak)
  - [DynamoDB Latency](#6-dynamodb-latency)
- [Cleanup](#cleanup)

---

## Getting Started

### Install Git

If you don't have Git installed, install it first:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install git

# Linux (RHEL/CentOS/Amazon Linux)
sudo yum install git

# macOS (using Homebrew)
brew install git

# Verify installation
git --version
```

### Clone the Repository

```bash
# Clone the repository
git clone https://github.com/aws-samples/AmazonEKS-Devops-agent-sample.git

# Navigate to the project directory
cd AmazonEKS-Devops-agent-sample
```

> **🔧 Troubleshooting Git Clone Issues?** If you're encountering issues with `git clone`, you can download the repository as a ZIP file instead:
> 1. Navigate to the repository in your browser: https://github.com/aws-samples/AmazonEKS-Devops-agent-sample
> 2. Click the **Code** button → **Download ZIP**
> 3. Extract the ZIP file to your desired location:
>    ```bash
>    unzip AmazonEKS-Devops-agent-sample-main.zip
>    cd AmazonEKS-Devops-agent-sample-main
>    ```

---

## Lab Introduction & Goals

This hands-on lab demonstrates how to deploy, operate, and troubleshoot a production-grade microservices application on Amazon EKS using the AWS DevOps Agent. You'll gain practical experience with real-world scenarios including fault injection, observability, and automated incident investigation.

### What You'll Learn

1. **Deploy the Full EKS Version of the Retail Sample App** - Deploy a complete microservices architecture to Amazon EKS using Terraform, including all backend dependencies and observability tooling.

2. **Understand the Microservices Architecture** - Explore how the five core microservices (UI, Catalog, Carts, Orders, Checkout) interact with each other and their backend dependencies.

3. **Work with AWS Managed Backend Services** - Configure and operate production-grade AWS services that power the application.

4. **Experience Observability in Action** - Use CloudWatch Container Insights, Application Signals, Amazon Managed Prometheus, and Amazon Managed Grafana to monitor application health and performance.

5. **Leverage the AWS DevOps Agent** - See how the DevOps Agent automatically detects, investigates, and helps resolve infrastructure and application issues.

### Architecture Overview

The Retail Store Sample App is a deliberately over-engineered e-commerce application designed to demonstrate microservices patterns and AWS service integrations:

![Architecture](./docs/images/architecture.png)

> **Note:** The UI service uses a ClusterIP service type (not a public ALB). To access the application, use `kubectl port-forward svc/ui 8080:80 -n ui` and open http://localhost:8080 in your browser. This approach is intentional for lab/demo environments to avoid exposing the application publicly.

### Microservice Components

| Component                  | Language | Container Image                                                             | Helm Chart                                                                        | Description                             |
| -------------------------- | -------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------- |
| [UI](./src/ui/)            | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui)       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui-chart)       | Store user interface                    |
| [Catalog](./src/catalog/)  | Go       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog)  | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog-chart)  | Product catalog API                     |
| [Cart](./src/cart/)        | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart)     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart-chart)     | User shopping carts API                 |
| [Orders](./src/orders)     | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders)   | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders-chart)   | User orders API                         |
| [Checkout](./src/checkout) | Node     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout) | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout-chart) | API to orchestrate the checkout process |

### Service Communication

The services communicate using synchronous HTTP REST calls within the Kubernetes cluster:

| Source | Target | Protocol | Endpoint | Purpose |
|--------|--------|----------|----------|---------|
| UI | Catalog | HTTP | `http://catalog.catalog.svc:80` | Fetch product listings and details |
| UI | Carts | HTTP | `http://carts.carts.svc:80` | Manage shopping cart operations |
| UI | Orders | HTTP | `http://orders.orders.svc:80` | View order history and status |
| UI | Checkout | HTTP | `http://checkout.checkout.svc:80` | Initiate checkout process |
| Checkout | Orders | HTTP | `http://orders.orders.svc:80` | Create new orders |

### Infrastructure Components

The Terraform modules in this repository provision the following AWS resources:

**Compute & Orchestration:**
- **Amazon EKS** (v1.33) - Kubernetes cluster with EKS Auto Mode enabled
  - General-purpose and system node pools
  - Network Policy Controller enabled
  - All control plane logging (API, audit, authenticator, controller manager, scheduler)

**Networking:**
- **Amazon VPC** - Custom VPC with public/private subnets across 3 AZs
  - NAT Gateway for private subnet internet access
  - VPC Flow Logs with 30-day retention
  - Kubernetes-tagged subnets for ELB integration

**Databases:**
- **Amazon Aurora MySQL** (v8.0) - Catalog service database
  - db.t3.medium instance class
  - Storage encryption enabled
- **Amazon Aurora PostgreSQL** (v15.10) - Orders service database
  - db.t3.medium instance class
  - Storage encryption enabled
- **Amazon DynamoDB** - Carts service NoSQL database
  - Global secondary index on customerId
  - On-demand capacity mode

**Messaging & Caching:**
- **Amazon MQ (RabbitMQ)** (v3.13) - Message broker for Orders service
  - mq.t3.micro instance type
  - Single-instance deployment
- **Amazon ElastiCache (Redis)** - Session/cache store for Checkout service
  - cache.t3.micro instance type

**Observability Stack:**
- **Amazon CloudWatch Container Insights** - Enhanced container monitoring with Application Signals
- **Amazon Managed Service for Prometheus (AMP)** - Metrics collection and storage
  - EKS Managed Prometheus Scraper
  - Scrapes: API server, kubelet, cAdvisor, kube-state-metrics, node-exporter, application pods
- **Amazon Managed Grafana** - Visualization and dashboards
  - Prometheus, CloudWatch, and X-Ray data sources
- **AWS X-Ray** - Distributed tracing
- **Network Flow Monitoring Agent** - Container network observability

**EKS Add-ons:**
- metrics-server
- kube-state-metrics
- prometheus-node-exporter
- aws-efs-csi-driver
- aws-secrets-store-csi-driver-provider
- amazon-cloudwatch-observability (with Application Signals)
- aws-network-flow-monitoring-agent
- cert-manager

### Observability Stack - Deep Dive

The Retail Store Sample App includes a comprehensive observability stack that provides full visibility into application and infrastructure health. This section details the instrumentation, metrics collection, and visualization capabilities.

#### Application Instrumentation

Each microservice is instrumented for observability:

| Service | Language | Prometheus Metrics | OpenTelemetry Tracing | Application Signals |
|---------|----------|-------------------|----------------------|---------------------|
| UI | Java | ✅ `/actuator/prometheus` | ✅ OTLP | ✅ Auto-instrumented |
| Catalog | Go | ✅ `/metrics` | ✅ OTLP | ❌ (Go not supported) |
| Carts | Java | ✅ `/actuator/prometheus` | ✅ OTLP | ✅ Auto-instrumented |
| Orders | Java | ✅ `/actuator/prometheus` | ✅ OTLP | ✅ Auto-instrumented |
| Checkout | Node.js | ✅ `/metrics` | ✅ OTLP | ✅ Auto-instrumented |

**Application Signals Auto-Instrumentation:**
Java and Node.js services are automatically instrumented via pod annotations:
```yaml
# Java services (UI, Carts, Orders)
instrumentation.opentelemetry.io/inject-java: "true"

# Node.js services (Checkout)
instrumentation.opentelemetry.io/inject-nodejs: "true"
```

> **Note:** The Catalog service (Go) does not support Application Signals auto-instrumentation. It uses manual OpenTelemetry SDK instrumentation.

#### CloudWatch Container Insights

Container Insights provides enhanced observability for EKS clusters with the following capabilities:

**Metrics Collected:**
- Container CPU/memory utilization and limits
- Pod network I/O (bytes received/transmitted)
- Container restart counts
- Cluster, node, and pod-level aggregations

**Application Signals Features:**
- Automatic service map generation
- Request latency percentiles (p50, p95, p99)
- Error rates and HTTP status code distribution
- Service dependency visualization
- SLO monitoring and alerting

#### CloudWatch Application Signals (APM)

Application Signals provides Application Performance Monitoring (APM) capabilities for your microservices. Four of the five services are auto-instrumented:

| Service | Language | Auto-Instrumented | APM Features |
|---------|----------|-------------------|--------------|
| UI | Java | ✅ Yes | Traces, metrics, service map |
| Carts | Java | ✅ Yes | Traces, metrics, service map |
| Orders | Java | ✅ Yes | Traces, metrics, service map |
| Checkout | Node.js | ✅ Yes | Traces, metrics, service map |
| Catalog | Go | ❌ No | Manual OTEL instrumentation only |

**Accessing Application Signals Console:**

1. Open the [CloudWatch Console](https://console.aws.amazon.com/cloudwatch)
2. In the left navigation, click **Application Signals** → **Services**
3. You will see the 4 instrumented services listed:
   - `ui` (Java)
   - `carts` (Java)
   - `orders` (Java)
   - `checkout` (Node.js)

**Key APM Features in Application Signals:**

- **Service Map**: Visual representation of service dependencies and traffic flow
  - Navigate to **Application Signals** → **Service Map**
  - See real-time connections between UI → Catalog, UI → Carts, Checkout → Orders, etc.

- **Service Details**: Click on any service to view:
  - Request rate (requests/second)
  - Latency percentiles (p50, p95, p99)
  - Error rate and fault rate
  - Top operations and endpoints

- **Traces**: Distributed tracing across services
  - Navigate to **Application Signals** → **Traces**
  - Filter by service, operation, or latency
  - View end-to-end request flow across microservices

- **SLO Monitoring**: Set Service Level Objectives
  - Define availability and latency targets
  - Get alerts when SLOs are breached

> **Note:** The Catalog service (Go) does not appear in Application Signals because Go auto-instrumentation is not supported. However, it still sends traces via manual OpenTelemetry SDK instrumentation visible in X-Ray.

**Container Logs Collection:**

Container logs from all pods are automatically collected by Fluent Bit and sent to CloudWatch Logs. The logs are organized into the following log groups:

| Log Group | Description |
|-----------|-------------|
| `/aws/containerinsights/retail-store/application` | Application container logs (stdout/stderr) from all pods |
| `/aws/containerinsights/retail-store/dataplane` | Kubernetes dataplane component logs |
| `/aws/containerinsights/retail-store/host` | Node-level host logs |
| `/aws/containerinsights/retail-store/performance` | Performance metrics in log format |

**Viewing Container Logs:**
```bash
# View recent logs for a specific service using CloudWatch Logs Insights
aws logs start-query \
  --log-group-name "/aws/containerinsights/retail-store/application" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter kubernetes.namespace_name = "catalog" | sort @timestamp desc | limit 50'

# Or use kubectl for real-time logs
kubectl logs -n catalog -l app.kubernetes.io/name=catalog --tail=100 -f
```

**Log Structure:**
Each log entry includes Kubernetes metadata for easy filtering:
- `kubernetes.pod_name` - Pod name
- `kubernetes.namespace_name` - Namespace
- `kubernetes.container_name` - Container name
- `kubernetes.host` - Node instance ID
- `log_processed` - Parsed JSON log content (if applicable)

**Access Container Insights:**
1. Open [CloudWatch Console](https://console.aws.amazon.com/cloudwatch)
2. Navigate to **Container Insights** → **Performance monitoring**
3. Select your EKS cluster from the dropdown
4. Explore metrics by: Cluster, Namespace, Service, Pod, or Container
5. For logs, navigate to **Logs** → **Log groups** → `/aws/containerinsights/retail-store/application`

#### Amazon Managed Prometheus (AMP)

AMP provides a fully managed Prometheus-compatible monitoring service.

**Metrics Scrape Configuration:**

The EKS Managed Prometheus Scraper collects metrics from multiple sources:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Prometheus Scraper                            │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ API Server   │  │ Kubelet      │  │ cAdvisor             │   │
│  │ /metrics     │  │ /metrics     │  │ /metrics/cadvisor    │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │kube-state-   │  │ node-        │  │ Application Pods     │   │
│  │metrics       │  │ exporter     │  │ (prometheus.io/      │   │
│  │              │  │              │  │  scrape: true)       │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │kube-scheduler│  │kube-         │                             │
│  │ /metrics     │  │controller-mgr│                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  AMP Workspace  │
                    │  (remote_write) │
                    └─────────────────┘
```

**Key Metrics Available:**

| Source | Metrics | Use Case |
|--------|---------|----------|
| kube-state-metrics | `kube_pod_status_phase`, `kube_deployment_status_replicas` | Kubernetes object states |
| node-exporter | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes` | Node hardware/OS metrics |
| cAdvisor | `container_cpu_usage_seconds_total`, `container_memory_usage_bytes` | Container resource usage |
| API Server | `apiserver_request_total`, `apiserver_request_duration_seconds` | Control plane performance |
| Application Pods | Custom application metrics | Business and application KPIs |

#### Amazon Managed Grafana

> **📌 Optional:** Amazon Managed Grafana is optional for this lab. The primary focus is on the AWS DevOps Agent, which automatically analyzes metrics from CloudWatch and Prometheus. Configure Grafana only if you want to manually review and visualize metrics through custom dashboards.

Grafana provides visualization and dashboarding for all collected metrics.

**Pre-configured Data Sources:**
- **Prometheus** - AMP workspace for Kubernetes and application metrics
- **CloudWatch** - AWS service metrics (RDS, DynamoDB, ElastiCache, etc.)
- **X-Ray** - Distributed traces and service maps

**Accessing Grafana:**
1. Get the Grafana workspace URL from Terraform output:
   ```bash
   terraform output grafana_workspace_endpoint
   ```
2. Sign in using AWS IAM Identity Center (SSO)
3. Navigate to **Dashboards** to view pre-built visualizations

**Configuring the Prometheus Data Source:**

The Prometheus data source must be manually configured in Grafana to query metrics from Amazon Managed Prometheus (AMP).

1. Get your AMP workspace endpoint:
   ```bash
   terraform output prometheus_workspace_endpoint
   ```
   
2. In Grafana, navigate to **Connections** → **Data sources** → **Add data source** → **Prometheus**

3. Configure the data source with these settings:
   - **Name:** `Amazon Managed Prometheus` (or your preferred name)
   - **URL:** Your AMP workspace endpoint (e.g., `https://aps-workspaces.us-east-1.amazonaws.com/workspaces/ws-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
   
   > **Note:** The Prometheus endpoint URL is unique to your deployment. Get it from the Terraform output above.

4. Under **Authentication**, enable **SigV4 auth**:
   - Toggle **SigV4 auth** to ON
   - **Default Region:** `us-east-1` (or your deployment region)
   - Leave **Assume Role ARN** empty (Grafana uses its workspace IAM role automatically)

5. Under **HTTP Method**, select **POST**

6. Click **Save & test** to verify the connection

> **Troubleshooting:** If you receive a `403 Forbidden` error, ensure SigV4 auth is enabled. Amazon Managed Grafana automatically uses its workspace IAM role for authentication - no manual credentials are needed.

**Recommended Dashboards to Import:**

**How to Import a Dashboard:**
1. In Grafana, click **Dashboards** in the left sidebar
2. Click **New** → **Import**
3. Enter the **Grafana ID** from the table below in the "Import via grafana.com" field
4. Click **Load**
5. Select your **Prometheus data source** (the one you configured above)
6. Click **Import**

The dashboard will be added to your Grafana instance and start displaying metrics immediately.

| Dashboard | Grafana ID | Description |
|-----------|------------|-------------|
| **Control Plane** | | |
| Kubernetes API Server | 15761 | API server request rates, latencies, and error rates |
| etcd | 3070 | etcd cluster health, leader elections, and disk I/O |
| Kubernetes Controller Manager | 12122 | Controller work queue depths and reconciliation metrics |
| Kubernetes Scheduler | 12123 | Scheduler latency, pending pods, and preemption metrics |
| **Kube State Metrics** | | |
| Kubernetes Cluster (via kube-state-metrics) | 13332 | Comprehensive cluster state overview |
| Kubernetes Deployment Statefulset Daemonset | 8588 | Workload replica status and rollout progress |
| Kubernetes Resource Requests vs Limits | 13770 | Resource allocation vs actual usage |
| Kubernetes Pod Status | 15759 | Pod phase distribution and container states |
| **Node Exporter** | | |
| Node Exporter Full | 1860 | Comprehensive node hardware and OS metrics |
| Node Exporter for Prometheus | 11074 | Simplified node metrics overview |
| Node Problem Detector | 15549 | Node conditions and kernel issues |
| **Network & Conntrack** | | |
| Kubernetes Networking | 12125 | Pod and service network traffic |
| Node Network and Conntrack | 14996 | Connection tracking table usage and network stats |
| CoreDNS | 14981 | DNS query rates, latencies, and cache hit ratios |
| **General Kubernetes** | | |
| Kubernetes Cluster Monitoring | 315 | Cluster-wide resource utilization |
| Kubernetes Pods | 6336 | Pod-level metrics and logs |
| Kubernetes Namespace Resources | 14678 | Per-namespace resource consumption |
| AWS RDS | 707 | RDS database performance |
| AWS DynamoDB | 12637 | DynamoDB table metrics |

#### Prometheus Node Exporter

Node Exporter exposes hardware and OS-level metrics from each Kubernetes node.

**Key Metrics:**
- `node_cpu_seconds_total` - CPU time spent in each mode
- `node_memory_MemTotal_bytes` - Total memory
- `node_memory_MemAvailable_bytes` - Available memory
- `node_filesystem_size_bytes` - Filesystem size
- `node_network_receive_bytes_total` - Network bytes received
- `node_load1`, `node_load5`, `node_load15` - System load averages

**Useful PromQL Queries:**
```promql
# CPU utilization percentage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory utilization percentage
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# Disk utilization percentage
100 - ((node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100)
```

#### Kube State Metrics

Kube State Metrics generates metrics about the state of Kubernetes objects.

**Key Metrics:**
- `kube_pod_status_phase` - Pod phase (Pending, Running, Succeeded, Failed, Unknown)
- `kube_pod_container_status_restarts_total` - Container restart count
- `kube_deployment_status_replicas_available` - Available replicas
- `kube_node_status_condition` - Node conditions (Ready, MemoryPressure, DiskPressure)
- `kube_horizontalpodautoscaler_status_current_replicas` - HPA current replicas

**Useful PromQL Queries:**
```promql
# Pods not in Running state
kube_pod_status_phase{phase!="Running",phase!="Succeeded"} == 1

# Deployments with unavailable replicas
kube_deployment_status_replicas_unavailable > 0

# Container restarts in last hour
increase(kube_pod_container_status_restarts_total[1h]) > 0
```

#### Network Flow Monitoring

The Network Flow Monitoring Agent provides container network observability.

**Capabilities:**
- Service-to-service traffic flow visualization
- Network latency between pods
- Packet loss detection
- TCP connection metrics
- Network policy effectiveness monitoring

**Access Network Flow Insights:**
1. Open [CloudWatch Console](https://console.aws.amazon.com/cloudwatch)
2. Navigate to **Network Monitoring** → **Network Flow Monitor**
3. View traffic flows between services in the retail store application

#### OpenTelemetry Instrumentation

OpenTelemetry provides distributed tracing across all microservices.

**Configuration:**
```yaml
# OTEL Instrumentation settings (from Terraform)
OTEL_SDK_DISABLED: "false"
OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf"
OTEL_RESOURCE_PROVIDERS_AWS_ENABLED: "true"
OTEL_METRICS_EXPORTER: "none"  # Metrics via Prometheus
OTEL_JAVA_GLOBAL_AUTOCONFIGURE_ENABLED: "true"
```

**Trace Propagation:**
- W3C Trace Context (`tracecontext`)
- W3C Baggage (`baggage`)

**Sampling:** Always-on sampling for complete trace visibility

#### Metrics Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EKS Cluster                                     │
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐   │
│  │ Application │    │ kube-state- │    │   node-     │    │  cAdvisor   │   │
│  │    Pods     │    │   metrics   │    │  exporter   │    │             │   │
│  │  /metrics   │    │  /metrics   │    │  /metrics   │    │  /metrics   │   │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘   │
│         │                  │                  │                  │          │
│         └──────────────────┴──────────────────┴──────────────────┘          │
│                                      │                                       │
│                           ┌──────────▼──────────┐                           │
│                           │  EKS Managed        │                           │
│                           │  Prometheus Scraper │                           │
│                           └──────────┬──────────┘                           │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
                            ┌──────────▼──────────┐
                            │  Amazon Managed     │
                            │  Prometheus (AMP)   │
                            └──────────┬──────────┘
                                       │
                            ┌──────────▼──────────┐
                            │  Amazon Managed     │
                            │  Grafana            │
                            └─────────────────────┘
```

#### Viewing Observability Data

**CloudWatch Container Insights:**
```bash
# Get cluster name
CLUSTER_NAME=$(terraform output -raw cluster_name)

# View in AWS Console
echo "https://console.aws.amazon.com/cloudwatch/home#container-insights:infrastructure"
```

**Amazon Managed Grafana:**
```bash
# Get Grafana endpoint
terraform output grafana_workspace_endpoint
```

**Prometheus Queries (via Grafana):**
```bash
# Get AMP workspace endpoint
terraform output prometheus_workspace_endpoint
```

### How Observability + DevOps Agent Work Together

The AWS DevOps Agent leverages the comprehensive observability stack to automatically investigate and diagnose issues:

1. **Resource Discovery** - All resources are tagged with `devopsagent = "true"`, enabling automatic discovery of related infrastructure components.

2. **Metrics Correlation** - The agent queries Amazon Managed Prometheus and CloudWatch to identify anomalies in:
   - Pod CPU/memory utilization
   - Request latency (p50, p95, p99)
   - Error rates and HTTP status codes
   - Database connection pools and query performance

3. **Log Analysis** - CloudWatch Logs from EKS control plane and application pods are analyzed for:
   - Error patterns and stack traces
   - Connection timeouts and failures
   - Resource exhaustion warnings

4. **Trace Investigation** - X-Ray traces help identify:
   - Slow service dependencies
   - Failed downstream calls
   - Latency bottlenecks in the request path

5. **Network Insights** - Network Flow Monitoring reveals:
   - Traffic patterns between services
   - Network policy violations
   - Connectivity issues

When you inject faults using the provided scripts, the DevOps Agent can automatically detect symptoms, correlate signals across the observability stack, and provide root cause analysis with remediation recommendations.

---

# 🚀 Deployment

---

## Prerequisites

Before deploying and running fault injection scenarios, install the following tools:

### 1. AWS CLI

```bash
# Linux (x86_64)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify installation
aws --version
```

Configure AWS credentials:
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and default region (us-east-1)
```

### 2. Terraform

```bash
# Linux/macOS using tfenv (recommended)
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
tfenv install 1.5.0
tfenv use 1.5.0

# Or direct installation (Linux)
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# macOS using Homebrew
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify installation
terraform --version
```

### 3. kubectl

```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS using Homebrew
brew install kubectl

# Verify installation
kubectl version --client
```

### 4. Helm (optional, for chart deployments)

```bash
# Linux/macOS
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# macOS using Homebrew
brew install helm

# Verify installation
helm version
```

### 5. AWS IAM Identity Center (SSO) for Amazon Managed Grafana

> **📌 Optional:** Amazon Managed Grafana is **disabled by default** in this deployment. Grafana requires AWS IAM Identity Center (SSO) to be configured, and if SSO is not set up, the Terraform deployment will fail. The AWS DevOps Agent does not require Grafana - it directly queries CloudWatch and Prometheus for automated analysis.

**To enable Grafana**, you must:
1. First configure AWS IAM Identity Center in your account
2. Set `enable_grafana = true` in your Terraform variables

**Setup Guide:** [Enable IAM Identity Center for Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/latest/userguide/authentication-in-AMG-SSO.html)

**Quick Steps to Enable Grafana:**
1. Open the [IAM Identity Center console](https://console.aws.amazon.com/singlesignon)
2. Click **Enable** if not already enabled
3. Create users or groups that will access Grafana
4. Deploy with Grafana enabled:
   ```bash
   terraform apply -var="enable_grafana=true"
   ```
5. After deployment, assign yourself as Grafana admin:
   - Go to [Amazon Managed Grafana console](https://console.aws.amazon.com/grafana)
   - Choose **All workspaces** from the left navigation
   - Select the `retail-store-grafana` workspace
   - Choose the **Authentication** tab
   - Choose **Configure users and user groups**
   - Select the checkbox next to your SSO user and choose **Assign user**
   - Select your user and choose **Make admin**
   
   For detailed instructions, see [Manage user and group access to Amazon Managed Grafana workspaces](https://docs.aws.amazon.com/grafana/latest/userguide/AMG-manage-users-and-groups-AMG.html)

### Terraform Deployment Options

The following options are available to deploy the application using Terraform:

| Name                                   | Description                                                                                                 |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [Amazon EKS (Full)](./terraform/eks/default/) | **Recommended for this lab.** Deploys the complete application to Amazon EKS with all AWS managed dependencies. |
| [Amazon EKS (Minimal)](./terraform/eks/minimal/) | Lightweight deployment with in-cluster dependencies only. |

### Deploy the Full EKS Version

> **Important:** For this lab, we are using the **full EKS version**. Make sure to run Terraform from the `terraform/eks/default` directory.

Navigate to the full EKS deployment directory:

```bash
cd terraform/eks/default
```

#### What Terraform Will Create

When you run `terraform apply`, the following resources will be provisioned:

**EKS Cluster & Compute:**
- Amazon EKS cluster (v1.33) with EKS Auto Mode enabled
- IAM roles for cluster and node management
- EKS managed add-ons (metrics-server, kube-state-metrics, prometheus-node-exporter, etc.)

**Networking:**
- New VPC with public and private subnets across 3 Availability Zones
- NAT Gateway for private subnet internet access
- VPC Flow Logs for network traffic analysis
- Security groups for all components

**Application Dependencies:**
- **Amazon DynamoDB** - Table for Carts service with GSI on customerId
- **Amazon Aurora MySQL** - Database for Catalog service
- **Amazon Aurora PostgreSQL** - Database for Orders service
- **Amazon MQ (RabbitMQ)** - Message broker for Orders service
- **Amazon ElastiCache (Redis)** - Cache for Checkout service
- **Application Load Balancer** - Managed by EKS Auto Mode for ingress

**Observability Stack:**
- Amazon CloudWatch Container Insights with Application Signals
- Amazon Managed Service for Prometheus (AMP) with EKS scraper
- Amazon Managed Grafana workspace (optional, requires `enable_grafana = true` and AWS SSO)
- AWS X-Ray integration
- Network Flow Monitoring Agent

**Retail Store Application:**
- All five microservices (UI, Catalog, Carts, Orders, Checkout) deployed to dedicated namespaces

#### Step-by-Step Deployment

```bash
# 1. Navigate to the full EKS deployment directory
cd terraform/eks/default

# 2. Initialize Terraform (downloads providers and modules)
terraform init

# 3. Review the execution plan
#    This shows all resources that will be created
terraform plan

# 4. Apply the configuration
#    Type 'yes' when prompted to confirm
#    This takes approximately 20-30 minutes
terraform apply

# 5. Note the outputs - you'll need these for kubectl configuration
#    Look for: cluster_name, region, and any endpoint URLs
terraform output
```

**Optional: Enable Amazon Managed Grafana**

> **⚠️ Important:** Grafana requires AWS IAM Identity Center (SSO) to be configured in your account. If SSO is not set up, Terraform will fail when `enable_grafana=true`. See [Prerequisites - AWS IAM Identity Center](#5-aws-iam-identity-center-sso-for-amazon-managed-grafana) for setup instructions.

```bash
# To deploy with Grafana enabled (requires AWS SSO):
terraform apply -var="enable_grafana=true"
```

#### Configure EKS Access Entry (Required Manual Step)

> **Important:** After the EKS cluster is created, you must manually add your IAM role to the cluster's access entries. Terraform does not configure this automatically.

**Steps to add your IAM role:**

1. Open the [Amazon EKS Console](https://console.aws.amazon.com/eks)
2. Select your cluster (default name: `retail-store`)
3. Navigate to **Access** tab → **IAM access entries**
4. Click **Create access entry**
5. Configure the access entry:
   - **IAM principal ARN:** Enter your IAM role ARN (e.g., your Isengard role ARN)
   - **Type:** Standard
6. Click **Next**
7. Add access policy:
   - **Policy name:** `AmazonEKSClusterAdminPolicy`
   - **Access scope:** Cluster
8. Click **Create**

**Alternative: Using AWS CLI**
```bash
# Get your current IAM identity
aws sts get-caller-identity

# Create access entry (replace YOUR_ROLE_ARN with your actual role ARN)
aws eks create-access-entry \
  --cluster-name retail-store \
  --principal-arn YOUR_ROLE_ARN \
  --type STANDARD

# Associate the admin policy
aws eks associate-access-policy \
  --cluster-name retail-store \
  --principal-arn YOUR_ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### Resource Tagging

All AWS resources created by this Terraform deployment are tagged with:

```
devopsagent = "true"
```

This tag enables the AWS DevOps Agent to automatically discover and monitor resources associated with this retail store application. The agent uses this tag to:
- Identify resources for automated investigation during incidents
- Correlate related resources across EKS, RDS, DynamoDB, and other AWS services
- Scope troubleshooting and root cause analysis to the correct infrastructure

### Configure kubectl Access

After the EKS cluster is deployed, configure kubectl to access it:

```bash
# Update kubeconfig (replace with your cluster name and region)
aws eks update-kubeconfig --name retail-store --region us-east-1

# Verify cluster access
kubectl get nodes

# Verify all pods are running
kubectl get pods -A
```

### Verify Application Deployment

```bash
# Check all retail store services are running
kubectl get pods -A | grep -E "carts|catalog|orders|checkout|ui"

# Get the UI service URL
kubectl get svc -n ui
```

## Application Access (UI Service)

> **Important:** The Retail Sample App UI is **not exposed publicly by default**. No public ALB or Ingress is created for the UI service. You must use `kubectl port-forward` to access the application from your local machine.

### Why Port-Forward?

For security and cost reasons, the default deployment does not create a public-facing load balancer for the UI. This is intentional for a lab/demo environment. In production, you would configure an Ingress resource with appropriate authentication.

### Access the Application from Your Laptop

**Step 1: Configure kubectl**

```bash
# Update your kubeconfig to connect to the EKS cluster
# Replace 'retail-store' and 'us-east-1' with your actual cluster name and region
aws eks update-kubeconfig --name retail-store --region us-east-1

# Verify you can connect to the cluster
kubectl get nodes
```

**Step 2: Verify the UI Service is Running**

```bash
# Check that UI pods are in Running state
kubectl get pods -n ui

# Expected output:
# NAME                  READY   STATUS    RESTARTS   AGE
# ui-xxxxxxxxxx-xxxxx   1/1     Running   0          10m

# Verify the service exists and has endpoints
kubectl get svc -n ui
kubectl get endpoints ui -n ui
```

**Step 3: Port-Forward to the UI Service**

```bash
# Forward local port 8080 to the UI service port 80
kubectl port-forward svc/ui 8080:80 -n ui
```

**Step 4: Open the Application**

Open your browser and navigate to: **http://localhost:8080**

You should see the Retail Store home page with product listings.

### Alternative: Port-Forward to a Specific Pod

If you need to connect to a specific UI pod (useful for debugging):

```bash
# Get the pod name
kubectl get pods -n ui -o name

# Port-forward to the specific pod
kubectl port-forward pod/ui-xxxxxxxxxx-xxxxx 8080:8080 -n ui
```

### Keeping the Connection Active

> **Note:** The `kubectl port-forward` command must remain running in your terminal. If you close the terminal or press Ctrl+C, the connection will be terminated.

**Tips for long-running sessions:**
```bash
# Run in background (output to file)
kubectl port-forward svc/ui 8080:80 -n ui > /tmp/port-forward.log 2>&1 &

# Or use a separate terminal/tmux session
tmux new-session -d -s port-forward 'kubectl port-forward svc/ui 8080:80 -n ui'
```

### Troubleshooting Port-Forward Issues

```bash
# Check if the UI pods are running
kubectl get pods -n ui

# Check if the service has endpoints (should show pod IPs)
kubectl get endpoints ui -n ui

# Check pod logs for errors
kubectl logs -n ui -l app.kubernetes.io/name=ui --tail=50

# Test connectivity from within the cluster
kubectl exec -n ui deploy/ui -- curl -s localhost:8080/actuator/health

# Try a different local port if 8080 is already in use
kubectl port-forward svc/ui 9090:80 -n ui

# Use verbose mode for debugging connection issues
kubectl port-forward svc/ui 8080:80 -n ui -v=6

# Check for network policies that might block traffic
kubectl get networkpolicies -n ui
```

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| `error: unable to forward port` | Pod not ready | Wait for pod to be in Running state |
| `bind: address already in use` | Port 8080 in use | Use a different local port (e.g., 9090) |
| `connection refused` | Service has no endpoints | Check pod status and logs |
| `timeout` | Network/firewall issue | Check VPN, firewall, or security groups |
| `unauthorized` | kubectl not configured | Run `aws eks update-kubeconfig` again |

## AWS DevOps Agent Integration

AWS DevOps Agent is a frontier AI agent that helps accelerate incident response and improve system reliability. It automatically correlates data across your operational toolchain, identifies probable root causes, and recommends targeted mitigations. This section provides step-by-step guidance for integrating the DevOps Agent with your EKS-based Retail Store deployment.

> **Note:** AWS DevOps Agent is currently in **public preview** and available in the **US East (N. Virginia) Region** (`us-east-1`). While the agent runs in `us-east-1`, it can monitor applications deployed in any AWS Region.

### Create an Agent Space

An **Agent Space** defines the scope of what AWS DevOps Agent can access as it performs tasks. Think of it as a logical boundary that groups related resources, applications, and infrastructure for investigation purposes.

#### Organizing Your Agent Space

You can organize Agent Spaces based on your operational model:
- **Per Application** - One Agent Space per application (recommended for this lab)
- **Per Team** - One Agent Space per on-call team managing multiple services
- **Centralized** - Single Agent Space for the entire organization

For this lab, we'll create an Agent Space specifically for the Retail Store application.

#### Step-by-Step: Create an Agent Space

1. **Navigate to AWS DevOps Agent Console**
   ```
   https://console.aws.amazon.com/devops-agent/home?region=us-east-1
   ```

2. **Create the Agent Space**
   - Click **Create Agent Space**
   - Enter a name: `retail-store-lab` (or your preferred name)
   - Optionally add a description: "Agent Space for AWS Retail Store Sample Application on EKS"

3. **Configure IAM Roles**
   
   The console will guide you to create the required IAM roles. AWS DevOps Agent needs permissions to:
   - Introspect AWS resources in your account(s)
   - Access CloudWatch metrics and logs
   - Query X-Ray traces
   - Read EKS cluster information
   
   The agent creates two IAM roles:
   - **AgentSpace Execution Role** - Used by the agent to perform investigations
   - **Cross-Account Role** (optional) - For monitoring resources in other AWS accounts

4. **Enable the Web App**
   - Check the option to **Enable AWS DevOps Agent web app**
   - This provides a web interface for operators to trigger and monitor investigations

5. **Click Create**
   - Wait for the Agent Space to be created (typically 1-2 minutes)

#### Required IAM Permissions

The IAM role created for the Agent Space requires the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:DescribeAlarms",
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "xray:GetTraceSummaries",
        "xray:BatchGetTraces",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters",
        "dynamodb:DescribeTable",
        "dynamodb:ListTables",
        "elasticache:DescribeCacheClusters",
        "mq:DescribeBroker"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Note:** The console automatically creates and attaches the appropriate policies. The above is for reference.

#### Mandatory Resource Tags

All AWS resources in this lab are tagged with:

```
devopsagent = "true"
```

This tag is **critical** for the DevOps Agent to:
- Automatically discover resources associated with the Retail Store application
- Correlate related resources during investigations
- Scope troubleshooting to the correct infrastructure

The Terraform deployment automatically applies this tag to all resources. If you create additional resources manually, ensure you add this tag.

#### EKS Cluster Discovery

AWS DevOps Agent automatically discovers your EKS cluster through the IAM roles configured during Agent Space creation. However, to access Kubernetes resources (pods, events, deployments), you must grant the DevOps Agent's IAM role access to the EKS cluster.

#### Configure EKS Access for DevOps Agent (Required)

> **⚠️ Important:** Without this step, the DevOps Agent will receive `401 Unauthorized` errors when trying to access Kubernetes events, pod status, and other cluster resources.

The DevOps Agent needs an EKS Access Entry to query the Kubernetes API. Follow these steps:

**Step 1: Get the DevOps Agent IAM Role ARN**

1. Open the [AWS DevOps Agent Console](https://console.aws.amazon.com/devops-agent/home?region=us-east-1)
2. Select your Agent Space
3. Navigate to **Capabilities** → **Cloud** → **Primary Source** → **Edit**
4. The IAM Role ARN used by the Agent Space is displayed in the configuration
5. Copy the role ARN (e.g., `arn:aws:iam::123456789012:role/DevOpsAgentRole-xxxxx`)

**Step 2: Add the Role to EKS Access Entries**

**Option A: Using AWS Console**

1. Open the [Amazon EKS Console](https://console.aws.amazon.com/eks)
2. Select your cluster: `retail-store`
3. Navigate to **Access** tab → **IAM access entries**
4. Click **Create access entry**
5. Configure:
   - **IAM principal ARN:** Paste the DevOps Agent Execution Role ARN
   - **Type:** Standard
6. Click **Next**
7. Add access policy:
   - **Policy name:** `AmazonEKSClusterAdminPolicy`
   - **Access scope:** Cluster
8. Click **Create**

**Option B: Using AWS CLI**

```bash
# Set your DevOps Agent's IAM role ARN
DEVOPS_AGENT_ROLE_ARN="arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_DEVOPS_AGENT_ROLE"

# Create the access entry
aws eks create-access-entry \
  --cluster-name retail-store \
  --principal-arn $DEVOPS_AGENT_ROLE_ARN \
  --type STANDARD

# Associate the cluster admin policy
aws eks associate-access-policy \
  --cluster-name retail-store \
  --principal-arn $DEVOPS_AGENT_ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

Once configured, the DevOps Agent will be able to:

1. **Automatically discover** your EKS cluster (`retail-store`) through the Topology view
2. **Correlate EKS resources** including:
   - Namespaces and deployments
   - Pod status and events
   - Service configurations
   - Resource utilization metrics
3. **Build relationships** between your EKS workloads and backend services (RDS, DynamoDB, ElastiCache, etc.)

To verify discovery, navigate to the **Topology** tab in your Agent Space. The topology shows key resources and relationships the agent has identified. As the agent completes more investigations, it will discover and add new resources to this view.

> **Note:** All resources in this lab are tagged with `devopsagent = "true"`, which helps the agent identify and correlate related infrastructure components.

> **📚 Documentation:** 
> - [Creating an Agent Space](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-creating-an-agent-space.html)
> - [EKS Access Setup for DevOps Agent](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-capabilities-for-aws-devops-agent-aws-eks-access-setup.html)

> **💡 Troubleshooting:** If you still encounter permission issues after configuring the EKS access entry, attach the `AmazonEKSClusterPolicy` managed policy to the DevOps Agent Execution Role in IAM to grant full EKS access.

### View Topology Graph

The **Topology** view provides a visual map of your system components and their relationships. AWS DevOps Agent automatically builds this topology by analyzing your infrastructure.

#### Accessing the Topology View

1. Open your Agent Space in the AWS Console
2. Click the **Topology** tab
3. View the automatically discovered resources and relationships

#### What the Topology Shows

The topology graph displays:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DevOps Agent Topology View                            │
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                    │
│  │   EKS       │────▶│   Aurora    │     │  DynamoDB   │                    │
│  │  Cluster    │     │   MySQL     │     │   Table     │                    │
│  └──────┬──────┘     └─────────────┘     └─────────────┘                    │
│         │                                                                    │
│  ┌──────▼──────┐     ┌─────────────┐     ┌─────────────┐                    │
│  │ Deployments │────▶│   Aurora    │     │ ElastiCache │                    │
│  │ (5 services)│     │ PostgreSQL  │     │   Redis     │                    │
│  └─────────────┘     └─────────────┘     └─────────────┘                    │
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐                                        │
│  │  CloudWatch │     │  Amazon MQ  │                                        │
│  │   Alarms    │     │  RabbitMQ   │                                        │
│  └─────────────┘     └─────────────┘                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Understanding Relationships

The DevOps Agent automatically detects:

| Relationship Type | Example | How Detected |
|-------------------|---------|--------------|
| Service Dependencies | UI → Catalog | Network traffic analysis, service mesh |
| Database Connections | Orders → Aurora PostgreSQL | Security group rules, connection strings |
| Message Queue Links | Orders → RabbitMQ | Environment variables, connection configs |
| Cache Dependencies | Checkout → Redis | Pod configurations, endpoint references |

#### Topology Discovery Process

1. **Initial Scan** - When you create the Agent Space, it scans for tagged resources
2. **Continuous Learning** - As investigations complete, new resources are discovered
3. **Relationship Mapping** - The agent analyzes:
   - Security group rules
   - IAM policies and roles
   - Kubernetes service configurations
   - Network flow logs
   - Application traces (X-Ray)

#### Filtering the Topology

Use filters to focus on specific areas:
- **By Service** - Show only resources related to a specific microservice
- **By Resource Type** - Filter by EKS, RDS, DynamoDB, etc.
- **By Health Status** - Highlight unhealthy or degraded resources

### Operator Access

Operator access allows your on-call engineers and DevOps team to interact with the AWS DevOps Agent through a dedicated web application.

#### Enabling Operator Access

1. **From the Agent Space Console**
   - Navigate to your Agent Space
   - Click **Operator access** in the left navigation
   - Click **Enable operator access** if not already enabled

2. **Access Methods**

   **Option A: Direct Console Access**
   - Click the **Operator access** link in your Agent Space
   - This opens the DevOps Agent web app directly
   - Requires AWS Console authentication

   **Option B: AWS IAM Identity Center (Recommended for Teams)**
   - Configure IAM Identity Center for your organization
   - Create a permission set for DevOps Agent access
   - Assign users/groups to the permission set
   - Users can access via the Identity Center portal

#### How the Agent Interacts with EKS

The DevOps Agent interacts with your EKS cluster through:

1. **Read-Only Kubernetes API Access**
   - Lists pods, deployments, services, events
   - Reads pod logs for error analysis
   - Checks resource utilization metrics

2. **CloudWatch Container Insights**
   - Queries container metrics (CPU, memory, network)
   - Analyzes Application Signals data
   - Reviews performance anomalies

3. **AWS API Calls**
   - Describes EKS cluster configuration
   - Checks node group status
   - Reviews security group rules

#### Safety Mechanisms

AWS DevOps Agent includes several safety mechanisms:

| Mechanism | Description |
|-----------|-------------|
| **Read-Only by Default** | The agent only reads data; it does not modify resources |
| **Scoped Access** | Access is limited to resources within the Agent Space |
| **Audit Logging** | All agent actions are logged to CloudTrail |
| **Investigation Boundaries** | Investigations are scoped to specific incidents |
| **Human-in-the-Loop** | Mitigation recommendations require human approval |

#### Approval Workflows

When the DevOps Agent identifies a mitigation:

1. **Recommendation Generated** - Agent proposes a fix (e.g., "Scale up deployment")
2. **Human Review** - Operator reviews the recommendation in the web app
3. **Approval Required** - Operator must explicitly approve any changes
4. **Implementation Guidance** - Agent provides detailed specs for implementation

> **Important:** The DevOps Agent does **not** automatically make changes to your infrastructure. All mitigations are recommendations that require human approval and manual implementation.

#### Starting an Investigation

From the Operator Web App:

1. Click **Start Investigation**
2. Choose a starting point:
   - **Latest alarm** - Investigate the most recent CloudWatch alarm
   - **High CPU usage** - Analyze CPU utilization across resources
   - **Error rate spike** - Investigate application error increases
   - **Custom** - Describe the issue in your own words

3. Provide investigation details:
   - **Investigation details** - Describe what you're investigating
   - **Date and time** - When the incident occurred
   - **AWS Account ID** - The account containing the affected resources

4. Click **Start** and watch the investigation unfold in real-time

#### Investigation Prompts for Fault Injection Scenarios

After injecting a fault using the scripts in the [Fault Injection Scenarios](#fault-injection-scenarios) section, use these prompts to start a DevOps Agent investigation:

| Scenario | Investigation Details | Investigation Starting Point |
|----------|----------------------|------------------------------|
| [Catalog Latency](#1-catalog-service-latency-injection) | "Product pages are loading slow. Users are complaining about the catalog taking forever to load." | "Check the catalog service pods in the catalog namespace. Look at latency metrics and CPU usage." |
| [RDS Stress Test](#2-rds-database-stress-test) | "Checkout is failing for customers. Orders aren't going through and we're seeing timeouts." | "Check the orders service and the RDS PostgreSQL database. Look at Performance Insights for slow queries." |
| [Network Partition](#3-network-partition-ui--cart) | "Users can browse products fine but Add to Cart is broken. Getting timeout errors." | "Check connectivity between the UI service and the carts service. Look for network policies or blocked traffic." |
| [RDS Security Group Block](#4-rds-security-group-misconfiguration) | "Orders and checkout are completely down. Getting 500 errors. RDS shows healthy but apps can't connect." | "Check the RDS security groups and VPC flow logs. The database is up but something is blocking connections." |
| [Cart Memory Leak](#5-cart-memory-leak) | "Cart service pods keep restarting every few minutes. Users are seeing intermittent failures." | "Check the carts namespace for pod restarts and OOMKilled events. Look at memory usage patterns." |
| [DynamoDB Latency](#6-dynamodb-latency) | "Adding items to cart is super slow. Used to be instant but now takes 3-5 seconds." | "Check DynamoDB metrics for the carts table. Look at latency and any throttling." |

**Investigation Flow:**

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  1. Inject Fault    │────▶│  2. Observe Symptoms│────▶│  3. Start           │
│  (run inject script)│     │  (monitoring tools) │     │  Investigation      │
└─────────────────────┘     └─────────────────────┘     └──────────┬──────────┘
                                                                   │
                                                                   ▼
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  6. Rollback Fault  │◀────│  5. Review & Approve│◀────│  4. Agent Analyzes  │
│  (run rollback      │     │  Recommendations    │     │  & Correlates Data  │
│   script)           │     │                     │     │                     │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

> **Tip:** For detailed investigation prompts with specific metrics and starting points, see the "DevOps Agent Investigation Prompts" section under each [Fault Injection Scenario](#fault-injection-scenarios).

#### Interacting During Investigations

You can interact with the agent during investigations:

- **Ask clarifying questions**: "Which logs did you analyze?"
- **Provide context**: "Focus on the orders namespace"
- **Steer the investigation**: "Check the RDS connection pool metrics"
- **Request AWS Support**: Create a support case with one click

### Reading Documentation

For the most up-to-date information about AWS DevOps Agent, refer to the official documentation:

#### Official Resources

| Resource | URL | Description |
|----------|-----|-------------|
| **Product Page** | https://aws.amazon.com/devops-agent | Overview and sign-up |
| **AWS News Blog** | [Launch Announcement](https://aws.amazon.com/blogs/aws/aws-devops-agent-helps-you-accelerate-incident-response-and-improve-system-reliability-preview/) | Detailed walkthrough |
| **IAM Reference** | [Service Authorization Reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_awsdevopsagentservice.html) | IAM actions and permissions |

#### Key Concepts to Understand

1. **Agent Spaces** - Logical boundaries for resource grouping
2. **Topology** - Visual map of infrastructure relationships
3. **Investigations** - Automated root cause analysis sessions
4. **Mitigations** - Recommended fixes with implementation guidance
5. **Integrations** - Connections to observability and CI/CD tools

#### Supported Integrations

AWS DevOps Agent integrates with:

**Observability Tools:**
- Amazon CloudWatch (native)
- Datadog
- Dynatrace
- New Relic
- Splunk
- Grafana/Prometheus (via MCP)

**CI/CD & Source Control:**
- GitHub Actions
- GitLab CI/CD

**Incident Management:**
- ServiceNow (native)
- PagerDuty (via webhooks)
- Slack (for notifications)

**Custom Tools:**
- Bring Your Own MCP Server for custom integrations

#### Best Practices for This Lab

1. **Tag All Resources** - Ensure `devopsagent = "true"` tag is applied
2. **Enable Container Insights** - Already configured in Terraform
3. **Configure Alarms** - Set up CloudWatch alarms for key metrics
4. **Use Fault Injection** - Test the agent's investigation capabilities
5. **Review Recommendations** - Learn from the agent's analysis

---

## Fault Injection Scenarios

This repository includes fault injection scripts for simulating production-like issues during demos and training sessions. These scenarios help demonstrate how DevOps agents and monitoring tools can detect and diagnose real-world problems.

### Prerequisites

- EKS cluster deployed with the retail store application
- `kubectl` configured to access the cluster
- AWS CLI configured with appropriate permissions

### Setup

Make all fault injection scripts executable:

```bash
chmod +x fault-injection/*.sh
```

### Available Scenarios

| Scenario | Inject Script | Rollback Script | Description |
| -------- | ------------- | --------------- | ----------- |
| [Catalog Latency](#1-catalog-service-latency-injection) | `inject-catalog-latency.sh` | `rollback-catalog.sh` | Adds 300-500ms latency + CPU throttling |
| [RDS Stress Test](#2-rds-database-stress-test) | `inject-rds-stress.sh` | `rollback-rds-stress.sh` | Overwhelms PostgreSQL with heavy queries |
| [Network Partition](#3-network-partition-ui--cart) | `inject-network-partition.sh` | `rollback-network-partition.sh` | Blocks traffic between UI and Cart services |
| [RDS Security Group Block](#4-rds-security-group-misconfiguration) | `inject-rds-sg-block.sh` | `rollback-rds-sg-block.sh` | Simulates accidental SG misconfiguration |
| [Cart Memory Leak](#5-cart-memory-leak) | `inject-cart-memory-leak.sh` | `rollback-cart-memory-leak.sh` | Causes OOMKill and CrashLoopBackOff |
| [DynamoDB Latency](#6-dynamodb-latency) | `inject-dynamodb-latency.sh` | `rollback-dynamodb-latency.sh` | Adds 500ms latency to DynamoDB calls |

---

### 1. Catalog Service Latency Injection

Simulates high latency in the Catalog microservice by adding a sidecar that injects network delay and reducing CPU limits.

**What it does:**
- Adds 300-500ms latency on outbound HTTP calls via `tc netem`
- Reduces CPU limits from 256m to 128m (50% reduction)

**Expected behavior after injection:**
- Catalog pods will restart with the new configuration (latency sidecar added)
- Product pages will load noticeably slower (3-5 seconds instead of <1 second)
- CPU throttling will cause intermittent slowdowns under load
- UI service may show timeout errors when fetching product listings
- Users will experience degraded browsing experience

**Expected symptoms in monitoring:**
- p99 latency spikes in Prometheus/CloudWatch (300-500ms increase)
- CPU throttling metrics elevated (`container_cpu_cfs_throttled_seconds_total`)
- Increased response times in application logs
- Potential timeout errors from dependent services (UI → Catalog calls)

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-catalog-latency.sh

# Verify injection
kubectl get pods -n catalog
kubectl logs -n catalog -l app.kubernetes.io/name=catalog -c latency-injector

# Rollback
./fault-injection/rollback-catalog.sh
```

**DevOps Agent Investigation Prompts:**

Use these prompts when starting an investigation in the AWS DevOps Agent web app:

> **Investigation Details:** "Product pages are loading slow. Users are complaining about the catalog taking forever to load. Started happening about 10 minutes ago."

> **Investigation Starting Point:** "Check the catalog service pods in the catalog namespace. Look at latency metrics and CPU usage."

---

### 2. RDS Database Stress Test

Creates heavy load on the PostgreSQL RDS instance to simulate database performance degradation.

**What it does:**
- Deploys 18 parallel stress workers (CPU, recursive, hash, lock, write)
- Creates a 100k row stress table
- Generates complex queries causing full table scans

**Expected behavior after injection:**
- A stress test pod will be created in the `orders` namespace
- Orders service will become slow or unresponsive within 1-2 minutes
- Checkout process will fail with database timeout errors
- Order history pages will take 10+ seconds to load or timeout
- New orders will fail to be created
- Application logs will show `Connection timed out` and `HikariPool` errors

**Expected symptoms in monitoring:**
- RDS CPU utilization: 70-100%
- Slow queries visible in Performance Insights (queries taking 5-30+ seconds)
- Lock wait events (LWLock, Lock:transactionid)
- Orders/Checkout service timeouts and 500 errors
- HikariCP connection pool exhaustion in pod logs

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-rds-stress.sh

# Monitor stress pod
kubectl logs -f rds-stress-test -n orders

# Check RDS metrics
# AWS Console > RDS > Performance Insights > retail-store-orders-one

# Rollback
./fault-injection/rollback-rds-stress.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Checkout is failing for customers. Orders aren't going through and we're seeing timeouts. Might be a database issue."

> **Investigation Starting Point:** "Check the orders service and the RDS PostgreSQL database. Look at Performance Insights for slow queries."

---

### 3. Network Partition (UI → Cart)

Blocks network traffic from UI service to Cart service using Kubernetes NetworkPolicy.

**Prerequisites:**
- Network Policy Controller must be enabled (configured in Terraform)

**What it does:**
- Applies NetworkPolicy blocking ingress to Cart pods from UI namespace
- Other services can still communicate with Cart

**Expected behavior after injection:**
- Pods will NOT restart (this is a network-level block, not a pod change)
- Product browsing will work normally (UI → Catalog is unaffected)
- "Add to Cart" button will hang for ~30 seconds then fail
- Cart page will show empty or fail to load
- Checkout will be completely broken (cannot access cart items)
- Users will see timeout errors when interacting with cart functionality

**Expected symptoms in monitoring:**
- UI page loads normally (catalog works fine)
- Add to cart / checkout fails with timeout (30+ seconds)
- Connection timeout errors in UI pod logs (`java.net.SocketTimeoutException`)
- Increased error rate in UI service metrics
- Network flow logs show blocked traffic from UI to Carts namespace

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-network-partition.sh

# Test partition (from UI namespace - should timeout)
kubectl run test-from-ui --rm -it --image=curlimages/curl --restart=Never --namespace=ui -- curl -s --max-time 5 http://carts.carts.svc.cluster.local/carts

# Test from another namespace (should work)
kubectl run test-from-default --rm -it --image=curlimages/curl --restart=Never -- curl -s --max-time 5 http://carts.carts.svc.cluster.local/carts

# Rollback
./fault-injection/rollback-network-partition.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Users can browse products fine but Add to Cart is broken. Getting timeout errors when trying to add items. Cart page also won't load."

> **Investigation Starting Point:** "Check connectivity between the UI service and the carts service. Look for network policies or blocked traffic."

---

### 4. RDS Security Group Misconfiguration

Simulates an accidental security group change that blocks EKS nodes from connecting to ALL RDS instances.

**What it does:**
- Auto-discovers all RDS instances in the region
- Removes ingress rules allowing EKS cluster SG to access RDS on ports 3306 (MySQL) and 5432 (PostgreSQL)
- Automatically restarts application pods to trigger connection failures
- RDS instances remain healthy but unreachable from EKS

**Expected behavior after injection:**
- Catalog, Orders, and Checkout pods will be restarted by the script
- Pods will enter `Running` state but application will fail health checks
- Pods may go into `CrashLoopBackOff` if health checks fail repeatedly
- All database-dependent operations will fail immediately
- Product catalog will be empty or show errors
- Order history will fail to load
- Checkout process will fail completely
- RDS instances will appear healthy in AWS Console (misleading!)

**Expected symptoms in monitoring:**
- Orders/Checkout/Catalog service failures (500 errors)
- "Connection timed out" or "SocketTimeoutException" errors in pod logs
- HikariCP connection pool failures (`Failed to create/setup connection`)
- RDS shows healthy in console but unreachable from application
- VPC Flow Logs show REJECT for ports 3306/5432 traffic

**Run the scenario:**
```bash
# Inject the fault (auto-discovers and blocks all RDS instances)
./fault-injection/inject-rds-sg-block.sh

# Rollback (restores all revoked rules)
./fault-injection/rollback-rds-sg-block.sh
```

**Check application logs for errors:**
```bash
# Orders service logs (PostgreSQL connection errors)
kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=50

# Checkout service logs
kubectl logs -n checkout -l app.kubernetes.io/name=checkout --tail=50

# Catalog service logs (MySQL connection errors)
kubectl logs -n catalog -l app.kubernetes.io/name=catalog --tail=50
```

**Expected error messages in logs:**
```
org.postgresql.util.PSQLException: The connection attempt failed.
Caused by: java.net.SocketTimeoutException: Connect timed out

com.zaxxer.hikari.pool.PoolBase: HikariPool-1 - Pool is empty, failed to create/setup connection

Error 1045 (28000): Access denied for user... (MySQL)
java.sql.SQLNonTransientConnectionException: Could not connect to address
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Orders and checkout are completely down. Getting 500 errors. RDS shows healthy in the console but apps can't seem to connect."

> **Investigation Starting Point:** "Check the RDS security groups and VPC flow logs. The database is up but something is blocking connections."

---

### 5. Cart Memory Leak

Simulates a memory leak in the Cart service causing OOMKill and pod restarts.

**What it does:**
- Adds memory-leaker sidecar that consumes ~10MB every 5 seconds
- Reduces main container memory from 512Mi to 256Mi
- Sidecar has 200Mi limit, triggers OOMKill when exceeded

**Expected behavior after injection:**
- Cart pods will restart with the new configuration (memory-leaker sidecar added)
- Within 1-2 minutes, memory usage will climb rapidly
- Pods will be killed by Kubernetes with `OOMKilled` status
- Pods will restart and enter `CrashLoopBackOff` cycle
- Cart functionality will be intermittently available (works briefly after restart, then fails)
- Users will see "Service Unavailable" errors when accessing cart
- Pod restart count will increase continuously (visible in `kubectl get pods`)

**Expected symptoms in monitoring:**
- Pod restarts due to `OOMKilled` (visible in `kubectl describe pod`)
- `CrashLoopBackOff` status in pod list
- Memory usage spikes to limit then drops (sawtooth pattern)
- Increased memory usage in Prometheus/CloudWatch before each crash
- Cart operation failures in UI (intermittent 500 errors)
- Kubernetes events showing `OOMKilled` reason

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-cart-memory-leak.sh

# Monitor pods (watch for restarts)
watch kubectl get pods -n carts

# Check memory leak progress
kubectl logs -n carts -l app.kubernetes.io/name=carts -c memory-leaker -f

# Check for OOMKilled events
kubectl describe pod -n carts -l app.kubernetes.io/name=carts | grep -A5 'Last State'

# Rollback
./fault-injection/rollback-cart-memory-leak.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Cart service pods keep restarting every few minutes. Users are seeing intermittent failures when using the cart."

> **Investigation Starting Point:** "Check the carts namespace for pod restarts and OOMKilled events. Look at memory usage patterns."

---

### 6. DynamoDB Latency

Adds artificial network latency to DynamoDB calls from the Cart service.

**What it does:**
- Adds sidecar with `tc qdisc netem` to inject 500ms ± 50ms latency
- Affects all Cart service outbound traffic

**Expected behavior after injection:**
- Cart pods will restart with the new configuration (latency sidecar added)
- All cart operations will become noticeably slow (500ms+ added to each operation)
- "Add to Cart" will take 2-3 seconds instead of <500ms
- Viewing cart will be slow
- Checkout process will be sluggish (multiple DynamoDB calls)
- Under load, requests may start timing out
- Users will experience frustrating delays but service remains functional

**Expected symptoms in monitoring:**
- Cart operations slow (add to cart, view cart taking 2-5 seconds)
- DynamoDB latency increase in CloudWatch (`SuccessfulRequestLatency` metric)
- Application timeouts during checkout under heavy load
- Thread queuing in Cart service (increased thread pool usage)
- p99 latency spikes in Prometheus (500ms+ increase)

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-dynamodb-latency.sh

# Monitor latency injection
kubectl logs -n carts -l app.kubernetes.io/name=carts -c dynamodb-latency-injector

# Check CloudWatch DynamoDB metrics
# AWS Console > CloudWatch > DynamoDB metrics

# Rollback
./fault-injection/rollback-dynamodb-latency.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Adding items to cart is super slow. Used to be instant but now takes 3-5 seconds. Checkout is also sluggish."

> **Investigation Starting Point:** "Check DynamoDB metrics for the carts table. Look at latency and any throttling. Also check the cart service pods."

---

### Demo Workflow

For a training session, follow this workflow:

1. **Verify baseline** - Ensure all services are healthy before injection
   ```bash
   kubectl get pods -A | grep -E "carts|catalog|orders|checkout|ui"
   ```

2. **Choose a scenario** - Select one fault injection scenario from the table above

3. **Inject the fault** - Run the inject script and wait for symptoms to appear

4. **Observe symptoms** - Use monitoring tools (CloudWatch, Prometheus, pod logs) to observe the impact

5. **Let DevOps Agent investigate** - Allow automated investigation to detect root cause

6. **Rollback** - Run the rollback script to restore normal operation

7. **Verify recovery** - Confirm all services return to healthy state

---

## Cleanup - Destroying the Lab Environment

When you're finished with the lab, it's important to clean up all AWS resources to avoid ongoing charges. This section provides detailed instructions for completely removing the environment.

### Why a Cleanup Script?

Running `terraform destroy` alone may not remove all resources because:

1. **AWS GuardDuty** automatically creates VPC endpoints and security groups for runtime monitoring
2. **CloudWatch Container Insights** creates log groups dynamically when the agent starts
3. **Kubernetes resources** (Helm releases, namespaces) can cause provider errors during destroy

The cleanup script handles all of these edge cases.

### Quick Cleanup (Recommended)

Use the provided destroy script for a complete cleanup:

```bash
# Make the script executable
chmod +x scripts/destroy-environment.sh

# Run the cleanup script
./scripts/destroy-environment.sh
```

The script will:
1. Remove Kubernetes resources from Terraform state (prevents provider errors)
2. Run `terraform destroy` to remove all Terraform-managed resources
3. Delete any GuardDuty-managed VPC endpoints and security groups
4. Clean up orphaned CloudWatch log groups

### Manual Cleanup Steps

If you prefer to clean up manually or need to troubleshoot:

**Step 1: Remove Kubernetes Resources from Terraform State**

```bash
cd terraform/eks/default

# Remove Helm releases (prevents Kubernetes provider errors)
terraform state rm 'helm_release.ui' 2>/dev/null || true
terraform state rm 'helm_release.catalog' 2>/dev/null || true
terraform state rm 'helm_release.carts' 2>/dev/null || true
terraform state rm 'helm_release.orders' 2>/dev/null || true
terraform state rm 'helm_release.checkout' 2>/dev/null || true

# Remove Kubernetes namespaces
terraform state rm 'kubernetes_namespace.ui' 2>/dev/null || true
terraform state rm 'kubernetes_namespace.catalog' 2>/dev/null || true
terraform state rm 'kubernetes_namespace.carts' 2>/dev/null || true
terraform state rm 'kubernetes_namespace.orders' 2>/dev/null || true
terraform state rm 'kubernetes_namespace.checkout' 2>/dev/null || true
terraform state rm 'kubernetes_namespace.rabbitmq' 2>/dev/null || true

# Remove aws_auth ConfigMap
terraform state rm 'kubernetes_config_map_v1_data.aws_auth' 2>/dev/null || true
```

**Step 2: Run Terraform Destroy**

```bash
terraform destroy -auto-approve
```

**Step 3: Clean Up GuardDuty Resources (if VPC deletion fails)**

If the VPC fails to delete, check for GuardDuty-managed resources:

```bash
# Get the VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:environment-name,Values=retail-store" --query "Vpcs[0].VpcId" --output text --region us-east-1)

# Delete VPC endpoints created by GuardDuty
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text --region us-east-1 | xargs -r aws ec2 delete-vpc-endpoints --vpc-endpoint-ids --region us-east-1

# Wait for endpoints to be deleted
sleep 30

# Delete GuardDuty security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=GuardDuty*" --query "SecurityGroups[*].GroupId" --output text --region us-east-1 | xargs -r -I {} aws ec2 delete-security-group --group-id {} --region us-east-1

# Now delete the VPC
aws ec2 delete-vpc --vpc-id $VPC_ID --region us-east-1
```

**Step 4: Clean Up CloudWatch Log Groups**

```bash
# Delete Container Insights log groups
aws logs delete-log-group --log-group-name /aws/containerinsights/retail-store/application --region us-east-1 2>/dev/null || true
aws logs delete-log-group --log-group-name /aws/containerinsights/retail-store/dataplane --region us-east-1 2>/dev/null || true
aws logs delete-log-group --log-group-name /aws/containerinsights/retail-store/host --region us-east-1 2>/dev/null || true
aws logs delete-log-group --log-group-name /aws/containerinsights/retail-store/performance --region us-east-1 2>/dev/null || true

# Delete EKS cluster log groups (if any remain)
aws logs describe-log-groups --log-group-name-prefix /aws/eks/retail-store --query "logGroups[*].logGroupName" --output text --region us-east-1 | xargs -r -I {} aws logs delete-log-group --log-group-name {} --region us-east-1
```

### Verify Cleanup

After running the cleanup, verify all resources are removed:

```bash
# Check for remaining EKS clusters
aws eks list-clusters --region us-east-1

# Check for remaining VPCs with retail-store tag
aws ec2 describe-vpcs --filters "Name=tag:environment-name,Values=retail-store" --region us-east-1

# Check for remaining CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/retail-store --region us-east-1
aws logs describe-log-groups --log-group-name-prefix /aws/eks/retail-store --region us-east-1

# Check Terraform state is empty
cd terraform/eks/default
terraform state list
```

### Troubleshooting Cleanup Issues

**Issue: VPC deletion hangs or fails**
- Cause: GuardDuty or other AWS services created resources in the VPC
- Solution: Use the cleanup script or manually delete VPC endpoints and security groups first

**Issue: Terraform provider errors during destroy**
- Cause: Kubernetes provider can't connect to deleted cluster
- Solution: Remove Kubernetes resources from state before destroying (Step 1 above)

**Issue: Log groups still exist after destroy**
- Cause: Container Insights creates log groups outside of Terraform
- Solution: Manually delete using AWS CLI (Step 4 above)

**Issue: "resource not found" errors**
- Cause: Resource was already deleted manually or by another process
- Solution: These errors are safe to ignore; the resource is already gone

---

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.
