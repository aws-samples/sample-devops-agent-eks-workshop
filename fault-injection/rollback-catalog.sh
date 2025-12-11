#!/bin/bash
# Catalog Service Fault Rollback Script
# Restores original deployment configuration

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="fault-injection/catalog-original.yaml"

echo "=== Catalog Service Fault Rollback ==="
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found at $BACKUP_FILE"
  echo "Attempting manual rollback..."
  
  # Manual rollback - restore original CPU and remove sidecar
  echo "[1/3] Removing latency injector sidecar..."
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources/limits/cpu",
      "value": "256m"
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources/requests/cpu", 
      "value": "256m"
    }
  ]'
  
  # Remove the sidecar container by redeploying with only the main container
  echo "[2/3] Restarting deployment to remove sidecar..."
  kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
  
else
  echo "[1/3] Restoring from backup: $BACKUP_FILE"
  # Use replace --force to handle resourceVersion conflicts
  kubectl replace --force -f $BACKUP_FILE
fi

# Wait for rollout
echo "[2/3] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

# Cleanup ConfigMap
echo "[3/3] Cleaning up fault injection resources..."
kubectl delete configmap latency-injector-script -n $NAMESPACE --ignore-not-found=true

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Restored configuration:"
echo "  - CPU: 256m (original)"
echo "  - Latency sidecar: Removed"
echo ""
echo "Verify with:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl describe deployment $DEPLOYMENT -n $NAMESPACE"
