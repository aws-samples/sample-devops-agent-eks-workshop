![Banner](./docs/images/banner.png)

<div align="center">
  <div align="center">

[![Stars](https://img.shields.io/github/stars/aws-containers/retail-store-sample-app)](Stars)
![GitHub License](https://img.shields.io/github/license/aws-containers/retail-store-sample-app?color=green)
![Dynamic JSON Badge](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Faws-containers%2Fretail-store-sample-app%2Frefs%2Fheads%2Fmain%2F.release-please-manifest.json&query=%24%5B%22.%22%5D&label=release)
![GitHub Release Date](https://img.shields.io/github/release-date/aws-containers/retail-store-sample-app)

  </div>

  <strong>
  <h2>AWS Containers Retail Sample</h2>
  </strong>
</div>

This is a sample application designed to illustrate various concepts related to containers on AWS. It presents a sample retail store application including a product catalog, shopping cart and checkout.

It provides:

- A demo store-front application with themes, pages to show container and application topology information, generative AI chat bot and utility functions for experimentation and demos.
- An optional distributed component architecture using various languages and frameworks
- A variety of different persistence backends for the various components like MariaDB (or MySQL), DynamoDB and Redis
- The ability to run in different container orchestration technologies like Docker Compose, Kubernetes etc.
- Pre-built container images for both x86-64 and ARM64 CPU architectures
- All components instrumented for Prometheus metrics and OpenTelemetry OTLP tracing
- Support for Istio on Kubernetes
- Load generator which exercises all of the infrastructure

See the [features documentation](./docs/features.md) for more information.

**This project is intended for educational purposes only and not for production use**

![Screenshot](/docs/images/screenshot.png)

## Application Architecture

The application has been deliberately over-engineered to generate multiple de-coupled components. These components generally have different infrastructure dependencies, and may support multiple "backends" (example: Carts service supports MongoDB or DynamoDB).

![Architecture](/docs/images/architecture.png)

| Component                  | Language | Container Image                                                             | Helm Chart                                                                        | Description                             |
| -------------------------- | -------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------- |
| [UI](./src/ui/)            | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui)       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui-chart)       | Store user interface                    |
| [Catalog](./src/catalog/)  | Go       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog)  | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog-chart)  | Product catalog API                     |
| [Cart](./src/cart/)        | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart)     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart-chart)     | User shopping carts API                 |
| [Orders](./src/orders)     | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders)   | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders-chart)   | User orders API                         |
| [Checkout](./src/checkout) | Node     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout) | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout-chart) | API to orchestrate the checkout process |

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

## Deployment

### Terraform

The following options are available to deploy the application using Terraform:

| Name                                   | Description                                                                                                 |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [Amazon EKS](./terraform/eks/default/) | Deploys the application to Amazon EKS using other AWS services for dependencies, such as RDS, DynamoDB etc. |

### Deploy the EKS Cluster

```bash
# Navigate to terraform directory
cd terraform/eks/default

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration (takes ~20-30 minutes)
terraform apply

# Note the outputs for cluster name and region
```

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

# For ALB-based ingress, get the load balancer URL
kubectl get ingress -n ui
```

### Access the Application from Your Laptop

You can access the retail store application from your local machine using kubectl port-forward:

```bash
# Ensure kubeconfig is configured
aws eks update-kubeconfig --name retail-store --region us-east-1

# Verify connectivity to the cluster
kubectl get nodes

# Port-forward the UI service to your local machine
kubectl port-forward svc/ui 8080:80 -n ui
```

Open your browser and navigate to: `http://localhost:8080`

**Troubleshooting port-forward issues:**

```bash
# Check if the UI pods are running
kubectl get pods -n ui

# Check if the service has endpoints
kubectl get endpoints ui -n ui

# Test connectivity from within the cluster
kubectl exec -n ui deploy/ui -- curl -s localhost:8080/actuator/health

# Try a different local port if 8080 is in use
kubectl port-forward svc/ui 9090:80 -n ui

# Use verbose mode for debugging
kubectl port-forward svc/ui 8080:80 -n ui -v=6
```

**Note:** The port-forward command must remain running in your terminal. Open a new terminal for other commands.

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

**Expected symptoms:**
- p99 latency spikes in Prometheus/CloudWatch
- CPU throttling metrics elevated
- Increased response times in application logs
- Potential timeout errors from dependent services

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

---

### 2. RDS Database Stress Test

Creates heavy load on the PostgreSQL RDS instance to simulate database performance degradation.

**What it does:**
- Deploys 18 parallel stress workers (CPU, recursive, hash, lock, write)
- Creates a 100k row stress table
- Generates complex queries causing full table scans

