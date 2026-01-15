#!/bin/bash
# RDS Security Group Misconfiguration Injection
# Removes ingress rules allowing EKS to connect to ALL RDS instances
# Blocks both MySQL (3306) and PostgreSQL (5432) ports

set -e

REGION="${AWS_REGION:-us-east-1}"

echo "=== RDS Security Group Misconfiguration Injection ==="
echo ""
echo "Region: $REGION"
echo ""

# Auto-discover EKS security group
echo "[1/4] Discovering EKS cluster security group..."
EKS_CLUSTER=$(AWS_PAGER="" aws eks list-clusters --region $REGION --query "clusters[0]" --output text 2>/dev/null)

if [ -z "$EKS_CLUSTER" ] || [ "$EKS_CLUSTER" == "None" ]; then
  echo "ERROR: No EKS cluster found in region $REGION"
  exit 1
fi

EKS_SG=$(AWS_PAGER="" aws eks describe-cluster --region $REGION --name "$EKS_CLUSTER" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null)

if [ -z "$EKS_SG" ] || [ "$EKS_SG" == "None" ]; then
  echo "ERROR: Could not find EKS security group for cluster $EKS_CLUSTER"
  exit 1
fi

echo "  EKS Cluster: $EKS_CLUSTER"
echo "  EKS Security Group: $EKS_SG"
echo ""

# Auto-discover all RDS instances and their security groups
echo "[2/4] Discovering RDS instances and security groups..."
RDS_INFO=$(AWS_PAGER="" aws rds describe-db-instances --region $REGION \
  --query "DBInstances[*].[DBInstanceIdentifier,VpcSecurityGroups[0].VpcSecurityGroupId,Endpoint.Port]" \
  --output json 2>/dev/null)

if [ -z "$RDS_INFO" ] || [ "$RDS_INFO" == "[]" ]; then
  echo "ERROR: No RDS instances found in region $REGION"
  exit 1
fi

echo "  Found RDS instances:"
echo "$RDS_INFO" | jq -r '.[] | "    - \(.[0]) (SG: \(.[1]), Port: \(.[2]))"'
echo ""

# Save backup info for rollback
echo "[3/4] Backing up security group rules and revoking access..."
REVOKED_RULES="[]"

# Process each RDS instance
for row in $(echo "$RDS_INFO" | jq -r '.[] | @base64'); do
  _jq() {
    echo ${row} | base64 --decode | jq -r ${1}
  }
  
  DB_ID=$(_jq '.[0]')
  RDS_SG=$(_jq '.[1]')
  DB_PORT=$(_jq '.[2]')
  
  echo "  Processing: $DB_ID (SG: $RDS_SG)"
  
  # Try to revoke port 5432 (PostgreSQL)
  if AWS_PAGER="" aws ec2 revoke-security-group-ingress \
    --group-id $RDS_SG \
    --protocol tcp \
    --port 5432 \
    --source-group $EKS_SG \
    --region $REGION 2>/dev/null; then
    echo "    ✓ Revoked port 5432 (PostgreSQL)"
    REVOKED_RULES=$(echo "$REVOKED_RULES" | jq ". + [{\"rds_sg\": \"$RDS_SG\", \"eks_sg\": \"$EKS_SG\", \"port\": 5432, \"db_id\": \"$DB_ID\"}]")
  else
    echo "    - Port 5432 rule not found or already removed"
  fi
  
  # Try to revoke port 3306 (MySQL)
  if AWS_PAGER="" aws ec2 revoke-security-group-ingress \
    --group-id $RDS_SG \
    --protocol tcp \
    --port 3306 \
    --source-group $EKS_SG \
    --region $REGION 2>/dev/null; then
    echo "    ✓ Revoked port 3306 (MySQL)"
    REVOKED_RULES=$(echo "$REVOKED_RULES" | jq ". + [{\"rds_sg\": \"$RDS_SG\", \"eks_sg\": \"$EKS_SG\", \"port\": 3306, \"db_id\": \"$DB_ID\"}]")
  else
    echo "    - Port 3306 rule not found or already removed"
  fi
done

# Save revoked rules for rollback (use script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "{\"region\": \"$REGION\", \"eks_sg\": \"$EKS_SG\", \"revoked_rules\": $REVOKED_RULES}" > "$SCRIPT_DIR/rds-sg-ids.json"
echo ""
echo "  Backup saved to: $SCRIPT_DIR/rds-sg-ids.json"

REVOKED_COUNT=$(echo "$REVOKED_RULES" | jq 'length')
if [ "$REVOKED_COUNT" -eq 0 ]; then
  echo ""
  echo "WARNING: No rules were revoked. Security groups may not have matching rules."
  exit 0
fi

echo ""
echo "=== Security Group Misconfiguration Injection Complete ==="
echo ""
echo "Revoked $REVOKED_COUNT security group rules"
echo ""

# Step 4: Restart pods to trigger connection errors
echo "[4/4] Restarting application pods to trigger connection errors..."

# Restart orders deployment
if kubectl get deployment -n orders orders &>/dev/null; then
  kubectl rollout restart deployment -n orders orders 2>/dev/null && echo "  ✓ Restarted orders deployment"
fi

# Restart checkout deployment
if kubectl get deployment -n checkout checkout &>/dev/null; then
  kubectl rollout restart deployment -n checkout checkout 2>/dev/null && echo "  ✓ Restarted checkout deployment"
fi

# Restart catalog deployment
if kubectl get deployment -n catalog catalog &>/dev/null; then
  kubectl rollout restart deployment -n catalog catalog 2>/dev/null && echo "  ✓ Restarted catalog deployment"
fi

echo ""
echo "Waiting 30 seconds for pods to restart and fail..."
sleep 30

# Step 5: Generate traffic to trigger errors via port-forward
echo ""
echo "[5/5] Generating traffic to trigger database connection errors..."

# Function to generate traffic to a service (services use port 80)
generate_traffic() {
  local namespace=$1
  local service=$2
  local local_port=$3
  local endpoint=$4
  
  # Start port-forward in background (service port is 80)
  kubectl port-forward -n $namespace svc/$service $local_port:80 &>/dev/null &
  local pf_pid=$!
  sleep 2
  
  if kill -0 $pf_pid 2>/dev/null; then
    echo "  Sending requests to $service..."
    for i in {1..10}; do
      curl -s -o /dev/null -w "%{http_code} " "http://localhost:$local_port$endpoint" 2>/dev/null
    done
    echo ""
    kill $pf_pid 2>/dev/null
    echo "  ✓ $service: 10 requests sent"
  else
    echo "  - Could not port-forward to $service"
  fi
}

# Generate traffic to services that use database (using different local ports)
generate_traffic "orders" "orders" 8080 "/orders"
generate_traffic "checkout" "checkout" 8081 "/checkout"
generate_traffic "catalog" "catalog" 8082 "/catalogue"

echo "  ✓ Traffic burst complete"

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Check application logs for errors:"
echo "  kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=50"
echo "  kubectl logs -n checkout -l app.kubernetes.io/name=checkout --tail=50"
echo "  kubectl logs -n catalog -l app.kubernetes.io/name=catalog --tail=50"
echo ""
echo "Rollback:"
echo "  ./~/fault-injection/rollback-rds-sg-block.sh"
