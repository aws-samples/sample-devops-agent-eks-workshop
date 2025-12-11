#!/bin/bash
# RDS Security Group Rollback Script
# Restores the ingress rule allowing EKS to connect to RDS on port 5432

set -e

RDS_SG="sg-0c6f37edee735b5bd"
EKS_SG="sg-0dd97c79226d012d2"
REGION="us-east-1"

echo "=== RDS Security Group Rollback ==="
echo ""

# Step 1: Restore the ingress rule
echo "[1/2] Restoring ingress rule (EKS -> RDS port 5432)..."
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG \
  --region $REGION 2>/dev/null || echo "  Rule may already exist"

# Add description to the rule
aws ec2 update-security-group-rule-descriptions-ingress \
  --group-id $RDS_SG \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$EKS_SG,Description='From allowed SGs'}]" \
  --region $REGION 2>/dev/null || true

echo "[2/2] Verifying rule restoration..."
aws ec2 describe-security-groups --group-ids $RDS_SG --region $REGION \
  --query "SecurityGroups[0].IpPermissions" --output table

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Restored: EKS nodes -> RDS PostgreSQL (port 5432)"
echo ""
echo "Verify connectivity:"
echo "  kubectl exec -n orders \$(kubectl get pod -n orders -l app.kubernetes.io/name=orders -o name | head -1) -- nc -zv retail-store-orders.cluster-cfkkvgfaqokl.us-east-1.rds.amazonaws.com 5432"
