
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
