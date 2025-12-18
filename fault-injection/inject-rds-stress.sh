#!/bin/bash
# RDS PostgreSQL Performance Degradation Script - Heavy Load Version
# Creates significant CPU spikes, lock contention, and slow queries

set -e

NAMESPACE="orders"
REGION="${AWS_REGION:-us-east-1}"

# Auto-discover RDS PostgreSQL endpoint
echo "=== RDS Performance Degradation Injection (Heavy) ==="
echo ""
echo "[0/2] Discovering RDS PostgreSQL endpoint..."

# Find PostgreSQL RDS instance (port 5432)
DB_HOST=$(AWS_PAGER="" aws rds describe-db-instances --region $REGION \
  --query "DBInstances[?Endpoint.Port==\`5432\`].Endpoint.Address" \
  --output text 2>/dev/null | head -1)

if [ -z "$DB_HOST" ] || [ "$DB_HOST" == "None" ]; then
  echo "ERROR: No PostgreSQL RDS instance found in region $REGION"
  exit 1
fi

DB_PORT="5432"
DB_NAME="orders"
DB_USER="root"

echo "  Found: $DB_HOST"
echo ""
echo "Target: $DB_HOST:$DB_PORT/$DB_NAME"
echo ""

# Create the stress test pod with more aggressive queries
echo "[1/2] Deploying heavy RDS stress test pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: rds-stress-scripts
  namespace: $NAMESPACE
data:
  run-stress.sh: |
    #!/bin/bash
    export PGPASSWORD="\$DB_PASS"
    
    echo "Starting HEAVY RDS stress test..."
    echo "Host: \$DB_HOST, DB: \$DB_NAME"
    
    # Create larger stress table
    echo "[1/3] Creating large stress table (100k rows)..."
    psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME <<EOSQL
    DROP TABLE IF EXISTS stress_test;
    CREATE TABLE stress_test (
      id SERIAL PRIMARY KEY,
      data TEXT,
      data2 TEXT,
      data3 TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      random_val NUMERIC,
      category INT
    );
    
    INSERT INTO stress_test (data, data2, data3, random_val, category)
    SELECT 
      md5(random()::text) || md5(random()::text) || md5(random()::text) || md5(random()::text),
      md5(random()::text) || md5(random()::text) || md5(random()::text) || md5(random()::text),
      md5(random()::text) || md5(random()::text) || md5(random()::text) || md5(random()::text),
      random() * 10000000,
      (random() * 100)::int
    FROM generate_series(1, 100000);
    
    -- No indexes to make queries slower
    ANALYZE stress_test;
    EOSQL
    
    echo "[2/3] Table created with 100k rows"
    
    # Heavy CPU query - full table scans with sorting and aggregation
    run_heavy_cpu() {
      while true; do
        psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME -c "
          SELECT 
            s1.category,
            COUNT(*) as cnt,
            AVG(s1.random_val) as avg_val,
            STRING_AGG(SUBSTRING(s1.data, 1, 10), ',' ORDER BY s1.random_val DESC) as agg_data,
            (SELECT COUNT(*) FROM stress_test s2 WHERE s2.category = s1.category AND s2.random_val > s1.random_val) as rank
          FROM stress_test s1
          GROUP BY s1.category, s1.id, s1.random_val, s1.data
          ORDER BY random_val DESC
          LIMIT 1000;
        " > /dev/null 2>&1
      done
    }
    
    # Recursive CTE - very CPU intensive
    run_recursive_stress() {
      while true; do
        psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME -c "
          WITH RECURSIVE heavy AS (
            SELECT id, data, random_val, 1 as depth
            FROM stress_test 
            WHERE id < 100
            UNION ALL
            SELECT s.id, s.data, s.random_val, h.depth + 1
            FROM stress_test s
            JOIN heavy h ON s.category = (h.id % 100)
            WHERE h.depth < 3
          )
          SELECT COUNT(*), AVG(random_val), md5(string_agg(data, ''))
          FROM heavy;
        " > /dev/null 2>&1
        sleep 0.5
      done
    }
    
    # Hash join stress - forces memory pressure
    run_hash_stress() {
      while true; do
        psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME -c "
          SELECT COUNT(*), SUM(a.random_val * b.random_val)
          FROM stress_test a
          CROSS JOIN LATERAL (
            SELECT random_val FROM stress_test b 
            WHERE b.category = a.category 
            ORDER BY random() 
            LIMIT 50
          ) b;
        " > /dev/null 2>&1
      done
    }
    
    # Lock contention with longer holds
    run_lock_stress() {
      while true; do
        psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME -c "
          BEGIN;
          SELECT * FROM stress_test WHERE category = (random()*100)::int FOR UPDATE LIMIT 500;
          UPDATE stress_test SET data = md5(random()::text), random_val = random() * 10000000 
          WHERE id IN (SELECT id FROM stress_test ORDER BY random() LIMIT 200);
          SELECT pg_sleep(0.3);
          COMMIT;
        " > /dev/null 2>&1
      done
    }
    
    # Continuous writes
    run_write_stress() {
      while true; do
        psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME -c "
          INSERT INTO stress_test (data, data2, data3, random_val, category)
          SELECT 
            md5(random()::text) || md5(random()::text),
            md5(random()::text) || md5(random()::text),
            md5(random()::text) || md5(random()::text),
            random() * 10000000,
            (random() * 100)::int
          FROM generate_series(1, 500);
          
          DELETE FROM stress_test WHERE id IN (
            SELECT id FROM stress_test ORDER BY random() LIMIT 300
          );
        " > /dev/null 2>&1
      done
    }
    
    echo "[3/3] Starting stress workers..."
    
    # Start many parallel workers
    for i in {1..6}; do run_heavy_cpu & done
    for i in {1..3}; do run_recursive_stress & done
    for i in {1..2}; do run_hash_stress & done
    for i in {1..4}; do run_lock_stress & done
    for i in {1..3}; do run_write_stress & done
    
    echo ""
    echo "=== Heavy stress test running ==="
    echo "Workers: 6 CPU + 3 recursive + 2 hash + 4 lock + 3 write = 18 total"
    echo "Press Ctrl+C or delete pod to stop"
    
    wait
