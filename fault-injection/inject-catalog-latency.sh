#!/bin/bash
# Catalog Service Fault Injection Script
# Injects latency (300-500ms), reduces CPU limit, AND generates CPU stress

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="~/fault-injection/catalog-original.yaml"

echo "=== Catalog Service Fault Injection (Network + CPU Stress) ==="
echo "Target: $DEPLOYMENT in namespace $NAMESPACE"
echo ""

# Step 1: Check if backup already exists (don't overwrite clean backup with injected state)
if [ -f "$BACKUP_FILE" ]; then
  # Check if current deployment has the sidecar (meaning injection is active)
  SIDECAR_EXISTS=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[?(@.name=="latency-injector")].name}' 2>/dev/null)
  if [ -n "$SIDECAR_EXISTS" ]; then
    echo "[1/4] Backup exists and injection appears active - keeping existing backup"
  else
    echo "[1/4] Backing up current (clean) deployment..."
    kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
    echo "  Backup saved to: $BACKUP_FILE"
  fi
else
  echo "[1/4] Backing up current deployment..."
  kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
  echo "  Backup saved to: $BACKUP_FILE"
fi

# Step 2: Create ConfigMap for latency AND CPU stress injection
echo "[2/4] Creating latency + CPU stress sidecar configuration..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: latency-injector-script
  namespace: $NAMESPACE
data:
  inject-latency.sh: |
    #!/bin/sh
    # Add random latency (300-500ms) to outbound traffic using tc
    apk add --no-cache iproute2 stress-ng >/dev/null 2>&1 || true
    
    # Add latency to eth0 interface - 400ms +/- 100ms (300-500ms range)
    tc qdisc add dev eth0 root netem delay 400ms 100ms distribution normal 2>/dev/null || \
    tc qdisc change dev eth0 root netem delay 400ms 100ms distribution normal
    
    echo "Latency injection active: 300-500ms on outbound traffic"
    echo "Starting EXTREME CPU stress workers..."
    
    # Start extreme CPU stress - 8 workers at 100% load, aggressive settings
    stress-ng --cpu 8 --cpu-load 100 --cpu-method all --aggressive --timeout 0 &
    
    # Keep container running and log periodically
    while true; do
      echo "\$(date): Latency + CPU stress running"
      sleep 30
    done
EOF

# Step 3: Patch deployment with latency sidecar and reduced CPU
echo "[3/4] Patching deployment with fault injection..."
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/resources/limits/cpu",
    "value": "128m"
  },
  {
    "op": "replace", 
    "path": "/spec/template/spec/containers/0/resources/requests/cpu",
    "value": "128m"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "latency-injector",
      "image": "alpine:3.18",
      "command": ["/bin/sh", "-c"],
      "args": ["cp /scripts/inject-latency.sh /tmp/inject.sh && chmod +x /tmp/inject.sh && /tmp/inject.sh"],
      "securityContext": {
        "capabilities": {
          "add": ["NET_ADMIN"]
        }
      },
      "resources": {
        "limits": {
          "cpu": "4000m",
          "memory": "512Mi"
        },
        "requests": {
          "cpu": "2000m", 
          "memory": "256Mi"
        }
      },
      "volumeMounts": [
        {
          "name": "latency-script",
          "mountPath": "/scripts"
        }
      ]
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "latency-script",
      "configMap": {
        "name": "latency-injector-script",
        "defaultMode": 493
      }
    }
  }
]'

# Step 4: Wait for rollout
echo "[4/4] Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

echo ""
echo "=== Fault Injection Complete ==="
echo ""
echo "Injected faults:"
echo "  - Latency: 300-500ms on outbound HTTP calls"
echo "  - CPU limit: Main container reduced to 128m (throttling)"
echo "  - CPU stress: 8 workers at 100% load with 4000m limit (EXTREME)"
echo "  - Expected: HPA will scale to max (10 pods), all at high CPU"

# Source verification functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/verify-functions.sh" 2>/dev/null || true

# Step 5: Check pod status
echo ""
echo "[5/7] Checking pod status..."
check_pod_status "$NAMESPACE" "app.kubernetes.io/name=catalog" 2>/dev/null || kubectl get pods -n $NAMESPACE --no-headers | sed 's/^/    /'

# Step 6: Check resource usage
echo ""
echo "[6/7] Checking resource usage (CPU throttling)..."
check_resource_usage "$NAMESPACE" "app.kubernetes.io/name=catalog" 2>/dev/null || kubectl top pods -n $NAMESPACE 2>/dev/null | sed 's/^/    /' || echo "    Metrics not available"

# Step 7: Test latency
echo ""
echo "[7/7] Testing response latency..."

echo ""
echo "  Measuring catalog service response time:"
kubectl port-forward -n $NAMESPACE svc/catalog 8085:80 &>/dev/null &
PF_PID=$!
sleep 2

if kill -0 $PF_PID 2>/dev/null; then
  for i in 1 2 3; do
    START=$(date +%s%3N)
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost:8085/catalogue 2>/dev/null)
    END=$(date +%s%3N)
    LATENCY=$((END - START))
    echo "    Request $i: HTTP $STATUS (${LATENCY}ms)"
  done
  kill $PF_PID 2>/dev/null
else
  echo "    Could not port-forward to catalog"
fi

echo ""
echo "=== Fault Injection Active ==="
echo ""
echo "Check latency + stress injector logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=catalog -c latency-injector --tail=10"
echo ""
echo "Rollback:"
echo "  ./~/fault-injection/rollback-catalog.sh"
