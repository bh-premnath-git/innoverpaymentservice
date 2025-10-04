# Innover Monorepo

This repository is a fully containerized playground for an event-driven payments platform. It comes with six Python microservices, pre-wired identity and API gateway layers, observability plumbing, and data infrastructure so that real business logic can be dropped in with minimal bootstrapping. Every component is orchestrated through `docker-compose` and surfaced via convenience Make targets for local development.

## Table of contents

## Service catalog


### Asynchronous jobs


## Resource limits and local tuning

## Identity and API gateway

### Keycloak + WSO2 API Manager checklist


### Automated API Publishing

2. **Configuration-based approach** - Edit `wso2/api-config.yaml` to define your APIs:
   - REST APIs: Standard HTTP/HTTPS endpoints
   - GraphQL APIs: GraphQL schema and endpoint
   - WebSocket APIs: Real-time streaming endpoints
   - AI/LLM APIs: High-timeout endpoints for AI/ML services

3. **Manual scripting** - Use `wso2/wso2-api-publisher.py` for programmatic API 
**What WSO2 knows after publishing:**
- All backend service URLs and health endpoints
- API contexts, versions, and descriptions
- Security schemes (OAuth2, API Key)
- CORS settings for cross-origin requests
- All HTTP methods (GET, POST, PUT, DELETE, PATCH)
- Throttling policies and visibility settings

**Accessing published APIs:**
- **Publisher Portal**: 
- **Developer Portal**: 
- **API Gateway**: 

### WSO2 integration tips

## Security & Configuration

### Environment Variables (.env)
**CRITICAL**: 

### Security Best Practices

### Keycloak as WSO2 Key Manager

- **Unified token validation**: WSO2 Gateway validates JWT tokens issued by Keycloak
- **Single issuer**: `https://auth.127.0.0.1.sslip.io/realms/innover`
- **JWKS integration**: WSO2 fetches public keys from Keycloak automatically
- **No token duplication**: Use Keycloak tokens directly with WSO2 APIs

**Run the Key Manager setup**:

**Test with Keycloak token**:
```bash
# Get token from Keycloak
TOKEN=$(curl -k -X POST https://auth.127.0.0.1.sslip.io/realms/innover/protocol/openid-connect/token \
  -d "client_id=${WSO2_AM_CLIENT_ID}" \
  -d "client_secret=${WSO2_AM_CLIENT_SECRET}" \
  -d "username=admin" \
  -d "password=${KC_BOOTSTRAP_ADMIN_PASSWORD}" \
  -d "grant_type=password" | jq -r '.access_token')

# Call API through WSO2 Gateway
curl -k -H "Authorization: Bearer $TOKEN" \
  https://apim.127.0.0.1.sslip.io/api/profile/1.0.0/health
```

### Role-Based Access Control (RBAC)

Keycloak tokens include **realm roles** and **client roles** in both ID Token and Access Token:

- **Realm roles**: `admin`, `ops_user`, `finance`, `auditor`, `user`
- **Token claims**: `realm_access.roles` and `resource_access.<client>.roles`
- **WSO2 integration**: Use roles for API subscription authorization and resource-level access control

**Test role inclusion**:
```bash
# Quick verification script
./test-roles.sh

# Or use Python script
python3 sandbox/test_keycloak_token.py admin admin
```

**Documentation**:
- `KEYCLOAK-ROLE-MAPPERS.md` - Complete guide to protocol mappers and role configuration
- `KEYCLOAK-OIDC-ENDPOINTS.md` - OIDC endpoint reference

**Example token structure with roles**:
```json
{
  "iss": "https://auth.127.0.0.1.sslip.io/realms/innover",
  "preferred_username": "admin",
  "realm_access": {
    "roles": ["admin", "user"]
  },
  "resource_access": {
    "wso2am": {
      "roles": []
    }
  },
  "email": "admin@innover.local",
  "azp": "wso2am"
}
```

### Generated Credentials

After running `docker compose up wso2-setup`, check generated application keys:
```bash
cat wso2/output/application-keys.json | jq
```

**Never commit this file** - it contains OAuth2 client credentials.

