
# Innover Monorepo

A scaffolded microservices workspace with separate service directories, Protobuf API definitions, and infrastructure configs for auth, API gateway, and observability. Many files are currently placeholders to be filled in.

## Repository Structure

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
```

## Components

- **`services/`**
  - Six Python-based microservices: `forex`, `ledger`, `payment`, `profile`, `rule-engine`, `wallet`.
  - Each has an `app/` directory with `main.py`, `otel.py`, and `requirements.txt` for dependencies.
  - `Dockerfile` provided per service. Implement service logic in `app/main.py` and add packages to `app/requirements.txt`.

- **`protos/`**
  - Protobuf definitions organized by domain and version (e.g., `protos/forex/v1`).
  - Use `generate_protos.sh` to compile stubs (script is currently a placeholder; see TODOs below).

- **`keycloak/`**
  - `realm-export.json` for Identity & Access Management configuration (placeholder).

- **`kong/`**
  - `kong.yml` declarative config for the API gateway (routes, services, plugins). Currently a placeholder.

- **`otel/`**
  - OpenTelemetry Collector config in `collector.yaml` for traces/metrics/logs pipeline.

- **`docker-compose.yml`**
  - Intended to orchestrate all services and infra locally. Currently empty/placeholder.

- **`Makefile`**
  - Intended for common developer tasks (build, run, lint, test, proto-gen). Currently empty/placeholder.

- **`sandbox/`**
  - `maintest.py` for quick experiments.

## Getting Started

Prerequisites (suggested):
- **Docker & Docker Compose** for local orchestration.
- **Python 3.10+** for running services directly.

### Install service dependencies (example)

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r services/forex/app/requirements.txt
```

### Run a service (example)

```bash
python services/forex/app/main.py
```

### Build and run with Docker (example)

```bash
# build
docker build -t innover/forex:dev services/forex

# run
docker run --rm -p 8080:8080 innover/forex:dev
```

## Protobuf Codegen

- Place `.proto` files under the corresponding domain and version, e.g. `protos/forex/v1/`.
- Expected languages: Python (and optionally others). Update `generate_protos.sh` accordingly.

Example outline for `generate_protos.sh` (to implement):

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT_DIR=services/<service>/app/generated

python -m grpc_tools.protoc \
  -I protos \
  --python_out="$OUT_DIR" \
  --grpc_python_out="$OUT_DIR" \
  protos/<domain>/v1/*.proto
```

## Observability

- Configure OpenTelemetry in each service via `app/otel.py`.
- Run an OTel Collector using `otel/collector.yaml` and export to your backend (e.g., OTLP/Jaeger/Tempo/Zipkin).

## Security / Auth

- Keycloak realm exported at `keycloak/realm-export.json` (placeholder). Import into a Keycloak instance and configure clients/roles.

## API Gateway

- Kong declarative config at `kong/kong.yml`. Define routes to each service and attach plugins (auth, rate-limit, tracing).


# validate YAML
docker compose config >/dev/null && echo "compose valid ✅"

# bring up
docker compose up -d --build
