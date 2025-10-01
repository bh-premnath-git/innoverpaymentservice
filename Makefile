SHELL := /bin/bash

.PHONY: up down rebuild logs ps proto keycloak-url

up:
	docker compose up -d --build

rebuild:
	docker compose build --no-cache

logs:
	docker compose logs -f --tail=200

down:
	docker compose down -v

ps:
	docker compose ps

proto:
	bash ./generate_protos.sh

keycloak-url:
	@echo "Keycloak: http://localhost:8081"
	@echo "Kong: http://localhost:8000"
	@echo "Jaeger: http://localhost:16686"
	@echo "Redpanda: http://localhost:8080"
	@echo "Cockroach: http://localhost:8082"
	@if docker compose config --services | grep -qx 'flower'; then \
		echo "Flower: http://localhost:5555"; \
	fi

