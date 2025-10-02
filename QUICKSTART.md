# Innover Platform - Quick Start Guide

## Prerequisites
- Docker and Docker Compose installed
- Ports available: 8000, 8001, 8081, 8082, 6379, 9092, 16686, 26257, 4317

## Starting the Platform

```bash
# Start all services
make up

# Or manually
docker compose up -d --build
```

The platform will automatically:
1. Start CockroachDB 3-node cluster
2. Initialize the cluster
3. Create the `innover` database
4. Start all microservices (6 FastAPI apps + 6 Celery workers)
5. Configure Kong API Gateway with OIDC
6. Start Keycloak with pre-configured realm and users
7. Start Redis, Redpanda (Kafka), Jaeger, and OpenTelemetry Collector

## Verify Everything is Running

```bash
# Quick health check
make health

# Or run comprehensive smoke tests
make smoke-test
```

## Access Points

### Web UIs
- **Keycloak Admin**: http://localhost:8081 (admin/admin)
- **CockroachDB UI**: http://localhost:8082
- **Jaeger Tracing**: http://localhost:16686
- **Kong Admin API**: http://localhost:8001

### API Gateway (Kong Proxy)
All services are accessible through Kong at `http://localhost:8000`:

- **Profile Service**: http://localhost:8000/api/profile/health
- **Payment Service**: http://localhost:8000/api/payment/health
- **Forex Service**: http://localhost:8000/api/fx/health
- **Ledger Service**: http://localhost:8000/api/ledger/health
- **Wallet Service**: http://localhost:8000/api/wallet/health
- **Rule Engine**: http://localhost:8000/api/rules/health

### Pre-configured Users

The Keycloak realm comes with 5 test users (username = password):

| Username | Password | Role |
|----------|----------|------|
| admin | admin | admin |
| ops_user | ops_user | ops_user |
| finance | finance | finance |
| auditor | auditor | auditor |
| user | user | user |

## Getting an Access Token

```bash
# Get token for admin user
curl -s -X POST 'http://localhost:8081/realms/innover/protocol/openid-connect/token' \
  -d 'client_id=kong' \
  -d 'client_secret=kong-secret' \
  -d 'grant_type=password' \
  -d 'username=admin' \
  -d 'password=admin' \
  | python3 -m json.tool

# Save token to file
curl -s -X POST 'http://localhost:8081/realms/innover/protocol/openid-connect/token' \
  -d 'client_id=kong' \
  -d 'client_secret=kong-secret' \
  -d 'grant_type=password' \
  -d 'username=admin' \
  -d 'password=admin' \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])" > /tmp/token.txt
```

## Testing Protected Endpoints

```bash
# Get token
TOKEN=$(curl -s -X POST 'http://localhost:8081/realms/innover/protocol/openid-connect/token' \
  -d 'client_id=kong' \
  -d 'client_secret=kong-secret' \
  -d 'grant_type=password' \
  -d 'username=admin' \
  -d 'password=admin' \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Call protected endpoint
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/profile/health
```

## Testing Celery Workers

```bash
# Test profile worker
make test-worker-profile

# View worker logs
make logs-profile-worker

# Check all worker status
make workers
```

## Database Access

```bash
# Open CockroachDB SQL shell
make db-shell

# Or manually
docker compose exec cockroach1 /cockroach/cockroach sql --insecure --host=cockroach1:26257 --database=innover
```

## Redis Access

```bash
# Open Redis CLI
make redis-cli

# Or manually
docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD"'
```

## Kafka/Redpanda

```bash
# List topics
make kafka-topics

# Create a topic
docker compose exec redpanda rpk topic create my-events --brokers redpanda:9092

# Produce a message
echo "test message" | docker compose exec -T redpanda rpk topic produce my-events --brokers redpanda:9092

# Consume messages
docker compose exec redpanda rpk topic consume my-events --brokers redpanda:9092
```

## Useful Commands

```bash
make up              # Start all services
make down            # Stop and remove containers + volumes
make ps              # Show container status
make health          # Show health status
make logs            # Tail all logs
make logs-<service>  # Tail specific service logs
make restart-<svc>   # Restart a service
make smoke-test      # Run comprehensive tests
make urls            # Show all service URLs
make nuke            # Complete cleanup (removes images too)
```

## Troubleshooting

### CockroachDB won't start
The cluster needs all 3 nodes to be reachable before initialization. Wait 60 seconds for the health checks to stabilize.

```bash
# Check CockroachDB logs
docker compose logs cockroach1 cockroach2 cockroach3

# Check init logs
docker compose logs cockroach-init-cluster
```

### Celery workers showing unhealthy
Workers take 30 seconds to start and register with Redis. The healthcheck uses `celery inspect ping` which requires the worker to be fully initialized.

```bash
# Check worker logs
docker compose logs profile-worker

# Manually test worker
docker compose exec profile python -c "from celery_app import celery_app; print(celery_app.control.inspect().active())"
```

### Kong can't reach services
Ensure all services are healthy before testing Kong routes:

```bash
make health
```

### Keycloak realm not loading
Check Keycloak logs for import errors:

```bash
docker compose logs keycloak | grep -i error
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Kong API Gateway                         │
│                  (OIDC Authentication)                       │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Profile    │    │   Payment    │    │    Forex     │
│   (FastAPI)  │    │   (FastAPI)  │    │   (FastAPI)  │
└──────────────┘    └──────────────┘    └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│Profile Worker│    │Payment Worker│    │ Forex Worker │
│   (Celery)   │    │   (Celery)   │    │   (Celery)   │
└──────────────┘    └──────────────┘    └──────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ CockroachDB  │    │    Redis     │    │   Redpanda   │
│  (3 nodes)   │    │  (Broker)    │    │   (Kafka)    │
└──────────────┘    └──────────────┘    └──────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                            ▼
                ┌──────────────────────┐
                │  OpenTelemetry       │
                │  Collector + Jaeger  │
                └──────────────────────┘
```

## Next Steps

1. **Add Business Logic**: Implement actual endpoints in `services/<name>/app/main.py`
2. **Define Protobuf APIs**: Edit `.proto` files in `protos/<domain>/v1/` and run `make proto`
3. **Add Celery Tasks**: Implement async tasks in `services/<name>/app/tasks.py`
4. **Configure RBAC**: Add role-based access control in Kong or service layer using the `x-roles` header
5. **Add Database Models**: Use SQLAlchemy or similar ORM with CockroachDB connection
6. **Implement Event Streaming**: Use Redpanda for event-driven architecture

## Support

For issues or questions, check:
- CockroachDB docs: https://www.cockroachlabs.com/docs/
- Kong docs: https://docs.konghq.com/
- Keycloak docs: https://www.keycloak.org/documentation
- Celery docs: https://docs.celeryq.dev/