**Expected symptoms:**
- RDS CPU utilization: 70-100%
- Slow queries visible in Performance Insights
- Lock wait events (LWLock, Lock:transactionid)
- Orders/Checkout service timeouts

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

---

### 3. Network Partition (UI → Cart)

Blocks network traffic from UI service to Cart service using Kubernetes NetworkPolicy.

**Prerequisites:**
- Network Policy Controller must be enabled (configured in Terraform)

**What it does:**
- Applies NetworkPolicy blocking ingress to Cart pods from UI namespace
- Other services can still communicate with Cart

**Expected symptoms:**
- UI page loads normally
- Add to cart / checkout fails with timeout
- 504 Gateway timeout errors in ALB logs
- Increased error rate in UI pod logs

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

---

### 4. RDS Security Group Misconfiguration

Simulates an accidental security group change that blocks EKS nodes from connecting to RDS.

**What it does:**
- Removes the ingress rule allowing EKS cluster SG to access RDS on port 5432
- RDS instance remains healthy but unreachable

**Expected symptoms:**
- Orders/Checkout service failures
- "Connection timed out" errors in pod logs
- ALB returning 500/502/504 errors
- RDS shows healthy in console but unreachable
- VPC Flow Logs show REJECT for port 5432 traffic

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-rds-sg-block.sh

# Monitor application failures
kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=20
kubectl logs -n checkout -l app.kubernetes.io/name=checkout --tail=20

# Rollback
./fault-injection/rollback-rds-sg-block.sh
```

---

### 5. Cart Memory Leak

Simulates a memory leak in the Cart service causing OOMKill and pod restarts.

**What it does:**
- Adds memory-leaker sidecar that consumes ~10MB every 5 seconds
- Reduces main container memory from 512Mi to 256Mi
- Sidecar has 200Mi limit, triggers OOMKill when exceeded

**Expected symptoms:**
- Pod restarts due to OOMKilled
- CrashLoopBackOff status
- Increased memory usage in Prometheus/CloudWatch
- Cart operation failures in UI

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

---

### 6. DynamoDB Latency

Adds artificial network latency to DynamoDB calls from the Cart service.

**What it does:**
- Adds sidecar with `tc qdisc netem` to inject 500ms ± 50ms latency
- Affects all Cart service outbound traffic

**Expected symptoms:**
- Cart operations slow (add to cart, view cart)
- DynamoDB latency increase in CloudWatch
- Application timeouts during checkout
- Thread queuing in Cart service
- p99 latency spikes in Prometheus

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

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the MIT-0 License.

This package depends on and may incorporate or retrieve a number of third-party
software packages (such as open source packages) at install-time or build-time
or run-time ("External Dependencies"). The External Dependencies are subject to
license terms that you must accept in order to use this package. If you do not
accept all of the applicable license terms, you should not use this package. We
recommend that you consult your company's open source approval policy before
proceeding.

Provided below is a list of External Dependencies and the applicable license
identification as indicated by the documentation associated with the External
Dependencies as of Amazon's most recent review.

THIS INFORMATION IS PROVIDED FOR CONVENIENCE ONLY. AMAZON DOES NOT PROMISE THAT
THE LIST OR THE APPLICABLE TERMS AND CONDITIONS ARE COMPLETE, ACCURATE, OR
UP-TO-DATE, AND AMAZON WILL HAVE NO LIABILITY FOR ANY INACCURACIES. YOU SHOULD
CONSULT THE DOWNLOAD SITES FOR THE EXTERNAL DEPENDENCIES FOR THE MOST COMPLETE
AND UP-TO-DATE LICENSING INFORMATION.

YOUR USE OF THE EXTERNAL DEPENDENCIES IS AT YOUR SOLE RISK. IN NO EVENT WILL
AMAZON BE LIABLE FOR ANY DAMAGES, INCLUDING WITHOUT LIMITATION ANY DIRECT,
INDIRECT, CONSEQUENTIAL, SPECIAL, INCIDENTAL, OR PUNITIVE DAMAGES (INCLUDING
FOR ANY LOSS OF GOODWILL, BUSINESS INTERRUPTION, LOST PROFITS OR DATA, OR
COMPUTER FAILURE OR MALFUNCTION) ARISING FROM OR RELATING TO THE EXTERNAL
DEPENDENCIES, HOWEVER CAUSED AND REGARDLESS OF THE THEORY OF LIABILITY, EVEN
IF AMAZON HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. THESE LIMITATIONS
AND DISCLAIMERS APPLY EXCEPT TO THE EXTENT PROHIBITED BY APPLICABLE LAW.

MariaDB Community License - [LICENSE](https://mariadb.com/kb/en/mariadb-licenses/)
MySQL Community Edition - [LICENSE](https://github.com/mysql/mysql-server/blob/8.0/LICENSE)
