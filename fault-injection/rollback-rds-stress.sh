#!/bin/bash
# RDS Stress Test Rollback Script
# Stops the stress test and cleans up resources including the stress_test table

set -e

NAMESPACE="orders"
REGION="${AWS_REGION:-us-east-1}"

echo "=== RDS Stress Test Rollback ==="
echo ""

# Auto-discover RDS PostgreSQL endpoint
echo "[0/4] Discovering RDS PostgreSQL endpoint..."
DB_HOST=$(AWS_PAGER="" aws rds describe-db-instances --region $REGION \
  --query "DBInstances[?Endpoint.Port==\`5432\`].Endpoint.Address" \
  --output text 2>/dev/null | head -1)

if [ -z "$DB_HOST" ] || [ "$DB_HOST" == "None" ]; then
  echo "WARNING: No PostgreSQL RDS instance found, skipping table cleanup"
  DB_HOST=""
fi

DB_PORT="5432"
DB_NAME="orders"
DB_USER="root"

echo "  Found: ${DB_HOST:-none}"
echo ""

# Stop the stress pod
echo "[1/4] Stopping stress test pod..."
kubectl delete pod rds-stress-test -n $NAMESPACE --ignore-not-found=true --grace-period=0 --force 2>/dev/null || true

# Clean up ConfigMap
echo "[2/4] Cleaning up ConfigMap..."
kubectl delete configmap rds-stress-scripts -n $NAMESPACE --ignore-not-found=true

# Get the database password from the secret and clean up table
echo "[3/4] Removing stress_test table from database..."
if [ -n "$DB_HOST" ]; then
  DB_PASS=$(kubectl get secret orders-db -n $NAMESPACE -o jsonpath='{.data.RETAIL_ORDERS_PERSISTENCE_PASSWORD}' | base64 -d)

  # Run cleanup pod to drop the stress_test table
  kubectl run rds-cleanup --rm -i --restart=Never -n $NAMESPACE \
    --image=postgres:15-alpine \
    --env="PGPASSWORD=$DB_PASS" \
    -- psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c 'DROP TABLE IF EXISTS stress_test;' 2>/dev/null || true
else
  echo "  Skipped (no RDS endpoint found)"
fi

echo "[4/4] Cleanup complete"
echo ""
echo "=== Rollback Complete ==="
echo ""
echo "RDS metrics should return to normal within 1-2 minutes."
