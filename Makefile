SHELL := /bin/bash

.PHONY: up down rebuild logs proto keycloak-url

up:
docker compose up -d --build

rebuild:
docker compose build --no-cache

logs:
docker compose logs -f --tail=200

down:
docker compose down -v

proto:
python -m pip install --quiet grpcio-tools || true
bash generate_protos.sh

keycloak-url:
@echo "Keycloak → http://localhost:8081"
@echo "Kong Gateway → http://localhost:8000"
@echo "Jaeger UI → http://localhost:16686"