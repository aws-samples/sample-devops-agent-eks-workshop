#!/bin/bash
# Network Partition Injection Script
# Blocks traffic from UI pods to Cart service using Kubernetes NetworkPolicy

set -e

echo "=== Network Partition Injection: UI -> Cart ==="
echo ""

# Step 1: Apply NetworkPolicy to block UI -> Cart traffic
echo "[1/2] Applying NetworkPolicy to block UI -> Cart traffic..."
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-ui-to-carts
  namespace: carts
  labels:
    fault-injection: "true"
    scenario: "network-partition"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: carts
      app.kubernetes.io/owner: retail-store-sample
  policyTypes:
  - Ingress
  ingress:
  # Allow traffic from all sources EXCEPT UI namespace
  - from:
    - namespaceSelector:
        matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values:
          - ui
EOF

echo "[2/2] Verifying NetworkPolicy..."
kubectl get networkpolicy -n carts

echo ""
echo "=== Network Partition Injection Complete ==="
echo ""
echo "Blocked: UI namespace -> Cart service"
echo "Allowed: All other services -> Cart service"

# Source verification functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/verify-functions.sh" 2>/dev/null || true

# Step 3: Verify the partition
echo ""
echo "[3/4] Verifying network partition..."

echo ""
echo "  Testing connectivity from UI to Carts (should FAIL):"
UI_POD=$(kubectl get pod -n ui -l app.kubernetes.io/name=ui -o name 2>/dev/null | head -1)
if [ -n "$UI_POD" ]; then
  RESULT=$(kubectl exec -n ui $UI_POD -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://carts.carts.svc.cluster.local/carts 2>/dev/null || echo "timeout")
  if [ "$RESULT" == "timeout" ] || [ "$RESULT" == "000" ]; then
    echo "    ✓ Connection blocked as expected (timeout)"
  else
    echo "    ⚠ Connection returned HTTP $RESULT (expected timeout)"
  fi
else
  echo "    - No UI pod found"
fi

echo ""
echo "  Testing connectivity from Checkout to Carts (should WORK):"
CHECKOUT_POD=$(kubectl get pod -n checkout -l app.kubernetes.io/name=checkout -o name 2>/dev/null | head -1)
if [ -n "$CHECKOUT_POD" ]; then
  RESULT=$(kubectl exec -n checkout $CHECKOUT_POD -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://carts.carts.svc.cluster.local/carts 2>/dev/null || echo "failed")
  if [ "$RESULT" == "200" ] || [ "$RESULT" == "201" ]; then
    echo "    ✓ Connection successful (HTTP $RESULT)"
  else
    echo "    ⚠ Connection returned: $RESULT"
  fi
else
  echo "    - No Checkout pod found"
fi

# Step 4: Generate traffic and check logs
echo ""
echo "[4/4] Generating traffic to trigger errors..."

# Generate traffic via UI service
generate_traffic_burst "ui" "ui" 8083 "/" 5 2>/dev/null || true

echo ""
echo "  Checking UI logs for cart errors:"
kubectl logs -n ui -l app.kubernetes.io/name=ui --tail=50 2>/dev/null | grep -iE "cart|timeout|error" | tail -5 | sed 's/^/    /' || echo "    No cart-related errors yet"

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Check logs:"
echo "  kubectl logs -n ui -l app.kubernetes.io/name=ui --tail=50"
echo ""
echo "Rollback:"
echo "  ./~/fault-injection/rollback-network-partition.sh"
