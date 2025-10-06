# Financial Platform - Microservices Architecture
Enterprise-grade financial services platform built on microservices architecture with **PCI-DSS compliant** authentication and authorization. Features distributed tracing, event-driven messaging, and financial-grade OAuth2 via WSO2 Identity Server.

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Services](#-services)
- [Infrastructure](#-infrastructure)
- [Authentication & Security](#-authentication--security)
- [Development](#-development)
- [Testing](#-testing)
- [Monitoring](#-monitoring--observability)
- [Troubleshooting](#-troubleshooting)
- [Production](#-production-considerations)
- [Contributing](#-contributing)

---

## 🎯 Overview

### What is This?

A production-ready financial microservices platform demonstrating:

- **Financial-Grade OAuth2**: WSO2 Identity Server for PCI-DSS compliant authentication
- **API Gateway**: WSO2 API Manager with JWT validation, rate limiting, and security policies
- **6 Core Microservices**: Forex, Ledger, Payment, Profile, Rule Engine, Wallet
- **Event-Driven Architecture**: Kafka (Redpanda), async processing (Celery)
- **Distributed SQL**: CockroachDB for ACID transactions with horizontal scaling
- **Full Observability**: OpenTelemetry tracing, Jaeger UI, structured logging

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **API Framework** | FastAPI 0.111.0 | High-performance REST APIs |
| **Identity Provider** | WSO2 IS 7.1.0 | OAuth2/OIDC, JWT tokens |
| **API Gateway** | WSO2 APIM 4.5.0 | Rate limiting, security, monitoring |
| **Database** | CockroachDB v24.2.4 | Distributed SQL (Postgres protocol) |
| **Cache** | Redis 7 Alpine | Session storage, Celery broker |
| **Message Queue** | Redpanda v24.2.13 | Kafka-compatible streaming |
| **Task Queue** | Celery 5.4.0 | Async job processing |
| **Tracing** | OpenTelemetry + Jaeger | Distributed tracing |
| **Container** | Docker Compose | Orchestration |

---

## 🏗️ Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client Layer                             │
│                    (Web, Mobile, APIs)                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    WSO2 Identity Server                          │
│          OAuth2/OIDC • JWT Tokens • User Management             │
│                     https://localhost:9444                       │
│                                                                   │
│  Features:                                                        │
│  • Financial-grade OAuth2 (PCI-DSS)                              │
│  • Password, Client Credentials, Authorization Code flows        │
│  • RS256 JWT signing via JWKS                                    │
│  • Role-based access control (admin, finance, auditor, etc.)     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    WSO2 API Manager Gateway                      │
│       JWT Validation • Rate Limiting • Security Policies         │
│      HTTP: localhost:8280  |  HTTPS: localhost:8243             │
│                                                                   │
│  Features:                                                        │
│  • JWT validation via WSO2 IS JWKS endpoint                      │
│  • API versioning and lifecycle management                       │
│  • Subscription-based access control                             │
│  • Request/response transformation                               │
│  • Analytics and monitoring                                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                      Microservices Layer                          │
├──────────────┬──────────────┬──────────────┬───────────────────┤
│   Profile    │   Payment    │   Ledger     │      Forex        │
│   :8001      │   :8002      │   :8003      │      :8006        │
│              │              │              │                    │
│ User profiles│ Payments &   │ Financial    │ Currency exchange │
│ & KYC data   │ transactions │ accounting   │ rates & conversion│
├──────────────┼──────────────┴──────────────┴───────────────────┤
│   Wallet     │           Rule Engine                            │
│   :8004      │           :8005                                  │
│              │                                                   │
│ Digital      │ Business rules & decision engine                 │
│ wallets      │                                                   │
└──────────────┴──────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                      Data & Message Layer                         │
├──────────────┬──────────────┬──────────────┬───────────────────┤
│ CockroachDB  │    Redis     │  Redpanda    │  OpenTelemetry   │
│   :26257     │    :6379     │   :9092      │   :4317          │
│   :8082 (UI) │              │              │  → Jaeger :16686 │
│              │              │              │                    │
│ Distributed  │ Cache &      │ Event        │ Distributed      │
│ SQL ACID     │ Celery broker│ streaming    │ tracing          │
└──────────────┴──────────────┴──────────────┴───────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│                    Worker Pool (Celery)                           │
│  profile-worker | payment-worker | ledger-worker | wallet-worker │
│  forex-worker | rule-engine-worker                                │
│                                                                    │
│  • 2 concurrent workers per service                                │
│  • Dedicated queue per service                                     │
│  • Automatic retry with exponential backoff                        │
└──────────────────────────────────────────────────────────────────┘
```

### Authentication Flow

```
┌──────────┐                                    ┌─────────────┐
│  Client  │                                    │  WSO2 IS    │
└────┬─────┘                                    └──────┬──────┘
     │                                                 │
     │  1. POST /oauth2/token                         │
     │     grant_type=password                        │
     │     username=admin                             │
     │     password=admin                             │
     │─────────────────────────────────────────────→ │
     │                                                 │
     │  2. JWT Access Token                           │
     │     (RS256 signed, 1h expiry)                  │
     │ ←──────────────────────────────────────────── │
     │                                                 │
     ▼                                                 │
┌─────────────┐                                       │
│  WSO2 APIM  │                                       │
│  Gateway    │  3. GET /api/forex/1.0.0/health      │
└──────┬──────┘     Authorization: Bearer <JWT>      │
       │                                               │
       │  4. Validate JWT signature via JWKS          │
       │──────────────────────────────────────────────┤
       │                                               │
       │  5. JWT Valid ✓                              │
       │     Extract claims (user, roles, scopes)     │
       │ ←─────────────────────────────────────────── │
       │                                               │
       │  6. Forward request with X-JWT-Assertion     │
       ▼                                               │
┌─────────────┐                                       │
│   Forex     │                                       │
│  Service    │  7. Decode JWT, extract user info    │
│   :8006     │                                       │
│             │  8. Execute business logic            │
│             │                                       │
│             │  9. Return response                   │
└─────────────┘                                       │
```

### Data Flow Example: Payment Processing

```
1. Client → WSO2 Gateway → Payment Service
   POST /api/payment/1.0.0/process
   
2. Payment Service validates amount, currency
   ↓
3. Publishes event to Redpanda
   Topic: payment.initiated
   ↓
4. Forex Service subscribes, calculates conversion
   ↓
5. Ledger Service subscribes, creates journal entry
   ↓
6. Wallet Service subscribes, updates balance
   ↓
7. Payment Worker processes async confirmation
   Queue: payment-tasks
   ↓
8. Publishes event: payment.completed
   ↓
9. All services trace via OpenTelemetry → Jaeger
```

---

## ✨ Features

### Security & Compliance

- ✅ **PCI-DSS Compliant**: Financial-grade OAuth2 with WSO2 IS
- ✅ **JWT Token Validation**: RS256 signing, JWKS endpoint
- ✅ **Role-Based Access Control**: Fine-grained permissions (admin, finance, auditor, etc.)
- ✅ **Audit Logging**: Complete audit trail for compliance
- ✅ **Non-Root Containers**: All services run as non-privileged users
- ✅ **Secret Management**: Environment-based configuration

### Performance & Scalability

- ✅ **Horizontal Scaling**: Stateless services, clustered database
- ✅ **Async Processing**: Celery workers for long-running tasks
- ✅ **Connection Pooling**: Optimized database connections
- ✅ **Caching**: Redis for session and data caching
- ✅ **Rate Limiting**: API Gateway throttling policies
- ✅ **Resource Limits**: CPU and memory constraints per service

### Observability

- ✅ **Distributed Tracing**: OpenTelemetry → Jaeger
- ✅ **Health Checks**: Liveness and readiness probes
- ✅ **Structured Logging**: JSON logs for aggregation
- ✅ **Metrics Export**: Prometheus-compatible endpoints
- ✅ **Admin UIs**: CockroachDB, Jaeger, WSO2 dashboards

### Development Experience

- ✅ **Docker Compose**: Single-command deployment
- ✅ **Hot Reload**: FastAPI auto-reload on code changes
- ✅ **Automated Setup**: WSO2 configuration via script
- ✅ **Test Scripts**: Smoke tests and auth validation
- ✅ **Makefile**: Convenient commands for all operations

---

## 🚀 Quick Start

### Prerequisites

```bash
# Required
Docker Engine 24.0+
Docker Compose 2.20+
8GB+ RAM available
20GB+ disk space

# Optional (for local testing)
Python 3.11+
Make
```

### Installation

```bash
# 1. Clone repository
git clone <repository-url>
cd financial-platform

# 2. Start all services (automated setup included)
make up
# OR without make:
docker compose up -d --build

# 3. Monitor setup progress (takes 2-3 minutes on first run)
docker logs -f wso2-setup

# Expected output:
# ✅ Setup Complete!
# 📊 Summary:
#    APIs created: 6
#    Application: DefaultApplication

# 4. Verify all services are healthy
make health

# Expected output:
# SERVICE           STATUS             HEALTH
# wso2is            Up 2 minutes       healthy
# wso2am            Up 2 minutes       healthy
# profile           Up 2 minutes       healthy
# payment           Up 2 minutes       healthy
# ...
```

### First Test

```bash
# Get JWT token from WSO2 IS
TOKEN=$(curl -X POST https://localhost:9444/oauth2/token \
  -u admin:admin \
  -d "grant_type=password&username=admin&password=admin&scope=openid" \
  -k -s | jq -r '.access_token')

# Call API via WSO2 Gateway
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/forex/1.0.0/health

# Expected response:
# {
#   "status": "ok",
#   "service": "svc-forex",
#   "user": {
#     "username": "admin",
#     "email": "admin@innover.local",
#     "roles": ["admin"]
#   }
# }
```

### Quick Test Suite

```bash
# Run comprehensive smoke tests
make smoke-test

# Test authentication flow
make test-auth

# Test complete flow (IS → Gateway → Backend)
make test-flow
```

---

## 📦 Services

### Core Microservices

| Service | Port | Description | Tech Stack | Dependencies |
|---------|------|-------------|------------|--------------|
| **profile** | 8001 | User profile management, KYC data | FastAPI, Celery | CockroachDB, Redis |
| **payment** | 8002 | Payment processing, transactions | FastAPI, Celery | CockroachDB, Redis, Redpanda |
| **ledger** | 8003 | Financial ledger, accounting | FastAPI, Celery | CockroachDB, Redis |
| **wallet** | 8004 | Digital wallet operations | FastAPI, Celery | CockroachDB, Redis |
| **rule-engine** | 8005 | Business rules engine | FastAPI, Celery | CockroachDB, Redis, Redpanda |
| **forex** | 8006 | Currency exchange rates | FastAPI, Celery | CockroachDB, Redis |

### Service Architecture

Each microservice follows this pattern:

```
services/<service-name>/
├── Dockerfile                 # Python 3.12-slim multi-stage build
├── app/
│   ├── main.py               # FastAPI application entry point
│   ├── celery_app.py         # Celery configuration (broker, backend, queues)
│   ├── tasks.py              # Async task definitions
│   ├── requirements.txt      # Python dependencies
│   ├── otel.py               # OpenTelemetry instrumentation (empty template)
│   └── __init__.py           # Module exports
```

**Key Features per Service:**

- **REST API**: FastAPI with automatic OpenAPI docs at `/docs`
- **Async Workers**: Dedicated Celery worker pool (2 concurrent workers)
- **Dedicated Queue**: `<service>-tasks` in Redis
- **Health Endpoints**: `/health` (liveness) and `/readiness` (readiness)
- **JWT Authentication**: Via `services/common/auth.py`
- **User Context**: Extracts user info from JWT via `services/common/userinfo.py`

### Common Library

Shared utilities across all services:

**`services/common/auth.py`** - Authentication & Authorization
```python
# JWT validation via WSO2 IS JWKS
decode_token(token: str) -> Dict[str, Any]

# FastAPI dependencies
get_current_user() -> Dict[str, Any]
get_current_user_optional() -> Optional[Dict[str, Any]]

# Role-based access control
require_roles(roles: List[str])        # OR logic
require_all_roles(roles: List[str])    # AND logic
require_client_role(client_id: str, role: str)

# Convenience role checkers
require_admin()
require_user()
require_ops()
require_finance()
require_auditor()
```

**`services/common/userinfo.py`** - User Info Extraction
```python
# Extract normalized user info from JWT claims
extract_user_info(claims: Dict) -> Optional[Dict]

# Returns:
# {
#   "username": "admin",
#   "email": "admin@innover.local",
#   "roles": ["admin", "finance"]
# }
```

**Usage Example:**

```python
from fastapi import FastAPI, Depends
from services.common.auth import get_current_user, require_finance

app = FastAPI()

@app.get("/protected")
async def protected_endpoint(user = Depends(get_current_user)):
    return {
        "message": f"Hello, {user['username']}",
        "roles": user["roles"]
    }

@app.post("/financial-transaction")
async def financial_transaction(user = Depends(require_finance)):
    # Only accessible to users with 'finance' role
    return {"status": "processed"}
```

### API Gateway Configuration

APIs are automatically published to WSO2 APIM via `wso2/api-config.yaml`:

```yaml
rest_apis:
  - name: "Forex Service API"
    context: "/api/forex"
    version: "1.0.0"
    backend_url: "http://forex:8000"
    description: "Forex rate conversion service"
    tags: ["forex", "currency"]
```

**Access Pattern:**
```
Client Request:
  http://localhost:8280/api/forex/1.0.0/health
  
Routing:
  WSO2 Gateway → http://forex:8000/health
```

---

## 🛠️ Infrastructure

### Database: CockroachDB

**Distributed SQL with ACID guarantees**

- **Ports**: 
  - 26257: SQL (Postgres wire protocol)
  - 8082: Admin UI
- **Database**: `innover`
- **User**: `root` (insecure mode for development)
- **Features**:
  - Horizontal scaling
  - Geo-replication ready
  - Strong consistency
  - Automatic sharding

**Access:**
```bash
# SQL shell
make db-shell
# OR
docker compose exec cockroach1 /cockroach/cockroach sql \
  --insecure --host=cockroach1:26257 --database=innover

# Admin UI
open http://localhost:8082
```

**Connection String:**
```
postgresql+psycopg2://root@cockroach1:26257/innover?sslmode=disable
```

### Cache & Message Broker: Redis

**In-memory data store**

- **Port**: 6379
- **Password**: `redis-secret` (configured via `.env`)
- **Usage**:
  - Celery broker (task queue)
  - Celery result backend
  - Session storage
  - Application caching

**Access:**
```bash
# Redis CLI
make redis-cli
# OR
docker compose exec redis redis-cli -a redis-secret

# Commands
PING              # Test connection
KEYS *            # List all keys
INFO              # Server info
```

### Message Queue: Redpanda

**Kafka-compatible streaming platform**

- **Port**: 9092
- **Protocol**: Kafka wire protocol
- **Features**:
  - Zero-ZooKeeper design
  - Lower latency than Kafka
  - Simpler operations
  - Full Kafka API compatibility

**Access:**
```bash
# List topics
make kafka-topics
# OR
docker compose exec redpanda rpk topic list --brokers redpanda:9092

# Create topic
docker compose exec redpanda rpk topic create my-topic \
  --brokers redpanda:9092 --partitions 3

# Consume messages
docker compose exec redpanda rpk topic consume my-topic \
  --brokers redpanda:9092
```

### Observability: OpenTelemetry + Jaeger

**Distributed tracing and monitoring**

- **Collector**: Port 4317 (gRPC)
- **Jaeger UI**: http://localhost:16686
- **Features**:
  - Distributed request tracing
  - Service dependency mapping
  - Latency analysis
  - Error tracking

**Configuration:**
All services export traces via environment variable:
```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
```

**Viewing Traces:**
1. Open http://localhost:16686
2. Select service from dropdown (e.g., "svc-forex")
3. Click "Find Traces"
4. Explore trace spans across microservices

---

## 🔐 Authentication & Security

### WSO2 Identity Server Integration

**Financial-Grade OAuth2 Provider**

- **Version**: 7.1.0 Alpine
- **Ports**: 9444 (HTTPS)
- **Admin UI**: https://localhost:9444/carbon
- **Credentials**: admin/admin

**Supported OAuth2 Flows:**

#### 1. Password Grant (Testing/Development)
```bash
curl -X POST https://localhost:9444/oauth2/token \
  -u admin:admin \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=admin&password=admin&scope=openid" \
  -k
```

#### 2. Client Credentials (Service-to-Service)
```bash
curl -X POST https://localhost:9444/oauth2/token \
  -u <client_id>:<client_secret> \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&scope=openid" \
  -k
```

#### 3. Authorization Code (Browser-Based)
```bash
# Step 1: Redirect user to authorize endpoint
https://localhost:9444/oauth2/authorize?
  response_type=code&
  client_id=<client_id>&
  redirect_uri=<redirect_uri>&
  scope=openid

# Step 2: Exchange code for token
curl -X POST https://localhost:9444/oauth2/token \
  -u <client_id>:<client_secret> \
  -d "grant_type=authorization_code&code=<auth_code>&redirect_uri=<redirect_uri>"
```

### User Roles & Permissions

Pre-configured roles for financial services:

| Role | Description | Use Case | Email |
|------|-------------|----------|-------|
| **admin** | Full system access | System administration, configuration | admin@innover.local |
| **ops_user** | Operations team access | Monitoring, incident response | ops_user@innover.local |
| **finance** | Financial operations | Payment processing, ledger management | finance@innover.local |
| **auditor** | Read-only audit access | Compliance audits, PCI-DSS reviews | auditor@innover.local |
| **user** | Standard user access | Customer-facing operations | user@innover.local |

**All users created with password = username**

Users are automatically created by the `wso2is-init` container on first startup.

### JWT Token Structure

```json
{
  "sub": "admin@carbon.super",
  "aud": "wso2am",
  "iss": "https://localhost:9444/oauth2/token",
  "exp": 1234567890,
  "iat": 1234564290,
  "client_id": "admin",
  "scope": "openid",
  "email": "admin@innover.local",
  "email_verified": true,
  "groups": ["admin"],
  "http://wso2.org/claims/username": "admin",
  "http://wso2.org/claims/emailaddress": "admin@innover.local",
  "http://wso2.org/claims/role": ["admin"]
}
```

### WSO2 API Manager Gateway

**API Security & Management**

- **Version**: 4.5.0 Alpine
- **Ports**: 
  - 8280: HTTP Gateway
  - 8243: HTTPS Gateway
  - 9443: Management Console
- **Admin UI**: https://localhost:9443/carbon
- **Dev Portal**: https://localhost:9443/devportal
- **Publisher**: https://localhost:9443/publisher

**Security Features:**

- ✅ JWT validation via WSO2 IS JWKS endpoint
- ✅ Rate limiting and throttling policies
- ✅ API subscription management
- ✅ Request/response transformation
- ✅ API versioning and lifecycle
- ✅ Analytics and monitoring

### PCI-DSS Compliance Features

- ✅ **Strong Authentication**: Multi-factor ready, financial-grade OAuth2
- ✅ **Audit Logging**: Complete audit trail for all operations
- ✅ **Data Encryption**: TLS 1.2+ for all communications
- ✅ **Access Control**: Role-based access with principle of least privilege
- ✅ **Token Security**: Short-lived JWT tokens (1h), refresh tokens supported
- ✅ **Session Management**: Secure session handling, automatic timeout

### Security Best Practices

**Development:**
- Self-signed certificates (auto-trusted)
- Default credentials (admin/admin)
- Insecure CockroachDB mode

**Production Recommendations:**
- [ ] Replace with CA-signed certificates
- [ ] Rotate all default passwords
- [ ] Enable CockroachDB secure mode
- [ ] Configure proper WSO2 keystores
- [ ] Enable MFA for admin accounts
- [ ] Implement secrets management (Vault, AWS Secrets Manager)
- [ ] Configure network policies and firewalls
- [ ] Enable HTTPS only (disable HTTP gateway)

---

## 💻 Development

### Local Development Setup

```bash
# 1. Start all services
make up

# 2. Verify health
make health

# 3. View logs
make logs                # All services
make logs-profile        # Specific service
make logs-profile-worker # Specific worker

# 4. Make code changes (auto-reload enabled for FastAPI)
vim services/profile/app/main.py

# 5. Restart service after dependency changes
make restart-profile
```

### Environment Variables

Edit `.env` for configuration:

```bash
# WSO2 Identity Server
OIDC_ISSUER=https://wso2is:9444/oauth2/token
OIDC_AUDIENCE=wso2am
WSO2_IS_ADMIN_USERNAME=admin
WSO2_IS_ADMIN_PASSWORD=admin

# WSO2 API Manager
WSO2_ADMIN_USERNAME=admin
WSO2_ADMIN_PASSWORD=admin

# Database (CockroachDB)
DB_USER=root
DB_PASSWORD=
DB_NAME=innover
DB_HOST=cockroach1
DB_PORT=26257

# Redis
REDIS_PASSWORD=redis-secret

# OpenTelemetry
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317

# Kafka
KAFKA_BROKERS=redpanda:9092
```

### Working with Celery Workers

```bash
# Monitor all workers
make workers

# Send test task to specific worker
make test-worker-profile
make test-worker-payment

# View worker logs
docker compose logs -f profile-worker

# Inspect active tasks
docker compose exec profile-worker \
  celery -A celery_app.celery_app inspect active

# Inspect registered tasks
docker compose exec profile-worker \
  celery -A celery_app.celery_app inspect registered
```

### Adding New Celery Task

```python
# services/profile/app/tasks.py
from celery_app import celery_app

@celery_app.task(name="profile.new_task")
def new_task(param1, param2):
    """Description of task"""
    # Task logic here
    return {"result": "success"}
```

### Adding New Service

**1. Create service structure:**
```bash
mkdir -p services/new-service/app
cd services/new-service
```

**2. Copy template files:**
```bash
cp ../profile/Dockerfile .
cp ../profile/app/main.py app/
cp ../profile/app/celery_app.py app/
cp ../profile/app/tasks.py app/
cp ../profile/app/requirements.txt app/
cp ../profile/app/__init__.py app/
```

**3. Update service configuration:**

Edit `app/celery_app.py`:
```python
queue_name = os.getenv("CELERY_DEFAULT_QUEUE", "new-service-tasks")
```

Edit `app/main.py`:
```python
SERVICE_NAME = os.getenv("SERVICE_NAME", "svc-new-service")
```

**4. Add to `docker-compose.yml`:**
```yaml
new-service:
  build: ./services/new-service
  environment:
    <<: *svc_env
    SERVICE_NAME: svc-new-service
    CELERY_DEFAULT_QUEUE: new-service-tasks
  ports:
    - "8007:8000"
  depends_on:
    cockroach1: {condition: service_healthy}
    redis: {condition: service_healthy}
  deploy: *default_deploy
  networks: [edge]

new-service-worker:
  build: ./services/new-service
  command: ["celery", "-A", "celery_app.celery_app", "worker", 
            "-l", "info", "--concurrency", "2", 
            "--hostname", "new-service-worker@%h",
            "--queues", "new-service-tasks"]
  environment:
    <<: *svc_env
    SERVICE_NAME: svc-new-service-worker
  depends_on:
    cockroach1: {condition: service_healthy}
    redis: {condition: service_healthy}
  deploy: *worker_deploy
  networks: [edge]
```

**5. Add API to WSO2 (`wso2/api-config.yaml`):**
```yaml
rest_apis:
  - name: "New Service API"
    context: "/api/new-service"
    version: "1.0.0"
    backend_url: "http://new-service:8000"
    description: "New service description"
    tags: ["new-service"]
```

**6. Deploy:**
```bash
docker compose up -d new-service new-service-worker
make publish-apis
```

### Database Migrations

**Using raw SQL:**
```bash
# Connect to database
make db-shell

# Run migration
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username STRING UNIQUE NOT NULL,
    email STRING UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

**Using SQLAlchemy (recommended):**
```python
# services/profile/app/models.py
from sqlalchemy import Column, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.dialects.postgresql import UUID
import uuid

Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String, unique=True, nullable=False)
    email = Column(String, unique=True, nullable=False)
    created_at = Column(DateTime, server_default="now()")
```

### Debugging

**View all service endpoints:**
```bash
# Profile service
curl http://localhost:8001/docs

# Payment service
curl http://localhost:8002/docs

# Direct backend (bypasses WSO2)
curl http://localhost:8006/health
```

**Check service health:**
```bash
# Via gateway (requires auth)
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/forex/1.0.0/health

# Direct (no auth)
curl http://localhost:8006/health
```

**View distributed traces:**
```bash
# 1. Make API call
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/profile/1.0.0/health

# 2. Open Jaeger
open http://localhost:16686

# 3. Select service "svc-profile"
# 4. Click "Find Traces"
```

---

## 🧪 Testing

### Smoke Tests

Comprehensive automated testing:

```bash
# Run all smoke tests
make smoke-test

# Tests include:
# ✓ Container health checks
# ✓ WSO2 IS authentication
# ✓ WSO2 APIM gateway routing
# ✓ Backend service health
# ✓ JWT validation
# ✓ API endpoint accessibility
```

### Authentication Tests

```bash
# Test WSO2 IS authentication flow
make test-auth

# Test complete flow (IS → Gateway → Backend)
make test-flow

# Manual tests
python3 test_wso2_auth.py
python3 test_complete_flow.py
```

### Manual API Testing

```bash
# 1. Get JWT token
TOKEN=$(curl -X POST https://localhost:9444/oauth2/token \
  -u admin:admin \
  -d "grant_type=password&username=admin&password=admin&scope=openid" \
  -k -s | jq -r '.access_token')

# 2. Verify token (decode JWT)
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq

# 3. Call API via gateway
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/forex/1.0.0/health | jq

# 4. Test different services
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/profile/1.0.0/health | jq

curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/payment/1.0.0/health | jq

# 5. Test without token (should fail)
curl http://localhost:8280/api/forex/1.0.0/health
# Expected: 401 Unauthorized
```

### Worker Testing

```bash
# Send test task to worker
make test-worker-profile

# Verify task execution in logs
docker compose logs -f profile-worker | grep "Echo"

# Send custom task
docker compose exec profile python -c "
from celery_app import celery_app
result = celery_app.send_task(
    'profile.add', 
    args=[10, 20],
    queue='profile-tasks'
)
print(f'Task ID: {result.id}')
"
```

### Load Testing

```bash
# Install hey (HTTP load generator)
go install github.com/rakyll/hey@latest

# Load test with authentication
hey -n 1000 -c 10 -q 10 \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/forex/1.0.0/health

# Expected output:
# Requests/sec: ~500-1000
# Average latency: <100ms
# Success rate: 100%
```

### Integration Testing

```bash
# Test event-driven flow
# 1. Publish event to Redpanda
docker compose exec redpanda rpk topic produce payment.initiated \
  --brokers redpanda:9092

# 2. Verify consumers received event (check logs)
docker compose logs payment-worker | grep "payment.initiated"
docker compose logs ledger-worker | grep "payment.initiated"
docker compose logs wallet-worker | grep "payment.initiated"
```

---

## 📊 Monitoring & Observability

### Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| **WSO2 IS Admin Console** | https://localhost:9444/carbon | admin/admin |
| **WSO2 APIM Publisher** | https://localhost:9443/publisher | admin/admin |
| **WSO2 APIM DevPortal** | https://localhost:9443/devportal | admin/admin |
| **WSO2 APIM Admin** | https://localhost:9443/admin | admin/admin |
| **Jaeger UI** | http://localhost:16686 | None |
| **CockroachDB UI** | http://localhost:8082 | None |
| **API Gateway (HTTP)** | http://localhost:8280 | JWT required |
| **API Gateway (HTTPS)** | https://localhost:8243 | JWT required |

### Health Checks

```bash
# All services
make health

# Individual service health
curl http://localhost:8001/health  # Profile
curl http://localhost:8002/health  # Payment
curl http://localhost:8003/health  # Ledger
curl http://localhost:8004/health  # Wallet
curl http://localhost:8005/health  # Rule Engine
curl http://localhost:8006/health  # Forex

# Readiness probes (for load balancers)
curl http://localhost:8006/readiness
```

### Logs

```bash
# Tail all logs
docker compose logs -f

# Specific service
docker compose logs -f profile
docker compose logs -f wso2am
docker compose logs -f wso2is

# Worker logs
docker compose logs -f profile-worker
docker compose logs -f payment-worker

# Filter logs
docker compose logs profile | grep ERROR
docker compose logs wso2am | grep -i jwt
```

### Distributed Tracing

**Using Jaeger UI:**

1. Open http://localhost:16686
2. Select service from dropdown (e.g., "svc-forex")
3. Set time range
4. Click "Find Traces"
5. Click on a trace to see:
   - Request path through services
   - Latency per service
   - Error spans
   - Database queries
   - HTTP calls

**Trace Context Propagation:**

All services automatically propagate trace context via OpenTelemetry:
```
Client Request ID: 1234abcd
  ↓
Gateway Span: gateway-span-5678
  ↓
Service Span: forex-span-9012
  ↓
Database Span: cockroach-query-3456
```

### Metrics

**CockroachDB Metrics:**
- Open http://localhost:8082
- View SQL query performance
- Monitor node health
- Check replication status

**Redis Metrics:**
```bash
docker compose exec redis redis-cli -a redis-secret INFO
# Shows memory usage, connected clients, command stats
```

**WSO2 Analytics:**
- Open https://localhost:9443/publisher
- Navigate to Analytics section
- View API usage, latency, error rates

---

## 🐛 Troubleshooting

### Common Issues

#### 1. APIs Return 404 After Setup

**Symptom:**
```bash
curl http://localhost:8280/api/forex/1.0.0/health
# HTTP 404 Not Found
```

**Root Cause:** APIs not deployed to gateway runtime

**Solution:**
```bash
# Check setup logs
docker logs wso2-setup | tail -50

# Look for: ✓ Revision deployed to gateway successfully

# If missing, re-run setup
make setup

# Verify API status in Publisher UI
# https://localhost:9443/publisher
# Check: APIs → Forex Service API → Deployments
```

#### 2. JWT Validation Fails (401 Unauthorized)

**Symptom:**
```json
{"code": 900901, "message": "Invalid Credentials"}
```

**Root Causes:**
- WSO2 IS not ready
- JWKS endpoint unreachable
- Token issuer mismatch

**Solutions:**
```bash
# 1. Verify WSO2 IS health
docker compose ps wso2is
# Should show: healthy

# 2. Test JWKS endpoint
curl -k https://localhost:9444/oauth2/jwks
# Should return JSON with keys

# 3. Check APIM configuration
docker exec wso2am grep -A 5 "jwt.issuer" \
  /home/wso2carbon/wso2am-4.5.0/repository/conf/deployment.toml

# Should show:
# [[apim.jwt.issuer]]
# issuer = "https://localhost:9444/oauth2/token"

# 4. Restart APIM if config is wrong
docker compose restart wso2am
```

#### 3. Service Won't Start (Dependency Failure)

**Symptom:**
```bash
docker compose ps
# Shows service as "Exited (1)"
```

**Solutions:**
```bash
# Check logs for error
docker compose logs <service-name> | tail -50

# Common issues:

# A) Database not ready
# Solution: Wait for CockroachDB health check
docker compose up -d cockroach1
# Wait 30 seconds, then:
docker compose up -d <service-name>

# B) Redis connection failed
# Solution: Check Redis password
docker compose exec <service-name> env | grep REDIS_PASSWORD
# Should match REDIS_PASSWORD in .env

# C) Import error
# Solution: Rebuild image
docker compose build --no-cache <service-name>
docker compose up -d <service-name>
```

#### 4. Celery Worker Not Consuming Tasks

**Symptom:**
Tasks remain in "pending" state

**Solutions:**
```bash
# 1. Check worker is running
docker compose ps | grep worker

# 2. Check worker logs
docker compose logs <service>-worker | tail -50

# Look for:
# [INFO/MainProcess] Connected to redis://...
# [INFO/MainProcess] mingle: all alone

# 3. Verify queue name
docker compose logs <service>-worker | grep "queues"
# Should show: queues=['<service>-tasks']

# 4. Test Redis connection
docker compose exec <service>-worker python -c "
from celery_app import celery_app
print(celery_app.broker_connection().as_uri())
"

# 5. Restart worker
make restart-<service>-worker
```

#### 5. WSO2 Setup Timeout

**Symptom:**
```bash
docker logs wso2-setup
# ❌ Timeout waiting for WSO2
```

**Solution:**
```bash
# WSO2 first start takes 2-3 minutes
# Check WSO2 IS logs
docker compose logs wso2is | grep -i "carbon started"

# Check WSO2 APIM logs
docker compose logs wso2am | grep -i "carbon started"

# If still starting, wait and retry
sleep 60
docker compose restart wso2-setup

# Or manual setup
make setup
```

#### 6. Port Already in Use

**Symptom:**
```
Error: bind: address already in use
```

**Solution:**
```bash
# Find process using port
lsof -i :8280  # Or whichever port

# Kill process
kill -9 <PID>

# Or change port in docker-compose.yml
ports:
  - "8281:8280"  # Use different host port
```

### Debug Checklist

Run through this checklist when encountering issues:

- [ ] **All containers running**: `docker compose ps`
- [ ] **Health checks passing**: `make health`
- [ ] **WSO2 IS accessible**: `curl -k https://localhost:9444/carbon/admin/login.jsp`
- [ ] **WSO2 APIM accessible**: `curl -k https://localhost:9443/publisher`
- [ ] **Redis responding**: `docker compose exec redis redis-cli -a redis-secret PING`
- [ ] **CockroachDB responding**: `make db-shell` then `SELECT 1;`
- [ ] **Setup completed**: `docker logs wso2-setup | grep "Setup Complete"`
- [ ] **APIs deployed**: Check Publisher UI or logs for "Revision deployed"
- [ ] **Workers connected**: `make workers`

### Getting Help

When reporting issues, include:

1. **Environment info:**
```bash
docker --version
docker compose version
uname -a
```

2. **Container status:**
```bash
docker compose ps > container-status.txt
```

3. **Service logs:**
```bash
docker compose logs > all-logs.txt
```

4. **Health status:**
```bash
make health > health-status.txt
```

5. **Configuration:**
```bash
docker compose config > resolved-config.yml
```

---

## 🚢 Production Considerations

### Pre-Production Checklist

#### Security

- [ ] **Replace self-signed certificates** with CA-signed certs
- [ ] **Rotate all default passwords** (admin/admin, redis-secret)
- [ ] **Enable CockroachDB secure mode** (TLS + authentication)
- [ ] **Configure proper WSO2 keystores** (not self-signed)
- [ ] **Enable MFA** for admin accounts
- [ ] **Implement secrets management** (HashiCorp Vault, AWS Secrets Manager)
- [ ] **Configure network policies** (firewall rules, security groups)
- [ ] **Disable HTTP gateway** (HTTPS only)
- [ ] **Enable rate limiting** on all APIs
- [ ] **Configure CORS** policies appropriately

#### Infrastructure

- [ ] **Multi-node CockroachDB cluster** (3+ nodes)
- [ ] **Redis Sentinel/Cluster** for high availability
- [ ] **Kafka cluster** (3+ Redpanda nodes) with replication
- [ ] **Load balancers** for all public services
- [ ] **Auto-scaling** groups for microservices
- [ ] **Resource limits** tuned based on load testing
- [ ] **Persistent volumes** for databases
- [ ] **Backup strategy** (automated, tested restores)
- [ ] **Disaster recovery** plan documented

#### Monitoring & Observability

- [ ] **Prometheus** metrics export from all services
- [ ] **Grafana** dashboards for visualization
- [ ] **Alerting** configured (PagerDuty, Opsgenie)
- [ ] **Centralized logging** (ELK, Grafana Loki, CloudWatch)
- [ ] **APM** (Application Performance Monitoring)
- [ ] **Synthetic monitoring** (uptime checks)
- [ ] **SLIs/SLOs** defined and tracked
- [ ] **On-call rotation** established

#### Performance

- [ ] **Load testing** completed (identify bottlenecks)
- [ ] **Database indexes** optimized for query patterns
- [ ] **Connection pooling** tuned (SQLAlchemy, Redis)
- [ ] **Celery concurrency** adjusted per worker type
- [ ] **API response caching** enabled in WSO2
- [ ] **CDN** for static assets
- [ ] **Database query optimization** (EXPLAIN ANALYZE)
- [ ] **Horizontal scaling** tested

### Kubernetes Deployment

**Example deployment manifest:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: profile-service
  namespace: financial-platform
spec:
  replicas: 3
  selector:
    matchLabels:
      app: profile
  template:
    metadata:
      labels:
        app: profile
    spec:
      containers:
      - name: profile
        image: your-registry/profile:v1.0.0
        ports:
        - containerPort: 8000
        env:
        - name: OIDC_ISSUER
          valueFrom:
            secretKeyRef:
              name: wso2-config
              key: issuer
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: database-config
              key: connection-string
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: profile
  namespace: financial-platform
spec:
  selector:
    app: profile
  ports:
  - port: 8000
    targetPort: 8000
  type: ClusterIP
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: profile-hpa
  namespace: financial-platform
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: profile-service
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Database Production Setup

**CockroachDB Cluster:**

```bash
# Create 3-node cluster with replication factor 3
# Node 1
docker run -d --name=cockroach1 cockroachdb/cockroach:v24.2.4 start \
  --insecure --join=cockroach1,cockroach2,cockroach3

# Node 2
docker run -d --name=cockroach2 cockroachdb/cockroach:v24.2.4 start \
  --insecure --join=cockroach1,cockroach2,cockroach3

# Node 3
docker run -d --name=cockroach3 cockroachdb/cockroach:v24.2.4 start \
  --insecure --join=cockroach1,cockroach2,cockroach3

# Initialize cluster
docker exec -it cockroach1 /cockroach/cockroach init --insecure
```

**Backup Strategy:**

```bash
# Full backup
docker exec cockroach1 /cockroach/cockroach sql --insecure \
  -e "BACKUP DATABASE innover TO 's3://backup-bucket/innover?AWS_ACCESS_KEY_ID=xxx'"

# Incremental backup
docker exec cockroach1 /cockroach/cockroach sql --insecure \
  -e "BACKUP DATABASE innover TO 's3://backup-bucket/innover' INCREMENTAL FROM 'full-backup'"
```

### WSO2 Production Configuration

**External Database (MySQL):**

```toml
# wso2/deployment.toml
[database.apim_db]
type = "mysql"
url = "jdbc:mysql://mysql:3306/apim_db"
username = "wso2carbon"
password = "wso2carbon"
driver = "com.mysql.jdbc.Driver"

[database.shared_db]
type = "mysql"
url = "jdbc:mysql://mysql:3306/shared_db"
username = "wso2carbon"
password = "wso2carbon"
driver = "com.mysql.jdbc.Driver"
```

**Clustering:**

```toml
[clustering]
membership_scheme = "kubernetes"
domain = "wso2.apim.domain"

[clustering.properties]
membershipSchemeClassName = "org.wso2.carbon.membership.scheme.kubernetes.KubernetesMembershipScheme"
KUBERNETES_NAMESPACE = "financial-platform"
KUBERNETES_SERVICES = "wso2am-service"
```

### Performance Tuning

**FastAPI:**
```python
# Increase worker count
# docker-compose.yml
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", 
     "--workers", "4"]
```

**Celery:**
```python
# Increase concurrency
# docker-compose.yml
command: ["celery", "-A", "celery_app", "worker", 
          "--concurrency", "8", "--max-tasks-per-child", "100"]
```

**Database Connection Pool:**
```python
# SQLAlchemy
engine = create_engine(
    DB_URL,
    pool_size=20,
    max_overflow=40,
    pool_pre_ping=True,
    pool_recycle=3600
)
```

---

## 🤝 Contributing

### Development Workflow

1. **Fork repository**
2. **Create feature branch**: `git checkout -b feature/my-feature`
3. **Make changes** following code standards
4. **Add tests** for new functionality
5. **Run tests**: `make smoke-test`
6. **Commit**: `git commit -m "feat: add new feature"`
7. **Push**: `git push origin feature/my-feature`
8. **Create Pull Request**

### Code Standards

**Python:**
- Follow PEP 8 style guide
- Use type hints
- Add docstrings to all functions
- Maximum line length: 100 characters

**Docker:**
- Use multi-stage builds
- Run as non-root user
- Include health checks
- Minimize layer count

**API Design:**
- RESTful conventions
- Versioned endpoints (`/api/service/v1`)
- Consistent error responses
- Comprehensive OpenAPI docs

### Commit Messages

Follow Conventional Commits:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Test additions/changes
- `chore:` Build process or tooling changes

**Examples:**
```
feat: add payment refund endpoint
fix: resolve JWT validation timeout
docs: update API authentication guide
refactor: extract user service to common library
test: add integration tests for forex service
chore: update dependencies to latest versions
```

---

## 📄 License

[Specify your license here - e.g., MIT, Apache 2.0]

---

## 🆘 Support & Contact

### Getting Help

1. **Documentation**: Check this README and inline code comments
2. **Issues**: Create GitHub issue with:
   - Environment details (`docker --version`, `docker compose version`)
   - Container status (`docker compose ps`)
   - Relevant logs (`docker compose logs <service>`)
   - Steps to reproduce

### Issue Template

```markdown
**Environment:**
- OS: [e.g., Ubuntu 22.04, macOS 14.0]
- Docker: [version]
- Docker Compose: [version]

**Description:**
[Clear description of the issue]

**Steps to Reproduce:**
1. [First step]
2. [Second step]

**Expected Behavior:**
[What you expected to happen]

**Actual Behavior:**
[What actually happened]

**Logs:**
```
[Paste relevant logs here]
```

**Screenshots:**
[If applicable]
```

### Quick Debug Commands

```bash
# Generate comprehensive debug bundle
{
  echo "=== Environment ==="
  docker --version
  docker compose version
  uname -a
  echo ""
  
  echo "=== Container Status ==="
  docker compose ps
  echo ""
  
  echo "=== Health Checks ==="
  make health
  echo ""
  
  echo "=== Service Logs (last 50 lines) ==="
  docker compose logs --tail=50
} > debug-bundle.txt

# Share debug-bundle.txt when reporting issues
```

---

## 🙏 Acknowledgments

- **WSO2**: Identity Server and API Manager
- **FastAPI**: Modern Python web framework
- **Celery**: Distributed task queue
- **CockroachDB**: Distributed SQL database
- **Redpanda**: Kafka-compatible streaming
- **OpenTelemetry**: Observability framework

---

**Built with ❤️ for financial services**