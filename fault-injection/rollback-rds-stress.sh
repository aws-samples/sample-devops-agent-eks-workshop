#!/bin/bash
# RDS Stress Test Rollback Script
# Stops the stress test and cleans up resources

set -e

NAMESPACE="orders"

echo "=== RDS Stress Test Rollback ==="
echo ""

# Stop the stress pod
echo "[1/3] Stopping stress test pod..."
kubectl delete pod rds-stress-test -n $NAMESPACE --ignore-not-found=true --grace-period=0 --force 2>/dev/null || true

# Clean up ConfigMap
echo "[2/3] Cleaning up ConfigMap..."
kubectl delete configmap rds-stress-scripts -n $NAMESPACE --ignore-not-found=true

# Optional: Clean up stress_test table from database
echo "[3/3] Stress test stopped"
echo ""
echo "=== Rollback Complete ==="
echo ""
echo "Note: The stress_test table remains in the database."
echo "To remove it, run:"
echo "  kubectl run cleanup --rm -it --image=postgres:15-alpine --restart=Never -- \\"
echo "    psql -h retail-store-orders.cluster-cfkkvgfaqokl.us-east-1.rds.amazonaws.com \\"
echo "    -U root -d orders -c 'DROP TABLE IF EXISTS stress_test;'"
echo ""
echo "RDS metrics should return to normal within 1-2 minutes."
