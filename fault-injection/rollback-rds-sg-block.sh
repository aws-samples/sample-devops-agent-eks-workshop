#!/bin/bash
# RDS Security Group Rollback Script
# Restores ingress rules allowing EKS to connect to RDS instances

set -e

REGION="${AWS_REGION:-us-east-1}"

echo "=== RDS Security Group Rollback ==="
echo ""

# Use script directory for backup file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE="$SCRIPT_DIR/rds-sg-ids.json"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: No backup file found at $BACKUP_FILE"
  echo "Cannot rollback without knowing which rules were revoked."
  echo ""
  echo "Manual rollback: Add ingress rules to your RDS security groups allowing"
  echo "traffic from your EKS cluster security group on ports 3306 and/or 5432."
  exit 1
fi

# Load backup info
REGION=$(jq -r '.region' "$BACKUP_FILE")
EKS_SG=$(jq -r '.eks_sg' "$BACKUP_FILE")
REVOKED_RULES=$(jq -r '.revoked_rules' "$BACKUP_FILE")

echo "Region: $REGION"
echo "EKS Security Group: $EKS_SG"
echo ""

RULE_COUNT=$(echo "$REVOKED_RULES" | jq 'length')
if [ "$RULE_COUNT" -eq 0 ]; then
  echo "No rules to restore. Backup file shows no rules were revoked."
  exit 0
fi

echo "[1/2] Restoring $RULE_COUNT security group rules..."
echo ""

RESTORED=0
FAILED=0

# Restore each revoked rule
for row in $(echo "$REVOKED_RULES" | jq -r '.[] | @base64'); do
  _jq() {
    echo ${row} | base64 --decode | jq -r ${1}
  }
  
  RDS_SG=$(_jq '.rds_sg')
  EKS_SG=$(_jq '.eks_sg')
  PORT=$(_jq '.port')
  DB_ID=$(_jq '.db_id')
  
  echo "  Restoring: $DB_ID (SG: $RDS_SG, Port: $PORT)"
  
  if AWS_PAGER="" aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG \
    --protocol tcp \
    --port $PORT \
    --source-group $EKS_SG \
    --region $REGION 2>/dev/null; then
    echo "    ✓ Port $PORT rule restored"
    
    # Add description to the rule
    AWS_PAGER="" aws ec2 update-security-group-rule-descriptions-ingress \
      --group-id $RDS_SG \
      --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,UserIdGroupPairs=[{GroupId=$EKS_SG,Description=From allowed SGs}]" \
      --region $REGION 2>/dev/null || true
    
    RESTORED=$((RESTORED + 1))
  else
    echo "    ✗ Failed to restore port $PORT (may already exist)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "[2/2] Verifying restoration..."

# Show current state of security groups
UNIQUE_SGS=$(echo "$REVOKED_RULES" | jq -r '.[].rds_sg' | sort -u)
for SG in $UNIQUE_SGS; do
  echo ""
  echo "  Security Group: $SG"
  AWS_PAGER="" aws ec2 describe-security-groups --group-ids $SG --region $REGION \
    --query "SecurityGroups[0].IpPermissions[*].{Port:FromPort,Source:UserIdGroupPairs[0].GroupId}" \
    --output table 2>/dev/null || echo "    Could not describe security group"
done

echo ""
echo "=== Security Group Rollback Complete ==="
echo ""
echo "Restored: $RESTORED rules"
echo "Failed: $FAILED rules"

# Step 3: Restart pods to reconnect to database
echo ""
echo "[3/5] Restarting application pods..."

if kubectl get deployment -n orders orders &>/dev/null; then
  kubectl rollout restart deployment -n orders orders 2>/dev/null && echo "  ✓ Restarted orders deployment"
fi

if kubectl get deployment -n checkout checkout &>/dev/null; then
  kubectl rollout restart deployment -n checkout checkout 2>/dev/null && echo "  ✓ Restarted checkout deployment"
fi

if kubectl get deployment -n catalog catalog &>/dev/null; then
  kubectl rollout restart deployment -n catalog catalog 2>/dev/null && echo "  ✓ Restarted catalog deployment"
fi

echo ""
echo "Waiting 45 seconds for pods to restart..."
sleep 45

# Step 4: Check pod status
echo ""
echo "[4/5] Checking pod status..."
echo ""
echo "  Orders pods:"
kubectl get pods -n orders -l app.kubernetes.io/name=orders --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Checkout pods:"
kubectl get pods -n checkout -l app.kubernetes.io/name=checkout --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Catalog pods:"
kubectl get pods -n catalog -l app.kubernetes.io/name=catalog --no-headers 2>/dev/null | sed 's/^/    /'

# Step 5: Check connectivity via port-forward
echo ""
echo "[5/5] Checking service connectivity..."

check_service() {
  local namespace=$1
  local service=$2
  local local_port=$3
  local endpoint=$4
  
  kubectl port-forward -n $namespace svc/$service $local_port:80 &>/dev/null &
  local pf_pid=$!
  sleep 2
  
  if kill -0 $pf_pid 2>/dev/null; then
    local status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$local_port$endpoint" 2>/dev/null)
    kill $pf_pid 2>/dev/null
    if [ "$status" == "200" ] || [ "$status" == "201" ]; then
      echo "  ✓ $service: HTTP $status (healthy)"
    else
      echo "  ⚠ $service: HTTP $status"
    fi
  else
    echo "  ✗ $service: Could not connect"
  fi
}

check_service "orders" "orders" 8080 "/orders"
check_service "checkout" "checkout" 8081 "/checkout"
check_service "catalog" "catalog" 8082 "/catalogue"

# Show recent logs
echo ""
echo "=== Recent Application Logs ==="
echo ""
echo "Orders (last 5 lines):"
kubectl logs -n orders -l app.kubernetes.io/name=orders --tail=5 2>/dev/null | sed 's/^/  /' || echo "  No logs available"
echo ""
echo "Catalog (last 5 lines):"
kubectl logs -n catalog -l app.kubernetes.io/name=catalog --tail=5 2>/dev/null | sed 's/^/  /' || echo "  No logs available"

echo ""
echo "=== Rollback Complete ==="
