#!/bin/bash
# Network Partition Rollback Script
# Removes the NetworkPolicy blocking UI -> Cart traffic

set -e

echo "=== Network Partition Rollback ==="
echo ""

# Remove the NetworkPolicy
echo "[1/2] Removing NetworkPolicy..."
kubectl delete networkpolicy block-ui-to-carts -n carts --ignore-not-found=true

echo "[2/2] Verifying removal..."
kubectl get networkpolicy -n carts 2>/dev/null || echo "No NetworkPolicies in carts namespace"

echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Traffic restored: UI -> Cart service"
echo ""
echo "Verify connectivity:"
echo "  kubectl exec -n ui -it \$(kubectl get pod -n ui -o name | head -1) -- curl -v --max-time 5 http://carts.carts.svc.cluster.local/carts"
