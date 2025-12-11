#!/bin/bash
# RDS Security Group Misconfiguration Injection
# Removes the ingress rule allowing EKS to connect to RDS on port 5432

set -e

RDS_SG="sg-0c6f37edee735b5bd"
EKS_SG="sg-0dd97c79226d012d2"
REGION="us-east-1"

echo "=== RDS Security Group Misconfiguration Injection ==="
echo ""
echo "RDS Security Group: $RDS_SG"
echo "EKS Cluster Security Group: $EKS_SG"
echo ""

# Step 1: Backup current security group rules
echo "[1/3] Backing up current security group rules..."
aws ec2 describe-security-groups --group-ids $RDS_SG --region $REGION > fault-injection/rds-sg-backup.json
echo "  Backup saved to: fault-injection/rds-sg-backup.json"

# Step 2: Remove the ingress rule allowing EKS -> RDS on port 5432
echo "[2/3] Removing ingress rule (EKS -> RDS port 5432)..."
aws ec2 revoke-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG \
  --region $REGION

echo "[3/3] Verifying rule removal..."
aws ec2 describe-security-groups --group-ids $RDS_SG --region $REGION \
  --query "SecurityGroups[0].IpPermissions" --output table

echo ""
echo "=== Security Group Misconfiguration Injection Complete ==="
echo ""
echo "Blocked: EKS nodes -> RDS PostgreSQL (port 5432)"
echo ""
echo "Expected symptoms:"
echo "  - Orders/Checkout service failures"
echo "  - 'Connection timed out' or 'Connection refused' in pod logs"
echo "  - ALB returning 500/502/504 errors"
echo "  - RDS instance shows healthy in console (but unreachable)"
echo "  - VPC Flow Logs show REJECT for port 5432 traffic"
echo ""
echo "Monitor:"
echo "  kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=20"
echo "  kubectl logs -n checkout -l app.kubernetes.io/name=checkout --tail=20"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-rds-sg-block.sh"