---
apiVersion: v1
kind: Pod
metadata:
  name: rds-stress-test
  namespace: $NAMESPACE
  labels:
    app: rds-stress-test
spec:
  containers:
  - name: stress
    image: postgres:15-alpine
    command: ["/bin/sh", "-c"]
    args:
    - |
      cp /scripts/run-stress.sh /tmp/run-stress.sh
      chmod +x /tmp/run-stress.sh
      /tmp/run-stress.sh
    env:
    - name: DB_HOST
      value: "$DB_HOST"
    - name: DB_PORT
      value: "$DB_PORT"
    - name: DB_NAME
      value: "$DB_NAME"
    - name: DB_USER
      value: "$DB_USER"
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: orders-db
          key: RETAIL_ORDERS_PERSISTENCE_PASSWORD
    volumeMounts:
    - name: scripts
      mountPath: /scripts
    resources:
      limits:
        cpu: "1"
        memory: "512Mi"
      requests:
        cpu: "200m"
        memory: "256Mi"
  volumes:
  - name: scripts
    configMap:
      name: rds-stress-scripts
      defaultMode: 0755
  restartPolicy: Never
EOF

echo "[2/2] Waiting for stress pod to start..."
kubectl wait --for=condition=Ready pod/rds-stress-test -n $NAMESPACE --timeout=120s || true

sleep 5
kubectl logs rds-stress-test -n $NAMESPACE --tail=20

echo ""
echo "=== RDS Heavy Stress Injection Complete ==="
echo ""
echo "Expected symptoms (visible in 2-3 minutes):"
echo "  - CPU utilization: 70-90%"
echo "  - Database connections: 30-50"
echo "  - Slow queries in Performance Insights"
echo "  - Lock wait events"
echo ""
echo "Monitor:"
echo "  kubectl logs -f rds-stress-test -n $NAMESPACE"
echo "  AWS Console > RDS > Performance Insights"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-rds-stress.sh"