## Observability
All Python services ship with OpenTelemetry environment variables that point at the local collector (`OTEL_EXPORTER_OTLP_ENDPOINT`). The collector pipeline receives OTLP gRPC traffic and forwards traces to Jaeger (`jaeger:4317`) and to the debug exporter for log visibility. After starting the stack you can browse to Jaeger at `http://localhost:16686` or tail the collector logs (`docker compose logs otel-collector`) to confirm span delivery.

## Protobuf toolchain
Domain APIs live under `protos/<domain>/v1`. The provided `generate_protos.sh` script iterates through each domain, compiles `.proto` definitions with `grpc_tools.protoc`, and drops Python stubs into the corresponding `services/<name>/app/generated` directory (creating it if necessary). Because the script shells out to `python -m grpc_tools.protoc`, developers must install `grpcio-tools` **before** invoking the Make target—for example:

```bash
pip install grpcio-tools
make proto
```

Empty `.proto` placeholders are already present so you only need to populate them before regenerating stubs.

## Repository layout
```
.
├─ .env
├─ Makefile
├─ README.md
├─ docker-compose.yml
├─ generate_protos.sh
├─ smoke-test.sh
├─ keycloak/
│  ├─ Dockerfile
│  └─ realm-export.json
├─ otel/
│  ├─ Dockerfile
│  └─ collector.yaml
├─ protos/
│  ├─ forex/
│  │  └─ v1/
│  │     └─ forex.proto
│  ├─ ledger/
│  │  └─ v1/
│  │     └─ ledger.proto
│  ├─ payment/
│  │  └─ v1/
│  │     └─ payment.proto
│  ├─ profile/
│  │  └─ v1/
│  │     └─ profile.proto
│  ├─ rule-engine/
│  │  └─ v1/
│  │     └─ rule-engine.proto
│  └─ wallet/
│     └─ v1/
│        └─ wallet.proto
├─ sandbox/
│  └─ maintest.py
└─ services/
   ├─ forex/
   │  ├─ Dockerfile
   │  └─ app/
   │     ├─ __init__.py
   │     ├─ celery_app.py
   │     ├─ main.py
   │     ├─ otel.py
   │     ├─ requirements.txt
   │     └─ tasks.py
   ├─ ledger/
   │  ├─ Dockerfile
   │  └─ app/
   │     ├─ __init__.py
   │     ├─ celery_app.py
   │     ├─ main.py
   │     ├─ otel.py
   │     ├─ requirements.txt
   │     └─ tasks.py
   ├─ payment/
   │  ├─ Dockerfile
   │  └─ app/
   │     ├─ __init__.py
   │     ├─ celery_app.py
   │     ├─ main.py
   │     ├─ otel.py
   │     ├─ requirements.txt
   │     └─ tasks.py
   ├─ profile/
   │  ├─ Dockerfile
   │  └─ app/
   │     ├─ __init__.py
   │     ├─ celery_app.py
   │     ├─ main.py
   │     ├─ otel.py
   │     ├─ requirements.txt
   │     └─ tasks.py
   ├─ rule-engine/
   │  ├─ Dockerfile
   │  └─ app/
   │     ├─ __init__.py
   │     ├─ celery_app.py
   │     ├─ main.py
   │     ├─ otel.py
   │     ├─ requirements.txt
   │     └─ tasks.py
   └─ wallet/
      ├─ Dockerfile
      └─ app/
         ├─ __init__.py
         ├─ celery_app.py
         ├─ main.py
         ├─ otel.py
         ├─ requirements.txt
         └─ tasks.py
```

Key directories at the repository root:

- `services/` – Six Python microservices with identical Dockerfiles, heartbeat loops, and Celery scaffolding.
- `protos/` – Versioned gRPC API definitions per domain.
- `keycloak/` – Realm export and Dockerfile consumed during Keycloak startup.
- `wso2/` – WSO2 API Manager automation scripts and API configuration (REST, GraphQL, WebSocket, AI/LLM).
- `otel/` – OpenTelemetry Collector pipeline.
- `docker-compose.yml` – Orchestrates services, infrastructure, and bootstrap jobs.
- `Makefile` – Convenience targets for the local workflow.
- `generate_protos.sh` – Regenerates gRPC stubs into each service directory.
- `sandbox/` – Scratch space for experiments.
Use this map to locate the right directories as you flesh out APIs, persistence, and messaging logic.
