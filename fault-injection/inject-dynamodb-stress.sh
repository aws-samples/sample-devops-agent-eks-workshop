#!/bin/bash
# DynamoDB Stress Test Injection (Read-Only)
# Deploys a stress pod that hammers DynamoDB with massive read requests
# No data is written, so rollback is instant (just delete the pod)

set -e

NAMESPACE="carts"
TABLE_NAME="retail-store-carts"
REGION="${AWS_REGION:-us-east-1}"

echo "=== DynamoDB Stress Test Injection (Read-Only) ==="
echo ""
echo "Target Table: $TABLE_NAME"
echo "Region: $REGION"
echo ""

# Step 1: Verify table
echo "[1/4] Verifying DynamoDB table..."
TABLE_STATUS=$(aws dynamodb describe-table --table-name $TABLE_NAME --region $REGION --query 'Table.TableStatus' --output text 2>/dev/null)
if [ "$TABLE_STATUS" != "ACTIVE" ]; then
  echo "ERROR: Table $TABLE_NAME not found or not active"
  exit 1
fi
echo "  Table status: $TABLE_STATUS"

# Step 2: Create ConfigMap with Python stress script
echo "[2/4] Creating stress test ConfigMap..."
kubectl apply -f - <<'CONFIGMAP_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: dynamodb-stress-script
  namespace: carts
data:
  stress.py: |
    import boto3
    import threading
    import time
    import os
    from concurrent.futures import ThreadPoolExecutor

    TABLE_NAME = os.environ.get('TABLE_NAME', 'retail-store-carts')
    REGION = os.environ.get('AWS_REGION', 'us-east-1')

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)

    scan_count = 0
    query_count = 0
    get_count = 0
    lock = threading.Lock()

    def scan_worker(worker_id):
        """Full table scans - very expensive on read capacity"""
        global scan_count
        while True:
            try:
                # Full table scan with large limit
                response = table.scan(Limit=1000)
                with lock:
                    scan_count += 1
                    if scan_count % 50 == 0:
                        print(f"Scans: {scan_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e) or 'ProvisionedThroughputExceeded' in str(e):
                    print(f"THROTTLED on scan! {e}", flush=True)
            time.sleep(0.01)

    def query_worker(worker_id):
        """Query on GSI - consumes read capacity"""
        global query_count
        while True:
            try:
                # Query the customerId GSI with a fake customer ID
                response = table.query(
                    IndexName='idx_global_customerId',
                    KeyConditionExpression='customerId = :cid',
                    ExpressionAttributeValues={':cid': f'stress-customer-{worker_id}'}
                )
                with lock:
                    query_count += 1
                    if query_count % 100 == 0:
                        print(f"Queries: {query_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e) or 'ProvisionedThroughputExceeded' in str(e):
                    print(f"THROTTLED on query! {e}", flush=True)
            time.sleep(0.005)

    def get_worker(worker_id):
        """GetItem requests - fast but still consume capacity"""
        global get_count
        while True:
            try:
                # Try to get non-existent items (still consumes RCU)
                response = table.get_item(Key={'id': f'stress-nonexistent-{worker_id}-{get_count}'})
                with lock:
                    get_count += 1
                    if get_count % 500 == 0:
                        print(f"Gets: {get_count}", flush=True)
            except Exception as e:
                if 'Throttl' in str(e) or 'ProvisionedThroughputExceeded' in str(e):
                    print(f"THROTTLED on get! {e}", flush=True)
            time.sleep(0.001)

    print("=== DynamoDB Read-Only Stress Test ===")
    print(f"Table: {TABLE_NAME}")
    print(f"Region: {REGION}")
    print("Starting 30 scan workers, 30 query workers, 40 get workers...")
    print("NOTE: Read-only - no cleanup needed on rollback!")
    print("")

    with ThreadPoolExecutor(max_workers=100) as executor:
        for i in range(30):
            executor.submit(scan_worker, i)
        for i in range(30):
            executor.submit(query_worker, i)
        for i in range(40):
            executor.submit(get_worker, i)
        while True:
            time.sleep(30)
            print(f"Status: {scan_count} scans, {query_count} queries, {get_count} gets", flush=True)
CONFIGMAP_EOF

# Step 3: Create stress pod
echo "[3/4] Deploying stress test pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: dynamodb-stress-test
  namespace: $NAMESPACE
  labels:
    app: dynamodb-stress-test
    fault-injection: "true"
spec:
  serviceAccountName: carts
  containers:
  - name: stress
    image: python:3.11-slim
    command: ["bash", "-c", "pip install boto3 --quiet && python /scripts/stress.py"]
    env:
    - name: TABLE_NAME
      value: "$TABLE_NAME"
    - name: AWS_REGION
      value: "$REGION"
    volumeMounts:
    - name: stress-script
      mountPath: /scripts
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
      limits:
        cpu: "2000m"
        memory: "1Gi"
  volumes:
  - name: stress-script
    configMap:
      name: dynamodb-stress-script
  restartPolicy: Never
EOF

# Step 4: Wait for pod
echo "[4/4] Waiting for stress pod to start..."
kubectl wait --for=condition=Ready pod/dynamodb-stress-test -n $NAMESPACE --timeout=120s 2>/dev/null || true
sleep 5

echo ""
echo "=== DynamoDB Stress Test Active (Read-Only) ==="
echo ""
echo "Rollback (instant - no data cleanup needed):"
echo "  ./~/fault-injection/rollback-dynamodb-stress.sh"
