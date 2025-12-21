#!/bin/bash
set -e

# Destroy script for EKS environment
# Handles Terraform-managed resources AND AWS auto-provisioned resources

# Default values (can be overridden via environment variables)
CLUSTER_NAME="${CLUSTER_NAME:-retail-store}"
REGION="${AWS_REGION:-us-east-1}"

# Get the repo root directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="${TERRAFORM_DIR:-$REPO_ROOT/terraform/eks/default}"

echo "=== Destroying EKS environment ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Terraform Dir: $TERRAFORM_DIR"
echo ""
echo "To override defaults, set environment variables:"
echo "  CLUSTER_NAME=<name> AWS_REGION=<region> $0"
echo ""

# Step 1: Get VPC ID before destroying (needed for cleanup)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:environment-name,Values=$CLUSTER_NAME" --query "Vpcs[0].VpcId" --output text --region $REGION 2>/dev/null || echo "None")
echo "VPC ID: $VPC_ID"

# Step 2: Clean up AWS auto-provisioned resources BEFORE terraform destroy
if [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ] && [ -n "$VPC_ID" ]; then
    echo ""
    echo "=== Step 2: Cleaning up AWS auto-provisioned resources in VPC ==="
    
    # Delete VPC endpoints (created by GuardDuty) - these block subnet deletion
    ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text --region $REGION 2>/dev/null || echo "")
    for ep in $ENDPOINTS; do
        echo "Deleting VPC endpoint: $ep"
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep --region $REGION 2>/dev/null || true
    done
    
    # Wait for endpoints to be deleted
    [ -n "$ENDPOINTS" ] && sleep 30
    
    # Delete GuardDuty security groups
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=GuardDuty*" --query "SecurityGroups[*].GroupId" --output text --region $REGION 2>/dev/null || echo "")
    for sg in $SG_IDS; do
        echo "Deleting GuardDuty security group: $sg"
        aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null || true
    done
fi

# Step 3: Run Terraform destroy (remove Kubernetes resources from state first to avoid provider issues)
echo ""
echo "=== Step 3: Removing Kubernetes resources from Terraform state ==="
cd $TERRAFORM_DIR
terraform state rm 'kubernetes_config_map_v1_data.aws_auth' 2>/dev/null || true
terraform state rm 'helm_release.ui' 'helm_release.catalog' 'helm_release.carts' 'helm_release.orders' 'helm_release.checkout' 2>/dev/null || true
terraform state rm 'kubernetes_namespace.ui' 'kubernetes_namespace.catalog' 'kubernetes_namespace.carts' 'kubernetes_namespace.orders' 'kubernetes_namespace.checkout' 'kubernetes_namespace.rabbitmq' 2>/dev/null || true

echo ""
echo "=== Step 4: Running Terraform destroy ==="
terraform destroy -auto-approve || true
cd - > /dev/null

# Step 5: Final VPC cleanup if it still exists
if [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ] && [ -n "$VPC_ID" ]; then
    echo ""
    echo "=== Step 5: Final VPC cleanup ==="
    # Try to delete VPC if it still exists
    echo "Attempting to delete VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null || true
fi

# Step 6: Clean up CloudWatch log groups created by Container Insights
echo ""
echo "=== Step 6: Cleaning up CloudWatch log groups ==="
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/$CLUSTER_NAME" --query "logGroups[*].logGroupName" --output text --region $REGION 2>/dev/null || echo "")
for lg in $LOG_GROUPS; do
    echo "Deleting log group: $lg"
    aws logs delete-log-group --log-group-name "$lg" --region $REGION 2>/dev/null || true
done

# Also clean up EKS cluster log groups
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" --query "logGroups[*].logGroupName" --output text --region $REGION 2>/dev/null || echo "")
for lg in $LOG_GROUPS; do
    echo "Deleting log group: $lg"
    aws logs delete-log-group --log-group-name "$lg" --region $REGION 2>/dev/null || true
done

# VPC flow log groups
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/vpc-flow-log" --query "logGroups[?contains(logGroupName, '$CLUSTER_NAME')].logGroupName" --output text --region $REGION 2>/dev/null || echo "")
for lg in $LOG_GROUPS; do
    echo "Deleting log group: $lg"
    aws logs delete-log-group --log-group-name "$lg" --region $REGION 2>/dev/null || true
done

echo ""
echo "=== Environment destroyed successfully ==="
