#!/bin/bash
# Catalog Service Fault Rollback Script
# Restores original deployment configuration by removing injected components

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="fault-injection/catalog-original.yaml"

echo "=== Catalog Service Fault Rollback ==="
echo ""

# Step 1: Delete ConfigMap FIRST (before deployment changes)
echo "[1/4] Cleaning up fault injection ConfigMap..."
kubectl delete configmap latency-injector-script -n $NAMESPACE --ignore-not-found=true

# Step 2: Remove sidecar and restore CPU via patch (more reliable than backup file)
echo "[2/4] Removing latency injector sidecar and restoring CPU limits..."

# Check if sidecar exists
SIDECAR_EXISTS=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[?(@.name=="latency-injector")].name}' 2>/dev/null)

if [ -n "$SIDECAR_EXISTS" ]; then
  # Find the index of the latency-injector container and latency-script volume
  CONTAINER_COUNT=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].name}' | wc -w)
  VOLUME_COUNT=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.volumes[*].name}' | wc -w)
  
  # Build patch to remove sidecar container and volume, restore CPU
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "256m"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "256m"},
    {"op": "remove", "path": "/spec/template/spec/containers/1"},
    {"op": "remove", "path": "/spec/template/spec/volumes/1"}
  ]' 2>/dev/null || {
    echo "  Patch failed, trying alternative approach..."
    # If patch fails, try removing just the sidecar
    kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "256m"},
      {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "256m"}
    ]'
    kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE
  }
else
  echo "  No sidecar found, just restoring CPU limits..."
  kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "256m"},
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "256m"}
  ]'
fi

# Step 3: Wait for rollout
echo "[3/4] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

# Step 4: Verify pods are healthy
echo "[4/5] Verifying pods are healthy..."
sleep 5
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=catalog

# Step 5: Scale deployment back to 2 replicas
echo ""
echo "[5/5] Scaling deployment back to 2 replicas..."
kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=2
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=60s

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Restored configuration:"
echo "  - CPU: 256m (original)"
echo "  - Latency sidecar: Removed"
echo "  - ConfigMap: Deleted"
echo "  - Replicas: Scaled to 2"
echo ""
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=catalog
