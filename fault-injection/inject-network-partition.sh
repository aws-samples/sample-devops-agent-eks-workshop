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
echo ""
echo "Expected symptoms:"
echo "  - UI page loads normally"
echo "  - Add to cart / checkout fails with timeout"
echo "  - 504 Gateway timeout errors in ALB logs"
echo "  - Increased error rate in UI pod logs"
echo "  - Prometheus: request_failures increase, success_rate drop"
echo ""
echo "Test the partition:"
echo "  # From UI pod (should fail/timeout):"
echo "  kubectl exec -n ui -it \$(kubectl get pod -n ui -o name | head -1) -- curl -v --max-time 5 http://carts.carts.svc.cluster.local/carts"
echo ""
echo "  # From another namespace (should work):"
echo "  kubectl run test-curl --rm -it --image=curlimages/curl --restart=Never -- curl -v --max-time 5 http://carts.carts.svc.cluster.local/carts"
echo ""
echo "Monitor:"
echo "  kubectl logs -f -n ui -l app.kubernetes.io/name=ui --tail=50"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-network-partition.sh"
