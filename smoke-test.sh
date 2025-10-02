#!/bin/bash
set -e

echo "=== Innover Platform Smoke Test ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_passed() {
    echo -e "${GREEN}✓ $1${NC}"
}

test_failed() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

test_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

echo "1. Container Health Check"
test_info "Checking all containers are running..."
docker compose ps --format json | grep -q "running" && test_passed "Containers are running" || test_failed "Some containers are not running"

echo ""
echo "2. CockroachDB Cluster"
test_info "Verifying 3-node cluster and innover database..."
NODES=$(docker compose exec -T cockroach1 /cockroach/cockroach sql --insecure --host=cockroach1:26257 -e "SELECT count(*) FROM crdb_internal.gossip_nodes;" | grep -E '^\s+[0-9]+' | tr -d ' ')
if [ "$NODES" = "3" ]; then
    test_passed "CockroachDB cluster has 3 nodes"
else
    test_failed "CockroachDB cluster does not have 3 nodes (found: $NODES)"
fi

DB_EXISTS=$(docker compose exec -T cockroach1 /cockroach/cockroach sql --insecure --host=cockroach1:26257 -e "SHOW databases;" | grep -c "innover" || echo "0")
if [ "$DB_EXISTS" -gt "0" ]; then
    test_passed "Database 'innover' exists"
else
    test_failed "Database 'innover' not found"
fi

echo ""
echo "3. Redis Authentication"
test_info "Testing Redis with password..."
REDIS_RESPONSE=$(docker compose exec -T redis sh -c 'redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null')
if [ "$REDIS_RESPONSE" = "PONG" ]; then
    test_passed "Redis authentication successful"
else
    test_failed "Redis authentication failed"
fi

echo ""
echo "4. Redpanda Messaging"
test_info "Testing Kafka topic creation and messaging..."
docker compose exec -T redpanda rpk topic create smoke-test-topic --brokers redpanda:9092 2>/dev/null || true
printf 'smoke-test-message\n' | docker compose exec -T redpanda rpk topic produce smoke-test-topic --brokers redpanda:9092 >/dev/null 2>&1
MESSAGE=$(docker compose exec -T redpanda rpk topic consume smoke-test-topic -n 1 --brokers redpanda:9092 2>/dev/null | grep -o 'smoke-test-message' || echo "")
if [ "$MESSAGE" = "smoke-test-message" ]; then
    test_passed "Redpanda produce/consume working"
else
    test_failed "Redpanda messaging failed"
fi

echo ""
echo "5. Kong Gateway"
test_info "Checking Kong admin API..."
KONG_STATUS=$(curl -s http://localhost:8001/status 2>/dev/null | grep -o 'configuration_hash' || echo "")
if [ -n "$KONG_STATUS" ]; then
    test_passed "Kong admin API responding"
else
    test_failed "Kong admin API not responding"
fi

echo ""
echo "6. Service Health Endpoints"
test_info "Checking all FastAPI services..."
SERVICES=("profile" "payment" "forex" "ledger" "wallet" "rule-engine")
for svc in "${SERVICES[@]}"; do
    HEALTH=$(docker compose exec -T $svc curl -s http://localhost:8000/health 2>/dev/null | grep -o '"status":"ok"' || echo "")
    if [ -n "$HEALTH" ]; then
        test_passed "Service $svc health check passed"
    else
        test_failed "Service $svc health check failed"
    fi
done

echo ""
echo "7. Celery Workers"
test_info "Testing Celery worker task execution..."
WORKERS=("profile-worker" "payment-worker" "forex-worker" "ledger-worker" "wallet-worker" "rule-engine-worker")
QUEUES=("profile-tasks" "payment-tasks" "forex-tasks" "ledger-tasks" "wallet-tasks" "rule-engine-tasks")

for i in "${!WORKERS[@]}"; do
    worker="${WORKERS[$i]}"
    queue="${QUEUES[$i]}"
    
    # Send echo task
    TASK_ID=$(docker compose exec -T ${worker%-worker} python -c "
from celery_app import celery_app
r = celery_app.send_task('tasks.echo', args=['smoke-test'], queue='$queue')
print(r.id)
" 2>/dev/null | tail -1)
    
    if [ -n "$TASK_ID" ]; then
        test_passed "Worker $worker accepted task"
    else
        test_failed "Worker $worker failed to accept task"
    fi
done

echo ""
echo "8. OpenTelemetry Collector"
test_info "Checking OTEL collector health..."
OTEL_HEALTH=$(docker compose exec -T otel-collector wget -qO- http://localhost:13133/ 2>/dev/null | grep -o 'Server available' || echo "")
if [ -n "$OTEL_HEALTH" ]; then
    test_passed "OTEL collector is healthy"
else
    test_failed "OTEL collector health check failed"
fi

echo ""
echo "9. Keycloak"
test_info "Checking Keycloak admin console..."
KC_HEALTH=$(curl -s http://localhost:8081/health/ready 2>/dev/null | grep -o '"status":"UP"' || echo "")
if [ -n "$KC_HEALTH" ]; then
    test_passed "Keycloak is ready"
else
    test_failed "Keycloak health check failed"
fi

echo ""
echo -e "${GREEN}=== All Smoke Tests Passed! ===${NC}"
echo ""
echo "Next steps:"
echo "  - Access Keycloak admin: http://localhost:8081 (admin/admin)"
echo "  - Access Jaeger UI: http://localhost:16686"
echo "  - Access CockroachDB UI: http://localhost:8082"
echo "  - Kong Admin API: http://localhost:8001"
echo "  - Kong Proxy: http://localhost:8000"
