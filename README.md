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
Each business domain lives in `services/<name>` and ships with both an HTTP placeholder (the `app/main.py` heartbeat) **and** a Celery worker that exercises the async infrastructure. The pattern is identical across all six domains:

| Service | Example scope | Runtime containers | Entrypoint(s) | Default env wiring |
|---------|---------------|-------------------|---------------|--------------------|
| `profile` | User profile orchestration | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `payment` | Payment initiation pipeline | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `ledger` | Financial ledger posting | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `wallet` | Customer wallet balance | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `rule-engine` | Decisioning / risk controls | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |
| `forex` | FX quote ingestion | API + Celery worker | `app/main.py`, `celery -A celery_app worker` | `SERVICE_NAME` (per container), CockroachDB URL, Redis broker, Redpanda brokers, OTEL, OIDC |

The `app/main.py` process still prints a startup banner that includes the injected `SERVICE_NAME`, then emits a tick every five seconds so the container stays healthy while you build real functionality. Each service also exposes a `celery_app.py`/`tasks.py` module pair so you can fire real jobs through Redis. All services share the same Dockerfile template that installs optional requirements, copies the app directory, adds a health check, and runs either the heartbeat script or the Celery worker with unbuffered logging. The `docker-compose.yml` file fans each container out with identical environment variables for CockroachDB, Redis, Redpanda, OpenTelemetry, and Keycloak integration.

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
- **Keycloak** starts with the `innover` realm imported from `keycloak/realm-export.json`, listening on `http://localhost:8081` for administrative access.
- **Kong Gateway** is configured declaratively from `kong/kong.yml`, enabling the OpenID Connect plugin to guard each route while proxying requests to the internal services.
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

- `keycloak/realm-export.json` defines the `innover` realm, role taxonomy, and a confidential `kong` client. Keep the `secret` field for that client in lock-step with the `KONG_OIDC_CLIENT_SECRET` value in `.env`, otherwise Kong will be unable to complete the authorization-code exchange.
- The realm also bundles two browser authentication flows (default and OTP-enforced) to illustrate step-up scenarios, giving you a head start on multi-factor experiments. The shipped export restricts redirect and post-logout URIs to `http://localhost:8000/*`, so add extra origins in the realm if you proxy Kong somewhere else.
- `kong/kong.yml` creates declarative services and routes (`/api/ledger`, `/api/wallet`, `/api/rules`, `/api/fx`) with the OpenID Connect plugin set to inject `sub` and `preferred_username` headers into each upstream request once tokens are validated. The claims arrive as `x-sub` and `x-username` headers on the upstream request.

### Keycloak + Kong checklist
1. Start the stack (`make up`) and wait for Keycloak (`http://localhost:8081`) and Kong (`http://localhost:8000`) to report healthy.
2. Sign in to the Keycloak admin console (`http://localhost:8081/admin`) with the bootstrap credentials declared in `docker-compose.yml`, then create a user with a password and mark it as verified/enabled.
3. In a second tab, request a service through Kong, e.g. `http://localhost:8000/api/ledger`.
4. When Kong redirects you to Keycloak, complete the login with the user from step 2. Keycloak returns you to the original `/api/<service>` URL after the authorization code exchange finishes.
5. Repeat your Kong request (browser refresh or `curl --cookie`) and observe the post-login response. The placeholder services in this repo only emit heartbeat logs, but any real upstream will now receive `x-sub` and `x-username` headers populated with the authenticated subject and username.

### Example Kong↔Keycloak flow
The snippet below shows the round-trip you should expect when exercising the `/api/ledger` route. The first call demonstrates the redirect, the second shows what hits the upstream once the browser session is authenticated:

```bash
# 1. Kong forces you through Keycloak when no session is present
curl -i "http://localhost:8000/api/ledger"
# HTTP/1.1 302 Found
# location: http://localhost:8081/realms/innover/protocol/openid-connect/auth?client_id=kong&...

# 2. After completing the browser login, reuse the Keycloak session cookie
curl -i --cookie cookies.txt "http://localhost:8000/api/ledger"
# HTTP/1.1 200 OK (or the upstream response your service returns)
# ... forwarded to ledger with headers:
#   x-sub: <Keycloak user id>
#   x-username: <preferred_username claim>
```

To capture the forwarded headers verbatim while you are experimenting, point one of the routes at an HTTP echo service or add temporary logging to your upstream application and watch for the `x-sub` and `x-username` headers after authenticating.

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

### Environment configuration
-  `.env` and replace placeholder secrets before starting the stack. The compose file now requires a non-placeholder `KONG_OIDC_CLIENT_SECRET` so Kong can authenticate with Keycloak, and other values should be customized to match your local setup.

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
├─ kong/
│  ├─ Dockerfile
│  ├─ kong.yml
│  └─ vendor/
│     └─ openid-connect/
│        ├─ LICENSE
│        ├─ README.md
│        ├─ filter.lua
│        ├─ handler.lua
│        ├─ schema.lua
│        ├─ session.lua
│        └─ utils.lua
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
- `kong/` – Declarative Kong configuration with the vendored OpenID Connect plugin.
- `otel/` – OpenTelemetry Collector pipeline.
- `docker-compose.yml` – Orchestrates services, infrastructure, and bootstrap jobs.
- `Makefile` – Convenience targets for the local workflow.
- `generate_protos.sh` – Regenerates gRPC stubs into each service directory.
- `smoke-test.sh` – Basic smoke test script for the stack.
- `sandbox/` – Scratch space for experiments.
Use this map to locate the right directories as you flesh out APIs, persistence, and messaging logic.
