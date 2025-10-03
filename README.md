# Innover Monorepo

This repository is a fully containerized playground for an event-driven payments platform. It comes with six Python microservices, pre-wired identity and API gateway layers, observability plumbing, and data infrastructure so that real business logic can be dropped in with minimal bootstrapping. Every component is orchestrated through `docker-compose` and surfaced via convenience Make targets for local development.

## Table of contents
1. [Service catalog](#service-catalog)
   - [Asynchronous jobs](#asynchronous-jobs)
2. [Supporting infrastructure](#supporting-infrastructure)
3. [Identity and API gateway](#identity-and-api-gateway)
4. [Observability](#observability)
5. [Local development workflow](#local-development-workflow)
6. [Protobuf toolchain](#protobuf-toolchain)
7. [Repository layout](#repository-layout)

## Service catalog
Each business domain lives in `services/<name>` and ships with both an HTTP placeholder FastAPI app (see `services/<service>/app/main.py`) **and** a Celery worker that exercises the async infrastructure. The pattern is identical across all six domains:

| Service | Example scope | Runtime containers | Entrypoint(s) | Default env wiring |
|---------|---------------|-------------------|---------------|--------------------|
| `profile` | User profile orchestration | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `payment` | Payment initiation pipeline | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `ledger` | Financial ledger posting | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `wallet` | Customer wallet balance | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `rule-engine` | Decisioning / risk controls | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `forex` | FX quote ingestion | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |

The `app/main.py` process exposes `/health` and `/readiness` endpoints that surface the injected `SERVICE_NAME` through FastAPI so the container stays responsive while you build real functionality. Each container keeps running by invoking `uvicorn main:app`, while Docker Compose launches the Celery workers separately via `celery -A celery_app worker`. Each service also exposes a `celery_app.py`/`tasks.py` module pair so you can fire real jobs through Redis. All services share the same Dockerfile template that installs optional requirements, copies the app directory, adds a health check, and runs either the Uvicorn process or the Celery worker with unbuffered logging. The `docker-compose.yml` file fans each container out with identical environment variables for CockroachDB, Redis, Redpanda, OpenTelemetry, and Keycloak integration.

### Asynchronous jobs

Every domain has a minimal Celery setup that demonstrates late acknowledgements, per-task routing, and idempotent worker configuration. To experiment locally:

1. Start the stack (`make up`).
2. Exec into a worker container, e.g. `docker compose exec profile-worker bash`.
3. Open a Python shell and queue sample jobs:

   ```python
   from tasks import add, slow

   add.delay(1, 2)   # -> 3
   slow.delay(5)     # sleeps 5 seconds, then returns 5
   ```

4. Watch execution from the worker logs (`docker compose logs -f profile-worker`).

Because the broker/backend are both Redis, results can be inspected with `redis-cli` or by awaiting the `AsyncResult`. Swap the URLs in `services/<name>/app/celery_app.py` if you want to point at production-grade infrastructure.

## Supporting infrastructure
The compose stack bootstraps every dependency you need to exercise the services locally:

- **Jaeger all-in-one** exposes `http://localhost:16686` for trace inspection and also accepts OTLP traffic on port 4317.
- **OpenTelemetry Collector** runs the `otel/collector.yaml` pipeline, receiving OTLP traces from the services and forwarding them to Jaeger and a debug exporter for console verification.
- **Keycloak** starts with the `innover` realm imported from `keycloak/realm-export.json`, listening on `http://localhost:8080` for administrative access and proxied through Nginx at `http://localhost/auth` for OIDC flows.
- **WSO2 API Manager** runs from the official Docker image, exposing the publisher, developer portal, and gateway surfaces (ports 9443/8280) so you can publish and secure APIs in front of the services.
- **CockroachDB** comes up as a three-node cluster with sequential health-checked startup, followed by automated cluster initialization and database/user bootstrapping jobs so schemas are ready before your services connect. Ports `26257` (SQL) and `8082` (admin UI) are forwarded from the first node.
- **Redis 7** provides a lightweight cache/message store on `localhost:6379` secured with the password supplied via `REDIS_PASSWORD`.
- **Redpanda** serves as the Kafka-compatible event broker with a single-node developer configuration bound to `localhost:9092` and persisted in a named volume.

## Resource limits and local tuning
The default `docker-compose.yml` now applies conservative CPU and memory caps to each container using `deploy.resources.limits`.
The anchors defined near the top of the file (`x-default-deploy`, `x-worker-deploy`, `x-support-deploy`, etc.) describe the
limits that are shared by common container types (HTTP APIs, Celery workers, infrastructure services, and databases). Adjust
these anchors to change the limits globally for each service category, or override an individual service by editing its
`deploy` block directly. The values are intentionally modest so that the entire stack can run on a developer laptop; if you need
more headroom for load testing, increase the `cpus` and `memory` values and restart the affected containers with
`docker compose up -d <service>`. Remember that Docker Compose will ignore these settings outside of Swarm mode but Docker will
still honour the cgroup constraints when the stack is running locally.

## Identity and API gateway
The identity layer is prewired so that local OAuth/OIDC flows work out of the box:

- `keycloak/realm-export.json` defines the `innover` realm, role taxonomy, and a confidential `wso2am` client used when wiring WSO2 API Manager to Keycloak. Keep the `secret` field for that client in lock-step with the `WSO2_AM_CLIENT_SECRET` value in `.env` so token introspection works as expected.
- The realm also bundles two browser authentication flows (default and OTP-enforced) to illustrate step-up scenarios, giving you a head start on multi-factor experiments. The shipped export restricts redirect and post-logout URIs to `https://localhost:9443/*`, so add extra origins in the realm if you proxy WSO2 somewhere else.
- WSO2 API Manager is auto-wired to Keycloak by the `wso2/configure-keycloak.py` helper that runs as part of `make up`. The script waits for both services to report healthy and then provisions the Keycloak connector through the Admin REST API, eliminating the need to click through the management console.

### Keycloak + WSO2 API Manager checklist
1. Start the stack (`make up`). The Makefile will block until Keycloak (`http://localhost:8080`) and WSO2 API Manager (`https://localhost:9443/carbon`) are healthy and the Keycloak key manager has been created automatically.
2. Sign in to the Keycloak admin console (`http://localhost:8080/admin`) with the bootstrap credentials declared in `docker-compose.yml`, then create a user with a password and mark it as verified/enabled.
3. (Optional) Log in to the WSO2 management console with the default `admin/admin` credentials if you want to inspect or tweak the generated Keycloak key manager. The configuration is driven by the `WSO2_AM_CLIENT_*` and `KEYCLOAK_*` variables in `.env`.
4. Publish an API in WSO2 that targets one of the internal services (for example `http://ledger:8000/health`) and enable OAuth2 security using the Keycloak connection.
5. Invoke the API through the WSO2 gateway via the developer portal or `curl`, using the HTTPS endpoint on port 9443 (or HTTP on 8280) that corresponds to the context you published.

Need to re-run the wiring after changing credentials? Execute `make configure-keycloak` to trigger the same automation without restarting the full stack.

### Automated API Publishing
The repository includes automation scripts to publish all microservices to WSO2 API Manager with support for REST, GraphQL, WebSocket, and AI/LLM APIs:

1. **Quick publish** - Publish all configured APIs:
   ```bash
   make publish-apis
   ```

   This will automatically publish all 6 microservices to WSO2:
   - Profile Service API → `/api/profile` → `http://profile:8000`
   - Payment Service API → `/api/payment` → `http://payment:8000`
   - Ledger Service API → `/api/ledger` → `http://ledger:8000`
   - Wallet Service API → `/api/wallet` → `http://wallet:8000`
   - Rule Engine Service API → `/api/rules` → `http://rule-engine:8000`
   - Forex Service API → `/api/forex` → `http://forex:8000`

2. **Configuration-based approach** - Edit `wso2/api-config.yaml` to define your APIs:
   - REST APIs: Standard HTTP/HTTPS endpoints
   - GraphQL APIs: GraphQL schema and endpoint
   - WebSocket APIs: Real-time streaming endpoints
   - AI/LLM APIs: High-timeout endpoints for AI/ML services

3. **Manual scripting** - Use `wso2/wso2-api-publisher.py` for programmatic API creation with custom logic

The automation handles:
- API creation with proper endpoint configuration
- Security scheme setup (OAuth2, API Key)
- CORS configuration
- Lifecycle management (auto-publish to PUBLISHED state)
- Support for future GraphQL, WebSocket, and AI/LLM endpoints

**What WSO2 knows after publishing:**
- All backend service URLs and health endpoints
- API contexts, versions, and descriptions
- Security schemes (OAuth2, API Key)
- CORS settings for cross-origin requests
- All HTTP methods (GET, POST, PUT, DELETE, PATCH)
- Throttling policies and visibility settings

**Accessing published APIs:**
- **Publisher Portal**: https://localhost:9443/publisher (manage and configure APIs)
- **Developer Portal**: https://localhost:9443/devportal (discover and subscribe to APIs)
- **API Gateway**: `https://localhost:9443/<context>` or `http://localhost:8280/<context>`
  - Example: `https://localhost:9443/api/profile/health`

### WSO2 integration tips
- Import the Keycloak JWKS endpoint (`http://keycloak:8080/realms/innover/protocol/openid-connect/certs`) so WSO2 can validate issued tokens without manual key rotation.
- The official WSO2 API Manager Docker samples at <https://github.com/wso2/docker-apim> illustrate how to script API publication and customizations. They are a good starting point for automating gateway configuration inside this stack.
- When developing locally, consider creating APIs with a unique context (for example `/api/ledger`) so they do not collide with the built-in WSO2 applications.

To customize identity:
1. Update the realm export file with additional clients, scopes, or roles.
2. Adjust WSO2 API Manager APIs, policies, or endpoints as new services are added.
3. Restart the relevant containers (`make down && make up`) to reload configuration.

## Observability
All Python services ship with OpenTelemetry environment variables that point at the local collector (`OTEL_EXPORTER_OTLP_ENDPOINT`). The collector pipeline receives OTLP gRPC traffic and forwards traces to Jaeger (`jaeger:4317`) and to the debug exporter for log visibility. After starting the stack you can browse to Jaeger at `http://localhost:16686` or tail the collector logs (`docker compose logs otel-collector`) to confirm span delivery.

## Local development workflow
### Prerequisites
- Docker Engine 24+
- Docker Compose v2 (bundled with recent Docker Desktop installations)
- Optional: Python 3.11+ and `grpcio-tools` if you plan to regenerate protobuf stubs outside the containers

### Environment configuration
-  `.env` and replace placeholder secrets before starting the stack. The compose file now requires a non-placeholder `WSO2_AM_CLIENT_SECRET` so WSO2 API Manager can authenticate with Keycloak, and other values should be customized to match your local setup.

### Start the stack
```bash
make up
```
`make up` performs a `docker compose up -d --build`, ensuring images are rebuilt before the services launch. Wait for the CockroachDB bootstrap jobs to finish (`docker compose logs -f cockroach-bootstrap`) before publishing or invoking APIs through WSO2 API Manager at `https://localhost:9443`.

### Useful commands
- `make up` – Start all containers with a fresh build (`docker compose up -d --build`).
- `make ps` – Show container status as reported by Docker Compose.
- `make health` – Print a table of container health checks for quick diagnostics.
- `make logs` – Follow all container logs with a 200-line tail, useful when developing service logic.
- `make logs-<svc>` – Tail logs for a specific service, mirroring `docker compose logs -f --tail=100 <svc>`.
- `make rebuild` – Force a clean rebuild of every image without starting containers, ideal when base images or dependencies change.
- `make restart-<svc>` – Restart a single service when you need to reload configuration quickly.
- `make down` – Tear down the environment and remove volumes so CockroachDB and Redpanda state resets between experiments.
- `make nuke` – Remove containers, volumes, and images for a completely clean slate.
- `make urls` – Echo quick links to Keycloak, WSO2 API Manager, Jaeger, CockroachDB, Redis, and Redpanda.
- `make smoke-test` – Run the comprehensive smoke test script (`./smoke-test.sh`).
- `make workers` – Inspect the active task list for every Celery worker container.
- `make test-worker-<svc>` – Dispatch a sample Celery task to a worker queue to verify connectivity.
- `make proto` – Regenerate protobuf stubs via `generate_protos.sh`.
- `make db-shell` – Open an interactive CockroachDB SQL shell inside the `cockroach1` container.
- `make redis-cli` – Launch the Redis CLI authenticated with the configured password.
- `make kafka-topics` – List Redpanda (Kafka) topics through `rpk`.
- `make publish-apis` – Automatically publish all APIs to WSO2 API Manager from `wso2/api-config.yaml`.

If you need direct access to a service container, use `docker compose exec <service> bash` and note that each heartbeat script runs in the foreground printing `[tick n] alive` messages.

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

- `services/` – Six placeholder Python microservices with identical Dockerfiles, heartbeat loops, and Celery scaffolding.
- `protos/` – Versioned gRPC API definitions per domain.
- `keycloak/` – Realm export and Dockerfile consumed during Keycloak startup.
- `wso2/` – WSO2 API Manager automation scripts and API configuration (REST, GraphQL, WebSocket, AI/LLM).
- `otel/` – OpenTelemetry Collector pipeline.
- `docker-compose.yml` – Orchestrates services, infrastructure, and bootstrap jobs.
- `Makefile` – Convenience targets for the local workflow.
- `generate_protos.sh` – Regenerates gRPC stubs into each service directory.
- `smoke-test.sh` – Basic smoke test script for the stack.
- `sandbox/` – Scratch space for experiments.
Use this map to locate the right directories as you flesh out APIs, persistence, and messaging logic.
