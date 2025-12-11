#!/bin/bash
# Cart Memory Leak Injection Script
# Adds a memory-consuming sidecar and reduces memory limits to trigger OOMKill

set -e

NAMESPACE="carts"
DEPLOYMENT="carts"
BACKUP_FILE="fault-injection/carts-original.yaml"

echo "=== Cart Memory Leak Injection ==="
echo "Target: $DEPLOYMENT in namespace $NAMESPACE"
echo ""

# Step 1: Backup current deployment
echo "[1/3] Backing up current deployment..."
kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
echo "  Backup saved to: $BACKUP_FILE"

# Step 2: Create ConfigMap for memory leak script
echo "[2/3] Creating memory leak sidecar configuration..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: memory-leak-script
  namespace: $NAMESPACE
data:
  leak-memory.sh: |
    #!/bin/sh
    echo "Starting memory leak simulation..."
    
    # Create a growing array to consume memory
    # This simulates a realistic memory leak pattern
    LEAK_DIR="/tmp/memleak"
    mkdir -p \$LEAK_DIR
    
    counter=0
    while true; do
      # Allocate ~10MB per iteration
      dd if=/dev/zero of=\$LEAK_DIR/leak_\$counter bs=1M count=10 2>/dev/null
      counter=\$((counter + 1))
      
      # Calculate total leaked memory
      total_mb=\$((counter * 10))
      echo "\$(date): Memory leaked: \${total_mb}MB (iteration \$counter)"
      
      # Slow leak - 10MB every 5 seconds
      sleep 5
      
      # After ~150MB, start aggressive leak (faster)
      if [ \$total_mb -gt 150 ]; then
        sleep 1
      fi
    done
EOF

# Step 3: Patch deployment with memory leak sidecar and reduced limits
echo "[3/3] Patching deployment with memory leak sidecar..."
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "256Mi"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "256Mi"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "memory-leaker",
      "image": "alpine:3.18",
      "command": ["/bin/sh", "-c"],
      "args": ["cp /scripts/leak-memory.sh /tmp/leak.sh && chmod +x /tmp/leak.sh && /tmp/leak.sh"],
      "resources": {
        "limits": {
          "cpu": "50m",
          "memory": "200Mi"
        },
        "requests": {
          "cpu": "10m",
          "memory": "50Mi"
        }
      },
      "volumeMounts": [
        {
          "name": "leak-script",
          "mountPath": "/scripts"
        },
        {
          "name": "leak-storage",
          "mountPath": "/tmp/memleak"
        }
      ]
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "leak-script",
      "configMap": {
        "name": "memory-leak-script",
        "defaultMode": 493
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "leak-storage",
      "emptyDir": {
        "medium": "Memory",
        "sizeLimit": "250Mi"
      }
    }
  }
]'

echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s || true

echo ""
echo "=== Memory Leak Injection Complete ==="
echo ""
echo "Injected faults:"
echo "  - Memory leak sidecar: Consumes ~10MB every 5 seconds"
echo "  - Main container memory: Reduced from 512Mi to 256Mi"
echo "  - Sidecar memory limit: 200Mi (will OOMKill around 200MB leaked)"
echo ""
echo "Expected symptoms (within 2-5 minutes):"
echo "  - Pod restarts due to OOMKilled"
echo "  - CrashLoopBackOff status"
echo "  - Increased memory usage in Prometheus/CloudWatch"
echo "  - Cart operation failures in UI"
echo ""
echo "Monitor:"
echo "  watch kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=carts -c memory-leaker -f"
echo "  kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=carts | grep -A5 'Last State'"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-cart-memory-leak.sh"
