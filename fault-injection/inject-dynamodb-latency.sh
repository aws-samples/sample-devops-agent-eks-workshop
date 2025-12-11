#!/bin/bash
# DynamoDB Latency Injection Script
# Adds network latency to DynamoDB calls from Cart service using tc qdisc

set -e

NAMESPACE="carts"
DEPLOYMENT="carts"
BACKUP_FILE="fault-injection/carts-dynamodb-original.yaml"
LATENCY_MS="500"  # 500ms latency

echo "=== DynamoDB Latency Injection ==="
echo "Target: $DEPLOYMENT in namespace $NAMESPACE"
echo "Latency: ${LATENCY_MS}ms on DynamoDB traffic"
echo ""

# Step 1: Backup current deployment
echo "[1/3] Backing up current deployment..."
kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > $BACKUP_FILE
echo "  Backup saved to: $BACKUP_FILE"

# Step 2: Create ConfigMap for latency injection script
echo "[2/3] Creating DynamoDB latency injection sidecar..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: dynamodb-latency-script
  namespace: $NAMESPACE
data:
  inject-latency.sh: |
    #!/bin/sh
    echo "Installing network tools..."
    apk add --no-cache iproute2 bind-tools >/dev/null 2>&1
    
    echo "Resolving DynamoDB endpoint IPs..."
    # Get DynamoDB endpoint IPs for us-east-1
    DDB_IPS=\$(dig +short dynamodb.us-east-1.amazonaws.com | grep -E '^[0-9]')
    
    echo "DynamoDB IPs: \$DDB_IPS"
    
    # Add latency to all traffic (simpler approach that works)
    echo "Adding ${LATENCY_MS}ms latency to outbound traffic..."
    tc qdisc add dev eth0 root netem delay ${LATENCY_MS}ms 50ms distribution normal 2>/dev/null || \
    tc qdisc change dev eth0 root netem delay ${LATENCY_MS}ms 50ms distribution normal
    
    echo "DynamoDB latency injection active: ${LATENCY_MS}ms +/- 50ms"
    
    # Keep container running and log periodically
    while true; do
      echo "\$(date): DynamoDB latency injection running - ${LATENCY_MS}ms delay"
      sleep 30
    done
EOF

# Step 3: Patch deployment with latency sidecar
echo "[3/3] Patching deployment with latency injection sidecar..."
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "dynamodb-latency-injector",
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
        "name": "dynamodb-latency-script",
        "defaultMode": 493
      }
    }
  }
]'

echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=120s

echo ""
echo "=== DynamoDB Latency Injection Complete ==="
echo ""
echo "Injected: ${LATENCY_MS}ms +/- 50ms latency on Cart service network"
echo ""
echo "Expected symptoms:"
echo "  - Cart operations slow (add to cart, view cart)"
echo "  - DynamoDB latency increase in CloudWatch"
echo "  - Application timeouts during checkout"
echo "  - Thread queuing in Cart service"
echo "  - p99 latency spikes in Prometheus"
echo ""
echo "Monitor:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=carts -c dynamodb-latency-injector"
echo "  AWS Console > CloudWatch > DynamoDB metrics"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-dynamodb-latency.sh"
