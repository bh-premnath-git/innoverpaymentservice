# Innover Monorepo

This repository is a fully containerized playground for an event-driven payments platform. It comes with six Python microservices, pre-wired identity and API gateway layers, observability plumbing, and data infrastructure so that real business logic can be dropped in with minimal bootstrapping. Every component is orchestrated through `docker-compose` and surfaced via convenience Make targets for local development.

## Table of contents
1. [Service catalog](#service-catalog)
2. [Supporting infrastructure](#supporting-infrastructure)
3. [Identity and API gateway](#identity-and-api-gateway)
4. [Observability](#observability)
5. [Local development workflow](#local-development-workflow)
6. [Protobuf toolchain](#protobuf-toolchain)
7. [Repository layout](#repository-layout)

## Service catalog
Each business domain lives in `services/<name>` and currently ships a Dockerized heartbeat worker. The pattern is identical across all six services:

| Service | Purpose placeholder | Entrypoint | Container image | Default env wiring |
|---------|---------------------|------------|-----------------|--------------------|
| `profile` | User profile orchestration | `app/main.py` | `python:3.14.0rc3-slim-trixie` | `SERVICE_NAME=svc-profile`, database, Redis, Kafka, OTEL, OIDC |
| `payment` | Payment initiation pipeline | `app/main.py` | `python:3.14.0rc3-slim-trixie` | `SERVICE_NAME=svc-payment`, database, Redis, Kafka, OTEL, OIDC |
| `ledger` | Financial ledger posting | `app/main.py` | `python:3.14.0rc3-slim-trixie` | `SERVICE_NAME=svc-ledger`, database, Redis, Kafka, OTEL, OIDC |
| `wallet` | Customer wallet balance | `app/main.py` | `python:3.14.0rc3-slim-trixie` | `SERVICE_NAME=svc-wallet`, database, Redis, Kafka, OTEL, OIDC |
| `rule-engine` | Decisioning / risk controls | `app/main.py` | `python:3.14.0rc3-slim-trixie` | `SERVICE_NAME=svc-rules`, database, Redis, Kafka, OTEL, OIDC |
| `forex` | FX quote ingestion | `app/main.py` | `python:3.14.0rc3-slim-trixie` | `SERVICE_NAME=svc-forex`, database, Redis, Kafka, OTEL, OIDC |

The `app/main.py` process prints a startup banner that includes the injected `SERVICE_NAME`, then emits a tick every five seconds so the container stays healthy while you build real functionality. All services share the same Dockerfile template that installs optional requirements, copies the app directory, adds a health check, and runs the heartbeat script with unbuffered logging. The `docker-compose.yml` file fans each container out with identical environment variables for CockroachDB, Redis, Redpanda, OpenTelemetry, and Keycloak integration.

## Supporting infrastructure
The compose stack bootstraps every dependency you need to exercise the services locally:

- **Jaeger all-in-one** exposes `http://localhost:16686` for trace inspection and also accepts OTLP traffic on port 4317.
- **OpenTelemetry Collector** runs the `otel/collector.yaml` pipeline, receiving OTLP traces from the services and forwarding them to Jaeger and a debug exporter for console verification.
- **Keycloak** starts with the `innover` realm imported from `keycloak/realm-export.json`, listening on `http://localhost:8081` for administrative access.
- **Kong Gateway** is configured declaratively from `kong/kong.yml`, enabling the OpenID Connect plugin to guard each route while proxying requests to the internal services.
- **CockroachDB** comes up as a three-node cluster with sequential health-checked startup, followed by automated cluster initialization and database/user bootstrapping jobs so schemas are ready before your services connect. Ports `26257` (SQL) and `8082` (admin UI) are forwarded from the first node.
- **Redis 7** provides a lightweight cache/message store on `localhost:6379`.
- **Redpanda** serves as the Kafka-compatible event broker with a single-node developer configuration bound to `localhost:9092` and persisted in a named volume.

## Identity and API gateway
The identity layer is prewired so that local OAuth/OIDC flows work out of the box:

- `keycloak/realm-export.json` defines the `innover` realm, role taxonomy, and a confidential `kong` client with `kong-secret` so Kong can exchange authorization codes and enrich upstream requests with user claims.
- The realm also bundles two browser authentication flows (default and OTP-enforced) to illustrate step-up scenarios, giving you a head start on multi-factor experiments.
- `kong/kong.yml` creates declarative services and routes (`/api/ledger`, `/api/wallet`, `/api/rules`, `/api/fx`) with the OpenID Connect plugin set to inject `sub` and `preferred_username` headers into each upstream request once tokens are validated.

To customize identity:
1. Update the realm export file with additional clients, scopes, or roles.
2. Adjust Kong routes or scopes as new services are added.
3. Restart the relevant containers (`make down && make up`) to reload configuration.

## Observability
All Python services ship with OpenTelemetry environment variables that point at the local collector (`OTEL_EXPORTER_OTLP_ENDPOINT`). The collector pipeline receives OTLP gRPC traffic and forwards traces to Jaeger (`jaeger:4317`) and to the debug exporter for log visibility. After starting the stack you can browse to Jaeger at `http://localhost:16686` or tail the collector logs (`docker compose logs otel-collector`) to confirm span delivery.

## Local development workflow
### Prerequisites
- Docker Engine 24+
- Docker Compose v2 (bundled with recent Docker Desktop installations)
- Optional: Python 3.11+ and `grpcio-tools` if you plan to regenerate protobuf stubs outside the containers

### Start the stack
```bash
make up
```
`make up` performs a `docker compose up -d --build`, ensuring images are rebuilt before the services launch. Wait for the CockroachDB bootstrap jobs to finish (`docker compose logs -f cockroach-bootstrap`) before hitting APIs through Kong at `http://localhost:8000`.

### Useful commands
- `make logs` – Follow all container logs with a 200-line tail, useful when developing service logic.
- `make rebuild` – Force a clean rebuild of every image without starting containers, ideal when base images or dependencies change.
- `make down` – Tear down the environment and remove volumes so CockroachDB and Redpanda state resets between experiments.
- `make keycloak-url` – Echo quick links to Keycloak, Kong, and Jaeger dashboards for convenience.

If you need direct access to a service container, use `docker compose exec <service> bash` and note that each heartbeat script runs in the foreground printing `[tick n] alive` messages.

## Protobuf toolchain
Domain APIs live under `protos/<domain>/v1`. The provided `generate_protos.sh` script iterates through each domain, compiles `.proto` definitions with `grpc_tools.protoc`, and drops Python stubs into the corresponding `services/<name>/app/generated` directory (creating it if necessary). Invoke it via the Make target:

```bash
make proto
```
The target quietly installs `grpcio-tools` if it is missing before running the script. Empty `.proto` placeholders are already present so you only need to populate them before regenerating stubs.

## Repository layout
```
innover/
├─ services/
│  ├─ forex/
│  │  ├─ Dockerfile
│  │  └─ app/
│  │     ├─ main.py
│  │     ├─ otel.py
│  │     └─ requirements.txt
│  ├─ ledger/
│  │  ├─ Dockerfile
│  │  └─ app/
│  │     ├─ main.py
│  │     ├─ otel.py
│  │     └─ requirements.txt
│  ├─ payment/
│  │  ├─ Dockerfile
│  │  └─ app/
│  │     ├─ main.py
│  │     ├─ otel.py
│  │     └─ requirements.txt
│  ├─ profile/
│  │  ├─ Dockerfile
│  │  └─ app/
│  │     ├─ main.py
│  │     ├─ otel.py
│  │     └─ requirements.txt
│  ├─ rule-engine/
│  │  ├─ Dockerfile
│  │  └─ app/
│  │     ├─ main.py
│  │     ├─ otel.py
│  │     └─ requirements.txt
│  └─ wallet/
│     ├─ Dockerfile
│     └─ app/
│        ├─ main.py
│        ├─ otel.py
│        └─ requirements.txt
├─ protos/
│  ├─ forex/ v1/
│  │  ├─ forex.proto
│  ├─ ledger/ v1/
│  │  ├─ ledger.proto
│  ├─ payment/ v1/
│  │  ├─ payment.proto
│  ├─ profile/ v1/
│  │  ├─ profile.proto
│  ├─ rule-engine/ v1/
│  │  ├─ rule-engine.proto
│  └─ wallet/ v1/
│     ├─ wallet.proto
│
├─ keycloak/
│  └─ realm-export.json
├─ kong/
│  └─ kong.yml
├─ otel/
│  └─ collector.yaml
├─ sandbox/
│  └─ maintest.py
├─ .env
├─ generate_protos.sh
├─ docker-compose.yml
├─ Makefile
innoverpaymentservice/
├─ services/            # Six placeholder Python microservices with identical Dockerfiles and heartbeat loops
├─ protos/              # Versioned gRPC API definitions per domain
├─ keycloak/            # Realm export consumed during Keycloak startup
├─ kong/                # Declarative Kong configuration with OIDC plugins
├─ otel/                # OpenTelemetry Collector pipeline
├─ docker-compose.yml   # Orchestrates services, infrastructure, and bootstrap jobs
├─ Makefile             # Convenience targets for the local workflow
├─ generate_protos.sh   # Regenerates gRPC stubs into each service directory
└─ sandbox/             # Scratch space for experiments
```
Use this map to locate the right directories as you flesh out APIs, persistence, and messaging logic.
