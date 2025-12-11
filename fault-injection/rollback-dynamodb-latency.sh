#!/bin/bash
# DynamoDB Latency Rollback Script
# Restores original Cart deployment without latency injection

set -e

NAMESPACE="carts"
DEPLOYMENT="carts"
BACKUP_FILE="fault-injection/carts-dynamodb-original.yaml"

echo "=== DynamoDB Latency Rollback ==="
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found at $BACKUP_FILE"
  echo "Attempting rollout restart..."
  kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
else
  echo "[1/3] Restoring from backup: $BACKUP_FILE"
  kubectl replace --force -f $BACKUP_FILE
fi

# Wait for rollout
echo "[2/3] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

# Cleanup ConfigMap
echo "[3/3] Cleaning up fault injection resources..."
kubectl delete configmap dynamodb-latency-script -n $NAMESPACE --ignore-not-found=true

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Restored: Normal DynamoDB latency"
echo ""
echo "Verify with:"
echo "  kubectl get pods -n $NAMESPACE"
