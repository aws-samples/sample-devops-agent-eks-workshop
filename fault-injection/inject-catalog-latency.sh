#!/bin/bash
# Catalog Service Fault Injection Script
# Injects latency (300-500ms) and reduces CPU by 50% to simulate production degradation

set -e

NAMESPACE="catalog"
DEPLOYMENT="catalog"
BACKUP_FILE="fault-injection/catalog-original.yaml"

echo "=== Catalog Service Fault Injection ==="
echo "Target: $DEPLOYMENT in namespace $NAMESPACE"
echo ""

# Step 1: Backup current deployment
echo "[1/4] Backing up current deployment..."
kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
echo "  Backup saved to: $BACKUP_FILE"

# Step 2: Create ConfigMap for latency injection script
echo "[2/4] Creating latency injection sidecar configuration..."
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
    apk add --no-cache iproute2 >/dev/null 2>&1 || true
    
    # Add latency to eth0 interface - 400ms +/- 100ms (300-500ms range)
    tc qdisc add dev eth0 root netem delay 400ms 100ms distribution normal 2>/dev/null || \
    tc qdisc change dev eth0 root netem delay 400ms 100ms distribution normal
    
    echo "Latency injection active: 300-500ms on outbound traffic"
    
    # Keep container running and log periodically
    while true; do
      echo "\$(date): Latency injection running - 400ms +/- 100ms"
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
          "cpu": "50m",
          "memory": "32Mi"
        },
        "requests": {
          "cpu": "10m", 
          "memory": "16Mi"
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
echo "  - CPU: Reduced from 256m to 128m (50% reduction)"
echo ""
echo "Expected observable symptoms:"
echo "  - p99 latency spikes in Prometheus/CloudWatch"
echo "  - CPU throttling metrics elevated"
echo "  - Increased response times in application logs"
echo "  - Potential timeout errors from dependent services"
echo ""
echo "To verify injection:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=catalog -c latency-injector"
echo ""
echo "To rollback:"
echo "  ./fault-injection/rollback-catalog.sh"
