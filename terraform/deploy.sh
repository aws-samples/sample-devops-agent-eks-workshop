#!/bin/bash
set -e

# =============================================================================
# Deploy script for EKS DevOps Agent Workshop
# One-click deployment of the complete lab environment
# =============================================================================

# Default values (can be overridden via environment variables)
CLUSTER_NAME="${CLUSTER_NAME:-retail-store}"
REGION="${AWS_REGION:-us-east-1}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"

# Get the repo root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/eks/default"

# Cleanup function for trap
cleanup() {
    rm -f "$TERRAFORM_DIR/tfplan" 2>/dev/null || true
}
trap cleanup EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# =============================================================================
# Banner
# =============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       🚀 EKS DevOps Agent Workshop - Deployment Script        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Configuration:"
echo "  Cluster Name:    $CLUSTER_NAME"
echo "  AWS Region:      $REGION"
echo "  Enable Grafana:  $ENABLE_GRAFANA"
echo ""
echo "To customize, set environment variables:"
echo "  CLUSTER_NAME=my-cluster AWS_REGION=us-west-2 ./deploy.sh"
echo ""

# =============================================================================
# Step 1: Validate Configuration
# =============================================================================
print_header "Step 1: Validating Configuration"

# Validate cluster name (must start with letter, alphanumeric and hyphens only)
if [[ ! "$CLUSTER_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
    print_error "Invalid cluster name: $CLUSTER_NAME"
    echo "  Must start with a letter and contain only alphanumeric characters and hyphens"
    exit 1
fi
print_success "Cluster name valid: $CLUSTER_NAME"

# Check if Terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    print_error "Terraform directory not found: $TERRAFORM_DIR"
    echo "  Make sure you're running from the repository root"
    exit 1
fi
print_success "Terraform directory found"

# =============================================================================
# Step 2: Check Prerequisites
# =============================================================================
print_header "Step 2: Checking Prerequisites"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform not found"
    echo "Install Terraform: https://developer.hashicorp.com/terraform/downloads"
    exit 1
fi
TERRAFORM_VERSION=$(terraform version | head -1 | awk '{print $2}' | tr -d 'v')
print_success "Terraform found (v$TERRAFORM_VERSION)"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found"
    echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
print_success "kubectl found"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found"
    echo "Install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi
print_success "AWS CLI found"

# Verify AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or invalid"
    echo "Run: aws configure"
    exit 1
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_IDENTITY=$(aws sts get-caller-identity --query Arn --output text)
print_success "AWS credentials valid (Account: $AWS_ACCOUNT)"
echo "  Identity: $AWS_IDENTITY"

# Check if Grafana is enabled but SSO might not be configured
if [ "$ENABLE_GRAFANA" = "true" ]; then
    print_warning "Grafana enabled - requires AWS IAM Identity Center (SSO)"
    echo "  If SSO is not configured, deployment will fail."
    echo "  See: https://docs.aws.amazon.com/grafana/latest/userguide/authentication-in-AMG-SSO.html"
fi

# Check Helm
if ! command -v helm &> /dev/null; then
    print_error "Helm not found"
    echo "Install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi
print_success "Helm found"

# Check network connectivity to AWS
echo "Checking network connectivity..."
if ! curl -s --connect-timeout 10 https://sts.$REGION.amazonaws.com > /dev/null 2>&1; then
    print_error "Cannot reach AWS endpoints"
    echo "  Check your internet connection and VPN status"
    exit 1
fi
print_success "AWS endpoints reachable"

# =============================================================================
# Step 3: Authenticate to ECR Public
# =============================================================================
print_header "Step 3: Authenticating to ECR Public"

echo "Logging into ECR Public registry (required for Helm charts)..."
if aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws 2>/dev/null; then
    print_success "ECR Public authentication successful"
else
    print_warning "ECR Public authentication failed - deployment may hit rate limits"
    echo "  You can manually run: aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws"
fi

# =============================================================================
# Step 4: Initialize Terraform
# =============================================================================
print_header "Step 4: Initializing Terraform"

cd "$TERRAFORM_DIR"
terraform init -input=false
print_success "Terraform initialized"

# =============================================================================
# Step 5: Plan Deployment
# =============================================================================
print_header "Step 5: Planning Deployment"

terraform plan \
    -var="cluster_name=$CLUSTER_NAME" \
    -var="region=$REGION" \
    -var="enable_grafana=$ENABLE_GRAFANA" \
    -out=tfplan

print_success "Terraform plan created"

# =============================================================================
# Step 6: Apply Terraform
# =============================================================================
print_header "Step 6: Deploying Infrastructure (this takes ~25-30 minutes)"

START_TIME=$(date +%s)

terraform apply tfplan

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

print_success "Infrastructure deployed in ${MINUTES}m ${SECONDS}s"

# =============================================================================
# Step 7: Configure kubectl
# =============================================================================
print_header "Step 7: Configuring kubectl"

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
print_success "kubectl configured for cluster: $CLUSTER_NAME"

# =============================================================================
# Step 8: Wait for Application Pods
# =============================================================================
print_header "Step 8: Waiting for Application Pods"

echo "Waiting for UI service..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ui -n ui --timeout=300s 2>/dev/null || true

echo "Waiting for Catalog service..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=catalog -n catalog --timeout=300s 2>/dev/null || true

echo "Waiting for Carts service..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=carts -n carts --timeout=300s 2>/dev/null || true

echo "Waiting for Orders service..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=orders -n orders --timeout=300s 2>/dev/null || true

echo "Waiting for Checkout service..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=checkout -n checkout --timeout=300s 2>/dev/null || true

print_success "All application pods ready"

# =============================================================================
# Step 9: Get Application URL
# =============================================================================
print_header "Step 9: Getting Application URL"

# Wait for ALB to be provisioned
echo "Waiting for Application Load Balancer..."
for i in {1..30}; do
    APP_URL=$(kubectl get ingress -n ui ui -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$APP_URL" ]; then
        break
    fi
    echo "  Waiting for ALB... ($i/30)"
    sleep 10
done

# =============================================================================
# Deployment Complete
# =============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎉 Deployment Complete!                          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -n "$APP_URL" ]; then
    echo -e "📱 ${GREEN}Application URL:${NC} http://$APP_URL"
else
    echo -e "${YELLOW}Application URL not yet available. Check with:${NC}"
    echo "   kubectl get ingress -n ui"
fi

echo ""
echo "📊 Terraform Outputs:"
cd "$TERRAFORM_DIR"
terraform output 2>/dev/null || true

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Create an Agent Space in the DevOps Agent console:"
echo "   https://console.aws.amazon.com/devops-agent/home?region=$REGION"
echo ""
echo "2. Add tag filter during Agent Space creation:"
echo "   Tag Key: devopsagent    Tag Value: true"
echo ""
echo "3. Configure EKS access for the Agent Space"
echo "   (Follow the console instructions)"
echo ""
echo "4. Run fault injection scenarios:"
echo "   cd $REPO_ROOT/fault-injection"
echo "   ./inject-catalog-latency.sh"
echo ""
echo "5. To destroy the environment:"
echo "   $SCRIPT_DIR/destroy.sh"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
